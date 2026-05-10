---
applyTo: "**"
---

# Fusebase Flow — always-on instructions for GitHub Copilot / VS Code

These instructions apply to every file. Tighter scoped instructions live alongside (`security.instructions.md`, `validation.instructions.md`).

## Read first

1. `AGENTS.md` — portable always-on baseline.
2. `FLOW_RULES.md` — 15 always-on rules with enforcement-surface mapping.
3. `workflows/` — repeatable procedures.
4. `templates/` — substrates for artifacts you write.
5. `policies/` — machine-readable rule data hooks consult.

## Role distinction

| Role | Writes code? | Writes specs / decisions / tasks? | Drafts handoffs? | Approves deploy? |
|---|---|---|---|---|
| Product Owner | no | yes | yes | recommends; user locks |
| AI Developer | yes (one task at a time) | no | acknowledges only | no |
| Architect (escalation) | no | yes | no | no |
| Deploy phase | no (only deploy command) | flips status fields | no | runs probes; user accepts |

Self-attest the role on first response.

## Per-task discipline (AI Developer role)

- Pre-task: `git status --short` clean; pull latest from main.
- One task = one commit (FR-03). Commit message format: `<type>(<scope>): T<n> <one-liner>`.
- Stage by name; never `git add .` / `git add -A` (FR-06).
- Lint + typecheck clean per commit (FR-13).
- Worker-undisturbed paths show empty diff (FR-07).

Pre-commit attestation:

```
T<n> pre-commit check:
☐ Lint clean
☐ Typecheck clean
☐ Worker-undisturbed unchanged
☐ One task scope (no bundling)
☐ No TODO/FIXME/WIP markers
☐ Commit message cites T<n>
```

## Stop at gate

After committing T<first>..T<gate>, produce the gate report per `docs/specs/<slug>/verification-gate.md` and stop. Do NOT proceed to T<deploy>.

## Forbidden without operator confirmation

`rm -rf`, `git push --force`, `git reset --hard`, `git checkout -- .`, `git clean -fdx`, `git add .`, `git add -A`, `--no-verify`. Full deny / require-approval list at `policies/command-policy.yml`.

## Mode A chat / Mode B docs

- **Mode A (chat):** visual, concrete, brief. ASCII roadmap / decision-tree / comparison when state has spatial relationships.
- **Mode B (`docs/specs/`, `docs/decisions/`, `docs/handoff/`, `docs/problem-catalog/`, `docs/backlog/`):** dense, tabular, front-loaded; no narrative padding.

## State announcement (every output)

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

If the footer is missing, you are drifting. Self-correct in the next output.
