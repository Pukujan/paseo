#!/usr/bin/env node
// Merges the friend package's settings into Paseo's config.json, and takes them
// out again. Used by install-friend.ps1; runs on its own too.
//
//   node paseo-config.mjs plan   --config <config.json> --state <state.json> --spec <spec.json>
//   node paseo-config.mjs apply  --config <config.json> --state <state.json> --spec <spec.json>
//   node paseo-config.mjs revert --config <config.json> --state <state.json>
//
// The spec says what we want:
//   {
//     "claudeProvider": { ...a Paseo provider override... } | null,
//     "listen": "100.x.y.z:6767" | null,      // null = leave the listen address alone
//     "plugin": { "id": "antigravity-cli", "path": "C:\\..." } | null
//   }
//
// Rules:
// - Only the keys we own are touched: agents.providers.claude, daemon.listen,
//   pluginsEnabled and plugins.<id>. Everything else stays exactly as it was.
// - Before the first change, the old value of each key goes into the state file.
//   Reruns keep that first record, so revert always gets back to the pre-install
//   value.
// - A key we set earlier that the spec no longer asks for (say, a rerun without
//   -Tailscale) goes back to its old value.
// - Before any write, the current file is copied to config.json.bak-<time>.
// - A config that isn't valid JSON is left alone (exit 1).
// Output: one JSON line on stdout, {"changed":bool,"backup":path|null,"changes":[...]}.
import { copyFileSync, existsSync, readFileSync, renameSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const STATE_SCHEMA = "paseo-friend.config-state.v1";

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export function getPath(obj, keys) {
  let cur = obj;
  for (const k of keys) {
    if (!isObject(cur) || !Object.prototype.hasOwnProperty.call(cur, k)) return { present: false };
    cur = cur[k];
  }
  return { present: true, value: clone(cur) };
}

export function setPath(obj, keys, value) {
  let cur = obj;
  for (const k of keys.slice(0, -1)) {
    if (!isObject(cur[k])) cur[k] = {};
    cur = cur[k];
  }
  cur[keys[keys.length - 1]] = clone(value);
}

export function deletePath(obj, keys) {
  const parents = [];
  let cur = obj;
  for (const k of keys.slice(0, -1)) {
    if (!isObject(cur[k])) return;
    parents.push([cur, k]);
    cur = cur[k];
  }
  delete cur[keys[keys.length - 1]];
  // Drop objects we emptied, but never the top level.
  for (let i = parents.length - 1; i >= 0; i--) {
    const [parent, k] = parents[i];
    if (isObject(parent[k]) && Object.keys(parent[k]).length === 0) delete parent[k];
    else break;
  }
}

function restore(obj, keys, previous) {
  if (previous && previous.present) setPath(obj, keys, previous.value);
  else deletePath(obj, keys);
}

const keyName = (keys) => keys.join(".");
const parseKey = (name) => name.split(".");

// Returns the wanted value for every key the spec manages.
export function wantedKeys(spec) {
  const want = new Map();
  if (spec.claudeProvider) want.set("agents.providers.claude", spec.claudeProvider);
  if (spec.listen) want.set("daemon.listen", spec.listen);
  if (spec.plugin) {
    if (!/^[a-z][a-z0-9-]*$/.test(spec.plugin.id)) throw new Error(`bad plugin id: ${spec.plugin.id}`);
    want.set("pluginsEnabled", true);
    want.set(`plugins.${spec.plugin.id}`, { source: "directory", path: spec.plugin.path, enabled: true });
  }
  return want;
}

export function emptyState() {
  return { schema: STATE_SCHEMA, previous: {} };
}

// Pure: returns { config, state, changes } without touching disk.
export function applySpec(config, state, spec) {
  const next = clone(config) ?? {};
  if (!("version" in next)) next.version = 1;
  const st = clone(state) ?? emptyState();
  const changes = [];
  const want = wantedKeys(spec);

  for (const [name, value] of want) {
    const keys = parseKey(name);
    const before = getPath(next, keys);
    if (!(name in st.previous)) st.previous[name] = before;
    if (!before.present || !same(before.value, value)) {
      setPath(next, keys, value);
      changes.push({ key: name, action: before.present ? "update" : "add" });
    }
  }
  // Keys we set before but the spec no longer wants: put them back.
  for (const name of Object.keys(st.previous)) {
    if (want.has(name)) continue;
    const keys = parseKey(name);
    const before = getPath(next, keys);
    restore(next, keys, st.previous[name]);
    const after = getPath(next, keys);
    if (!same(before, after)) changes.push({ key: name, action: "restore" });
    delete st.previous[name];
  }
  return { config: next, state: st, changes };
}

export function revertState(config, state) {
  const next = clone(config) ?? {};
  const changes = [];
  for (const [name, previous] of Object.entries(state?.previous ?? {})) {
    const keys = parseKey(name);
    const before = getPath(next, keys);
    restore(next, keys, previous);
    if (!same(before, getPath(next, keys))) changes.push({ key: name, action: "restore" });
  }
  return { config: next, changes };
}

function readJson(file, fallback) {
  if (!existsSync(file)) return fallback;
  const text = readFileSync(file, "utf8").replace(/^\uFEFF/, "");
  if (text.trim() === "") return fallback;
  return JSON.parse(text);
}

function writeJsonAtomic(file, value) {
  mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify(value, null, 2) + "\n", "utf8");
  renameSync(tmp, file);
}

