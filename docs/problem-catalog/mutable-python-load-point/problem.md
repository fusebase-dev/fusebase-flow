# Problem: a security check that loads working-tree code/patterns/config can be neutralized by tampering that working-tree copy

**Slug:** `mutable-python-load-point`
**Filed:** 2026-07-03
**Severity:** high
**Status:** resolved
**Filed by:** PO per FR-15 (operator requested lessons "so next time we avoid such problems")

## Symptom

The FR-07 §3 / FR-12 §2 pre-commit checks EXECUTED enforcement code, secret patterns, and policy read from the WORKING TREE. Any tamper of that working-tree copy — even UNSTAGED, and even via Python startup files (`sitecustomize.py`/`usercustomize.py`) or a hostile `PYTHONPATH` — could make the check lie ("nothing protected" / "no secrets") and self-pass.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Edit the working-tree enforcer to return "nothing protected" (unstaged), commit a protected-path change | ALLOWED — the check ran the tampered working-tree code |
| 2 | Drop a `sitecustomize.py` on the hook import root, commit | startup file ran BEFORE the check and could disable it |
| 3 | Set a hostile `PYTHONPATH`, commit | shadow module loaded ahead of the trusted one |

Reproduces: 3/3 (distinct mechanisms, each closed in turn — see FR-10)

## Root cause

Working-tree code was trusted to check working-tree changes. The interpreter has many mutable entry points that all reach BEFORE the check's own logic: the module file, its imported patterns/config, Python startup files, `PYTHONPATH`/`PYTHONSTARTUP`/`PYTHONHOME` env vars, and user site-packages. Each is a "load-point" an attacker (or a tampering agent) controls in the working tree.

## Why it matters

- The control meant to protect the repo could be turned off by editing the very files it lives in — without staging them.
- This is the DEEPEST class behind the fail-open family: not a missing branch, but a wrong trust boundary.

## Mitigation / workaround

Run security checks from the TRUSTED committed copy, under a scrubbed interpreter:

1. `git show HEAD:` extract the enforcement code + policy + patterns into a fresh `mktemp` dir (T28-T31).
2. Run under `python3 -S` with a scrubbed env (`unset PYTHONPATH/PYTHONSTARTUP/PYTHONHOME`, `PYTHONNOUSERSITE=1`) (T29/T30).
3. Make the trusted-vs-fallback decision in GIT (`git ls-tree HEAD`, shell-side, unforgeable), never in the mutable Python (T30).
4. Extend the same hardening to §2 (secret scanner + patterns from HEAD) (T31).

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `180f4a1` (release v3.30.5) · tag v3.30.5 · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- A hook/gate that `import`s or `exec`s code, patterns, or config from the repo working tree
- `git show HEAD:` / `mktemp` extraction in an enforcement path (the FIX pattern — keep it)
- Protecting `sitecustomize.py`/`usercustomize.py` in `protected-paths.yml` (the T29 tripwire)

## Guardrail (the lesson)

Never trust working-tree code to check working-tree changes. Load the enforcement code, patterns, and policy from the committed (trusted) copy; run under a scrubbed `-S` interpreter; decide trusted-vs-fallback in git (unforgeable), not in the mutable Python.

## Related

- `docs/problem-catalog/security-check-fail-open-class/problem.md` — the umbrella fail-open lesson
- `docs/problem-catalog/cwd-on-syspath-under-dash-S/problem.md` — the specific tail bug that showed `-S` alone is not enough

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
