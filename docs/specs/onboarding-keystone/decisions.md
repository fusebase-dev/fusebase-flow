# Decisions — onboarding-keystone

**Letter prefix:** D
**Approval status:** Locked by operator ("proceed with implementation") on 2026-05-31
**Linked spec:** `docs/specs/onboarding-keystone/spec.md`

| ID | Title | Decision | Lock |
|---|---|---|---|
| D1 | Constitution | Do NOT regenerate Flow's `docs/constitution.md`; project vision lives in `docs/north-star.md` + AGENTS project-values | LOCKED |
| D2 | zoom-out FR | Already shipped (FR-20, v3.3.0) — out of scope here | LOCKED |
| D3 | Onboarding trigger | `/onboard` slash command + natural language; PO-owned | LOCKED |
| D4 | Domain-expert skill location | project-local (not Flow canonical, not mirrored) | LOCKED |
| D5 | Offer-once | instruction-based (skill offers North Star at most once, respects silence); no state-tracking artifact in v1 | LOCKED |
| D6 | Downstream surface | all Flow-canonical (downstream inherits on install); artifacts are per-project, created locally | LOCKED |
| D7 | Discovery mechanism | **3-layer, hook-independent**: (1) AGENTS.md baseline instruction [universal], (2) `session_start.py` scan [Claude accelerator], (3) per-skill existence-guard [universal floor] | LOCKED |
| D8 | Change-detection (checksum) | OUT for v1 — presence + `last_updated` frontmatter only; checksum-based "changed since referenced" deferred | LOCKED |
| D9 | v1 scope | G1 + G2 + discovery + commands + template; G5/G6/G9/G11 follow-up | LOCKED |

## D1. Constitution stays Flow-owned
`docs/constitution.md` describes Flow itself and is referenced by Flow docs. Regenerating it per-project risks the health-engine couplings and confuses Flow's own identity. Project vision/identity lives in **`docs/north-star.md`** (new, project-specific) + the existing `AGENTS.md` § Project-specific values fields. Lowest risk; no health-marker impact.

## D5. Offer-once without state
A skill may offer to capture a North Star at most once per session when relevant, then respect silence (FR-11/FR-16/FR-19). No `state/` tracking file in v1 — keeps it simple and stateless; the cost is a possible re-offer in a later session, which is acceptable.

## D7. Hook-independent discovery (the load-bearing decision)
Hooks are Claude-Code-only (Codex differs; Cursor/Copilot/Gemini none). Therefore discovery MUST work with hooks OFF:
- **Layer 1 (universal):** `AGENTS.md` "## Active project context" instruction — every surface reads AGENTS.md, so every agent is told to check for project artifacts at session start.
- **Layer 2 (accelerator):** `session_start.py` deterministically scans + injects on Claude Code. Optional; never a dependency.
- **Layer 3 (floor):** each input-dependent skill's first step is an existence check (artifact absent → silent no-op; never auto-create).
Correctness rests on Layers 1+3 (universal); Layer 2 is enhancement.

## D9. v1 scope (prove the mechanism, then replicate)
Build the full mechanism + `north-star` as the flagship gated skill. G5/G6/G9/G11 reuse the identical guard pattern in a follow-up — lower risk than a 6-skill mega-batch.

## Lock confirmation
All D1..D9 LOCKED 2026-05-31 (operator delegated). Implementation authorized.
