# Changelog

All notable changes to Fusebase Flow. Format follows [Keep a Changelog](https://keepachangelog.com/) (lite). This project follows the conventions in `PUBLISHING.md` for cutting releases.

Public release versions ship as annotated git tags on `main`. Per-version detail lives in `docs/release-notes/v<version>.md`.

## [5.11] — 2026-10-16

**One validator run, honest gate rows, watched waits, a project tool profile.** From a review of 5.10
against one consumer's measured release. Pre-commit runs lint and typecheck once (the separate
validator pass and the dead receipt-reuse code are gone) and prints per-stage timings; a project may
declare docs-only paths (`policies/validator-free-paths.yml`, absent by default) whose commits skip
lint and typecheck while the secret scan, protected paths and module size still run. FR-13 reads
"Lint+typecheck per code commit (declared docs-only paths skip)". The command policy refuses
`git commit -n` clusters, abbreviated `--no-veri…` options and any `core.hooksPath` setting form.
Gate reports carry PASS/FAIL rows with their own evidence and the verdict belongs to the Product
Owner side (gate rounds share the 2-round bound); `verify-gate.sh` validates values. A committed
`policies/agent-tools.yml` generates `<agent>-project` agent variants beside untouched Flow mirrors;
tasks declare their inputs. Liveness guidance watches hangs from outside with documented wake paths;
`bounded_run` writes a heartbeat file and `bounded_wait` is new; `liveness` joins the release gate
(47 tags). Smaller: task-delegation unattended-run and pending-answer rules, smoke live-run
discipline, slice-first reading, token-waste-audit advisor pricing and wall-time lens, the 1h cache
break-even, find-wasted-effort template linking, one Git Bash locator for Windows tests, hygiene.
Four hook handlers (`pre_tool_use`, `user_prompt_submit`, `post_tool_use`, `session_start`) now
reply in the format Claude Code accepts (`flow_decision` plus the host channel), so wired projects
stop seeing hook-error notices and their warnings reach the model.
Not shipped: the Stop-hook rework (failed its final review; the next release retires the Stop gate).
See `docs/release-notes/v5.11.md`.

## [5.10] — 2026-10-12

**The orphan watcher now works on Windows.** When a test run was killed, the watcher that stops its
child processes only noticed once the run's parent had collected it; on MSYS that could take many
seconds or never happen, leaving children alive. It now detects the exit itself (`/proc/<pid>/exe`
gone and state `Z`), acting within one poll of the run exiting — about 1–2 s on an idle host — and
on hosted Windows detects in 29–622 ms with no survivors. The `signal-reap` release check gates on the
watcher's own heartbeats and on no descendant surviving when it finishes, instead of wall-clock limits.
`task-delegation`'s correction-ownership fallback reads as the stricter rule. Test-only hardening for
the secret-pattern matrix and token-audit fixtures; three follow-ups filed in the backlog.
**Drop-in from 5.9.** See `docs/release-notes/v5.10.md`.

## [5.9] — 2026-10-11

**Fixes from a FuseBase CLI update escalation, plus the v5.8 follow-ups.** `.git/info/exclude` now
covers `/policies/*.local.yml` and `/.claude/worktrees/`, so the CLI's `git add -A` checkpoint no longer
stages them into Flow's protected-path block (the install snippet uses the glob; `.gitignore` is never
touched). `post-fusebase-update.sh` without `--refresh-overlays` compares against the pre-run bytes and
reports a line-endings-only difference as an exit-0 advisory instead of "Recovery uncertainty"; the
heading migration moved to Python and no longer rewrites every CRLF on Windows. The six key secret
patterns are anchored (word boundary, or glued with a digit and an uppercase letter; bounded lookahead),
so URL slugs stop matching, with a new release-gated `secret-patterns` phase. New approval rule:
`fusebase isolated-store sql bundle … --apply` requires `database_migration` in every environment.
Delegated returns carry a context field read by correction ownership; TE-20 gives the break-even per
cache-read price; `/token-waste-audit` measures send-to-send gaps, counts polling repeats correctly and
marks observed vs estimated cost. **Drop-in from 5.8.** See `docs/release-notes/v5.9.md`.

## [5.8] — 2026-10-08

