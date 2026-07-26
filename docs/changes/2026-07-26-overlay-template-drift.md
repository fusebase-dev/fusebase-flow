# Change-note — overlay-template-drift (Lightweight, FR-21)

**Date:** 2026-07-26 · **Lane:** Lightweight · **Tier:** 1 (change-note only)

## Problem

`hooks/local/fusebase-flow-overlays/{agents,claude}-md-overlay.md` carried rows **staler** than the live inline blocks in `AGENTS.md` / `CLAUDE.md`. Those templates are what `post-fusebase-update.sh` appends on the restore path (`:278`) and re-splices under `--refresh-overlays` (`:270`), so **either path would have silently downgraded a consumer's overlay**:

| Carrier | Row that was stale |
|---|---|
| `agents-md-overlay.md` | business-logic row had lost `docs/<app>/business-logic-index.md` (the AI-default index) and the `docs/en/business-logic.md` CLI-team variant |
| `claude-md-overlay.md` | slash-command row had lost the cross-agent equivalents pointer |
| `claude-md-overlay.md` | `product-owner` row had lost the po-investigate clarification — that a direct Bash call bypassing the wrapper is a **discipline breach, not a hook-blocked action** |

Found during `token-floor-remediation` T3 (2026-07-26), recorded as pre-existing and out of that task's scope, then closed here rather than left on disk as a consumer-facing regression.

## Change

Synced all three rows in the templates to match the inline blocks. Also refreshed `docs/specs/repo-context.md`, stale since v4.3.2 — its own freshness gate calls for regeneration after major restructuring, and this ticket added a root file (`FLOW_RULES_HISTORY.md`) and restructured `FLOW_RULES.md`.

Direction of sync: inline → template. The inline blocks held the newer content, so someone previously edited inline without re-splicing. The maintenance posture (`AGENTS.md` § Maintenance posture) treats the template as canonical, which is exactly why the drift was dangerous rather than cosmetic.

**Not changed:** the template's leading blank line. That is structural — `post-fusebase-update.sh:278` does `cat template >> AGENTS.md`, so the leading newline is the separator. Only the content rows drifted.

## Verification

`bash hooks/tests/run-tests.sh` **620/620 PASS**, 0 FAIL · `bash hooks/tests/test-sync-allowlist.sh` 8/8 (the content-derived gate that a new tracked doc could trip) · `bash hooks/local/preflight.sh` 0 errors / 0 warnings · byte-identity confirmed both ways: `diff <(sed -n '/CUSTOM:SKILL:BEGIN/,/CUSTOM:SKILL:END/p' <file>.md) <(tail -n +2 <template>)` → empty for both AGENTS and CLAUDE.

Run on the exact tree being pushed, per the guardrail from `docs/problem-catalog/docs-only-commit-broke-content-derived-gate/`.

## Rollback

`git revert <sha>` — templates return to their prior (stale) content; no consumer state is touched, since neither the restore nor refresh path had been run against the stale templates in this repo.
