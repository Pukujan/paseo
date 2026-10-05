import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, test } from "vitest";

import { loadConfig, resolveDirectorySearchExtraRoots } from "./config.js";

const roots: string[] = [];

async function createHome(config: object = {}): Promise<string> {
  const home = await mkdtemp(path.join(os.tmpdir(), "paseo-config-dirsearch-"));
  roots.push(home);
  await writeFile(path.join(home, "config.json"), JSON.stringify(config));
  return home;
}

describe("daemon directory search roots config", () => {
  afterEach(async () => {
    await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
  });

  test("defaults to no extra roots so search stays home-only", async () => {
    const home = await createHome();

    expect(loadConfig(home, { env: {} }).directorySearchExtraRoots).toEqual([]);
  });

  test("loads absolute extra roots from daemon.directorySearch", async () => {
    const extra = path.join(os.tmpdir(), "paseo-extra-root");
    const home = await createHome({
      daemon: { directorySearch: { extraRoots: [extra, `${extra}${path.sep}`, "  "] } },
    });

    expect(loadConfig(home, { env: {} }).directorySearchExtraRoots).toEqual([path.resolve(extra)]);
  });

  test("rejects unknown keys under daemon.directorySearch", async () => {
    const home = await createHome({ daemon: { directorySearch: { rootz: ["/"] } } });

    expect(() => loadConfig(home, { env: {} })).toThrow();
  });

  test("merges env roots, expands tilde, and drops relative paths", () => {
    const first = path.join(os.tmpdir(), "first-root");
    const second = path.join(os.tmpdir(), "second-root");
    const resolved = resolveDirectorySearchExtraRoots(
      {
        HOME: os.homedir(),
        PASEO_DIRECTORY_SEARCH_EXTRA_ROOTS: [second, "relative/dir", first].join(path.delimiter),
      },
      { daemon: { directorySearch: { extraRoots: [first, "~"] } } } as never,
    );

    expect(resolved).toEqual([
      path.resolve(first),
      path.resolve(process.env.HOME || os.homedir()),
      path.resolve(second),
    ]);
  });

  test("loads replacement search roots and project sync roots in order", async () => {
    const first = path.join(os.tmpdir(), "dev-root");
    const second = path.parse(os.tmpdir()).root;
    const home = await createHome({
      daemon: {
        directorySearch: { roots: [first, second] },
        projectSync: { roots: [first] },
      },
    });
    const config = loadConfig(home, { env: {} });

    expect(config.directorySearchRoots).toEqual([path.resolve(first), path.resolve(second)]);
    expect(config.projectSyncRoots).toEqual([path.resolve(first)]);
  });
});
