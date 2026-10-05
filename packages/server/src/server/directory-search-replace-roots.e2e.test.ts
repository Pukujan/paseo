import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { afterAll, beforeAll, expect, test } from "vitest";

import { DaemonClient } from "./test-utils/index.js";
import { createTestPaseoDaemon } from "./test-utils/paseo-daemon.js";

let devRoot: string;
let daemon: Awaited<ReturnType<typeof createTestPaseoDaemon>>;
let client: DaemonClient;

beforeAll(async () => {
  devRoot = realpathSync.native(mkdtempSync(path.join(tmpdir(), "paseo-dev-root-")));
  mkdirSync(path.join(devRoot, "eval-lab"));
  mkdirSync(path.join(devRoot, "octo-db"));
  mkdirSync(path.join(devRoot, ".scratch"));
  daemon = await createTestPaseoDaemon({
    directorySearchRoots: [devRoot],
    projectSyncRoots: [devRoot],
  });
  client = new DaemonClient({ url: `ws://127.0.0.1:${daemon.port}/ws` });
  await client.connect();
}, 60000);

afterAll(async () => {
  await client?.close();
  await daemon?.close();
  rmSync(devRoot, { recursive: true, force: true });
});

test("configured roots replace home and a blank query lists the root's folders", async () => {
  const blank = await client.getDirectorySuggestions({ query: "", limit: 30 });
  expect(blank.directories).toEqual([
    path.join(devRoot, "eval-lab"),
    path.join(devRoot, "octo-db"),
  ]);

  const home = await client.getDirectorySuggestions({ query: "~", limit: 30 });
  expect(home.directories.some((entry) => entry.startsWith(homedir()))).toBe(false);
}, 30000);

test("project sync registers new folders and removes deleted ones", async () => {
  const roots = async () => (await client.listProjects()).projects.map((p) => p.projectRootPath);
  await expect.poll(roots, { timeout: 10_000 }).toContain(path.join(devRoot, "eval-lab"));
  expect(await roots()).not.toContain(path.join(devRoot, ".scratch"));

  mkdirSync(path.join(devRoot, "fresh"));
  await expect.poll(roots, { timeout: 10_000 }).toContain(path.join(devRoot, "fresh"));
  rmSync(path.join(devRoot, "fresh"), { recursive: true });
  await expect.poll(roots, { timeout: 10_000 }).not.toContain(path.join(devRoot, "fresh"));
}, 40000);
