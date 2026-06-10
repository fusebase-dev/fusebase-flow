# Decisions — module-size-discipline (FR-25)

**Status:** LOCKED (operator approved all-recommended 2026-06-10; spec Q-A..Q-E)
**Letter prefix:** M

| ID | Decision | Alternatives rejected (why) |
|---|---|---|
| M1 | Gate = `hooks/shared/module_size.py` (logic; stdlib + PyYAML) + thin wrapper `hooks/local/check-module-size.sh`; invoked from `hooks/git/pre-commit` (new step between protected-paths and lint). Modes: `--staged` (pre-commit default), `--worktree` (diff vs HEAD; opt-in Claude Stop wiring), `--all` (full scan), `--write-baseline`. | Lifecycle handler under `hooks/handlers/` (those carry the JSON-stdin event contract — wrong shape for a git hook); Node script (new runtime; Windows CVE history); pure-bash glob matching (no `**` semantics). |
| M2 | Ratchet semantics: file matching `source_globs` minus `exempt_globs` → (a) NOT in baseline + lines > ceiling → BLOCK; (b) in baseline + lines > ceiling + lines > baseline value → BLOCK; (c) otherwise pass. Baseline = committed `policies/module-size-baseline.txt` (`<lines> <path>` rows). `--write-baseline` (re)generates; auto-tightens (lower/remove rows), never raises silently. | Hard ceiling without ratchet (forces big-bang refactors of legacy monoliths — rejected by spec); auto-raising baseline on commit (defeats the ratchet). |
| M3 | Defaults in `policies/module-size.yml`: `ceiling: 800`; `source_globs` = common code extensions; `exempt_globs` = deps/build/generated/lockfiles/minified + `.fusebase-flow-source/**`; `local_override_file: policies/module-size.local.yml` (gitignored; top-level keys override) — same posture as `comment-policy.yml`. Markdown/docs NOT in source_globs (FR-23 governs docs). | Per-language ceilings (config bloat; projects tune via local override); including `*.md` (skills/docs have their own budget rules). |
| M4 | No baseline file ships in the template → gate runs **warn-only** with a generation instruction until `policies/module-size-baseline.txt` is committed (spec Q-D). Greenfield template users generate an empty baseline at ticket #1; legacy-repo installs generate a populated one. | Shipping an empty baseline (blocks legacy-repo installs on first touch of any pre-existing big file — violates Q-D adoption-safety). |
| M5 | Tests: new `hooks/tests/test-module-size.sh` (self-contained temp git repo; 6 deterministic scenarios) invoked by `run-tests.sh` as a second phase; totals reported together (16 fixtures + 6 scenarios = 22). | JSON fixtures through the existing runner (that harness is handler-stdin-shaped; module-size is a git-context check). |
| M6 | Steering/plan-time delivery mirrors FR-22/24 precedent: FR-25 row+implication in FLOW_RULES; one digest row in role-discipline § Write-time discipline digest; `code-review` step 5c dimension + failure rows; `implementation-planning` step 6 target-file rule + anti-pattern; `templates/tasks.md` per-task `Module-size (FR-25)` line; `lightweight-lane` interplay note (extraction-to-satisfy-ratchet is in-scope, not scope creep / not by itself a promotion trigger); `session_start.py` reminder broadened. | New always-on skill (rejected for FR-24 already — context tax); regex gate for split QUALITY (seam-vs-mechanical is semantic → review-time only). |
| M7 | Commit strategy: single release commit + annotated tag `v3.16.0`, direct to origin main with `--follow-tags` (precedent v3.12.0–v3.15.0). Independent reviewer agent validates pre-commit. | Per-task commits (v3.11.0 style) — heavier; operator asked for execute→review→ship in one pass. |

## Cross-refs

- Spec: `docs/specs/module-size-discipline/spec.md` (LOCKED)
- Skill (new): `flow-skills/module-size-discipline/SKILL.md`
- Precedent: FR-22 carve-out policy (`policies/comment-policy.yml`), FR-24 digest (`flow-skills/role-discipline/SKILL.md:405`)
