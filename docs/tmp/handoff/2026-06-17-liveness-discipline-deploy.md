# Deploy handoff — liveness-discipline (FR-27) → v3.28.0 (MINOR)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.27.0 → shipping **v3.28.0**. Self-attest FR-01..FR-26 (+ the new FR-27), DP section. Operator approved the full ship (Option A) — DP.12 plain go-ahead. **Run everything SYNCHRONOUSLY — no background monitors.** (Eat our own dogfood: FR-27 — if you background any long check, bound it via `hooks/local/lib/bounded-run.sh` or poll it in-turn; never end a step "watching in background.")

## What ships
**FR-27 — liveness discipline** (first always-on rule added since FR-26): a new FR rule + `flow-skills/liveness-discipline/SKILL.md` (32nd skill) + the structural `hooks/local/lib/bounded-run.sh` watchdog helper + 3-tier present-by-construction delivery (role digest row + session_start reminder + handoff Hard-invariants). No blocking gate, no verification hook (a hang is undetectable by construction — the honest model). Driven by a consumer report (a background re-verify probe hung; the agent idled until nudged). 6 local commits on origin/main `bb7a70a`, HEAD `9361526`. Double-reviewed: design RESCOPE folded + impl review (DO-NOT-SHIP on a stale-count miss → fixed `9361526` → re-confirm **SHIP**).

## Step 1 — version bump
- VERSION + `.claude-plugin/plugin.json` 3.27.0 → **3.28.0** (equal).
- `bash hooks/local/sync-version-strings.sh` — verify all framework adapters incl. **GEMINI.md** = v3.28.0; FR-range already FR-01..FR-27 + 32 skills (synced at implement); under-reach guard passes; no consumer doc touched.

## Step 2 — README
- **Badge** (line ~9): `version-3.27.0` → `version-3.28.0` (manual — sync doesn't touch the shields.io badge).
- Confirm the `liveness-discipline` row is present in § Skill catalog + § Commands & capabilities (added at implement T4); the skill-count prose reads 32. If anything reads stale, fix.

## Step 3 — release notes + CHANGELOG
New `docs/release-notes/v3.28.0.md` + `CHANGELOG.md [3.28.0]` (date 2026-06-17, deploy hash): **FR-27 liveness discipline** — any long/silent background work (own probe/script/deploy/fetch-loop/browser, sub-agent, or workflow) must be made observable before launch (bounded by a timeout/watchdog, completed in-turn, or `BLOCKED-AT-<gate>` + record-then-read pointer); ships the `bounded-run.sh` structural helper (reuses the health-check timeout core) + the `liveness-discipline` skill + present-by-construction delivery. **Honest model:** no blocking gate, no verification hook — a hang is undetectable by construction, so enforcement is safe-by-default tooling + delivery (the tooling bounds the monitored process; it does not chase `&`-detached grandchildren or prove host re-invocation). Driven by a real consumer hang. Deferred follow-ups: pre-launch warn nudge, Python watchdog helper, template skeleton.

## Step 4 — final gate
preflight 0/0 · `bash -n hooks/local/lib/bounded-run.sh` · run-tests **132/132** PASS · check-module-size --all exit 0 · mirror 0 drift (32 skills + agents) · plugin==VERSION==3.28.0 · the 5 FR-07 surfaces UNCHANGED (FLOW_RULES FR-01..FR-26 rows, approval-policy, protected-paths, command-policy, ratchet-governance — note FR-27 is an APPEND, existing rows byte-unchanged) · `run-with-timeout.sh` byte-unchanged (ffhc_* intact) · git clean after the release commit.

## Step 5 — release
1. `git push origin main`.
2. `git tag -a v3.28.0 -m "FuseBase Flow v3.28.0 — FR-27 liveness discipline (anti-hang)"`; `git push origin v3.28.0`.
3. `gh release create v3.28.0 --title "v3.28.0 — FR-27 liveness discipline (anti-hang)" --notes-file docs/release-notes/v3.28.0.md --latest`.
4. Capture deploy hash.

## Step 6 — probes + smoke (capture evidence)
- mirror byte-identical (skills + agents); sync --dry-run framework-only; GEMINI.md = v3.28.0; README badge = 3.28.0; adapters carry FR-01..FR-27 + 32 skills; `git grep -ni headroom` = 0 (clean-room intact).
- **Feature smoke (the structural fix):** `source hooks/local/lib/bounded-run.sh` and run a `sleep 30` through it with a ~2s deadline → MUST terminate at ~2s with a timeout line + rc 124 (the silent-unbounded-wait is structurally bounded) + incremental progress emitted. Capture the rc + line. Confirm the health-check timeout suite still passes (ffhc_* intact).

## Step 7 — single FR-14 docs commit
- Flip `docs/specs/liveness-discipline/spec.md` → DONE + deploy hash.
- File `docs/backlog/fr27-prelaunch-nudge/README.md` (the deferred D3 warn-only nudge — must ship as allow+warning, not a block; + note D4 Python watchdog helper + D5 template skeleton as smaller follow-ups) + add a `docs/backlog/index.md` row.
- Push. Output the deploy report.

## Hard rules
FR-07: existing FR-01..FR-26 rows + the 3 deploy-policy rule semantics + `ratchet-governance.yml` + `run-with-timeout.sh` (ffhc_* API) UNCHANGED; FR-27 is an append. Keep internal/ + repo-polish + `.claude/settings.local.json` + `*-implement.md`/`*-deploy.md` handoffs UNTRACKED. NO blocking gate / verification hook may be added at deploy. If any gate/probe fails, STOP and report.

## Rollback
`git revert <release range>` — additive (new rule/skill/helper/delivery/docs); no existing behavior changed; ffhc_* untouched. Re-push; re-mirror.

## Return
Deploy report: version, deploy hash, tag, release URL, GEMINI + README badge = v3.28.0, FR-range FR-01..FR-27 + 32 skills confirmation, the bounded-run smoke evidence (sleep-30 → rc 124 + timeout line; health-check intact), FR-07 confirmation (5 surfaces + ffhc_* unchanged), FR-14 docs commit SHA, fr27-prelaunch-nudge backlog path.
