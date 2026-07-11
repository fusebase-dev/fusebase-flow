---
name: product-owner
description: Use when the operator types /product-owner, asks to activate Product Owner, start a Product Owner or PO session, or searches /product in Codex for Fusebase Flow project management. Do NOT use for implementing code; route implementation to the AI Developer role.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 4.4
risk_level: low
invocation: automatic
expected_outputs:
  - Product Owner role activation in chat
  - Next Specify/Clarify action or pointer to the active Product Owner artifact
related_workflows:
  - eight-phase-flow.md
hook_dependencies:
  - none
---

# Product Owner

> **Style:** Mode-B-lite. Codex-visible activation bridge for the canonical Fusebase Flow Product Owner role. This skill exists so Codex skill discovery can find "Product Owner" even though the full role body lives in the role agent files.

## Purpose

Activate the Product Owner workflow on surfaces where agents are not first-class slash commands. The canonical role instructions remain in `agents/product-owner/AGENT.md` and the Codex mirror `.codex/agents/product-owner.md`; this skill only routes discovery and activation.

## When to invoke

- Operator types `/product-owner`.
- Operator asks to activate Product Owner, start a PO session, or use the Product Owner role.
- Operator searches `/product` or `/skills` in Codex and expects the Product Owner option.
- A new ticket needs Product Owner phases: Specify, Clarify, Plan, Decisions, Tasks, Verify, Review, or deploy handoff drafting.

## Do not invoke when

- The operator asks to implement, fix, test, or deploy code directly; use the AI Developer role/handoff path.
- The task is `/onboard` or project vision capture; `project-onboarding` owns that flow after Product Owner activation.
- The task is product documentation design; `product-docs-first` owns that workflow.
- The task is app decomposition; `product-apps-decomposition` owns that workflow.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Always-on Flow rules | `FLOW_RULES.md` down to `## Amendment log` | Stop and read before acting |
| Product Owner role discipline | `flow-skills/role-discipline/references/product-owner.md` | Stop and read before acting |
| Canonical Product Owner role body | `agents/product-owner/AGENT.md` | Use `.codex/agents/product-owner.md`; if both are missing, stop and report mirror/canonical drift |
| Codex Product Owner mirror | `.codex/agents/product-owner.md` | Use canonical `agents/product-owner/AGENT.md` and report that `mirror-agents.sh` should be run |

## Procedure

1. Read the Product Owner role body, preferring `.codex/agents/product-owner.md` on Codex and falling back to `agents/product-owner/AGENT.md`.
2. Execute the role body's activation boot exactly enough to satisfy its `PO-BOOT-BLOCK` / `PO-ACTIVATED` checks; do not paste or fork the full role body into this skill.
3. Continue as Product Owner under the eight-phase flow, starting at Specify unless the operator provides an active artifact or phase.
4. Route any implementation request to an AI Developer handoff or fresh AI Developer session; do not write production code as Product Owner.

## Worked example

1. Input: operator types `/product-owner` in Codex and says "Let's ship intake forms."
2. Load `.codex/agents/product-owner.md`; emit Product Owner self-attestation plus `PO-ACTIVATED`.
3. Start Specify for `intake-forms`; produce clarify questions or a spec draft.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Product Owner activation | Chat | Mode A |
| Spec/planning artifacts, when the operator proceeds | `docs/specs/<slug>/` | Mode B |
| Implementation relay, when locked | `docs/tmp/handoff/<date>-<slug>-implement.md` | Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Product Owner role body missing | Neither canonical nor Codex mirror exists | Stop; report Flow agent surface drift |
| Codex mirror missing only | `.codex/agents/product-owner.md` absent, canonical exists | Use canonical role body; report mirror regeneration needed |
| Operator asks for implementation | Request targets code edits/tests/deploy | Produce/point to AI Developer handoff; do not implement as Product Owner |
| Activation skipped | No `PO-ACTIVATED` marker or role self-attestation | Re-run activation from the role body before continuing |

## Escalation path

- If the canonical agent contradicts this bridge, follow `agents/product-owner/AGENT.md` and update this skill later.
- If Codex still does not show this skill after mirrors are regenerated, inspect `.codex-plugin/plugin.json` and `.agents/skills/product-owner/SKILL.md`.
- If the operator needs code work, prepare an AI Developer handoff or ask them to start the AI Developer role.

## Anti-patterns

- Do not duplicate the full Product Owner agent body here.
- Do not treat this skill as a new role definition; it is a discovery bridge.
- Do not use this skill for Product Owner-adjacent implementation work.
- Do not promise bare custom slash-command parity in Codex; Codex exposes reusable workflows through skills/plugins.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
