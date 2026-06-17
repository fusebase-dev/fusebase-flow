# Spec — po-verifiable-boot

**Status:** DONE — shipped in **FuseBase Flow v3.27.0** (release commit `53e9437`, tag `v3.27.0`, 2026-06-17). Design review folded. Feature commits `8b79af3..eea8bd9`.
**Created:** 2026-06-16
**Baseline:** FuseBase Flow v3.26.0 (stacks on the local fr22-delivery-guarantee Phase 1 commits)
**Source:** Operator request — make `/product-owner` run the FuseBase Flow operating requirements as a verifiable activation "boot sequence" so the PO provably starts by the rules. Builds directly on the `fr22-delivery-guarantee` lesson: *"mandatory" without delivery + artifact-level verification is just "optional with extra words."*
**Lane:** Full (entry-point command + agent + 2 hooks + a signal + tests).
**Design review:** Codex 2026-06-16 → **RESCOPE** (feasible, not inert). Decisive check PASSED: `UserPromptSubmit → user_prompt_submit.py` (`.claude/settings.json.example:28-33`) and `Stop → stop.py` (`:60-77`) are wired in both example settings (`.codex/hooks.json.example` too); no tool-matcher gap. Folded corrections: **(BLOCKER)** `stop.py` only runs recommended-signal checks AFTER a done/deploy claim — so a separate PO-activation Stop path is required, NOT a `before_done_claim.recommended` entry; **(HIGH)** edit canonical `agents/product-owner/AGENT.md` then mirror (not the generated `.claude`/`.codex` copies); **(MEDIUM)** detect the PO session via transcript scan for the exact `/product-owner` input or the marker — do NOT rely on audit-log session correlation (audit_logger keys session from env, not event.session_id); **(LOW)** ASCII-only marker. D1–D5 locked below.

## Problem
`/product-owner` today (`.claude/commands/product-owner.md:9`) says "Self-attest per FLOW_RULES.md (FR-01..FR-26); load role-discipline + communication" — but it produces **no visible, structured proof** the PO booted by the rules. Same class as the FR-22 finding: prose-mandatory, voluntary-in-practice, invisible. In a long/automated session you can't tell whether the PO actually adopted its operating discipline before doing ticket work.

## Goal (Tier 2 — verifiable boot)
1. **Delivery (present-by-construction):** invoking `/product-owner` renders a compact operating-rules checklist the PO completes and echoes as its FIRST output, ending with a one-line machine-detectable marker.
2. **Verification (the "verifiable" part):** a hook records whether the activation marker appeared, so "the PO booted by the rules" is a **checkable signal**, not a hope — at a firing point that ACTUALLY runs (the FR-22 hook-F lesson).

## Why this is enforceable where FR-22 hook F was not
FR-22's pre-delegation hook needed a **Task-tool** PreToolUse matcher that the shipped `settings.json.example` does not include → inert. The PO boot rides on **UserPromptSubmit** (detect the `/product-owner` invocation) + **Stop** (detect the marker in the transcript) — both are **general events already wired** in `.claude/settings.json.example` / `.codex/hooks.json.example` (per CLAUDE.md: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, PreCompact). No new matcher coverage required. `user_prompt_submit.py` + `stop.py` already have the pattern-detect / transcript-signal architecture to extend.

## In scope
- **A — command boot block (delivery).** `.claude/commands/product-owner.md` **and** its overlay source `hooks/local/fusebase-flow-overlays/commands/product-owner.md` (kept byte-identical): replace step 1 with a literal, present-by-construction **activation block** — a **6–8 line** operating-rules checklist (role: advise+plan, NO app code FR-01 · lane-first FR-21 · lifecycle Specify→…→handoff · decisions operator-locked · questions in chat FR-19 · deploy approval-gated · Mode A/B + pointers-over-re-paste FR-23/26 · read North Star if onboarded) — that the PO must **echo as its first reply**, ending with the **ASCII-only** one-line marker (no box/middle-dot glyphs — grep/transcript-stable):
  `[[ PO-ACTIVATED | FuseBase Flow <VERSION> | FR-01..FR-26 | no-app-code | lane-first | operator-locked-decisions | approval-gated-deploy | context:<north-star|generic> ]]`
  **Lean:** pointers to FLOW_RULES, never a re-paste. The rules stay canonical in FLOW_RULES.
