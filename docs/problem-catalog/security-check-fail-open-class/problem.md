# Problem: pre-commit security checks had MULTIPLE reachable fail-opens (FR-07 §3 + FR-12 §2)

**Slug:** `security-check-fail-open-class`
**Filed:** 2026-07-03
**Severity:** high
**Status:** resolved
**Filed by:** PO per FR-15 (operator explicitly requested records "so next time we avoid such problems")

## Symptom

The whole-roadmap review of the shipped v3.30.x hook found that the pre-commit security checks (FR-07 §3 protected-path AND FR-12 §2 secret scan) FAILED OPEN — silently PASSED — on multiple reachable error/edge paths instead of blocking. A commit touching a protected path or carrying a secret could slip through when any of those paths was hit.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | `git rm` a protected file, commit (pre-T23 hook) | ALLOWED — `--diff-filter=ACM` never saw the delete |
| 2 | Uninstall PyYAML, commit an internals edit (pre-T25) | ALLOWED — import error silently fail-open |
| 3 | Empty/remove `protected-paths.yml`, commit (pre-T27) | ALLOWED — total FR-07 disable, no protection |

Reproduces: 3/3 (each path independently demonstrated during the roadmap review + convergence PoCs — see FR-10)

## Root cause

A security control assembled from N individually-reasonable diffs accreted N reachable exits that defaulted to "allow" on error: an ACM-only diff-filter (deletes/renames unseen); a bare `except Exception`/import-error/enumeration-failure that returned an empty list (read as "nothing protected"); a `SystemExit(0)` from a tampered module treated as success; a missing/malformed policy read as "no policy ⇒ nothing to enforce." None of these were the happy path, so happy-path tests were all green.

## Why it matters

- A protected-path bypass or a leaked secret is a security-surface regression in the exact control meant to prevent it.
- The failures were invisible to happy-path tests — only adversarial/fail-path testing surfaced them.

## Mitigation / workaround

Each fail-open was closed to FAIL CLOSED in turn (v3.30.5):

1. Delete/rename skipped → `staged_change_paths` A/C/M/D/R (T23).
2. Import/enumeration/`SystemExit(0)`/`except Exception` → catch `BaseException`, exit 1 + FR-07 diagnostic (T25/T26/T27).
3. Missing/empty/malformed policy → BLOCK; `protected-paths.local.yml` additive-only (T27).

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `180f4a1` (release v3.30.5) · tag v3.30.5 · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- Adding/modifying a pre-commit or PreToolUse security check (`hooks/git/pre-commit`, `hooks/shared/path_policy.py`, `policies/*-patterns.yml`)
- A `try/except` or diff-filter in an enforcement path
- Logs show a security check "passed" on a malformed/missing policy or import error

## Guardrail (the lesson)

A security control must FAIL CLOSED at EVERY reachable load-point. Tests must cover the BYPASS and the FAIL-OPEN path, not just the happy path. Enumerate the full change set (deletes + rename old+new), never just ACM.

## Related

- `docs/problem-catalog/mutable-python-load-point/problem.md` — the deepest sibling (trusted-HEAD pattern)
- `docs/problem-catalog/cwd-on-syspath-under-dash-S/problem.md` — the specific tail bug
- `docs/specs/windows-msys-hardening/roadmap.md` — the shipped roadmap this corrects

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
