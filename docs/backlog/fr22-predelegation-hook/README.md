# Backlog — fr22-predelegation-hook (FR-22 Phase 2 / item F)

**Status:** parked
**Source:** deferred from `fr22-delivery-guarantee` (Phase 1 shipped v3.27.0); design review (Codex 2026-06-16) RESCOPE.
**Lane (when picked up):** Full (PreToolUse hook + matcher coverage + config + tests).

## What F is
A **pre-delegation PreToolUse check** that a code-writing sub-agent launch carries the FR-22 comment-policy Delegation push block. Concept is FR-22-safe — it inspects the **prompt / referenced handoff text** (a process artifact), never comment **content** semantics.

## Why it was deferred (not shipped in Phase 1)
Design review found F, as originally written, **inert** and its heuristic **fuzzy**:
1. **Inert under the shipped matchers.** `.claude/settings.json.example` + `.codex/hooks.json.example` invoke PreToolUse for **Bash / Edit / Write only**, NOT the Task / Agent (sub-agent launch) tool. A handler keyed to delegation would never run → it would recreate the exact mandatory-but-undelivered failure `fr22-delivery-guarantee` exists to fix.
2. **Fuzzy heuristic.** A "code-writing delegation" keyword heuristic over-fires on research / Explore delegations and misses code delegations that use other tool names or dynamic prompts.

## Prerequisites this ticket MUST add before F is buildable
1. **Host-matcher coverage.** `.claude/settings.json.example` + `.codex/hooks.json.example` + the settings-merge defaults + hook-coverage docs must invoke PreToolUse for the delegation tool(s); otherwise the handler never fires.
2. **Explicit delegation markers, not generic keywords.** Fire only on a `docs/tmp/handoff/*-implement.md` reference OR a structured `Role boundary: code-edit` field — never on words like "implementation" / "codebase". Allow when the prompt or referenced handoff already contains the FR-22 block marker.
3. **Warn-only default + telemetry.** No hard block on a missing block (matches Phase 1's warn-class posture); record a supplemental audit event.
4. **Config home = `policies/comment-policy.yml`** (not `required-artifacts.yml`).

## Boundary (unchanged from FR-22)
- Still **no content gate** — F inspects prompt/handoff text only, never comment semantics.
- No FR rule-row edit; no deploy-policy / `ratchet-governance.yml` change.

## Relation to shipped work
- Phase 1 (A–E) shipped v3.27.0: present-by-construction handoff block, write-time digest non-propagation note, `comment_policy_review_applied` warn-signal, artifact-vs-content distinction doc, carve-out clarity.
- Spec for the parent ticket: `docs/specs/fr22-delivery-guarantee/spec.md` (item F / AC6 marked DEFERRED there).