function backup(file) {
  if (!existsSync(file)) return null;
  const d = new Date();
  const two = (n) => String(n).padStart(2, "0");
  const stamp = `${d.getFullYear()}${two(d.getMonth() + 1)}${two(d.getDate())}-${two(d.getHours())}${two(d.getMinutes())}${two(d.getSeconds())}`;
  let dest = `${file}.bak-${stamp}`;
  for (let i = 1; existsSync(dest); i++) dest = `${file}.bak-${stamp}-${i}`;
  copyFileSync(file, dest);
  return dest;
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) out[a.slice(2)] = argv[++i];
    else out._.push(a);
  }
  return out;
}

export function main(argv) {
  const args = parseArgs(argv);
  const op = args._[0];
  if (!["plan", "apply", "revert"].includes(op) || !args.config || !args.state) {
    process.stderr.write("usage: paseo-config.mjs plan|apply|revert --config FILE --state FILE [--spec FILE]\n");
    return 2;
  }
  let config;
  try {
    config = readJson(args.config, {});
  } catch {
    process.stderr.write(`paseo-config: ${args.config} is not valid JSON; left it as it is.\n`);
    return 1;
  }
  if (!isObject(config)) {
    process.stderr.write(`paseo-config: ${args.config} is not a JSON object; left it as it is.\n`);
    return 1;
  }
  const state = readJson(args.state, null);

  if (op === "revert") {
    if (!state) {
      process.stdout.write(JSON.stringify({ changed: false, backup: null, changes: [] }) + "\n");
      return 0;
    }
    const { config: next, changes } = revertState(config, state);
    const bak = changes.length ? backup(args.config) : null;
    if (changes.length) writeJsonAtomic(args.config, next);
    rmSync(args.state, { force: true });
    process.stdout.write(JSON.stringify({ changed: changes.length > 0, backup: bak, changes }) + "\n");
    return 0;
  }

  if (!args.spec) {
    process.stderr.write("paseo-config: --spec is required for plan and apply\n");
    return 2;
  }
  const spec = readJson(args.spec, {});
  const { config: next, state: nextState, changes } = applySpec(config, state, spec);
  if (op === "plan") {
    process.stdout.write(JSON.stringify({ changed: changes.length > 0, backup: null, changes }) + "\n");
    return 0;
  }
  const bak = changes.length ? backup(args.config) : null;
  if (changes.length || !existsSync(args.config)) writeJsonAtomic(args.config, next);
  if (Object.keys(nextState.previous).length) writeJsonAtomic(args.state, nextState);
  else rmSync(args.state, { force: true });
  process.stdout.write(JSON.stringify({ changed: changes.length > 0, backup: bak, changes }) + "\n");
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
