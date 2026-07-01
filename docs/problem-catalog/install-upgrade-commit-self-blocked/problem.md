# Problem: fresh install / self-upgrade cannot make the documented setup commit

**Slug:** `install-upgrade-commit-self-blocked`
**Filed:** 2026-07-01
**Severity:** high
**Status:** resolved
**Filed by:** PO per FR-15 (consumer field reports — Slices 1/2/5/8/9, Windows MINGW64)

## Symptom

A fresh install AND a self-upgrade could not make the documented setup/upgrade commit through Flow's own just-installed pre-commit — two gates fired and the docs forbid `--no-verify`, a documented dead-end.

## Root cause

Three independent blockers on the setup changeset: (a) the secret scan self-tripped on the designed PAT tokens in `test-secret-scan-staged.sh` (one level above the excluded `hooks/tests/fixtures/`); (b) FR-07 protected-paths blocked the newly-added Flow internals with no `state/approvals/` exception on a fresh/upgrade tree; (c) `upgrade.sh`/`post-fusebase-update.sh` never (re)installed the fixed pre-commit, so it stayed inert on upgrade.

## Why it matters

- The very first thing a consumer does after install/upgrade — commit the setup — failed, with `--no-verify` (the obvious escape) explicitly forbidden. Adoption dead-end.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v3.30.3 G1+G3 (WS1a/b/c): (a) runtime-constructed test tokens + narrow excludes + a release-gate self-test; (b) a SINGLE-USE, digest-bound, short-TTL bootstrap approval (`write-bootstrap-approval.sh`) minted for exactly the setup changeset and consumed after — NOT a standing FR-07 bypass; (c) `upgrade.sh` + `post-fusebase-update.sh --wire-hooks` (re)install the fixed pre-commit and document the mint→commit→consume flow (no `git add -A`) |

## Recurrence triggers (so future sessions recognize this)

- A setup/upgrade commit is blocked by the secret scan or FR-07 and the docs say no `--no-verify`.
- A "fix" to the pre-commit is claimed live after upgrade without the upgrade actually re-installing it.

## Guardrail (the lesson)

The install/upgrade path must be able to make its OWN documented commit through Flow's own gates with no `--no-verify` — validate the FIRST hop that adopts a fix, not just steady state. A bootstrap FR-07 exception must be SINGLE-USE (digest+op+TTL bound, consumed after) so it never becomes a reusable hole; keep secret excludes narrow (a real secret in non-designed test code must still block).

## Related

- `docs/problem-catalog/inaccurate-consumer-prompt/problem.md` — the "upgrade installs the fixed pre-commit" false claim (self-mistake).
- `hooks/local/write-bootstrap-approval.sh`, `hooks/shared/path_policy.py` — the single-use exception mechanism.
