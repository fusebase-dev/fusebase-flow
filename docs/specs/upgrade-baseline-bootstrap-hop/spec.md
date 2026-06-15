# Spec — upgrade-baseline-bootstrap-hop

**Status:** DONE — shipped **v3.25.1** (2026-06-15), PATCH hotfix. Found by post-ship Codex adversarial review of v3.25.0; Codex re-review verdict **SHIP**.
**Created:** 2026-06-15
**Baseline:** FuseBase Flow v3.25.0
**Deploy hash:** `ea85585793cb5906ab9aad7a018066746c1b80be` (release commit, tag `v3.25.1`)
**Release:** https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.25.1
**Source:** post-ship Codex adversarial review of the v3.25.0 ship.

## Blocker (verified)

v3.25.0 shipped the U3/W2 `module-size-baseline.txt` + policy-state **merge-preserve** rule, but the merge was **skipped on the adoption hop** — the FIRST upgrade that brings a project onto v3.25.x. Root cause (source ordering, not the rule):

- `upgrade.sh` sourced the merge lib from the **local (pre-upgrade) tree** before `hooks/` was refreshed → the new merge code wasn't present yet.
- `bootstrap-upgrade.sh` did **not** stage `hooks/local/lib/` → the merge lib never reached disk before handoff.

Net: on the adoption hop, the new merge code was **never on disk when the merge had to run** → a project's own `module-size-baseline.txt` rows were **clobbered on adoption** (the exact WorkHub Managed failure U3 was meant to prevent, one hop earlier than the v3.25.0 gate caught).

## Fix (bounded to how/when the lib is sourced — LOCKED merge rule unchanged)

| Task | Commit | What |
|---|---|---|
| P1 | `49f335c` | `bootstrap-upgrade.sh` stages `hooks/local/lib/` so the new `upgrade.sh` finds its merge code before handoff |
| P2 | `b562166` | `upgrade.sh` sources merge lib from the authoritative target tree (`$SOURCE_CLONE/hooks/local/lib/`) + local fallback + **re-source before Step 1a** + **loud no-skip warning** if the lib can't load |
| P3 | `5324358` | README routes pre-v3.25 installs through `bootstrap-upgrade.sh` for the v3.25.x hop (merge ships in target version; clobbered baseline recoverable from `.pre-upgrade` backup) |
| P4 | `28fe2ea` | `hooks/tests/test-bootstrap-baseline-hop.sh` (13 cases) wired into `run-tests` — RED-then-GREEN adoption-hop proof + P1 staging preconditions |

Bundled into release commit `ea85585`.

## Acceptance criterion

**The adoption-hop merge actually runs:** on the first upgrade adopting v3.25.x, a project's `module-size-baseline.txt` project rows are preserved (not clobbered). Proven by the RED-then-GREEN test: `red-prefix-loses-row` (pre-fix engine loses the row) + `green-engine-preserves-row` (fixed engine preserves it — "1 preserved project row(s)").

## ACCEPTED-RISK

An old, already-installed `upgrade.sh` run **directly** (not via bootstrap) still cannot run the target-version merge code (it predates the fix and sources its own old lib). Mitigated by P3 — route pre-v3.25 installs through `bootstrap-upgrade.sh`. Only residual Codex flagged.

## FR-07 scope

No change to FLOW_RULES FR rows, the 3 deploy-policy rule semantics, `ratchet-governance.yml`, or the LOCKED merge rule — **only how/when the merge lib is sourced** + bootstrap staging + routing docs + a test.

## Verification (post-deploy, released tree)

preflight 0/0 · run-tests **92/92** (79 + 13 adoption-hop) · `check-module-size --all` exit 0 · mirror 31 skills / **0 drift** (byte-identical) · sync `--dry-run` framework-scoped, consumer decoy excluded · plugin == VERSION == **3.25.1** · **GEMINI.md = v3.25.1** · health **no `PARTIAL_UPGRADE` false-positive** (drift checks all ✓; verdict PARTIAL_UNVERIFIED = host preflight/test timeouts only, already passed unbounded) · recovery-sim **31/31 exit 0** (`state/audit/recovery-sim-v3.25.1-2026-06-15.log`, referenced not re-run) · `bash hooks/tests/test-bootstrap-baseline-hop.sh` **13/13 PASS** on the released tree. Evidence: `docs/tmp/handoff/2026-06-15-upgrade-baseline-bootstrap-hop-smoke/`.

## Rollback

`git revert ea85585` (and `49f335c..28fe2ea` if reverting the underlying fix) — additive (source-ordering + bootstrap staging + docs + test); steady-state behavior unchanged. Re-push; re-mirror.
