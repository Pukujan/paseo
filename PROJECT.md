# Paseo (Pukujan fork) — Project Contract

<!-- continuity:project {"id":"paseo-pukujan-fork","protocol_version":"0.1.0-draft","schema":"project-continuity.project.v1","title":"Paseo (Pukujan fork)"} -->

<!-- pcm:github-progression:start -->

## GitHub-owned progression

GitHub Issues are required for PCM-governed project work and own task scope, acceptance, priority, ownership, dependencies, lifecycle and durable project progression. Merged default-branch history owns accepted code and normative/domain documents; PR checks and merge records own delivery facts. Checked-in PROJECT/CURRENT/TASK/checkpoint/handoff documents are mandatory versioned projections for task state, not a parallel authority. Local files, registries, context packs and chat are ephemeral execution aids. Domain-document ownership stays with the target project.

Every issue progress update MUST link the leaf child issue that owns the work, its parent ancestry and dependencies (or explicitly none). A top-level deliverable identifies itself as the leaf and says parent: none. Create one child per independently deliverable scope, never one per comment. Record task ID, primary writer and branch on the issue before creating its repository projection. Re-read live issues and relevant source revisions before resuming; the issue verifier checks identity/status, not semantic agreement.

Authorized owner/user direction can revise intent: record it on the owning GitHub issue with a correction/supersession link before dependent work. It cannot alter observed CI/merge facts or waive required gates. Stale projections yield to their field's authority. If direction, ownership or evidence conflicts remain unresolved, pause affected work and record uncertainty; continue independent safe work. One primary writer owns each task branch/checkpoint stream. Coordinate shared-document edits through linked issues/PRs, re-read the current base and reconcile concurrent changes; never force-push or overwrite another writer. Issue prose is not an atomic lock.

Label observed results, repository/external evidence, agent reports and inference separately. Preserve contradictory evidence with source/revision and mark conclusions disputed or unknown until resolved. Append correction/supersession evidence; never rewrite checkpoint history. An upstream correction MUST identify affected descendants and assumptions on their issues; pause, re-plan and revalidate dependent work before resuming. Follow explicit parent/dependency links within the affected scope; cycles or unknown lineage block affected claims. No graph database, local canonical ledger or autonomous polling agent is required.

Before every push, synchronize relevant docs and task/checkpoint projections, CURRENT/HANDOFF when affected, and reviewed catalog/generated index. Record leaf/parent/dependency links, source issue/comment revision, as-of status, evidence, blockers and next action. Commit product/docs first; `continuity checkpoint` then commits and synchronously pushes the checkpoint with a stable request ID. After every successful push, manually publish a leaf issue receipt keyed by request ID and exact pushed SHA, linking changed docs/checkpoint, PR, tests and pending gates; add a linked parent progression update. Retry a missing receipt without another checkpoint/push; inspect for the same key before posting. --receipt-repo and --receipt-issue are opt-in and still require a proven lookup; omit them and the receipt stays manual. Automatic issue-comment synchronization is not implemented; issue #67 is CLOSED (owner freeze decision 2026-09-25) and its unmet guaranteed-completion acceptance transferred to #110.

Required CI and GitHub auto-merge are mandatory. Arm auto-merge only after the increment's final push: a later push races the merge window and strands outside accepted history. Verify protection, required reviews/checks on the exact current-base or merge-queue candidate, and auto-merge; missing, failed, skipped, stale or unverified gates fail closed: no completion or cleanup. After CI/merge, append the exact check results, PR/merge SHA and live issue status to the leaf and link the parent update; fetch and verify accepted history. Reconcile material doc/status corrections in a new synchronized increment. Receipt-only transitions need no recursive doc commit: docs retain an explicit as-of/pending state and point to the live issue. Never label local-only or merely pushed work delivered. Preserve unsafe resources and keep incomplete issues open.

<!-- pcm:github-progression:end -->

## Main goal

Keep a working copy of [Paseo](https://github.com/getpaseo/paseo) that agents can change for Alex's agent manager, while it stays easy to sync with upstream.

## Why

Alex adopted Paseo instead of building an agent manager from scratch ([Pukujan/agent-manager-gui#2](https://github.com/Pukujan/agent-manager-gui/issues/2)). Most gaps should be fixed upstream first. This fork is where those fixes are prepared and tried, and where a fix lives if upstream won't take it.

## Scope

- Small, reviewable changes to Paseo for gaps found while running it on Alex's machines, each with its own issue in this fork.
- The agent stack files that let several agents share the fork: continuity (PCM), writing rules (CGM) and the ACS multi-agent hot-loader in `.coord/`.
- Keeping `main` in step with `getpaseo/paseo` `main`.

## Non-goals

- Renaming the fork or drifting from upstream without a reason recorded on an issue.
- Editing upstream's agent instructions (`CLAUDE.md`, which `AGENTS.md` links to). Stack rules for this fork live in `HANDOFF.md` and `.coord/`.
- Storing secrets, host passwords or private paths in the repository.

## Definition of success

An agent opening this fork knows what to work on and who holds the decision seat, every change reaches `main` through a pull request linked to an issue, and upstream syncs stay conflict-free outside the files a task actually changed.
