# Problem: consumer apply-prompt asserted unverified tool behavior

**Slug:** `inaccurate-consumer-prompt`
**Filed:** 2026-07-01
**Severity:** medium
**Status:** resolved
**Filed by:** PO per FR-15 (self-inflicted mistake, roadmap §4.2)

## Symptom

An operator-facing "apply + validate" prompt claimed "the upgrade installs the fixed pre-commit." False: `upgrade.sh` / `post-fusebase-update.sh` did NOT run `install-git-hooks.sh`, so the active `.git/hooks/pre-commit` stayed stale after an upgrade.

## Root cause

Tool behavior was asserted in operator-facing guidance without being verified against source. The upgrade scripts refreshed `hooks/git/` (the source copy) but never re-copied it into `.git/hooks/` (the active copy), so the "fixed" hook was inert until a manual reinstall.

## Why it matters

- A consumer follows the prompt, believes they are protected by the fixed hook, and is not.
- Erodes trust in operator guidance; the failure is silent (the stale hook still runs, just the old version).

## Mitigation / workaround

1. Verify every tool-behavior claim against the actual script BEFORE putting it in operator-facing text.
2. When an upgrade should make a hook live, the upgrade must actually (re)install it.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v3.30.3 G3 (WS1c) — `upgrade.sh` + `post-fusebase-update.sh --wire-hooks` now (re)install the fixed pre-commit via `install-git-hooks.sh`; the recommended-commit wording is corrected (`7335d8e`) |

## Recurrence triggers (so future sessions recognize this)

- About to state "the upgrade does X" / "the tool installs Y" in a consumer prompt or release note.
- A hook/script "fix" is claimed live without a step that actually re-copies it into its active location.

## Guardrail (the lesson)

Verify tool behavior against source before asserting it in operator-facing guidance. A refreshed SOURCE file is not a live ACTIVE file — an upgrade that should make a hook live must actually (re)install it.

## Related

- `docs/problem-catalog/truncated-manifest-on-bound-hit/problem.md` — sibling self-mistake (verify-before-trust).
- `hooks/local/install-git-hooks.sh` — the safe (re)install now called by the upgrade path (WS1c).
