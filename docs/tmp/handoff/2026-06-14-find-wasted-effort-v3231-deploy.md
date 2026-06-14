# Deploy handoff — find-wasted-effort containment patch → v3.23.1

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.23.0 → shipping **v3.23.1**. Self-attest per FLOW_RULES.md (FR-01..FR-26), DP section.

**Lane:** Lightweight patch (additive containment hardening to a read-only dev tool; reversible). DP.12 — plain operator go-ahead replaces DP.1/DP.6. **Go-ahead GIVEN:** operator chose option (a) "fix fixture honesty + add threat-model scope note, ship v3.23.1, stop."

## Pre-deploy state
- Branch `main` @ origin = `bc48560`. Local ahead by **`1e36b8b`** (the hardlink containment fix: atomic temp+`os.replace()` + `st_nlink>1` rejection) — UNPUSHED. v3.23.1 ships `1e36b8b` + the Step-0 cleanup below.
- VERSION 3.23.0; plugin.json 3.23.0.
- Final Codex confirm verdict: the containment invariant HOLDS (hardlink write-through defeated, fail-closed). Two non-security-logic cleanups remain (Step 0). The active-mid-run-directory-rename race is **explicitly OUT OF SCOPE** for a local read-only audit tool.

## Step 0 — two cleanups (one commit), then verify
1. **Fixture honesty** — `hooks/local/find_wasted_effort/selftest_containment.py` g2 fixture: it currently asserts "report still lands despite planted hardlink," but the fix is **fail-closed** (a pre-planted hardlink raises `RootError` via the `st_nlink>1` rejection; the outside file stays byte-unchanged). Rename/re-assert the fixture to reflect the TRUE contract: a pre-planted hardlink at the target ⇒ `write_audit_file` **raises `RootError` (fail-closed)** AND the outside aliased file is byte-unchanged (the safety invariant). Keep the g-case that proves a *swapped-in-before-replace* hardlink is severed by `os.replace` (new inode) if present. Do NOT change the write_audit_file security logic — only make the test claim accurate.
2. **Threat-model scope note** — add a concise docstring/comment at `write_audit_file()` (and/or `contained_audit_path()`) in `hooks/local/find-wasted-effort.py`: *"Containment defends pre-planted symlink / hardlink / traversal targets AT REST. Active concurrent filesystem races during a run (e.g. renaming `state/audit/` between temp-create and replace) are OUT OF SCOPE — this is a local, single-operator, read-only audit tool."* Keep it ≤2 lines (FR-22 tripwire style).
- Commit: `fix(find-wasted-effort): fixture asserts fail-closed hardlink contract + document at-rest containment threat model`.
- Verify: `--selftest` all exercised pass (skips separate); `bash hooks/local/preflight.sh` 0/0; `bash hooks/local/mirror-skills.sh` 0 drift. Analyzer still read-only.

## Step 1 — version bump
VERSION + plugin.json 3.23.0 → **3.23.1** (equal). `bash hooks/local/sync-version-strings.sh` (FR-01..FR-26, 31 skills — unchanged). Dated history untouched.

## Step 2 — release notes
New `docs/release-notes/v3.23.1.md` + `CHANGELOG.md [3.23.1]`: date, selftest tally, deploy hash. Summary: containment hardening for `/find-wasted-effort` — the audit's report/proposals write is now atomic temp+`os.replace()` and rejects hardlinked/symlinked targets (fail-closed), defeating a pre-planted-alias write-through; documented at-rest threat model (active mid-run FS races out of scope). Read-only invariant unchanged; no behavior change to verdicts/proposals.

## Step 3 — final gate
preflight 0/0 · `--selftest` all pass · `run-tests.sh` 24/24 · health HEALTHY · mirror 0 · plugin valid · git clean.

## Step 4 — release
1. `git push origin main`.
2. `git tag -a v3.23.1 -m "FuseBase Flow v3.23.1 — find-wasted-effort containment hardening (atomic write, hardlink/symlink fail-closed)"`; `git push origin v3.23.1`.
3. `gh release create v3.23.1 --title "v3.23.1 — find-wasted-effort containment hardening" --notes-file docs/release-notes/v3.23.1.md --latest`.
4. Capture deploy hash.

## Step 5 — probes + smoke
- Probes G-M..G-Q.
- Smoke: run `/find-wasted-effort` against THIS repo → report + proposals JSON land under `state/audit/`, `git status` clean (nothing outside `state/audit/`), verdicts honest, applies nothing.

## Step 6 — single FR-14 docs commit
Optional spec/tasks note (Phase-2A containment patch v3.23.1) + deploy hash. Output the deploy report.

## Rollback
`git revert <deploy hash>` (+ `1e36b8b` if needed) — additive, read-only-safe; clean revert.

## Notes
- FR-07: NO change to FLOW_RULES FR rows / 3 deploy policies / ratchet-governance.yml. Analyzer read-only. Do NOT start Phase 2B/3 (consumer repo). **No further Codex review for this patch** — operator closed the containment-edge loop at the documented at-rest threat model.