**`/token-waste-audit` sees the whole run, and the guidance targets the real cost drivers.**
Measured on three consumer runs, sub-agents were 77–84% of the cost and the audit never read them;
its "large output" rows were screenshots sized as base64 text. The audit now parses sub-agent and
workflow-agent transcripts (`--main-only` keeps the old scope), counts images as images, opens with a
list-price cost estimate by category, and flags transcripts whose context peaked past 500k and cache
rewrites after the cache lifetime expired, capped at 10 rows per class per session. New
`token-economy` rows TE-19 (bounded context: ~50 tool calls per worker, fresh worker for larger
work and for fixes once a worker is large), TE-20 (wake on events or check at least every 4 min with
a bounded check loop; the 60–90 s poll stays only for a delegate that never started) and TE-21
(compare screenshots by script, read each once, always view the decisive capture). FR-17: offering
to continue from the handoff in a fresh session at a milestone is forward momentum (offered once
after a compaction or 3 closed outcomes; the operator opens the session). One canonical sub-agent
start-up text; `AGENTS.md` is read unless its Flow section is already in context (Codex loads only
the first 32 KiB). Operator settings such as `autoCompactWindow` are documented, not defaulted.
**Drop-in from 5.7.** See `docs/release-notes/v5.8.md`.

## [5.7] — 2026-10-05

**The model-routing worked example names current models.** The commented example in
`policies/model-routing.yml` now shows one operator's current setup: Opus 5.5
(`claude-opus-5-5`) for planning, implementation and execution, and GPT-6 Astra (`gpt-6-astra`)
for adversarial review with GPT-6.1 Sol (`gpt-6.1-sol`) as its backup, with effort noted as
comments. It is still an example only: the five shipped rows stay `null` and `/step-out` names no
model. **Drop-in from 5.6.** See `docs/release-notes/v5.7.md`.

## [5.6] — 2026-10-01

**Same changes as 5.5, which was tagged but never published.** GitHub's Windows test runner froze
during the 5.5 release run, and the run could be neither cancelled nor re-run. 5.6 ships the same
content with new version strings; see [5.5] below for the changes. **Drop-in from 5.4 or 5.5.** See
`docs/release-notes/v5.6.md`.

## [5.5] — 2026-09-30

**The upgrade clone stays out of commits, pre-commit lint/typecheck failures name the project's
command, and `/fusebase-health` flags split `@fusebase/*` installs.** Every `upgrade.sh`,
`bootstrap-upgrade.sh` and `post-fusebase-update.sh` run now adds `/.fusebase-flow-source/` to
`.git/info/exclude`, and the template `.gitignore` lists it, so the FuseBase CLI's pre-update
`git add -A` checkpoint no longer commits the clone as an embedded repository (gitlink, no
`.gitmodules`); `docs/fusebase-cli-edition.md` gains the cleanup/ESLint section the `AGENTS.md`
pointer names. The pre-commit BLOCK line for a failing lint or typecheck now quotes the project's
command and its exit code and says the failure is in the project, not in Flow. In a FuseBase CLI
project the health check resolves every `@fusebase/*` dependency across `package.json` roots the
way Node does and prints a verdict-neutral line when one package is installed at more than one
version (separate SDK copies break `instanceof ApiError`); the advisory section is renamed "CLI
advisory", and verdict, counts and exit code are unchanged. The split's root cause, `fusebase
update` rewriting only the root and SPA `package.json`, belongs to the FuseBase CLI. A blocking
pre-commit SDK version check was considered and not shipped: it would block the CLI's own
checkpoint commit. **Drop-in from 5.4.** See `docs/release-notes/v5.5.md`.

## [5.4] — 2026-09-17

**New `/step-out` command for unattended runs, review depth tied to severity with a durable
two-round cap, and optional model-tier routing.** `/step-out` is the eighth slash command:
invoked with an explicit absence grant ("I'm stepping out", "run this unattended"), it records
that grant verbatim in the run-ledger (`docs/tmp/handoff.md`) and continues every authorized,
unblocked slice. Three limits ship with it — the grant dies with the run (a later session
inherits the ledger, never the grant); it satisfies "the operator asked" but **opens no gate**,
so an unmet gate parks that slice as `BLOCKED-AT-<gate>` while the run continues elsewhere; and
a question it cannot settle read-only is recorded with options and a clearing condition rather
than guessed. `task-delegation`'s always-loaded description now carries the absence trigger, so
routing works even for a single simple edit. `code-review` gains § Review depth and severity:
BLOCKER/HIGH/MEDIUM/LOW grading, independent adversarial review for security-relevant,
cross-cutting or HIGH-risk diffs and a focused pass otherwise, and a **review round cap of 2
that is now durably recorded** (in the review record, else the run-ledger) so a fresh session
inherits the count instead of restarting it — only the operator can raise it, and exhaustion
never makes a blocker shippable. `task-delegation` gains §§ Model routing · Correction ownership
· Unattended scheduling; the new `policies/model-routing.yml` maps five work properties to a
model and **ships inert** — all five rows `null`, Flow names no model, no loader resolves the
selectors, and an absent or unreachable selector is a recorded fallback that never stops a run.
A tier selects a model, never authority. README gains "How it keeps context cost down", which
publishes **no percentage or savings figure** because no controlled measurement exists; every
number in it is readable out of this repository. **Drop-in from 5.3** — no hook behavior,
installer, approval, gate or role-boundary change. See `docs/release-notes/v5.4.md`.

## [5.3] — 2026-09-14

**Agents now follow the four Karpathy coding guidelines, and comment cleanup is scoped to the
task.** **Behavior change:** `comment-policy` (FR-22) applies its "remove everything else" rule
only to comments the task introduces or necessarily changes. Agents no longer trim pre-existing
comments beside an edit, and `code-review` no longer flags them; unrelated comment cleanup is a
separate task. New `flow-skills/zoom-out/references/karpathy-guidelines.md` (Think Before Coding,
Simplicity First, Surgical Changes, Goal-Driven Execution) is read by the AI Developer before the
first code edit and used by `zoom-out`, `code-review` and delegated code-edit workers; overlapping
Flow wording now points to it. The guidelines are imported verbatim under the MIT License from
`multica-ai/andrej-karpathy-skills`; attribution is in the file header and
`docs/source-map.md#karpathy-guidelines`. **Drop-in from 5.2** — no hook, policy, installer or
upgrade change. Internal: maintainer-checkout `.gitignore` rules (not delivered to installed
projects), maintainer ask-boundary wording, tracked E8/E9 decision records, the `v5.2`
fingerprint row. See `docs/release-notes/v5.3.md`.

