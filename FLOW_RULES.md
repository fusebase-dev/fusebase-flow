# Fusebase Flow — always-on rules (FR-01..FR-16)

**Status:** v0.2 (FR-16 added in v2.6.0 per Operator Stewardship initiative)
**Scope:** every session in any IDE/agent must follow these regardless of which skill or workflow is active.

These rules are clean-room original. Each rule states *what*, *why*, and *enforcement surface* (rule-only, policy, hook, workflow, skill). Enforcement details live in `policies/`, `hooks/`, and `workflows/` — this file is the readable contract.

| ID | Rule | Why | Enforcement |
|---|---|---|---|
| FR-01 | Spec before code | Production-code edits without an approved spec leak scope, lose audit trail, and bypass risk review | rule + `required-artifacts.yml` + `pre_tool_use` hook |
| FR-02 | Plan before edit | Multi-file changes without a written task list produce silent drift across files | rule + workflow `implementation-planning` + skill |
| FR-03 | One task = one commit | Bundled commits hide which change caused a regression and break per-task rollback | rule + `commit-msg` git hook |
| FR-04 | Persist handoffs | Cross-session prompts that exist only in chat are not replay-able and not auditable | rule + workflow + `stop` hook |
| FR-05 | Stop at gate | Implementation that flows into deploy without explicit approval skips production-safety review | rule + workflow + `pre_tool_use` hook on deploy commands |
| FR-06 | Reversible by default | Destructive ops (`rm -rf`, force push, reset --hard, `git add -A`, `--no-verify`) erase recoverable state without operator consent | rule + `command-policy.yml` + `pre_tool_use` hook |
| FR-07 | Worker-undisturbed | Paths declared protected must show empty git diff between deploys unless an approved exception is on file | rule + `protected-paths.yml` + `pre_tool_use` + `pre-commit` git hook |
| FR-08 | Mode-A operator chat | Operators scan; prose paragraphs are slow. Visual + concrete + brief in chat; never in artifact files | mandatory skill `skills/communication/SKILL.md` (Mode A pattern library) |
| FR-09 | Mode-B AI-optimized internal docs | Internal artifacts are AI-consumed. Prose padding wastes context budget on every load | mandatory skill `skills/communication/SKILL.md` (Mode B principles + anti-patterns) |
| FR-10 | Reproducibility before fix | Observed single-failure reports often reflect model variance. Drafting fix decisions before reproducing 3/3 wastes effort and ships speculative changes | rule + workflow `validation-and-qa` |
| FR-11 | Stop and ask, don't improvise | Ambiguity on locked decisions, missing context, or undeclared scope creep should surface as a question, not a guess | rule (judgment-bound) + `user_prompt_submit` flag for "skip clarify" patterns |
| FR-12 | Approval-gated side effects | DB migrations, customer-visible external messages, auth/permission changes, secret handling, and production deploys require an approval artifact on disk | rule + `approval-policy.yml` (committed default) + optional `approval-policy.local.yml` (ignored override) + `permission_request` hook |
| FR-13 | Lint+typecheck per commit | Broken state on main forces emergency rollback and breaks downstream pulls | rule + `pre-commit` git hook |
| FR-14 | Single docs commit on deploy | DRAFT→DONE flip, tasks marks, backlog index update belong together so a single revert restores known-good doc state | rule + workflow `greenlight-deploy` |
| FR-15 | Knowledge curation triggers | Without persistent capture, every new session re-discovers solved problems | rule + workflow `knowledge-curation` (operator-confirmed only) |
| FR-16 | Operator is a thin relay | The human operator's job is (1) product/business decisions, (2) gate approvals, (3) physically moving messages between sessions. Every other cognitive task — interpreting status, recommending next steps, composing prompts to paste back — is the agent's job, especially the PO's. Operator attention is the most expensive resource; sessions must protect it. | rule + skill `skills/role-discipline/SKILL.md` (PO Operator Relay Protocol) + return-path templates (`templates/gate-report.md`, `templates/deploy-report.md`, `templates/architect-response.md`) |

