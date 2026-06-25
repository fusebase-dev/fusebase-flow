# Deploy handoff — fr22-delivery-guarantee + po-verifiable-boot → v3.27.0 (MINOR)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.26.0 → shipping **v3.27.0**. Self-attest FR-01..FR-26, DP section. Operator authorized "deploy and update README" (DP.12 plain go-ahead). **Run everything SYNCHRONOUSLY — no background monitors.**

## What ships (two FR-22-family tickets, both already Codex-SHIP, local-only)
- **fr22-delivery-guarantee Phase 1** (6 commits `b7b2d87..35d9a82`): present-by-construction FR-22 block in the implement handoff template; write-time digest carries the full two-kinds rule + the "does NOT propagate to sub-agents" note; artifact-vs-content distinction doc; `comment_policy_review_applied` warn-signal (non-blocking `recommended` list); carve-out clarity. (Phase 2/F deferred.)
- **po-verifiable-boot** (5 commits `8b79af3..eea8bd9`): `/product-owner` activation boot — operating-rules checklist + ASCII `[[ PO-ACTIVATED | … ]]` marker delivered by construction via the command (+overlay) AND canonical agent; UserPromptSubmit `/product-owner` reminder; dedicated warn-only Stop-hook verification (outside CLAIM_PATTERNS).
Both: warn-only (no gate loosened), FR-07-clean. **11 commits total** on top of origin/main `60805e1`; HEAD `eea8bd9`.

## Step 1 — version bump
- VERSION + `.claude-plugin/plugin.json` 3.26.0 → **3.27.0** (equal).
- `bash hooks/local/sync-version-strings.sh` — verify all framework adapters incl. **GEMINI.md** = v3.27.0; under-reach guard passes; no consumer doc touched. (No new FR rule, no new skill — version sweep only.)

## Step 2 — README (operator asked: "update README")
- **Badge** (line ~9): `version-3.26.0` → `version-3.27.0` (sync does NOT touch the shields.io badge — do it manually).
- **Commands & capabilities** table (the section added in v3.26.0): update the **`/product-owner`** row to note it now opens with a **verifiable activation boot** (echoes its operating-rules checklist + `PO-ACTIVATED` marker; a Stop-hook warns if a PO session skips it). Keep it one line, existing style.
- Do NOT change historical "shipped in vX" notes.

## Step 3 — release notes + CHANGELOG
New `docs/release-notes/v3.27.0.md` + `CHANGELOG.md [3.27.0]` (date 2026-06-17, deploy hash): two features in the FR-22 family —
1. **FR-22 delivery guarantee** (from a consumer report: "mandatory in prose, undelivered in practice"): the comment-policy is now present-by-construction in code-writing handoffs, the write-time digest states it doesn't auto-propagate to sub-agents, and a warn-only `comment_policy_review_applied` signal ends the loop's comment-blindness — all artifact-level, never gating on comment content.
2. **PO verifiable boot**: `/product-owner` now boots with an operating-rules checklist + a machine-detectable marker (delivered via command + canonical agent), with a warn-only Stop-hook verification riding the already-wired UserPromptSubmit/Stop events.
Note: warn-only, FR-07-clean, no deny gate loosened; both independently Codex-SHIP'd (design RESCOPE folded + impl review). **Deferred:** `fr22-predelegation-hook` (the pre-delegation PreToolUse check — needs host-matcher coverage first).

## Step 4 — final gate
preflight 0/0 · `python -m py_compile hooks/handlers/stop.py hooks/handlers/user_prompt_submit.py` · run-tests **118/118** PASS · check-module-size --all exit 0 · mirror 0 drift (skills + agents byte-identical; `mirror-skills.sh` + `mirror-agents.sh`) · plugin==VERSION==3.27.0 · the 5 FR-07 surfaces (FLOW_RULES FR rows, approval-policy, protected-paths, command-policy, ratchet-governance) UNCHANGED across the release · git clean after the release commit.

## Step 5 — release
1. `git push origin main`.
2. `git tag -a v3.27.0 -m "FuseBase Flow v3.27.0 — FR-22 delivery guarantee + PO verifiable boot"`; `git push origin v3.27.0`.
3. `gh release create v3.27.0 --title "v3.27.0 — FR-22 delivery guarantee + PO verifiable boot" --notes-file docs/release-notes/v3.27.0.md --latest`.
4. Capture deploy hash.

## Step 6 — probes + smoke (capture evidence)
- mirror byte-identical (skills + agents); sync --dry-run framework-only; GEMINI.md = v3.27.0; README badge = 3.27.0; `git grep -ni headroom` = 0 (clean-room intact from prior release).
- **Feature smoke (the two tickets):** (a) the implement-handoff template contains the FR-22 push block (present-by-construction); (b) `stop.py` on a synthetic transcript: `comment-policy review: applied (FR-22)` → detected; a `/product-owner` activation with NO marker → **warn + allow (rc 0)**, with the marker → no warn; a done-claim missing a required signal → still **deny (rc 2)**. Capture the rc/decision evidence.

## Step 7 — single FR-14 docs commit
- Flip `docs/specs/fr22-delivery-guarantee/spec.md` AND `docs/specs/po-verifiable-boot/spec.md` → DONE + deploy hash (resolves the prior untracked-spec LOW finding — commit both specs).
- File `docs/backlog/fr22-predelegation-hook/README.md` (the deferred Phase 2/F + its prerequisites: host-matcher coverage, explicit delegation markers, warn-only) + add a row to `docs/backlog/index.md`.
- Push. Output the deploy report.

## Hard rules
FR-07: NO diff to FLOW_RULES FR rule rows / the 3 deploy-policy rule semantics / ratchet-governance.yml (version attestation lines allowed). Keep internal/ + repo-polish + `.claude/settings.local.json` + the `*-implement.md` handoffs untracked. If any gate/probe fails, STOP and report before pushing further.

## Rollback
`git revert <release range>` — additive, warn-only, behavior-preserving for existing gates. Re-push; re-mirror.

## Return
Deploy report: version, deploy hash, tag, release URL, GEMINI + README badge = v3.27.0, the feature-smoke evidence (FR-22 block present; PO-activation warn+allow rc 0; required-missing deny rc 2), FR-07 confirmation (5 surfaces unchanged), FR-14 docs commit SHA (both specs DONE), and the fr22-predelegation-hook backlog path.
