# Deploy handoff — token-economy context-compression discipline → v3.26.0 (MINOR)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.25.1 → shipping **v3.26.0** (MINOR feature). Self-attest FR-01..FR-26, DP section. Operator authorized publish-to-GitHub-as-latest (DP.12 plain go-ahead). No interactive DP.6. **Run everything SYNCHRONOUSLY — no background monitors.**

## What this ships (first release of this feature — currently all uncommitted)
The clean-room FR-26 **context-compression discipline**: a new `## Context compression discipline` section in the token-economy skill (route-by-type, extract-before-reasoning, pointer-backed summaries with retrieval handles, reopen-original-before-deciding, reference-an-in-context-body-once, large-output hygiene, generated/vendored restraint, compression-is-not-verification) + new audit candidate classes **`large-output`** (oversized results from any output-producing tool incl. **MCP** — generic exclude-writes predicate) and **`repeat-output`** (identical large body re-sent across turns, detected by a one-way stdlib hash; body never emitted). Clean-room, MIT, stdlib-only, no caps. Triple-validated: gap-analysis workflow + two Codex SHIP reviews + a name/license firewall audit (reference is Apache-2.0; we copied nothing; `git grep -ni headroom` = 0).

## Pre-state
- VERSION 3.25.1; origin/main `e96f63f`. 8 uncommitted files: `flow-skills/token-economy/SKILL.md`, `.claude/commands/token-waste-audit.md`, `hooks/local/fusebase-flow-overlays/commands/token-waste-audit.md`, `hooks/local/token-waste-audit.py`, `docs/source-map.md`, + regenerated mirrors `.claude/skills/token-economy/SKILL.md`, `.agents/skills/token-economy/SKILL.md`, `audit/skill-mirror-manifest.txt`.
- Operator-private `.claude/settings.local.json` is untracked — do NOT stage it.

## Step 1 — commit the feature
One commit of the 8 files: `feat(token-economy): FR-26 context-compression discipline + large-output/repeat-output audit (clean-room)`. Verify preflight 0/0 on the committed tree.

## Step 2 — version bump + version sweep
- VERSION + `.claude-plugin/plugin.json` 3.25.1 → **3.26.0** (equal).
- `bash hooks/local/sync-version-strings.sh` — verify all framework adapters incl. **GEMINI.md** = v3.26.0; under-reach guard passes; no consumer doc touched. (FR count + skill count unchanged: no new FR rule, no new skill — this extends the existing token-economy skill.)

## Step 3 — documentation (update ALL release-facing docs)
- **README.md badge** (line ~9): `version-3.25.1` → `version-3.26.0` (sync does NOT touch the shields.io badge — do it manually).
- **README.md token-economy catalog line** (~310): extend it to name the new capability, e.g. append "— plus **context-compression discipline** for large context/output (route-by-type, extract-before-reasoning, pointer-backed summaries, reopen-original-before-deciding); `/token-waste-audit` now flags `large-output` + `repeat-output` candidates across built-in **and MCP** tools." Keep it one line, existing style. Do NOT change the historical "shipped in vX" notes (lines ~313/678) — token-economy's skill debut stays v3.20; this is an extension, not a new skill.
- New `docs/release-notes/v3.26.0.md` + `CHANGELOG.md [3.26.0]` (date 2026-06-15, deploy hash): summarize the discipline + the two new audit classes + the MCP-coverage correctness fix (the old allowlist silently missed MCP) + repeat-output (one-way hash, never emits the body). Note clean-room/MIT/stdlib/no-deps; credit the validation (gap analysis + Codex). NO third-party tool named.
- `docs/source-map.md` — already carries the clean-room attestation (no change needed; confirm present).
- Scan `docs/rail-mapping.md` / `docs/operator-discipline.md` for a token-economy/FR-26 description that now materially understates the capability; update ONLY if it would be wrong post-release (light touch). Do not rewrite historical docs/specs/release-notes.

## Step 4 — final gate
preflight 0/0 · `python -m py_compile hooks/local/token-waste-audit.py` OK · `bash hooks/local/check-module-size.sh --all` exit 0 (parser ~479 lines) · mirror manifest byte-identical (`bash hooks/local/mirror-skills.sh` → 0 drift) · `git grep -ni headroom` = 0 · LICENSE untouched · plugin==VERSION==3.26.0 · git clean after the release commit. (Recovery-sim NOT required — this change does not touch the upgrade/recovery engine.)

## Step 5 — release (publish as latest)
1. `git push origin main`.
2. `git tag -a v3.26.0 -m "FuseBase Flow v3.26.0 — FR-26 context-compression discipline (large-output/repeat-output audit, MCP coverage)"`; `git push origin v3.26.0`.
3. `gh release create v3.26.0 --title "v3.26.0 — context-compression discipline" --notes-file docs/release-notes/v3.26.0.md --latest`.
4. Capture deploy hash.

## Step 6 — probes + smoke (capture evidence)
- mirror manifest byte-identical; sync --dry-run scoped (framework-only); GEMINI.md = v3.26.0; README badge = 3.26.0; `git grep headroom` = 0.
- Audit smoke (the feature): build a synthetic transcript OUTSIDE the repo with an oversized MCP result + an identical large body sent ≥2×; run `python hooks/local/token-waste-audit.py --dir <tmp> --last 1`; confirm `large-output` ≥1 (incl. the mcp__ tool) and `repeat-output` ≥1, and that a unique content marker appears **0** times in the report. Clean up.

## Step 7 — single FR-14 docs commit (closeout)
If any spec/backlog status needs flipping, do it in one docs commit. (No spec ticket exists for this operator-prompted feature; the release notes + CHANGELOG are the record.) Push. Output the deploy report: version, deploy hash, tag, release URL, GEMINI/badge=v3.26.0, probe/smoke evidence, headroom=0, LICENSE untouched.

## Hard rules
FR-07: NO change to FLOW_RULES FR rule rows / the 3 deploy-policy rule semantics / ratchet-governance.yml (version-string attestation lines are allowed). Keep internal/ + repo-polish + `.claude/settings.local.json` untracked. Clean-room: no third-party tool named in any shipped artifact. If any gate/probe fails, STOP and report before pushing further.

## Rollback
`git revert <release range>` — additive (skill section + audit classes + docs); behavior-preserving for existing classes; no deps. Re-push; re-mirror.