---

## Role distinction

Every session names its role on first response so other rules have an anchor.

| Role | Writes code? | Writes specs/decisions/tasks? | Drafts handoffs? | Approves deploy? |
|---|---|---|---|---|
| **Product Owner** | no | yes | yes | recommends; user locks |
| **AI Developer** | yes (one task at a time) | no | acknowledges; doesn't draft | no |
| **Architect (escalation)** | no | yes | no | no |
| **Deploy phase** | no (only deploy command) | flips status fields | no | runs probes; user accepts |

If a session writes code outside its role, FR-01 fires and the agent must stop and re-attest its role.

---

## Self-attestation (mandatory at first response of every session)

Every role declares: "Operating as {role} under Fusebase Flow v2.1. I will follow FR-01 through FR-16. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

If self-attestation is missing from the first response, the session is drifting. Self-correct in the next output.

**FR-16 implication for PO sessions:** when the operator pastes output from another role (AI Developer gate report, Deploy report, Architect response), the PO MUST follow the **Operator Relay Protocol** (skills/role-discipline/SKILL.md PO section) — analyze, brief in Mode A, present options with #1 marked, await approval, then generate the verbatim paste-back prompt. PO does not push framework jargon onto the operator and does not ask the operator to compose return prompts. See FR-16 above.

---

## State announcement (mandatory at every output)

Append to every output to the operator:

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

If the footer is missing, the session is drifting. Self-correct in the next output.

---

## Communication discipline

Communication is governed by a single mandatory skill, **`skills/communication/SKILL.md`**, loaded at every session start. It defines:

- **Mode A** — operator chat output: visual, concrete, brief; full ASCII pattern library (roadmap, status snapshot, decision tree, dependency, comparison, timeline, state diagram, architecture).
- **Mode B** — internal-artifact writes: dense, tabular, front-loaded; 12 numbered principles + concrete anti-patterns.
- **File classification** — which files are Mode B (full), Mode-B-lite, or human-readable.

Every session names this skill in its self-attestation. FR-08 and FR-09 are the rule pointers; the skill is where the discipline content lives.

---

## Direct-to-main vs branch/PR

Solo/local default: **direct-to-main** + pre-task git checkpoint + one task = one commit + verification gate. This is the speed mode.

Team/shared/high-risk default: **feature branch + PR**. Switch via `approval-policy.yml: workflow_mode: branch_pr` (or override locally in `approval-policy.local.yml`). The flow rules are identical; only the git surface changes.

Both modes preserve FR-03, FR-13, FR-14.

---

## Where each rule's full text lives

| Where | Content |
|---|---|
| `FLOW_RULES.md` (this file) | Rule statements + enforcement map |
| `policies/*.yml` | Machine-readable policies the hooks read |
| `hooks/handlers/*.py` | Deterministic enforcement handlers |
| `workflows/*.md` | Step-by-step procedures (eight-phase flow, greenlight-implement, etc.) |
| `skills/*/SKILL.md` | On-demand expertise (specification, planning, validation, review, security, release) |
| `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` | Tool-portable always-on baseline pointing back here |

---

## Amendment log

```
2026-05-08 — v0.1 initial. 15 always-on rules codified from clean-room redesign of
             prior Product Owner Flow rails. Communication and implementation discipline
             moved from "skills" into rules per design thesis.

2026-05-10 — v0.2. FR-16 added (operator is a thin relay). Codifies the Operator
             Stewardship principle: human operator's job narrows to product
             decisions, gate approvals, and physical relay between sessions.
             Cognitive load — interpreting reports, recommending options,
             composing return prompts — moves to PO via the Operator Relay
             Protocol (skills/role-discipline/SKILL.md). Driver: operator
             friction during paperclip+hermes-v1 deploy gate where operator
             couldn't decode "DP.6 magic phrase" guidance and PO gave
             framework-jargon responses instead of plain action steps.
             Shipped in framework v2.6.0.
```
