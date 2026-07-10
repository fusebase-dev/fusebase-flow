---
name: client-vs-internal
description: Use ONLY when docs/audience.md exists (audiences defined during onboarding) OR the operator explicitly asks to optimize a surface for client-facing vs internal use. Steers app surfaces differently — client-facing = simple/guided/trust-first; internal = robust controls/power-features. If docs/audience.md is absent and the operator did not explicitly request the posture check, this skill does nothing (silent no-op) — do NOT create the file. Not for projects without defined audiences.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.5
risk_level: low
invocation: automatic
expected_outputs:
  - per-surface audience classification (client-facing vs internal)
  - simplicity/robustness guidance applied to the surface being built
  - posture checklist rows persisted as spec ACs (via requirements-specification, alongside QP-xx)
related_workflows:
  - eight-phase-flow.md
hook_dependencies:
  - none
---

# Client vs Internal

> **Style:** Mode-B-lite. **Artifact-gated by default** — inert unless `docs/audience.md` exists or the operator explicitly requests the posture check.

## Purpose

Client-facing teams build for two very different audiences. Clients need simplicity and trust (never Salesforce-complex); internal teams need robust controls and power-features. This skill applies the right posture to each surface, using the audiences defined at onboarding (or the audience the operator states when explicitly requesting the check).

## When to invoke

- `docs/audience.md` exists AND a UI/app surface is being designed or built.
- Operator says "is this for clients or internal", "simplify for the client", "this is an internal tool".

## Do not invoke when

- **`docs/audience.md` absent and no explicit operator request** → silent no-op; do not activate or create it.
- Non-UI / backend-only work with no audience-facing surface.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Audience definitions | `docs/audience.md` or the audience stated in an explicit operator posture-check request | **STOP — no-op** only when both are absent. Do not create the file; onboarding (`/onboard`) creates it. |
| Surface being built | current task | nothing to classify; exit |

## Procedure

1. **Existence gate (FIRST STEP).** No `docs/audience.md` and no explicit operator posture-check request → exit silently. If the operator explicitly requested the check and stated the audience, continue with that audience without creating the file.
2. **Read** `docs/audience.md` when present (which surfaces are client-facing vs internal; per-audience needs); otherwise use the audience stated in the explicit operator request.
3. **Classify** the surface in scope: client-facing, internal, or shared.
4. **Apply the matching posture checklist** (§ Posture checklists below): client-facing, internal, or shared — walk every row for the surface in scope; each row is pass / fail / N-A, not vibes.
5. **Persist — the classification must not evaporate in chat.** If a spec is in flight (or being drafted) for this surface, hand the result to `requirements-specification`: the posture + each applicable checklist row becomes a numbered spec AC citing its ID (e.g., "AC7 — client-facing surface: destructive actions confirm with object + consequence before executing (client-vs-internal C2)"), alongside the QP-xx ACs from `app-quality-patterns` (C2/C4 overlap the QP delete-policy and empty/loading/error patterns — cite both IDs on one AC line, don't duplicate the AC). No spec in flight → record posture + failed rows in the design brief or change-note so Implement and `code-review` inherit them.
6. **Flag mismatches** (e.g. exposing internal complexity to a client surface) and recommend the audience-appropriate alternative.
7. **Ambiguous audience → ask** the operator (FR-19).

## Worked example

Operator: "This billing settings page is client-facing; run the posture check."

1. Classify `Billing settings` as client-facing from the explicit request.
2. Apply C2 because cancellation is destructive.
3. Spec AC: `AC4 — Cancellation confirms the subscription and consequence before executing (client-vs-internal C2).`

Output: client-facing posture + AC4 handed to `requirements-specification`.

## Posture checklists

Apply per classified surface. Row IDs (C/I/S-n) are citable in spec ACs (step 5).

**Client-facing — simple, guided, trust-first:**

| ID | Check | Concretely |
|---|---|---|
| C1 | No internal jargon or raw IDs | Labels/errors/emails use the client's domain words; no record IDs, status enums, table names, or team slang on any client-visible string |
| C2 | Confirm before destructive | Delete/cancel/send/submit-final actions show an explicit confirm naming the object + consequence; no one-click irreversible ops (overlaps QP delete-cascade ACs — cite both) |
| C3 | Guided defaults | Happy path completes with pre-filled sensible values and zero configuration; advanced options collapsed behind an explicit affordance |
| C4 | Reassuring empty/error/loading states | Empty = what this is + the first step to take; error = plain words + what to do next, never stack traces or status codes; loading = visible progress (overlaps QP UI-polish patterns — cite both) |
| C5 | No admin affordances | No bulk-delete, impersonation, raw-data export, config, or diagnostics reachable from client routes — removed, not hidden |
| C6 | Portal-embed + permission scoping | Surface works embedded in the client portal (CLI skill `fusebase-portal-specific-apps`); every query scoped to the client's own records — verify the permission model, never assume |

**Internal — robust, efficient, transparent:**

| ID | Check | Concretely |
|---|---|---|
| I1 | Bulk operations | Multi-select + bulk edit/delete/export wherever lists exist |
| I2 | Audit visibility | Who/when/what on records; change history visible, not buried |
| I3 | Keyboard + density efficiency | Dense tables, keyboard nav, fast filters; optimize for repeat power use, not first-run hand-holding |
| I4 | Full error detail | Real causes + IDs surfaced — internal users debug; don't over-soften |

**Shared surfaces (both audiences):**

| ID | Check | Concretely |
|---|---|---|
| S1 | Role-gated affordances | Internal-only controls rendered only for internal roles — gate by permission check, never by CSS hiding or an unlinked route |
| S2 | Progressive disclosure | Client-simple default view; power controls behind an explicit "advanced" affordance that internal roles see |

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Audience classification + posture guidance | chat / design brief | Mode A / Mode-B-lite |
| Posture checklist ACs (C/I/S IDs cited) | `docs/specs/<slug>/spec.md` via `requirements-specification` | Mode B |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact absent with no explicit operator request | step 1 | silent no-op (correct) |
| Client surface over-complex | step 6 | flag; recommend simplification |

## Escalation path

- Ambiguous audience → ask operator (FR-19).
- Audience model needs updating → `project-onboarding`.

## Anti-patterns

- Do not activate when `docs/audience.md` is absent unless the operator explicitly requests the posture check and states the audience; never create the file from this skill.
- Do not make client surfaces Salesforce-complex.
- Do not strip necessary controls from internal surfaces for "simplicity".
- Do not leave the classification chat-only when a spec is in flight — posture rows become ACs (step 5) or they evaporate.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
