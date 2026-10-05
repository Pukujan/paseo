import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterAll, beforeAll, expect, test } from "vitest";

import { DaemonClient } from "./test-utils/index.js";
import { createTestPaseoDaemon } from "./test-utils/paseo-daemon.js";

let extraRoot: string;
let daemon: Awaited<ReturnType<typeof createTestPaseoDaemon>>;
let client: DaemonClient;

beforeAll(async () => {
  extraRoot = realpathSync.native(mkdtempSync(path.join(tmpdir(), "paseo-extra-search-root-")));
  mkdirSync(path.join(extraRoot, "development", "eval-lab"), { recursive: true });
  mkdirSync(path.join(extraRoot, "development", "octo-db"), { recursive: true });
  mkdirSync(path.join(extraRoot, "$RECYCLE.BIN", "development-trash"), { recursive: true });
  daemon = await createTestPaseoDaemon({ directorySearchExtraRoots: [extraRoot] });
  client = new DaemonClient({ url: `ws://127.0.0.1:${daemon.port}/ws` });
  await client.connect();
}, 60000);

afterAll(async () => {
  await client?.close();
  await daemon?.close();
  rmSync(extraRoot, { recursive: true, force: true });
});

test("home-scoped directory suggestions include configured extra roots", async () => {
  const result = await client.getDirectorySuggestions({ query: "eval-lab", limit: 30 });

  expect(result.error).toBeNull();
  expect(result.directories).toContain(path.join(extraRoot, "development", "eval-lab"));
}, 30000);

test("typed absolute paths inside an extra root list matching child folders", async () => {
  const result = await client.getDirectorySuggestions({
    query: `${path.join(extraRoot, "development")}${path.sep}`,
    limit: 30,
  });

  expect(result.error).toBeNull();
  expect(result.directories).toEqual([
    path.join(extraRoot, "development"),
    path.join(extraRoot, "development", "eval-lab"),
    path.join(extraRoot, "development", "octo-db"),
  ]);
}, 30000);

test("extra-root search skips system directories", async () => {
  const result = await client.getDirectorySuggestions({ query: "development", limit: 100 });

  expect(result.error).toBeNull();
  expect(result.directories.some((entry) => entry.includes("$RECYCLE.BIN"))).toBe(false);
  expect(result.directories).toContain(path.join(extraRoot, "development"));
}, 30000);
