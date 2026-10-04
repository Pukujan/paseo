# TASK-PSO-0001 — Install the ACS multi-agent hot-loader

<!-- continuity:task {"acceptance":["the pinned ACS hotload_check.py prints `hotload_check: OK` against this repository","PCM continuity files and the nine pinned schemas are present and `continuity validate` prints VALID","the CGM 0.5.12 adapter lists all eight modules and the pinned validate_content_system.py prints VALID","the .coord assignment, boss claim and stack-manifest.json are pinned to release train 2026-10-01 and the train's check_manifest.py passes","the `gates` check passes on the pull request and Paseo's own format and lint checks still pass on the new files","no Paseo runtime code, package manifest, lockfile or existing workflow changes, and no secrets are stored"],"depends_on":[],"goal":"Install the ACS multi-agent-hotload 0.1.0 module (with full PCM 0.6.0 and full CGM 0.5.12) in the Pukujan/paseo fork, pinned to release train 2026-10-01, and prove it with the pinned validators in a gates check.","id":"PSO-0001","issue_url":"https://github.com/Pukujan/paseo/issues/1","next_action":"Let auto-merge land the pull request once its checks are green, then post the receipt on issue #1.","owner":"Alex; executor agent installs","priority":"P1","protocol_version":"0.1.0-draft","schema":"project-continuity.task.v1","status":"active","why":"Agents working on this fork need a checkpoint to resume from, a shared record of the decision-boss seat and a CI check for that setup, without changing Paseo's own code."} -->

- Status: active
- Owner: Alex; executor agent installs
- Priority: P1
- Depends on: none

## Goal

Install the ACS multi-agent-hotload 0.1.0 module (with full PCM 0.6.0 and full CGM 0.5.12) in the Pukujan/paseo fork, pinned to release train 2026-10-01, and prove it with the pinned validators in a gates check.

## Why

Agents working on this fork need a checkpoint to resume from, a shared record of the decision-boss seat and a CI check for that setup, without changing Paseo's own code.

## Allowed files

- `.continuity/`, `schemas/v1/`, `PROJECT.md`, `HANDOFF.md`, `checkpoints/CURRENT.md`, `tasks/`
- `.content-system/`, `.coord/`, `stack-manifest.json`
- `.github/workflows/acs-gates.yml`

## Human outcome

An agent opening this fork finds a checkpoint to resume from and a record of who holds the decision seat, and the `gates` check catches a broken stack setup before it reaches `main`.

## Scope and boundaries

