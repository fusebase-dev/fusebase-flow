# Implement handoff — Phase C S1b: stop.py fail-closed on transcript-extraction failure

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.6. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (edits protected stop.py — note), FR-10, FR-22. **Synchronous; bound long runs (export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; STOP at gate; do NOT bump VERSION/push/tag/deploy.** ONE coherent commit stacked on the current HEAD (Phase C S6 `eb50078`). BLOCKER from the consolidated deploy-gate review (Codex). **CRITICAL — surface any pre-commit/FR-25/protected-path blocker you cannot resolve within your role IMMEDIATELY in your first response; do NOT stall silently.**

## PROTECTED-PATH NOTE (FR-07)
Edits `hooks/handlers/stop.py` (protected `fusebase_flow_internals`). REFRESH the wired hook (`bash hooks/local/install-git-hooks.sh`), mint ONE sanctioned single-use bootstrap approval (`bash hooks/local/write-bootstrap-approval.sh` binds the staged changeset), commit, `--consume`, confirm `.git/hooks/pre-commit` == source. Fixtures under `hooks/tests/fixtures/**` + `hooks/tests/*.sh` are NOT protected. NEVER `--no-verify`.

## The finding (Codex deploy-gate review, BLOCKER — verified)
S1 (`4acb535`) made the Stop done/deploy gate fire on native Claude Code events by extracting the FINAL assistant message from `transcript_path` when `agent_message` is absent. BUT: when that extraction returns `""` (a corrupt / wrong-shape / format-drifted transcript, or a transcript with no extractable final assistant text) AND `agent_message` is absent, stop.py falls through to `allow` — even if the raw transcript CONTAINS a done/deploy claim. Reproduced at HEAD `eb50078`: `printf '{"hook_event_name":"Stop","transcript_path":"hooks/tests/fixtures/09_stop_blocks_done_without_gate.json"}' | python3 hooks/handlers/stop.py` → `{"decision":"allow"}` despite the raw text containing "Implementation complete... Ready to deploy." This is a reachable-under-corruption/drift fail-OPEN in a security gate. (It is no worse than baseline — which was fully inert for native Stop — but must be closed for consistency with the FR-07/FR-12 fail-closed-at-every-reachable-load-point discipline.)

## Scope — ONE commit (fail-closed on extraction failure; NO over-trigger in the normal case)
In `hooks/handlers/stop.py`, after the existing claim-detection loop (which gates on `claim_text = agent_message or _final_assistant_text(...)`), ADD a fail-closed fallback:
- Define `extraction_failed = (not agent_message) and (not claim_text) and bool(transcript_text.strip())` — i.e. there IS a transcript but we could not extract a final assistant message to gate on.
- If `not triggered_gate` AND `extraction_failed`: scan the RAW `transcript_text` (lowercased) for the CLAIM_PATTERNS. If any done/deploy claim pattern matches → we have an UNGATEABLE claim → **fail closed**: set the corresponding `triggered_gate` and proceed into the existing gate logic (which will DENY because the required signals can't be verified from an unparseable transcript), emitting a clear reason like "could not extract the final assistant message from transcript_path (corrupt/unknown shape) to verify the FR-04/05/14 done/deploy gate — failing closed." Print the deny reason to stderr (Stop exit-2 semantics) as the S1 deny path already does.
- If `extraction_failed` but NO claim pattern in the raw text → keep `allow` (nothing to gate — same as baseline; do not deny on a claimless corrupt transcript).
- **Preserve the NORMAL path exactly:** when `_final_assistant_text` DOES extract a final message (the common case), gate ONLY on that (unchanged) — the raw-text fallback must fire ONLY on extraction failure, so a stale done-claim EARLIER in a WELL-FORMED transcript with a clean final message still ALLOWS (no over-trigger — fixture 19 stays green).
- Do NOT touch the CLAIM_PATTERNS / BYPASS_PATTERNS / secret-scan / signal_definitions / required-artifacts (input/fallback only, not the detection logic).

## Tests (add to the Stop fixtures/suite) — RED→GREEN
- **stop-native-corrupt-transcript-with-claim-fails-closed:** a native Stop whose `transcript_path` is a wrong-shape/unparseable file (e.g. the fixture-09 JSON, or a JSONL with no assistant-role text lines) that CONTAINS done/deploy claim text → now DENIES (exit 2). RED on `eb50078` → allow.
- **stop-native-corrupt-transcript-no-claim-allows:** a wrong-shape transcript with NO claim text → allows (no false-deny on a claimless corrupt transcript).
- **no-over-trigger regression:** the existing fixture-19 (stale claim earlier, clean final message, well-formed) still ALLOWS (extraction succeeds → gates on the clean final message → the raw-text fallback does NOT fire). Confirm all existing Stop fixtures (09/13/14/15/16/18/19) stay green.

## Do NOT
Do NOT weaken the deny/warn LOGIC (this only ADDS a fail-closed fallback on extraction failure). Do NOT re-introduce over-trigger in the normal path. Do NOT touch hooks/git/pre-commit or hooks/shared/**. Do NOT bump VERSION/push/tag. Do NOT `--no-verify`.

## Gate (scoped) — stop, report, HALT
FR-10 RED→GREEN (Codex repro now DENIES; claimless-corrupt still allows; fixture-19 no-over-trigger still allows). fixture/handler phase (FF_ONLY=fixtures) + po-verifiable-boot + fr22-delivery 0-FAIL; py_compile stop.py; bash -n tests; preflight green; SINGLE mirror --check 0-drift; check-module-size --all exit 0; FR-07 approval consumed + .git/hooks==source. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: commit SHA; FR-10 evidence (Codex's fixture-09 repro RED→GREEN deny; claimless-corrupt allows; fixture-19 no-over-trigger preserved; all existing Stop fixtures green); confirmation the normal-path final-message gating + detection logic are unchanged (only an extraction-failure fail-closed fallback added); FR-07 approval used + .git/hooks==source; scoped-gate numbers; module-size/mirror clean; VERSION 3.30.6. Do NOT push/tag/deploy.
