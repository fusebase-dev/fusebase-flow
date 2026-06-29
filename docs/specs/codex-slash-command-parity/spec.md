# Spec — codex-slash-command-parity

**Status:** DONE — shipped in **v3.29.0** (deploy hash `8799992`, tag `v3.29.0`, 2026-06-29). Operator chose **B + optional A**; both arms shipped. Release: https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.29.0
**Created:** 2026-06-26
**Baseline:** FuseBase Flow v3.28.0
**Source:** Operator — Flow's 6 slash commands (`/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort`) are Claude-Code-only (`.claude/commands/*.md`). The compatibility matrix says Codex has "no slash commands — invoke skills by name." Multi-agent users (Claude Code + Codex) want command parity.
**Lane:** Full (AGENTS.md + optional installer + docs + tests; additive/low-risk).
**Design review:** Codex 2026-06-26 → **RESCOPE**, with authoritative GROUND TRUTH on its OWN mechanism: native Codex custom prompts live in **`~/.codex/prompts/*.md` — user-global, NOT repo-shared, and DEPRECATED in favor of skills**; invoked **`/prompts:<basename>`** (namespaced, not bare `/<name>`); they USE YAML frontmatter (`description:`, `argument-hint:` — do NOT strip); args `$1..$9`/`$ARGUMENTS`; a repo-local `.codex/prompts/` is **not supported**; Codex **plugins bundle skills/mcp/apps/hooks, NOT slash commands**. Net: **B (the AGENTS.md command convention) is the genuine, repo-portable parity and matches Codex's recommended skills model; A (native prompts) is at best an optional per-machine, namespaced, deprecated polish.** Findings folded below; D1–D5 locked.

