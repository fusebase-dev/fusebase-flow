# approval-collection-fails-silent-on-damaged-shared

**Status:** open, NOT scheduled — low severity (a second control already catches the trigger), correctness of the verdict is unaffected. Fail-loud hardening, not a bug fix.
**Filed:** 2026-09-12 — latent item found while diagnosing the m9 `health-check-timeout` fixture regression; it is NOT the m9 fix (that was a test-fixture under-copy, `hooks/tests/test-health-check-timeout.sh` `build_golden`).

## Defect

`hooks/local/lib/active-approvals.sh` collects each `state/approvals/*.json` by running a Python
block per artifact. Two lines combine to make a damaged `hooks/shared/` fail SILENTLY:

| Site | Code | Effect |
|---|---|---|
| `:84` | `python3 - … <<'PY' 2>/dev/null` | the block's stderr (a traceback) is discarded |
| `:124` | `from shared.command_policy import command_gated_actions` | top-level import (added by T100 / `133a381`, v4.17.0); NOT inside the inner `try` |
| `:200-201` | `except Exception:` / `sys.exit(2)` | any import-time error becomes a bare exit 2 |

If a consumer's `hooks/shared/` is damaged or partial — e.g. a botched upgrade drops
`command_policy.py` or one of its import closure (`command_rules.py`, `denial_message.py`,
`git_push_binding.py`) — the `:124` import raises `ModuleNotFoundError`, the outer handler exits 2,
and `2>/dev/null` hides the reason. Back in bash the per-artifact `summary` capture is empty, so
EVERY approval artifact is dropped: none reaches `ACTIVE_ARTIFACTS`, no `ARTIFACT_NOTES` line is
emitted, and no deferral is registered. A tree that should classify `EXCEPTION_IN_EFFECT` (exit 3)
instead reads `FLOW_LAYER_DRIFT` (exit 1) with no visible cause. This is the same silent-drop
mechanism the m9 fixture bug exercised, but here on a real (damaged) consumer tree.

## Scope / severity

- **Real consumers are normally safe:** they ship the complete `hooks/shared/`. The trigger is a
  damaged/partial shared dir, not normal operation.
- **A second control already catches the trigger:** the hook-layer manifest-integrity critical
  reports DRIFT on any damaged/missing covered `hooks/shared/*.py`, so the damage is not invisible
  overall — only the approval-collection path's own explanation is missing. Hence LOW severity.
- **Does NOT touch verdict precedence.** The classification order in
  `fusebase-flow-health-check.sh` is unchanged; this ticket only asks the collector to be loud
  about its own failure.

## The fix this needs

Fail LOUD, not silent: when the per-artifact Python block exits non-zero for a
non-artifact-specific reason (import/environment failure vs. a single malformed artifact),
surface it as a visible `APPROVAL_POLICY_ERRORS[]` entry (the array and its rendering already
exist — `:26`, `:63` uses it for an unloadable approval-policy) naming the failure, instead of
dropping the artifact set with no note. Distinguish a broken collection PATH (report the error;
do not silently imply "no active approvals") from one bad artifact (skip that one). Keep the
`2>/dev/null` discipline only where a captured stdout summary is the contract; do not let it hide
a collector-level failure.

## Non-goals

- Not a change to which artifacts exit 0 / land in `ACTIVE_ARTIFACTS` (the array contract at
  `active-approvals.sh:150-159`).
- Not a change to verdict precedence or the M9 staleness contract.
- Not the m9 fixture fix (`health-check-timeout` `build_golden` import-closure copy).
