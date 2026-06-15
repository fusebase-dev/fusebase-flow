# Backlog ticket — adapter-overlay-refresh-parity

**Status:** parked (filed 2026-06-15 as the U6 follow-up deferred from `upgrade-tooling-hardening`, shipped v3.25.0)
**Source friction:** TWO independent consumer upgrade reports (paperclip+hermes-v1 I5, WorkHub Managed W3) — `v3.21.1 → v3.23.1` on Windows/Git-Bash.
**Predecessor:** `docs/specs/upgrade-tooling-hardening/spec.md` (v3.25.0). That release shipped U5 (the GEMINI **version-string** regex fix — un-stuck the `Fusebase Flow Local v2.1` drift) but **deferred U6**: a full marker-anchored **overlay-refresh** path for the secondary adapters, because it needs a marker-strategy design of its own (per the Codex RESCOPE verdict).

## Pain

`AGENTS.md` and `CLAUDE.md` get a **marker-anchored overlay refresh** on upgrade (the `FLOW:PRESERVE` blocks survive, project rules are preserved, only the Flow-owned overlay region is rewritten). The secondary adapters — **`GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules/*.mdc`** — have **no equivalent refresh path**:

- They only receive the **version-string sweep** (U5), not a content overlay refresh. So when the Flow overlay content evolves (new FR rows, new skills, changed attestation, new state-announcement format), these adapters silently fall behind the canonical AGENTS/CLAUDE overlay.
- This is exactly how GEMINI drifted to a stale header in the first place — version-only sync masks deeper content drift. Fixing the version string (U5) does not fix the missing-overlay-region problem.
- A consumer who relies on Gemini/Antigravity, Copilot, or Cursor as their primary surface gets a progressively staler Flow overlay with each upgrade, with no signal.

## Why it was deferred (not folded into v3.25.0)

Unlike AGENTS/CLAUDE (which already carry begin/end overlay markers), the secondary adapters have **no marker convention**. Designing one requires deciding, per adapter:
- where the Flow-owned region begins/ends without clobbering IDE-specific or project-specific content,
- how `FLOW:PRESERVE`-equivalent project carve-outs work in each file format (`.md`, `.mdc`, copilot-instructions),
- how the refresh interacts with the U4 sync allowlist and the health-check `PARTIAL_UPGRADE` derived-fact comparison (so a stale secondary adapter becomes a *detectable* fact, not silent drift).

## Rough acceptance (to be specified)

- A **marker-anchored overlay-refresh path** for GEMINI / copilot / cursor adapters, parallel to AGENTS/CLAUDE: rewrites only the Flow-owned overlay region, preserves project + IDE-specific content (a `FLOW:PRESERVE`-equivalent).
- `upgrade.sh` / `post-fusebase-update.sh --refresh-overlays` refreshes these adapters' overlay regions, not just their version strings.
- The health-check derived-fact comparison flags a **secondary adapter whose overlay region is stale** (extends the v3.24.0/v3.25.0 `PARTIAL_UPGRADE` engine beyond version/FR/skill-count to overlay-region content).
- The U4 sync allowlist + under-reach guard continue to hold (no consumer-doc reach; no framework file omitted).
- No regression to the AGENTS/CLAUDE overlay refresh or the byte-exact copy / mirror contracts.

## Notes

- Builds directly on v3.25.0: the U4 executable allowlist + the U7 `PARTIAL_UPGRADE` derived-fact engine are the foundation; this ticket extends them from version-string parity to **overlay-content parity**.
- Reactive-shipping context: same two consumer reports that drove `upgrade-tooling-hardening`. U5 (version) shipped; U6 (overlay) is the remaining half.
