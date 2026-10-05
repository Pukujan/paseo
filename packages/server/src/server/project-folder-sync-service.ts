import { watch as watchPath, type FSWatcher } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import type pino from "pino";
import { areEquivalentPaths, looksLikeDefiniteWindowsPath } from "../utils/path.js";
import type {
  PersistedProjectRecord,
  ProjectRegistry,
  WorkspaceRegistry,
} from "./workspace-registry.js";

const DEFAULT_RESCAN_INTERVAL_MS = 30_000;
const DEFAULT_DEBOUNCE_MS = 500;
// Operating-system bookkeeping folders that can sit at a drive root; never projects.
const IGNORED_FOLDER_NAMES = new Set([
  "$recycle.bin",
  "system volume information",
  "$winreagent",
  "config.msi",
  "node_modules",
]);

export interface ProjectFolderSyncResult {
  added: string[];
  removed: string[];
  skipped: string[];
}

export interface ProjectFolderSyncServiceOptions {
  roots: readonly string[];
  projectRegistry: ProjectRegistry;
  workspaceRegistry: Pick<WorkspaceRegistry, "list">;
  findOrCreateProjectForDirectory: (cwd: string) => Promise<PersistedProjectRecord>;
  logger: pino.Logger;
  rescanIntervalMs?: number;
  debounceMs?: number;
}

/**
 * Keeps every top-level folder of the configured roots registered as a project. New folders are
 * registered, and projects whose folder no longer exists are removed, as long as they have no
 * active workspace (a running workspace is never torn down by a folder disappearing). A
 * filesystem watcher triggers a debounced sync; a periodic rescan covers missed events.
 */
export class ProjectFolderSyncService {
  private readonly roots: readonly string[];
  private readonly options: ProjectFolderSyncServiceOptions;
  private readonly logger: pino.Logger;
  private readonly watchers: FSWatcher[] = [];
  private rescanTimer: NodeJS.Timeout | null = null;
  private debounceTimer: NodeJS.Timeout | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private disposed = false;

  constructor(options: ProjectFolderSyncServiceOptions) {
    this.options = options;
    this.roots = options.roots;
    this.logger = options.logger.child({ module: "project-folder-sync" });
  }

  async start(): Promise<void> {
    if (this.roots.length === 0) return;
    for (const root of this.roots) this.watchRoot(root);
    this.rescanTimer = setInterval(
      () => void this.syncNow().catch(() => undefined),
      this.options.rescanIntervalMs ?? DEFAULT_RESCAN_INTERVAL_MS,
    );
    this.rescanTimer.unref?.();
    await this.syncNow().catch(() => undefined);
  }

  dispose(): void {
    this.disposed = true;
    for (const watcher of this.watchers.splice(0)) watcher.close();
    if (this.rescanTimer) clearInterval(this.rescanTimer);
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.rescanTimer = null;
    this.debounceTimer = null;
  }

  /** Runs one sync pass. Passes are serialized so overlapping triggers never race. */
  syncNow(): Promise<ProjectFolderSyncResult> {
    const run = this.queue.then(() => this.syncOnce());
    this.queue = run.catch(() => undefined);
    return run;
  }

  private watchRoot(root: string): void {
    try {
      const watcher = watchPath(root, { persistent: false }, () => this.scheduleSync());
      watcher.on("error", (error) => {
        this.logger.warn({ err: error, root }, "Project folder watcher failed; relying on rescan");
      });
      this.watchers.push(watcher);
    } catch (error) {
      this.logger.warn({ err: error, root }, "Cannot watch project root; relying on rescan");
    }
  }

  private scheduleSync(): void {
    if (this.disposed) return;
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.syncNow().catch(() => undefined);
    }, this.options.debounceMs ?? DEFAULT_DEBOUNCE_MS);
    this.debounceTimer.unref?.();
  }

  private async syncOnce(): Promise<ProjectFolderSyncResult> {
    const result: ProjectFolderSyncResult = { added: [], removed: [], skipped: [] };
    if (this.disposed) return result;
    const projects = (await this.options.projectRegistry.list()).filter(
      (project) => !project.archivedAt,
    );
    for (const root of this.roots) {
      const folders = await listProjectFolders(root);
      // An unreadable root (unmounted drive, permissions) is never evidence that its folders
      // are gone, so it neither adds nor removes anything.
      if (!folders) continue;
      await this.addMissingProjects(folders, projects, result);
      await this.removeVanishedProjects(root, projects, result);
    }
    if (result.added.length > 0 || result.removed.length > 0) {
      this.logger.info(result, "Project folders synced");
    }
    return result;
  }

  private async addMissingProjects(
    folders: string[],
    projects: PersistedProjectRecord[],
    result: ProjectFolderSyncResult,
  ): Promise<void> {
    for (const folder of folders) {
      if (projects.some((project) => areEquivalentPaths(project.rootPath, folder))) continue;
      try {
        const project = await this.options.findOrCreateProjectForDirectory(folder);
        projects.push(project);
        result.added.push(folder);
      } catch (error) {
        this.logger.warn({ err: error, folder }, "Failed to register project folder");
      }
    }
  }

  private async removeVanishedProjects(
    root: string,
    projects: PersistedProjectRecord[],
    result: ProjectFolderSyncResult,
  ): Promise<void> {
    const workspaces = await this.options.workspaceRegistry.list();
    for (const project of projects) {
      if (!isDirectChild(root, project.rootPath)) continue;
      if (await isDirectory(project.rootPath)) continue;
      const hasActiveWorkspace = workspaces.some(
        (workspace) => workspace.projectId === project.projectId && !workspace.archivedAt,
      );
      if (hasActiveWorkspace) {
        result.skipped.push(project.rootPath);
        continue;
      }
      try {
        await this.options.projectRegistry.remove(project.projectId);
        result.removed.push(project.rootPath);
      } catch (error) {
        this.logger.warn({ err: error, project: project.rootPath }, "Failed to remove project");
      }
    }
  }
}

async function listProjectFolders(root: string): Promise<string[] | null> {
  try {
    const entries = await readdir(root, { withFileTypes: true });
    return entries
      .filter(
        (entry) =>
          entry.isDirectory() &&
          !entry.name.startsWith(".") &&
          !IGNORED_FOLDER_NAMES.has(entry.name.toLowerCase()),
      )
      .map((entry) => path.join(root, entry.name))
      .sort((left, right) => left.localeCompare(right));
  } catch {
    return null;
  }
}

function isDirectChild(root: string, candidate: string): boolean {
  const platformPath = looksLikeDefiniteWindowsPath(candidate) ? path.win32 : path.posix;
  return areEquivalentPaths(platformPath.dirname(candidate), root);
}

async function isDirectory(target: string): Promise<boolean> {
  return (await stat(target).catch(() => null))?.isDirectory() === true;
}