- **B — same boot in the CANONICAL agent source (both invocation paths).** Edit `agents/product-owner/AGENT.md` (the canonical source), then **re-mirror via `mirror-agents.sh`** → `.claude/agents/product-owner.md` + `.codex/agents/product-owner.md` (do NOT hand-edit the generated mirrors — they'd be overwritten). Carries the activation block + marker so the PO boots-by-construction whether reached via the slash command OR spawned via the Agent tool / description-match. A test asserts the command boot block and the agent boot block match (drift guard, D4).
- **C — UserPromptSubmit detection.** `hooks/handlers/user_prompt_submit.py`: detect a `/product-owner` invocation in `event.user_prompt` (it already reads that field) → emit a one-line non-blocking reminder ("PO session — emit the activation boot + marker first") + a `po_activation_requested` audit event (supplemental telemetry only — NOT relied on for the Stop check, per the MEDIUM finding). Warn-class, never blocks.
- **D — dedicated PO-activation Stop check (NOT the done/deploy recommended list).** `hooks/handlers/stop.py`: add a **separate** PO-activation path that runs **independent of the done/deploy `CLAIM_PATTERNS` gate** (the existing recommended-list only fires after a done/deploy claim — a normal PO first reply has none, so it would never fire). The path: if the transcript shows a `/product-owner` activation (exact `/product-owner` input OR the PO self-attestation) AND the ASCII `PO-ACTIVATED | FuseBase Flow` marker is absent → emit a **warn** (never deny; never touches the done/deploy decision). Detects PO-session + marker by literal transcript scan only — no audit-log session correlation, no rule-content inspection. Add `po_activation_attested` to `signal_definitions` for documentation/consistency, but the firing logic is the dedicated path, not `before_done_claim`.

## Out of scope / non-goals
- Enforcing every later PO turn (this verifies the **boot**, not each subsequent reply — the per-output footer + the existing gates cover ongoing conduct).
- Blocking/deny on a missing boot (warn only — a hard block on activation would be heavy and brittle).
- Re-pasting FLOW_RULES into the command (pointers only; FR-23/26).
- Changing the PO role rules themselves (canonical in FLOW_RULES + role-discipline).

## Constraints (FR-07)
- **No diff** to: `FLOW_RULES.md` FR rule rows; the 3 deploy-policy rule semantics; `ratchet-governance.yml`.
- **Editable:** the command (+ overlay), the product-owner agent (+ mirror), `user_prompt_submit.py`, `stop.py`, `required-artifacts.yml`.
- Agent files are mirrored (`mirror-agents.sh`) — re-mirror after editing; keep `.claude`/`.codex` agent copies in sync.

## Decisions (LOCKED — design review folded)
- **D1 (firing point + PO-session detection):** UserPromptSubmit (detect `/product-owner` → reminder) **+** a dedicated Stop path (verify marker). Both events confirmed wired (no matcher gap). stop.py detects "PO session" by **literal transcript scan** for the exact `/product-owner` input or the PO marker — NOT the audit event (fragile session keying). The dedicated path runs outside `CLAIM_PATTERNS` so it actually fires on a PO first reply.
- **D2 (posture):** **warn, never deny.** Missing boot is telemetry, not a hard lifecycle gate.
- **D3 (marker + leanness):** **ASCII-only** marker `[[ PO-ACTIVATED | FuseBase Flow <VERSION> | ... ]]` (grep-stable); checklist **6–8 tight lines**; pointers, not re-paste.
- **D4 (single-source):** **both** command (+overlay) and **canonical `agents/product-owner/AGENT.md`** (then mirror) — command covers the slash path, agent covers the description/sub-agent path. Drift guard = a test comparing the delimited boot block across both homes.
- **D5 (safety):** FR-07-clean (no FR rows / 3 deploy-policy / ratchet edits); delivery + artifact-level verification only (Stop inspects the literal marker, never PO reasoning); existing deny gates untouched — RED/GREEN tests prove a required done-gate signal still denies.

## Acceptance criteria
- **AC1 (A)** `/product-owner` renders the 6–8 line activation block + the ASCII marker by construction; a test asserts both command copies contain the block + marker template and are byte-identical.
- **AC2 (B)** Canonical `agents/product-owner/AGENT.md` carries the boot block + marker; after `mirror-agents.sh` the `.claude`/`.codex` copies match canonical (mirror 0 drift); a drift-guard test asserts the command boot block and the agent boot block match.
- **AC3 (C)** `user_prompt_submit.py` detects a `/product-owner` prompt → emits the reminder (+ supplemental `po_activation_requested` event); non-PO prompts do not (no false positive); never blocks. Test proves both.
- **AC4 (D)** `stop.py`'s dedicated PO-activation path (independent of `CLAIM_PATTERNS`): a transcript with a `/product-owner` activation but no marker → **warn + stop ALLOWS**; with the marker → no warn; a non-PO transcript → no warn (no false positive); a done/deploy claim missing a **required** signal → still **deny** (gate not loosened). RED-then-GREEN proving the path fires without a claim phrase.
- **AC5 (gate)** preflight 0/0; run-tests PASS incl. new tests; `py_compile` stop.py + user_prompt_submit.py; check-module-size --all exit 0 (both handlers under ceiling); mirror 0 drift (agent mirrors); FR-07 clean (FR rows / 3 deploy policies / ratchet unchanged).

## Tasks
- **T1 (A)** command boot block + ASCII marker (both command copies, byte-identical).
- **T2 (B)** canonical `agents/product-owner/AGENT.md` boot block + marker → `mirror-agents.sh`.
- **T3 (C)** user_prompt_submit.py `/product-owner` detection + reminder (+ supplemental audit event).
- **T4 (D)** stop.py dedicated PO-activation Stop path (outside CLAIM_PATTERNS; warn-only; literal transcript scan) + `po_activation_attested` signal_definition.
- **T5** tests (AC1 command-contains-block, AC2 command/agent drift-guard, AC3 prompt-detect, AC4 PO-activation RED-GREEN incl. required-still-denies) + re-mirror agents.

## Risks
- **Another inert lever (the FR-22 trap):** mitigated by riding UserPromptSubmit + Stop (already-wired general events) — design review must CONFIRM they fire under the shipped example settings.
- **Boot bloat:** a heavy boot taxes every PO session and violates the economy rules it enforces — keep ~12 lines, pointers only (D3).
- **"Is this a PO session" false positives:** keep detection to the explicit `/product-owner` invocation + the self-identifying marker, not fuzzy keywords (D1).
- **Command/agent drift:** two homes for the block (D4) — a test asserts they match.
