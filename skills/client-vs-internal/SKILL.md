---
name: client-vs-internal
description: Use ONLY when docs/audience.md exists (audiences defined during onboarding) OR the operator explicitly asks to optimize a surface for client-facing vs internal use. Steers app surfaces differently — client-facing = simple/guided/trust-first; internal = robust controls/power-features. If docs/audience.md is absent, this skill does nothing (silent no-op) — do NOT activate or create the file. Not for projects without defined audiences.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.5
risk_level: low
invocation: automatic
expected_outputs:
  - per-surface audience classification (client-facing vs internal)
  - simplicity/robustness guidance applied to the surface being built
related_workflows:
  - eight-phase-flow.md
hook_dependencies:
  - none
---

# Client vs Internal

> **Style:** Mode-B-lite. **Artifact-gated** — inert unless `docs/audience.md` exists.

## Purpose

Client-facing teams build for two very different audiences. Clients need simplicity and trust (never Salesforce-complex); internal teams need robust controls and power-features. This skill applies the right posture to each surface, using the audiences the operator defined at onboarding.

## When to invoke

- `docs/audience.md` exists AND a UI/app surface is being designed or built.
- Operator says "is this for clients or internal", "simplify for the client", "this is an internal tool".

## Do not invoke when

- **`docs/audience.md` absent** → silent no-op; do not activate or create it.
- Non-UI / backend-only work with no audience-facing surface.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Audience definitions | `docs/audience.md` | **STOP — no-op.** Onboarding (`/onboard`) creates it. |
| Surface being built | current task | nothing to classify; exit |

## Procedure

1. **Existence gate (FIRST STEP).** No `docs/audience.md` → exit silently. Do not create it.
2. **Read** `docs/audience.md` (which surfaces are client-facing vs internal; per-audience needs).
3. **Classify** the surface in scope: client-facing, internal, or shared.
4. **Apply posture:** client-facing → simplest viable flow, guided, minimal options, trust-critical interactions real; internal → fuller controls, power-features, admin affordances.
5. **Flag mismatches** (e.g. exposing internal complexity to a client surface) and recommend the audience-appropriate alternative.
6. **Ambiguous audience → ask** the operator (FR-19).

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Audience classification + posture guidance | chat / design brief | Mode A / Mode-B-lite |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact absent | step 1 | silent no-op (correct) |
| Client surface over-complex | step 5 | flag; recommend simplification |

## Escalation path

- Ambiguous audience → ask operator (FR-19).
- Audience model needs updating → `project-onboarding`.

## Anti-patterns

- Do not activate/create the file when `docs/audience.md` is absent.
- Do not make client surfaces Salesforce-complex.
- Do not strip necessary controls from internal surfaces for "simplicity".

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
