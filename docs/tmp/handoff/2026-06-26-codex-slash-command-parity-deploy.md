# Deploy handoff — codex-slash-command-parity → v3.29.0 (MINOR)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.28.0 → shipping **v3.29.0**. Self-attest FR-01..FR-27, DP section. Operator approved the full loop through ship ("B + optional A") — DP.12. **Run SYNCHRONOUSLY — no background monitors (FR-27: bound/poll any long check; never leave a run bare).**

## What ships
**Codex (+ cross-agent) slash-command parity.** (B, primary) a compact 6-row **command-equivalents table** in `AGENTS.md` + overlay → all 6 Flow commands work across **Codex / Cursor / Copilot / Gemini** via the portable convention (matches Codex's skills model). (A, optional opt-in) `hooks/local/install-codex-prompts.sh` → single-sourced transform installs native `/prompts:<cmd>` into `$CODEX_HOME/prompts/` (per-machine, namespaced, Codex-deprecated — honestly labeled), marked + collision-safe + idempotent + hard-fails on a frontmatter-less body; **NOT wired into any default path.** No FR rule / skill added (FR-01..FR-27, 32 skills unchanged). 5 local commits on origin/main `528219d`, HEAD `cdf7bf6`. Codex impl review: **SHIP** (LOW hardened → `cdf7bf6`, bite-verified).

## Step 1 — version bump
- VERSION + `.claude-plugin/plugin.json` 3.28.0 → **3.29.0** (equal).
- `bash hooks/local/sync-version-strings.sh` — verify adapters incl. **GEMINI.md** = v3.29.0; FR-01..FR-27 + 32 skills unchanged; under-reach guard passes; **the AGENTS.md command-equivalents table is OUTSIDE the swept region → confirm it's byte-unchanged after sync**; no consumer doc touched.

## Step 2 — README
- Badge (line ~9) 3.28.0 → 3.29.0 (manual). Confirm the § Commands note (added at implement T3) reads correctly.

## Step 3 — release notes + CHANGELOG
New `docs/release-notes/v3.29.0.md` + `CHANGELOG.md [3.29.0]` (date, deploy hash): **Codex / cross-agent slash-command parity.** Until now the 6 commands were Claude-Code-only. B: an `AGENTS.md` command-equivalents table (Command · Claude `/cmd` · Codex `/prompts:cmd` if installed · Portable = invoke the skill / type the command) so they work in every agent. A (optional): `install-codex-prompts.sh` for native `/prompts:<cmd>` in Codex (per-machine, namespaced, Codex-deprecated — opt-in, marked, collision-safe). Grounded in Codex 0.128.0's verified mechanism (user-global `~/.codex/prompts/`, not repo-local; plugins don't carry commands). Possible follow-up: a Codex-plugin packaging of Flow's skills/agents.

## Step 4 — final gate
preflight 0/0 · `bash -n hooks/local/install-codex-prompts.sh` · run-tests **151/151** PASS · check-module-size --all exit 0 · mirror 0 drift · plugin==VERSION==3.29.0 · the 5 FR-07 surfaces UNCHANGED (FLOW_RULES FR rows, approval-policy, protected-paths, command-policy, ratchet-governance) · AGENTS.md table byte-unchanged post-sweep · git clean after the release commit.

## Step 5 — release
1. `git push origin main`.
2. `git tag -a v3.29.0 -m "FuseBase Flow v3.29.0 — Codex / cross-agent slash-command parity"`; `git push origin v3.29.0`.
3. `gh release create v3.29.0 --title "v3.29.0 — Codex / cross-agent slash-command parity" --notes-file docs/release-notes/v3.29.0.md --latest`.
4. Capture deploy hash.

## Step 6 — probes + smoke (capture evidence)
- mirror byte-identical; sync --dry-run framework-only; GEMINI.md = v3.29.0; README badge = 3.29.0; FR-01..FR-27 + 32 skills; `git grep -ni headroom` = 0.
- **B smoke:** AGENTS.md carries the 6-row table + all 6 commands + the portable column; table byte-unchanged after `sync --dry-run`.
- **A smoke:** run `CODEX_HOME=<tmp> bash hooks/local/install-codex-prompts.sh` → 6 prompts written, **all marked (flow-generated)**, **0 `.claude/agents` paths leaked**, re-run idempotent (written: 0), unmarked-collision refused, a frontmatter-less fixture **hard-fails** (no unmarked file). Capture evidence. Clean up the tmp.

## Step 7 — single FR-14 docs commit
- Flip `docs/specs/codex-slash-command-parity/spec.md` → DONE + deploy hash.
- File `docs/backlog/codex-plugin-packaging/README.md` (the out-of-scope follow-up: package Flow's skills/agents as a Codex plugin via `codex plugin marketplace`) + a `docs/backlog/index.md` row. (Optional — only if it reads as a real future item.)
- Push. Output the deploy report.

## Hard rules
FR-07: FR-01..FR-27 rows + 3 deploy-policy semantics + ratchet UNCHANGED (version attestation lines allowed). The installer stays opt-in (no default-path wiring). Keep internal/ + repo-polish + `.claude/settings.local.json` + the `*-implement.md`/`*-deploy.md` handoffs untracked. If any gate/probe fails, STOP and report.

## Rollback
`git revert <release range>` — additive (a doc table + a new opt-in helper + docs); no existing behavior changed; installer never default-on. Re-push; re-mirror.

## Return
Deploy report: version, deploy hash, tag, release URL, GEMINI + README badge = v3.29.0, FR-01..FR-27/32-skills confirmation, the B smoke (table + 6 commands, survives sweep) + A smoke (6 marked prompts, 0 claude-path leak, idempotent, collision-refuse, no-frontmatter hard-fail), FR-07 confirmation, FR-14 docs commit SHA.
