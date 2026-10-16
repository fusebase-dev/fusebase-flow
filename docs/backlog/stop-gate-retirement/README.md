# stop-gate-retirement

**Status:** open — 6.0.0 rebuild, **wave 1**, with a wave-3 tail. Closes `typed-stop-claim-and-subagent-stop` and `hook-output-host-validity`; folds in `enforcement-only-hook-wiring`. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 11, handler retirement and wiring detection (R §2). **Surface:** `hooks/handlers/{stop,user_prompt_submit,pre_compact,permission_request,session_start}.py`, `policies/required-artifacts.yml`, their fixtures, the wiring detection in `hooks/local/fusebase-flow-health-check.sh:251-275`, `hooks/local/check-cli-flow-conflicts.sh:403-449`, `hooks/local/fusebase-flow-overlays/settings-json-merge.py:22-29`, `hooks/local/post-fusebase-update.sh`, `.claude/settings.json.example`. **FR-07:** yes for the removal commit (`hooks/handlers/**`, `policies/*.yml`); the re-key commit is maintainer code and not protected.

## Delivers

- **The Stop keyword gate goes, in every form** (H non-negotiable 3), with its second-refusal warning (R2, decision H) and the unshipped O17 rework (R §6). `policies/required-artifacts.yml` goes with `stop.py`, its only reader.
- **Five handlers removed** (R §3 "Not in the list"): `stop.py`, `user_prompt_submit.py`, `pre_compact.py`, `permission_request.py`, `session_start.py` (dropped: it holds no input-tools check; `BLOCKED-AT-input` is the slicer's, R §3 answers table). Their fixtures retire, and the kept-fixture denominator in `hooks/tests/run_hook_tests.py` drops to the 13 kept `pre_tool_use` fixtures plus the new `post_tool_use` ones. The stop arms of `test-fr22-delivery-guarantee.sh` and `test-po-verifiable-boot.sh` go in the same commit; the rest of those suites retire with `eight-rule-kernel-and-cards`.
- **Hooks-wired detection re-keyed onto the two kept handlers** (H non-negotiable 4; R §3): today the health engine counts the Flow event set and greps for `stop.py` (`fusebase-flow-health-check.sh:251-275`), the conflict reporter gates its CLI Stop checks on `has_flow_stop` (`check-cli-flow-conflicts.sh:403`), and the merge map writes six events including `SessionStart`, `UserPromptSubmit`, `Stop` and `PreCompact` (`settings-json-merge.py:22-29`). After the change the map is `PreToolUse`, `PostToolUse` and `PostToolUseFailure`; the Stop append and the `.claude/settings.json.example` Stop, SessionStart, UserPromptSubmit and PreCompact blocks go; `CLI_STOP_UNVERIFIED` and `CLI_STOP_BASELINE_DRIFT` retire with the CLI-stop baseline receipt, because Flow no longer writes the Stop chain. The model is the exact-command match `hooks/local/lib/hook-wiring-intent.sh` already uses (`FFHC_HWI_HANDLER`, `:30`).
- **Wave-3 tail** (plan proposal): once `heartbeat-reader` ships `hooks_state()`, the maintainer engines call it instead of their own match, so one implementation decides "wired" (R §3).
- Wired projects: `flow-migrate` removes exactly the retired handlers' canonical entries when the wiring intent is enabled (R §2 WP 12); without that, `run-handler.sh` prints "handler not found … skipping (allow)" on every retired event (`hooks/local/run-handler.sh:88`). A wired maintainer clone needs its settings re-merged after this commit.
- **`enforcement-only-hook-wiring`:** with only the two enforcement and audit handlers left in the merge map, ask 1's "wire only enforcement" is the default shape and the mint-then-trim procedure is no longer needed; ask 4 (consumer-declared chain expectations) is not built in 6.0.0 and stays described in that entry.

## Decisions and asks carried

| Item | Effect here |
|---|---|
| H non-negotiable 3 (no Stop gate in any form) | Removal |
| R2 and decision H (Stop refusal warning); O17 | Retired with the Stop gate (R §6) |
| Decision 9 / ask 9 (hooks wired per provider) | Detection keys on the two kept handlers per provider |
| R §3 (`session_start.py` dropped; hooks-wired detection moves off `stop.py`) | Removal and re-key |
| Backlog `hook-output-host-validity` | Closed: the three handlers still on the old reply format are removed |

## Estimate

Share of R §2 WP 11 (21.5 to 29.5 agent-h for the four WP 11 entries): 7.5 to 9.5 (mid 8.5), the largest part being the re-key across two engines, the merge script, two examples, the skill row in four copies and seven test suites (about 6 agent-h in the team's WP 11 analysis). Hosted proof includes the `cli-flow-recovery` groups, which run near their 1800 s wall on MSYS (`docs/backlog/gate-bounds-lack-headroom/`).

## Depends

`core-hook-inventory` (the `run-handler.sh` no-Python marker lands before `session_start.py`, which carries today's only warning, `run-handler.sh:80`), `audit-line-command-hash` (same example and merge files: serialize). Blocks: `flow-migrate` (the retired-entry cleanup), `heartbeat-reader`'s `hooks_state()` adoption (wave-3 tail).

## Acceptance

1. The hooks-wired detection no longer looks for `stop.py` (H WP 11); a settings file wiring only the two kept handlers reads "wired", and one with no Flow entries reads "unenforced", not drift.
2. Nothing in the core runs on Stop; no `required-artifacts.yml` remains.
3. The kept `pre_tool_use` fixtures pass unchanged (`fixtures` group); the denominator matches the kept set.
4. The merge script and both engines agree on the event set (hosted `wire-hooks-beside`, `hook-wiring-intent`, `cli-0259`, `cli-flow-recovery`, `cli-flow-recovery-selectors`).
5. `typed-stop-claim-and-subagent-stop` and `hook-output-host-validity` are closed in the index.

## Wave split

- **Wave 1**, two commits: (a) re-key the detection, the merge map and the Claude Code example onto the kept handlers (maintainer side, not FR-07); (b) remove the five handlers, `required-artifacts.yml` and their fixtures (one FR-07 approval).
- **Wave 3 tail:** the engines call `hooks_state()`.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
