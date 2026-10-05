import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import pino from "pino";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ProjectFolderSyncService } from "./project-folder-sync-service.js";
import type { PersistedProjectRecord } from "./workspace-registry.js";

function record(rootPath: string, id: string): PersistedProjectRecord {
  return {
    projectId: id,
    rootPath,
    kind: "non_git",
    displayName: path.basename(rootPath),
    projectKey: null,
    customName: null,
    customIconRevision: null,
    createdAt: "2026-10-04T00:00:00.000Z",
    updatedAt: "2026-10-04T00:00:00.000Z",
    archivedAt: null,
  } as unknown as PersistedProjectRecord;
}

function createHarness(root: string, workspaceProjectIds: string[] = []) {
  const projects = new Map<string, PersistedProjectRecord>();
  let next = 0;
  const projectRegistry = {
    list: async () => [...projects.values()],
    remove: async (projectId: string) => void projects.delete(projectId),
  };
  const service = new ProjectFolderSyncService({
    roots: [root],
    projectRegistry: projectRegistry as never,
    workspaceRegistry: {
      list: async () =>
        workspaceProjectIds.map((projectId) => ({ projectId, archivedAt: null })) as never,
    },
    findOrCreateProjectForDirectory: async (cwd) => {
      const created = record(cwd, `prj_${next++}`);
      projects.set(created.projectId, created);
      return created;
    },
    logger: pino({ level: "silent" }),
    debounceMs: 20,
  });
  return { service, projects };
}

describe("ProjectFolderSyncService", () => {
  let root: string;
  let service: ProjectFolderSyncService | null = null;

  beforeEach(() => {
    root = realpathSync.native(mkdtempSync(path.join(tmpdir(), "project-folder-sync-")));
    mkdirSync(path.join(root, "alpha"));
    mkdirSync(path.join(root, "beta"));
    mkdirSync(path.join(root, ".scratch"));
    mkdirSync(path.join(root, "$RECYCLE.BIN"));
  });

  afterEach(() => {
    service?.dispose();
    service = null;
    rmSync(root, { recursive: true, force: true });
  });

  it("registers top-level folders and skips hidden and system folders", async () => {
    const harness = createHarness(root);
    service = harness.service;
    const result = await harness.service.syncNow();

    expect(result.added).toEqual([path.join(root, "alpha"), path.join(root, "beta")]);
    expect(await harness.service.syncNow()).toEqual({ added: [], removed: [], skipped: [] });
  });

  it("removes projects whose folder vanished unless a workspace is active", async () => {
    const harness = createHarness(root, ["kept"]);
    service = harness.service;
    harness.projects.set("gone", record(path.join(root, "gone"), "gone"));
    harness.projects.set("kept", record(path.join(root, "busy"), "kept"));
    harness.projects.set("elsewhere", record(path.join(tmpdir(), "not-under-root"), "elsewhere"));

    const result = await harness.service.syncNow();

    expect(result.removed).toEqual([path.join(root, "gone")]);
    expect(result.skipped).toEqual([path.join(root, "busy")]);
    expect([...harness.projects.keys()]).toContain("elsewhere");
  });

  it("never removes anything when the root is unreadable", async () => {
    const harness = createHarness(path.join(root, "missing-root"));
    service = harness.service;
    harness.projects.set("x", record(path.join(root, "missing-root", "x"), "x"));

    expect(await harness.service.syncNow()).toEqual({ added: [], removed: [], skipped: [] });
  });

  it("picks up added and deleted folders through the watcher", async () => {
    const harness = createHarness(root);
    service = harness.service;
    await harness.service.start();
    const roots = () => [...harness.projects.values()].map((project) => project.rootPath);

    mkdirSync(path.join(root, "gamma"));
    await expect.poll(roots, { timeout: 5_000 }).toContain(path.join(root, "gamma"));
    rmSync(path.join(root, "gamma"), { recursive: true });
    await expect.poll(roots, { timeout: 5_000 }).not.toContain(path.join(root, "gamma"));
  });
});