- In scope: the hot-loader install copied from Pukujan/agent-manager-gui (issue #1, PR #3), with project text rewritten for this fork.
- Out of scope: Paseo's runtime code, packages, lockfile and existing workflows; `AGENTS.md` and `CLAUDE.md`; the OIO issue form and triage workflow; the agent-less watchdog workflow.
- Dependencies/uncertainty: `AGENTS.md` is a symlink to upstream's `CLAUDE.md`. `continuity init` ran in a scratch folder and everything except its `README.md` and `AGENTS.md` was copied in. The OIO installer refuses symlinked targets, so OIO is named in `stack-manifest.json` (the train check requires it) but its files are not installed. That needs Alex's call on a later issue.

## Acceptance criteria

- [ ] the pinned ACS hotload_check.py prints `hotload_check: OK` against this repository
- [ ] PCM continuity files and the nine pinned schemas are present and `continuity validate` prints VALID
- [ ] the CGM 0.5.12 adapter lists all eight modules and the pinned validate_content_system.py prints VALID
- [ ] the .coord assignment, boss claim and stack-manifest.json are pinned to release train 2026-10-01 and the train's check_manifest.py passes
- [ ] the `gates` check passes on the pull request and Paseo's own format and lint checks still pass on the new files
- [ ] no Paseo runtime code, package manifest, lockfile or existing workflow changes, and no secrets are stored

## Evidence and sources

Link repository state at a revision and cite external factual claims directly. Record commands and results for claims that need verification.

## Reproduction details (only when needed)

Starting revision, material inputs/configuration, runtime, exact command or prompt, observed result, and limitations.

## Related records

- Leaf issue: https://github.com/Pukujan/paseo/issues/1. Parent: https://github.com/Pukujan/agent-manager-gui/issues/2. Dependencies: none.
- Primary writer: executor agent for Alex. Branch: `task/PSO-0001-install-acs-hotload`. As of 2026-10-04: active, pull request being opened.
- PR and CI evidence: pending. Check results and the merge commit go on issue #1 once the pull request merges.

## Checkpoint log

No checkpoints yet.

### 2026-10-04 17:36:28 UTC — executor-paseo

<!-- continuity:checkpoint {"agent":"executor-paseo","blocked":["OIO files not installed (AGENTS.md symlink); needs Alex's call on a later issue."],"changed":[".content-system/, .continuity/, .coord/, .github/workflows/acs-gates.yml, HANDOFF.md, PROJECT.md, checkpoints/CURRENT.md, schemas/v1/, stack-manifest.json, tasks/"],"completed":["This fork had no checkpoint, no shared record of the decision-boss seat and no check for the agent stack, so the ACS multi-agent hot-loader 0.1.0 was installed: PCM files via continuity init (overlay, without README.md and AGENTS.md), a hand-written eight-module CGM adapter, .coord state, stack-manifest.json and an acs-gates workflow."],"decisions":["AGENTS.md is a symlink to upstream CLAUDE.md, so neither is edited; the stack notes live in HANDOFF.md. OIO is pinned in stack-manifest.json because the train requires it, but its installer refuses symlinked targets, so its files wait for Alex's decision."],"evidence":["All pinned validators passed on the box at 76d2e7c: release-train check_manifest OK (4 components), continuity validate VALID (one warning: AGENTS.md links to upstream CLAUDE.md and has no PCM issue-log marker), CGM validate_content_system VALID, hotload_check OK. Paseo's oxfmt 0.46.0 --check and oxlint 1.61.0 were clean and scripts/ci-workflow.test.mjs passed 9 of 9."],"next_action":"Open the pull request linked to issue #1 and let auto-merge land it once the checks are green.","protocol_version":"0.1.0-draft","schema":"project-continuity.checkpoint.v1","task_id":"PSO-0001","timestamp":"2026-10-04T17:36:28Z"} -->
<!-- continuity:checkpoint-operation {"payload_sha256":"5da6193d1295e6879b8086fe2f5cf45dcfd2ba407c4aa9796b25cf57cc212232","request_id":"16ff43eae3c04d4d96b9f81b7e1a666b","schema":"project-continuity.checkpoint-operation.v1","task_id":"PSO-0001"} -->

Completed:

- This fork had no checkpoint, no shared record of the decision-boss seat and no check for the agent stack, so the ACS multi-agent hot-loader 0.1.0 was installed: PCM files via continuity init (overlay, without README.md and AGENTS.md), a hand-written eight-module CGM adapter, .coord state, stack-manifest.json and an acs-gates workflow.

Evidence:

- All pinned validators passed on the box at 76d2e7c: release-train check_manifest OK (4 components), continuity validate VALID (one warning: AGENTS.md links to upstream CLAUDE.md and has no PCM issue-log marker), CGM validate_content_system VALID, hotload_check OK. Paseo's oxfmt 0.46.0 --check and oxlint 1.61.0 were clean and scripts/ci-workflow.test.mjs passed 9 of 9.

Decisions:

- AGENTS.md is a symlink to upstream CLAUDE.md, so neither is edited; the stack notes live in HANDOFF.md. OIO is pinned in stack-manifest.json because the train requires it, but its installer refuses symlinked targets, so its files wait for Alex's decision.

Changed:

- .content-system/, .continuity/, .coord/, .github/workflows/acs-gates.yml, HANDOFF.md, PROJECT.md, checkpoints/CURRENT.md, schemas/v1/, stack-manifest.json, tasks/

Blocked/uncertain:

- OIO files not installed (AGENTS.md symlink); needs Alex's call on a later issue.

Next:

- Open the pull request linked to issue #1 and let auto-merge land it once the checks are green.

## Handoff

Read PROJECT → CURRENT → this task → minimum relevant spec. Checkpoint before stopping.
