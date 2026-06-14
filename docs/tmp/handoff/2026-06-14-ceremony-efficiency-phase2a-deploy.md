# Deploy handoff — ceremony-efficiency-middle-lane Phase 2A → v3.23.0

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.22.0 → shipping **v3.23.0**. Self-attest per FLOW_RULES.md (FR-01..FR-26), Deploy-phase (DP) section.

**Lane:** Phase 2A is **Lightweight** (additive, read-only-safe — adds proposal *output* to the audit; analyzer still writes nothing outside gitignored `state/audit/`). Per **DP.12** a plain operator go-ahead replaces DP.1/DP.6. **Go-ahead is GIVEN:** operator directive "build and finalize everything necessary in this repository" + Codex review verdict **SHIP** on Phase 2A. Proceed.

## Pre-deploy state
- Branch `main`, local ahead of origin: `c7d2512` (spec reshape, pushed) → `d2f9ecc` (T24 Phase 2A) — d2f9ecc UNPUSHED. Plus untracked Phase-2A handoffs under `docs/tmp/handoff/`.
- Phase 2A gate PASS; Codex independent review **SHIP** (one acceptable-LOW: harden `contained_audit_path` — Step 0 below).
- VERSION `3.22.0`; plugin.json `3.22.0`.

## Step 0 — fold in the Codex acceptable-LOW (one commit, then verify)
Harden the internal containment helper so `../`/absolute basenames can't escape `state/audit/` even under internal misuse (currently unreachable from the CLI, but it's a containment helper — close it):
- In `hooks/local/find-wasted-effort.py` `contained_audit_path(root, basename)` (~line 95): resolve the target before the relative check — `target = (resolved_audit / basename).resolve(strict=False)` — and **reject** a basename that is absolute or contains `..`/path separators; raise `RootError` on escape. Both real callers pass fixed basenames, so behavior is unchanged for them.
- Add a fixture: `contained_audit_path(root, "../evil.md")` → rejected (no write outside `state/audit/`); a normal basename → resolves under `state/audit/`.
- Commit: `fix(find-wasted-effort): harden contained_audit_path against ../ basenames (Codex Phase-2A LOW)`.
- Verify: `--selftest` all pass (skips separate); `bash hooks/local/preflight.sh` 0/0; `bash hooks/local/mirror-skills.sh` 0 drift. Analyzer still read-only.

## Step 1 — version bump + sweep
- VERSION + plugin.json `3.22.0` → **3.23.0** (keep equal).
- `bash hooks/local/sync-version-strings.sh` (live attestation / FR-01..FR-26 / skill-count 31 — unchanged; no new skill, this extends `find-wasted-effort`). Confirm dated history untouched.
- Reconcile any count strings (selftest tally is the live number after Step 0).

## Step 2 — release notes
- New `docs/release-notes/v3.23.0.md` + `CHANGELOG.md [3.23.0]`: real date, final selftest tally, deploy hash (after push). Summary: Phase 2A — `/find-wasted-effort` now emits schema'd **proposals** (Proposed memory entries report section + gitignored `state/audit/` JSON), still **read-only to the project**; the write-apply (Phase 2B) + Middle Lane (Phase 3) remain deferred to the consumer-repo prototype per the spec.

## Step 3 — final pre-push gate
`preflight.sh` 0/0 · `--selftest` all pass · `run-tests.sh` 24/24 · health HEALTHY · mirror 0 · plugin valid · `git status` clean.

## Step 4 — release
1. `git push origin main`.
2. `git tag -a v3.23.0 -m "FuseBase Flow v3.23.0 — find-wasted-effort proposal output (Phase 2A)"`; `git push origin v3.23.0`.
3. `gh release create v3.23.0 --title "v3.23.0 — find-wasted-effort proposal output" --notes-file docs/release-notes/v3.23.0.md --latest`.
4. Capture deploy hash.

## Step 5 — probes + smoke
- Probes G-M..G-Q (push/tag landed; preflight on shipped tree; skill resolves; analyzer runs; docs updated).
- **Smoke:** run `/find-wasted-effort` against THIS repo; confirm the report now has a **"Proposed memory entries"** section + a gitignored `state/audit/find-wasted-effort-proposals-<date>.json`, makes **NO** edits outside `state/audit/` (`git status` clean), and applies nothing.

## Step 6 — single FR-14 docs commit
Spec Phase-2A status note + deploy hash; tasks T24..T26 SHAs + verification. (Spec stays LOCKED — Phase 2B/3 remain.) Output the deploy report.

## Rollback
`git revert <deploy hash>` (additive, read-only-safe — clean revert); re-push; re-mirror.

## Notes
- Worker-undisturbed: NO change to FLOW_RULES FR rows or the 3 deploy policies or ratchet-governance.yml. Analyzer stays read-only. Do NOT start Phase 2B/3 (consumer-repo).
