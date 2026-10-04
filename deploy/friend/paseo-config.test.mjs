// node --test deploy/friend/paseo-config.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { applySpec, revertState, main } from "./paseo-config.mjs";

// Shaped like a real config that already has a daemon section, a plugin and
// other providers. Values are placeholders.
const existing = () => ({
  version: 1,
  daemon: { listen: "192.0.2.10:6767", cors: { allowedOrigins: ["https://app.paseo.sh"] }, relay: { enabled: false } },
  app: { baseUrl: "https://app.paseo.sh" },
  plugins: { other: { source: "directory", path: "C:\\plugins\\other", enabled: true } },
  agents: {
    providers: {
      claude: { label: "Somebody else's Claude", command: ["claude-wrapper"] },
      grok: { extends: "acp", label: "Grok", command: ["grok", "agent", "stdio"] },
    },
  },
  pluginsEnabled: false,
});

const claude = {
  label: "Claude (InferHub launcher)",
  command: ["node", "C:\\Users\\friend\\AppData\\Local\\claude-code-launcher\\app\\shared\\integrations\\claude-env-exec.mjs"],
  models: [{ id: "sonnet", label: "Main seat (sonnet)", isDefault: true }],
};
const fullSpec = {
  claudeProvider: claude,
  listen: "203.0.113.5:6767",
  plugin: { id: "antigravity-cli", path: "C:\\Users\\friend\\.paseo\\friend-plugins\\antigravity-cli\\node_modules\\paseo-plugin-antigravity-cli" },
};

test("apply sets only our keys and keeps the rest", () => {
  const { config, changes } = applySpec(existing(), null, fullSpec);
  assert.deepEqual(config.agents.providers.claude, claude);
  assert.deepEqual(config.agents.providers.grok, existing().agents.providers.grok);
  assert.equal(config.daemon.listen, "203.0.113.5:6767");
  assert.deepEqual(config.daemon.cors, existing().daemon.cors);
  assert.deepEqual(config.plugins.other, existing().plugins.other);
  assert.equal(config.pluginsEnabled, true);
  assert.equal(config.plugins["antigravity-cli"].source, "directory");
  assert.equal(config.plugins["antigravity-cli"].enabled, true);
  assert.equal(changes.length, 4);
});

test("apply twice equals apply once (idempotent)", () => {
  const once = applySpec(existing(), null, fullSpec);
  const twice = applySpec(once.config, once.state, fullSpec);
  assert.deepEqual(twice.config, once.config);
  assert.deepEqual(twice.state, once.state);
  assert.equal(twice.changes.length, 0);
});

test("revert after apply gives back the original config", () => {
  const once = applySpec(existing(), null, fullSpec);
  const twice = applySpec(once.config, once.state, fullSpec);
  const { config } = revertState(twice.config, twice.state);
  assert.deepEqual(config, existing());
});

test("revert on an empty start leaves only the version", () => {
  const once = applySpec({}, null, fullSpec);
  const { config } = revertState(once.config, once.state);
  assert.deepEqual(config, { version: 1 });
});

test("a rerun without listen puts the old listen address back", () => {
  const once = applySpec(existing(), null, fullSpec);
  const rerun = applySpec(once.config, once.state, { ...fullSpec, listen: null });
  assert.equal(rerun.config.daemon.listen, "192.0.2.10:6767");
  assert.ok(!("daemon.listen" in rerun.state.previous));
  assert.ok(rerun.changes.some((c) => c.key === "daemon.listen" && c.action === "restore"));
});

test("a rerun without the plugin removes it and restores pluginsEnabled", () => {
  const once = applySpec(existing(), null, fullSpec);
  const rerun = applySpec(once.config, once.state, { ...fullSpec, plugin: null });
  assert.equal(rerun.config.pluginsEnabled, false);
  assert.ok(!("antigravity-cli" in rerun.config.plugins));
  assert.deepEqual(rerun.config.plugins.other, existing().plugins.other);
});

test("bad plugin ids are refused", () => {
  assert.throws(() => applySpec({}, null, { plugin: { id: "Bad Id", path: "x" } }));
});

test("CLI: apply backs up, writes, and revert restores the file", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "paseo-config-"));
  const cfg = path.join(dir, "config.json");
  const state = path.join(dir, "friend-config-state.json");
  const spec = path.join(dir, "spec.json");
  const original = JSON.stringify(existing(), null, 4);
  writeFileSync(cfg, "\uFEFF" + original);
  writeFileSync(spec, JSON.stringify(fullSpec));
  const log = [];
  const write = process.stdout.write;
  process.stdout.write = (s) => (log.push(String(s)), true);
  try {
    assert.equal(main(["plan", "--config", cfg, "--state", state, "--spec", spec]), 0);
    assert.equal(readFileSync(cfg, "utf8"), "\uFEFF" + original, "plan must not write");
    assert.ok(!existsSync(state));
    assert.equal(main(["apply", "--config", cfg, "--state", state, "--spec", spec]), 0);
    assert.equal(main(["apply", "--config", cfg, "--state", state, "--spec", spec]), 0);
    assert.equal(main(["revert", "--config", cfg, "--state", state]), 0);
  } finally {
    process.stdout.write = write;
  }
  assert.equal(JSON.parse(log[0]).changes.length, 4);
  assert.equal(JSON.parse(log[2]).changed, false);
  assert.deepEqual(JSON.parse(readFileSync(cfg, "utf8")), existing());
  assert.ok(!existsSync(state));
  const backups = readdirSync(dir).filter((f) => f.startsWith("config.json.bak-"));
  assert.equal(backups.length, 2, "one backup for the first apply, one for the revert");
  assert.equal(readFileSync(path.join(dir, backups.sort()[0]), "utf8"), "\uFEFF" + original);
});

test("CLI: invalid JSON is left alone", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "paseo-config-"));
  const cfg = path.join(dir, "config.json");
  const spec = path.join(dir, "spec.json");
  writeFileSync(cfg, "{ not json");
  writeFileSync(spec, JSON.stringify(fullSpec));
  const err = process.stderr.write;
  process.stderr.write = () => true;
  try {
    assert.equal(main(["apply", "--config", cfg, "--state", path.join(dir, "s.json"), "--spec", spec]), 1);
  } finally {
    process.stderr.write = err;
  }
  assert.equal(readFileSync(cfg, "utf8"), "{ not json");
});