## [5.2] — 2026-09-13

**Versioning moves to two-part `MAJOR.MINOR`.** From this release versions drop the patch
component (`5.2`, `6.0`; tags `v5.2`, …). The jump from 4.17.1 consolidates the 4.17.x
approval-binding command-authorization cutover into a clean major line. **Drop-in from 4.17.1 —
no runtime behavior change beyond 4.16.x–4.17.1.** Historical three-part version strings stay
recognised. **Supersedes the unpublished `v5.1`** (its release gate went red on a test-only
version-lag fixture that assumed a three-part string; no Release was published, tag stays
immutable).

Maintainer and gate-hardening content: test-harness fixes that reach a consumer's own gate (the
suite uses the resolved interpreter instead of a bare `python` on Linux; a killed gate reaps its
orphan process group on Windows/MSYS), and `signal-reap`, `health-check-timeout` and
`preboundary-consumed` promoted into the essential release profile. Internal: gate-bounds cost
attributed with measured timings (no wall changed), a git-context oracle corrected, a convergence
discriminator added, a proposed FR-28 drift-checkpoint rule reviewed and declined, and the
publisher-packaging parity fixture made part-count-agnostic (test-only; the fix that unblocks the
two-part scheme). See `docs/release-notes/v5.2.md`.

## [5.1] — 2026-09-13

**Versioning moves to two-part `MAJOR.MINOR`.** From v5.1 releases drop the patch component
(`5.1`, `5.2`, `6.0`; tags `v5.1`, …). The jump from 4.17.1 consolidates the 4.17.x
approval-binding command-authorization cutover into a clean major line. **Drop-in from 4.17.1 —
no runtime behavior change beyond 4.16.x–4.17.1.** Historical three-part version strings stay
recognised.

Maintainer and gate-hardening content: test-harness fixes that reach a consumer's own gate (the
suite uses the resolved interpreter instead of a bare `python` on Linux; a killed gate reaps its
orphan process group on Windows/MSYS), and `signal-reap`, `health-check-timeout` and
`preboundary-consumed` promoted into the essential release profile. Internal: gate-bounds cost
attributed with measured timings (no wall changed), a git-context oracle corrected, a convergence
discriminator added, and a proposed FR-28 drift-checkpoint rule reviewed and declined. See
`docs/release-notes/v5.1.md`.

## Earlier releases

4.17.1 and older: `docs/release-notes/CHANGELOG-pre-5.md`.
