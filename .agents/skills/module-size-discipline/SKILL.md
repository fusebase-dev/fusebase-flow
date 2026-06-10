---
name: module-size-discipline
description: Use when planning tasks that touch big source files, when an edit would push a file past the module-size ceiling, when the pre-commit module-size ratchet warns or blocks, or when generating policies/module-size-baseline.txt. Operationalizes FR-25 — module-size ratchet (ceiling default 800; over-ceiling files may shrink, never grow; extraction along a responsibility seam is in-scope, not scope creep). Do NOT use for docs/markdown size (FR-23 owns docs), to force decomposition of an existing monolith (that is its own explicit ticket), or to judge split quality by regex (seam-vs-mechanical is semantic — code-review owns it).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: "3.16"
risk_level: medium
invocation: automatic
expected_outputs:
  - per-task target-file declarations (tasks.md) with extraction-or-exemption for over-ceiling targets
  - extraction into a new module along a responsibility seam, or an explicit exemption
  - policies/module-size-baseline.txt via operator-run --write-baseline
related_workflows:
  - greenlight-implement.md
  - verification-gate.md
  - lightweight-lane.md
hook_dependencies:
  - hooks/git/pre-commit (module-size step)
---

# Module-Size Discipline (FR-25)

## Purpose

Stop source files from accreting into monoliths nobody (human or agent) can load in one pass. Source in a Flow workflow is AI-read (FR-22/FR-24 audience principle): a 19k-line file forces slice-reads on every future session. Monoliths are the integral of N individually-reasonable diffs — no single diff is ever flagged — so the framework gates the accumulating dimension deterministically (line count is objective, unlike FR-22/FR-23 semantics) and steers extraction at plan- and write-time.

## The ratchet (deterministic gate)

Config: `policies/module-size.yml` (`ceiling` default 800 · `source_globs` · `exempt_globs` · `baseline_file` · `enforcement` · gitignored `module-size.local.yml` override). Engine: `hooks/shared/module_size.py`, wrapper `hooks/local/check-module-size.sh`, wired into `hooks/git/pre-commit`.

| Case | Verdict |
|---|---|
| Gated file NOT in baseline, lines ≤ ceiling | pass |
| Gated file NOT in baseline, lines > ceiling | **BLOCK** — extract or get operator exemption |
| Baselined file, lines ≤ its baseline value | pass (shrinking/holding is always fine) |
| Baselined file, lines > its baseline value | **BLOCK** — over-ceiling files may not grow |
| File matches `exempt_globs` | never gated |
| No `baseline_file` committed | **warn-only** + generation instruction (adoption-safe) |

Modes: `--staged` (pre-commit default) · `--worktree` (vs HEAD; optional Stop-hook wiring) · `--all` (full scan; also a CI step in `fusebase-flow-verify.yml`) · `--write-baseline` (**operator-run only** — freezes current over-ceiling files; commit the result; presence switches warn → block) · `--write-baseline <path>` (re-keys ONE row — the targeted refresh; a full regen grandfathers every current violation, so prefer the single-file form).

Baseline shipping: the template **ships its own committed baseline**, so the gate is live from commit #1 on greenfield instantiations. Installing into an **existing** repo: regenerate it once (`--write-baseline`, then commit) right after copying — until then legacy over-ceiling files block on first touch (the block message prints this exact remedy).

Local override (`policies/module-size.local.yml`, gitignored) is **additive-only**: it may append `exempt_globs` / `source_globs` entries; `enforcement`, `ceiling`, and `baseline_file` cannot be overridden locally (a gitignored kill switch would disarm the gate invisibly). The engine prints a notice whenever a local override is active.

Rename tripwire: the baseline keys by path — after renaming a baselined over-ceiling file, its first content edit blocks (fail-closed, zero-growth included) until the operator re-keys it: `--write-baseline <new-path>` (and the old row disappears on the next targeted or full refresh; stale rows for absent files are inert).

## Plan-time rule (where the problem starts)

In `implementation-planning` / `tasks.md`: **every task names its target file(s)**. A task targeting an over-ceiling file must either (a) extract the addition into a new module, or (b) carry a one-line exemption with reason. "Where does this code live" is a cheap question at Plan and a never-asked question mid-implement.

## Write-time rule (AI Developer)

- An edit that would push a gated file over the ceiling, or grow an already-over-ceiling file → extract along a **responsibility seam** (a nameable concern), not a mechanical `utils2.ts` split.
- That extraction is **in-scope for the task**: it is NOT scope creep and NOT by itself an FR-21 promotion trigger. (FR-21 interplay — see `lightweight-lane`.)
- Never bypass with `--no-verify` (FR-06). Remedies: extract, or surface the exemption question to the operator (FR-19).

## Exemptions (deliberate, reviewable)

Justified monolith classes go in `exempt_globs`: generated code (SDK/OpenAPI output), lockfiles, vendored complete-file mirrors, data-as-code catalogs/fixtures, migrations. Exemption is a policy edit the operator sees — never silent.

## What this skill does NOT do

- No forced refactor: existing monoliths freeze at baseline; decomposition is its own (usually Full-lane) ticket with its own risk assessment.
- No split-quality regex: seam-vs-mechanical is semantic — `code-review` checks it by reading.
- No docs gating: artifact/doc size is FR-23's axis.

## Anti-patterns

- Splitting mechanically to satisfy the gate — observable criterion: an extraction landing in a file whose name does not state a responsibility (`utils2`, `helpers2`, `misc`, `extra`, `more`-style names) is a review blocker; a named seam is judged by reading.
- Raising the baseline to make a violation pass — `--write-baseline` is operator-run, never agent-initiated; prefer the single-file form so refreshes are never global amnesties.
- Treating the ratchet warning as noise in warn-only mode — surface it to the operator with the activation instruction instead.
- Adding `exempt_globs` entries for ordinary source because extraction is inconvenient.

## Clean-room note

Original Fusebase Flow content. Ratchet-style size gating is common public CI practice (grandfathering + no-growth baselines); no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
