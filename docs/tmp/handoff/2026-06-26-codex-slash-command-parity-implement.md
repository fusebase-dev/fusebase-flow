# Implement handoff — codex-slash-command-parity (B + optional A)

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.28.0. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07, FR-13, FR-22 (comments), FR-23/FR-26 (keep the always-on table compact, pointers not re-paste), FR-25, **FR-27 (liveness — bound/poll any long check, never launch bare)**. **Synchronous; stop at gate; do NOT bump VERSION/push/deploy.**

## COMMENT POLICY (FR-22) — for any code you write (the installer/transform)
```
ONLY tripwire + retrieval-pointer comments. Remove WHAT-restating / recorded-elsewhere / changelog. Don't match density upward. Keep pointers.
```
At done emit `comment-policy review: applied (FR-22)` (or the N/A marker if no code diff).

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-27 (stop at Amendment log).
2. `docs/specs/codex-slash-command-parity/spec.md` — LOCKED (decisions D1–D5, tasks T1–T4, ACs). The design review's GROUND TRUTH on Codex is authoritative: native prompts = `$CODEX_HOME/prompts/*.md`, user-global, deprecated, invoked `/prompts:<basename>`, YAML frontmatter (`description:`/`argument-hint:`), args `$1..$9`/`$ARGUMENTS`; repo-local `.codex/prompts` NOT a read path; plugins don't carry commands.
3. The 6 canonical command bodies: `hooks/local/fusebase-flow-overlays/commands/{fusebase-health,onboard,product-owner,handoff,token-waste-audit,find-wasted-effort}.md`.
4. Where slash commands are currently described — grep across `AGENTS.md`, `hooks/local/fusebase-flow-overlays/agents-md-overlay.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules/*.mdc`, `docs/compatibility.md`, `README.md`.
5. `flow-skills/role-discipline/references/ai-developer.md`.

## Scope — T1–T4, one commit each. B is primary; A is optional/opt-in.

- **T1 (B) — command-equivalents table (the portable parity).** Single source of truth = a compact **6-row table** in `AGENTS.md` (the portable baseline every agent reads) + its canonical overlay source `hooks/local/fusebase-flow-overlays/agents-md-overlay.md`. Columns: **Command · Claude Code (`/cmd`) · Codex (`/prompts:cmd` if installed) · Portable (invoke the `<skill>` skill / type `/cmd`)**. Place it where the current "slash commands" sentence lives (NOT inside `FLOW:PRESERVE`, NOT in a version-swept region). Then make every adapter's slash-command mention CONSISTENT with it: Claude keeps native `/cmd`; Codex/Gemini/Copilot/Cursor should reference the portable convention (don't imply bare `/cmd` works natively there). Keep it pointer-style — do NOT paste command bodies (FR-23/26).
- **T2 (A) — optional native Codex installer (opt-in, safe).** A transform that GENERATES Codex prompt bodies from the 6 canonical command bodies: Claude frontmatter → Codex YAML (keep `description:`; no `argument-hint:` needed — these commands take no args); repoint `.claude/agents/...` → `.codex/agents/...`; preserve the PO-activation boot block + markers. Ship `hooks/local/install-codex-prompts.sh`: writes the generated `.md` to `$CODEX_HOME/prompts/` (default `~/.codex/prompts/`), each file carrying a **Flow-generated marker header**; idempotent; REFUSES to overwrite an UNMARKED existing file unless `--force`; prints the `/prompts:<name>` usage + the "deprecated, per-machine" honest note. **MUST NOT be called by `post-fusebase-update.sh` or any default path** (it writes user-global files) — explicit opt-in only. `bash -n` clean; FR-25 <ceiling.
- **T3 (docs).** `docs/compatibility.md` Codex row: "no slash commands" → "command parity via the AGENTS.md command-equivalents convention (every agent) + optional `install-codex-prompts.sh` for native `/prompts:<cmd>` (per-machine, deprecated)." README § Commands & capabilities: one note that the commands work in Codex/Cursor/Copilot/Gemini via the convention (+ optional native Codex install).
- **T4 — tests.** `hooks/tests/`: AC1 (AGENTS.md carries the table + lists all 6 commands + the portable column); AC2 (the transform is single-sourced — generated body matches canonical post-transform; editing a canonical body changes the generated output → drift-guard); AC3 (installer structural: writes marked files to a temp `CODEX_HOME`, idempotent, REFUSES unmarked-collision without `--force`). Wire into run-tests.sh. Re-mirror only if a skill/agent changed (none expected). Genuine, loud asserts, no false-green.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / the 3 deploy-policy rule semantics / ratchet-governance.yml. In-scope: AGENTS.md + overlay + adapters (slash-command mentions), a new `hooks/local/install-codex-prompts.sh`, docs, tests. The AGENTS.md table must sit OUTSIDE the version-swept region (so `sync-version-strings` doesn't mangle it) and outside `FLOW:PRESERVE`. The installer must never run by default. Do NOT bump VERSION/push/deploy.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ FR-22 comments (installer)  ☐ FR-25 <ceiling  ☐ table compact (FR-23/26)  ☐ installer opt-in only (not default-on)
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n hooks/local/install-codex-prompts.sh` · run-tests PASS incl. new tests · check-module-size --all exit 0 · mirror 0 drift · FR-07 clean · the AGENTS.md table survives a `sync-version-strings.sh --dry-run` unchanged (outside the swept region). Emit the FR-22 marker. Produce the gate report; HALT. A Codex impl review runs after the gate.

## Return
Gate report: per-task SHAs (T1–T4), AC evidence (B table present + lists 6; A transform drift-guard; A installer collision-safe + idempotent + opt-in), gate numbers, FR-07 confirmation, and confirmation the installer is NOT wired into any default path.