## Grounded facts (verified 2026-06-26)
- Codex CLI **0.128.0** installed. `codex plugin marketplace` exists (Codex HAS a plugin system, parallel to Flow's Claude Code plugin). No `prompt` CLI subcommand (custom prompts are a TUI feature). No `~/.codex/prompts/` on the machine yet.
- Flow's `.codex/` ships **agents + config.toml.example + hooks.json.example** — **no commands**. The 6 command bodies live canonically at `hooks/local/fusebase-flow-overlays/commands/*.md` (mirrored to `.claude/commands/*.md`).
- Codex command bodies need light adaptation: strip the Claude `description:` frontmatter; repoint `.claude/agents/...` → `.codex/agents/...`; keep `python hooks/local/...` paths (portable).

## Goal — both arms
- **A — native Codex `/commands`.** Make `/fusebase-health` etc. real slash commands in Codex's interactive UI, single-sourced from the canonical command bodies (no hand-maintained 3rd copy).
- **B — universal command convention.** An `AGENTS.md` "command equivalents" table so typing `/product-owner` (as text) triggers the right action in **Codex, Cursor, Copilot, Gemini** — repo-committed, every agent, no native mechanism required.

## In scope — B (primary) + optional A
### B — universal command convention (PRIMARY, repo-portable)
- In the canonical Flow overlay that becomes `AGENTS.md` (the portable baseline every agent reads — edit the overlay source so it propagates to AGENTS.md/CLAUDE.md/GEMINI.md), REPLACE the current single "slash commands" sentence with a compact **6-row command-equivalents table**: `command` · native Claude `/cmd` · Codex native `/prompts:cmd` (if A installed) · **portable fallback** (e.g. "invoke the `product-owner` skill / type `/product-owner`"). Pointer-style, no command-body re-paste (FR-23/FR-26). Outside any version-swept region + outside `FLOW:PRESERVE`.

### A — optional native Codex prompts (per-machine polish, opt-in)
- A transform that GENERATES Codex prompt bodies from canonical `hooks/local/fusebase-flow-overlays/commands/*.md`: convert the Claude frontmatter to Codex YAML (`description:` kept; add `argument-hint:` only if the command takes args — none do today); repoint `.claude/agents/...` → `.codex/agents/...`; preserve the PO-activation boot block (FR-27/PO-boot) + markers. Single-source — drift-guard test, no hand-maintained copy.
- An explicit opt-in installer `hooks/local/install-codex-prompts.sh`: writes the generated prompts to `$CODEX_HOME/prompts/` (default `~/.codex/prompts/`), top-level `.md`, each MARKED as Flow-generated (a header sentinel), idempotent, and REFUSES to overwrite an unmarked existing file unless `--force`. **Never default-on; never called by `post-fusebase-update.sh` automatically** (it writes user-global files). The commands appear in Codex as `/prompts:fusebase-health` etc. (namespaced; the feature is Codex-deprecated — documented honestly).

### Docs
- `docs/compatibility.md` Codex row: "no slash commands" → "command parity via the AGENTS.md command-equivalents convention (every agent) + optional `install-codex-prompts.sh` for native `/prompts:<cmd>` (per-machine, deprecated)." README § Commands & capabilities note.

## Out of scope / non-goals
- A Codex *plugin* package (parallel to the Claude Code plugin) — note as a possible follow-up if the design review finds the plugin path cleaner/more-portable than prompts (D1).
- Changing command behavior/bodies (only delivery/adaptation).
- Cursor/Copilot native command mechanisms (B covers them by convention).

## Constraints (FR-07)
- No diff to FLOW_RULES FR rows / the 3 deploy-policy rule semantics / ratchet-governance.yml.
- `AGENTS.md` is editable (portable baseline; sync sweeps its version/FR strings — keep the new table out of the swept regions). New helper under `hooks/local/`. If a repo `.codex/prompts|commands/` source dir is added, it mirrors from canonical (don't hand-maintain).

## Decisions (LOCKED — design review folded)
- **D1 (mechanism — verified ground truth):** native Codex commands = **`$CODEX_HOME/prompts/*.md` (default `~/.codex/prompts/`)**, top-level markdown, **YAML frontmatter** (`description:`, `argument-hint:` — normalize, do NOT strip), args `$1..$9`/`$ARGUMENTS`, invoked **`/prompts:<basename>`**. **User-global, NOT repo-local; deprecated** by Codex in favor of skills. A repo `.codex/prompts/` is NOT a Codex read path — drop it. Plugins do NOT carry commands (follow-up packaging only).
- **D2 (posture):** **B is the primary, portable parity** (matches Codex's skills model). **A is optional, per-machine "native polish"** with honest expectations (`/prompts:<name>`, user-global, deprecated). Do NOT have `post-fusebase-update.sh` write user-global Codex files by default — A is an explicit opt-in installer.
- **D3 (single-source):** generate the Codex prompt bodies from canonical `hooks/local/fusebase-flow-overlays/commands/*.md` via a transform (Claude frontmatter → Codex `description`/`argument-hint`; `.claude/agents`→`.codex/agents`); drift-guard test; no hand-maintained copy.
- **D4 (B format + budget):** REPLACE the existing slash-command sentence in the Flow overlay (the AGENTS.md/overlay region, NOT `FLOW:PRESERVE`) with a compact **6-row command-equivalents table** (columns: command · native Claude `/cmd` · Codex native `/prompts:cmd` if installed · portable fallback = "invoke the `<skill>` skill / type the command"). Compact, pointer-style, outside the version-swept region.
- **D5 (installer):** A = an explicit, idempotent opt-in helper `hooks/local/install-codex-prompts.sh` → writes to `$CODEX_HOME/prompts`, MARKS generated files + REFUSES unmarked-collision overwrites unless `--force`. Optional recovery-integration flag; never default-on.

## Acceptance criteria
- **AC1 (B)** The overlay→`AGENTS.md` (and the propagated CLAUDE.md/GEMINI.md) carry the 6-row command-equivalents table (all 6 commands, with the portable fallback column); a test asserts it's present + lists each command; compact, outside the version-swept region + outside `FLOW:PRESERVE`.
- **AC2 (A — transform single-source)** `install-codex-prompts.sh`'s generated bodies are produced from canonical `fusebase-flow-overlays/commands/*.md` (Codex frontmatter; `.codex/agents/` paths); a drift-guard test asserts each generated body matches its canonical source post-transform (regenerating after a canonical edit changes the output) — no hand-maintained copy.
- **AC3 (A — honest surfacing + safety)** A structural test: the installer writes marked `.md` files to a temp `$CODEX_HOME/prompts/`, is idempotent, and REFUSES to overwrite an unmarked file without `--force`. Headless "Codex recognizes them as `/prompts:<name>`" is NOT fully assertable (TUI feature) → document a one-line manual verification (`open Codex, type /prompts:`) + the structural checks. Never default-on; `post-fusebase-update.sh` does not call it.
- **AC4 (docs)** compatibility.md Codex row + README updated to the real new state (B convention + optional A; A labeled per-machine/deprecated/namespaced).
- **AC5 (gate)** preflight 0/0; run-tests PASS incl. new tests; check-module-size --all exit 0; mirror 0 drift; FR-07 clean.

## Tasks
- **T1 (B)** overlay command-equivalents table → AGENTS.md/CLAUDE.md/GEMINI.md (via the overlay source; re-sweep if needed).
- **T2 (A)** transform + `hooks/local/install-codex-prompts.sh` (opt-in, marked, collision-safe, idempotent; NOT wired into post-fusebase-update).
- **T3 (docs)** compatibility.md Codex row + README § Commands note.
- **T4** tests (AC1 table-present, AC2 transform drift-guard, AC3 installer structural+collision) + re-mirror if a skill/agent changed (none expected).

## Risks
- **Building on an assumed Codex mechanism** (the recurring trap) — mitigated: T0/D1 verify it FIRST, and the Codex design-review agent confirms its own mechanism.
- **Global-not-repo native prompts** — if A is per-machine, lean on B (repo-portable) as the primary parity guarantee; A is the polish layer (D2).
- **Always-on bloat** from B's table — keep it compact, pointer-style (D4).
- **Drift** between Claude commands and Codex-adapted copies — single-source + drift-guard test (D3).
