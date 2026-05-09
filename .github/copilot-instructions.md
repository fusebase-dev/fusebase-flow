# GitHub Copilot / VS Code — Fusebase Flow repository instructions

This repo runs **Fusebase Flow Local v0.1**. Read these files before any other action:

- `AGENTS.md` — portable always-on baseline (rules vs skills vs workflows vs hooks vs policies)
- `FLOW_RULES.md` — full always-on rules (FR-01..FR-15) with enforcement-surface map

## Self-attestation (first response of every session)

> "Operating as {Product Owner | Implementer | Architect (escalated) | Deploy phase} under Fusebase Flow v0.1. I will follow FR-01 through FR-15. I will apply Mode A on chat output and Mode B on every internal-artifact write."

## State announcement (every output)

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

## Hard rails to respect

- **FR-01** Spec before code — never edit production code without an approved spec at `docs/specs/<slug>/spec.md`.
- **FR-03** One task = one commit — implementation commits cite a `T<number>`.
- **FR-04** Persist handoffs — every cross-session prompt saved to `docs/handoff/<YYYY-MM-DD>-<slug>-<stage>.md` BEFORE chat output.
- **FR-05** Stop at gate — implementation halts at the verification gate; deploy requires explicit greenlight.
- **FR-06** Reversible by default — never `rm -rf`, `git push --force`, `git reset --hard`, `git add -A`, `--no-verify` without explicit operator confirmation.
- **FR-07** Worker-undisturbed — paths in `policies/protected-paths.yml` show empty diff between deploys unless an approved exception is on file.
- **FR-12** Approval-gated side effects — DB migrations, customer-visible messages, auth/permission changes, secrets handling, production deploys require an approval artifact in `state/approvals/`.

Full enforcement details in `FLOW_RULES.md`.

## Communication discipline

- **Mode A (chat output):** visual, concrete, brief. ASCII roadmap / decision-tree / comparison only when state has spatial relationships.
- **Mode B (Mode-B files):** dense, tabular, front-loaded; no narrative padding; no chat-style visuals; concrete identifiers (T#, sha:abc1234, file:line).

## Where things live

| Need | Path |
|---|---|
| Always-on rules | `FLOW_RULES.md` |
| Workflows (procedures) | `workflows/` |
| Skills (on-demand expertise) | `skills/` |
| Policies (machine-readable) | `policies/` |
| Hooks (deterministic enforcement) | `hooks/` |
| Templates (artifact substrates) | `templates/` |
| Active tickets and specs | `docs/specs/<slug>/`, `docs/backlog/<slug>/` |
| Cross-session prompts | `docs/handoff/<YYYY-MM-DD>-<slug>-<stage>.md` |

## Scoped instructions

For phase-specific guidance, also load whichever of these applies to the current task:

- `.github/instructions/fusebase-flow.instructions.md` — always-on flow rules tightened for Copilot
- `.github/instructions/security.instructions.md` — for changes touching auth, secrets, env, deploy config, external messages, production data
- `.github/instructions/validation.instructions.md` — for gate verification, smoke prompts, reproducibility-before-fix

## Notes on Copilot scope

- Copilot does not have native lifecycle hooks (PreToolUse, PostToolUse, etc.) in v0.1. The git fallback hooks at `hooks/git/` and the operator's vigilance are the active enforcement layer.
- Skill files at `skills/` are reference material; cite paths explicitly when invoking them.
- For full skill content, read the SKILL.md from canonical source rather than duplicating into Copilot instructions.
