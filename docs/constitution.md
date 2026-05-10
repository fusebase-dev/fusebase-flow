# Project constitution (narrative)

> The narrative half of the project constitution: identity, motivation, scope, why-this-exists. The data half lives in `policies/*.yml` (worker-undisturbed paths, approval rules, command policy, secret patterns, etc.) and the project-specific values section of `AGENTS.md`. This document explains the *why* behind those entries.

## What this document is for

A project that uses Fusebase Flow Local has its identity scattered across several files for good reason — machine-readable data goes in `policies/`, always-on operator guidance goes in `AGENTS.md`, runtime artifacts go in `docs/specs/`. But scattering means the *narrative* — the reason this project exists, what it does for whom, what's in scope and what isn't — has no canonical home.

This document is that home. It's narrative-only. It links to the data layer; it doesn't duplicate it.

## Template structure (fill in for your project)

Replace the example content below with your project's narrative. Keep it short — under one printed page. Anything longer probably belongs in `docs/specs/` or in a per-feature README.

---

### Project identity

**Name:** {project name}

**One-line:** {what this project does in 15 words}

**Origin:** {when, why, who needed this}

**Stakeholders:** {who depends on this — operators, end-users, downstream systems}

### What's in scope

{One paragraph describing the bounded problem. The constitution doesn't list every feature; it names the *territory* the project occupies.}

Examples:
- "Browser-extension data fetching for AI Top Voice (LinkedIn / X / TikTok / YouTube creator metadata)."
- "Internal operator dashboard for our enrichment pipeline; not a customer product."

### What's out of scope (deliberately)

{2–4 bullets naming what this project will NOT become. The constitution is a forward-looking commitment to NOT do certain things. Without this, scope drifts.}

Examples:
- Multi-tenant SaaS (single-org by design).
- Real-time push notifications (batch is sufficient).
- Mobile clients (web-only).

### Critical constraints

{The 2–4 invariants that shape every architectural decision. These are platform / vendor / regulatory / operational constraints — not preferences.}

Examples:
- "Migration apply has a known checksum-validation bug; prefer no-migration designs until upstream fix lands."
- "Browser extension installed per-machine; mixed-fleet safety required (old clients must keep working through deploys)."
- "Data residency: all customer data processing must happen in Fusebase-Apps-hosted infrastructure."

For machine-readable enforcement of these, see:
- `policies/protected-paths.yml` (what must show empty diff)
- `policies/command-policy.yml` (what's forbidden / approval-gated)
- `AGENTS.md` "Project-specific values" section

### Production safety posture

{How aggressive is the deploy cadence; what's the rollback plan; what's the operator's tolerance for risk; who's on-call.}

Examples:
- "Direct-to-main; multiple deploys per day during active development; rollback via `git revert` + redeploy; operator monitors first-hour metrics."
- "Branch + PR + sign-off; weekly deploy window; rollback via platform-managed previous version; 24/7 on-call rotation."

For machine-readable enforcement, see `policies/approval-policy.yml: workflow_mode`.

### Quality bar

{What "good enough" means for this project.}

- **Code:** {language conventions, type-safety stance — e.g., "TypeScript strict, no `any` in production paths"}
- **Tests:** {coverage stance — e.g., "every behavior change has at least one integration test; smoke prompts cover user-facing flows"}
- **Commits:** {convention — e.g., "T-numbered, lint+typecheck clean, one task per commit per FR-03"}
- **Reviews:** {process — e.g., "PO runs cross-artifact consistency check before deploy approval"}

### Why this project exists (motivation)

{One paragraph. Why this project, not an off-the-shelf alternative? Why the chosen architecture? The motivation answers a future maintainer's question: "should we keep this, replace it, or rewrite it?"}

Examples:
- "Existing scrapers don't honor the worker-undisturbed posture our extension requires; building this in-house lets us keep the per-machine-install assumption central."
- "Our enrichment pipeline runs on Fusebase Apps; this project is the operator UI for it. Replacing the pipeline would replace this; replacing this would not require replacing the pipeline."

### Amendment process

This narrative changes when the project's identity changes — new stakeholders, dropped scope, changed constraints. Amendment is a deliberate act:

1. Operator drafts the change as a decision in a regular Fusebase Flow ticket (e.g., `docs/specs/constitution-amend-<topic>/decisions.md`).
2. Decision is locked normally.
3. The amendment lands as a single docs commit alongside the spec's deploy commit, OR as a standalone `docs(constitution): amend <topic>` commit when the change is doc-only.

Constitution amendments are rare. If you're amending more than once per quarter, the constitution is too narrow.

### Last amended

```
{YYYY-MM-DD} — initial draft
```

---

## How this constitution interacts with the data layer

| Concept | Where the data lives | Where the narrative lives |
|---|---|---|
| Worker-undisturbed paths | `policies/protected-paths.yml: worker_undisturbed` | "Critical constraints" section above |
| Workflow mode (direct-to-main vs branch+PR) | `policies/approval-policy.yml: workflow_mode` | "Production safety posture" section above |
| Approval-required actions | `policies/approval-policy.yml: require_approval` | "Production safety posture" section above |
| Banned commands | `policies/command-policy.yml: deny` | "Critical constraints" + `AGENTS.md` "Destructive ops" |
| Secret patterns | `policies/secret-patterns.yml` | (no narrative needed — patterns are exhaustive) |
| Auth model | `AGENTS.md` "Project-specific values" | "Critical constraints" + per-ticket `decisions.md` |
| Letter decisions / T-numbers | `templates/decisions.md` + `templates/tasks.md` | (substrate; no narrative) |

If a piece of project identity needs both a narrative justification and a machine-readable enforcement, write the narrative here and the enforcement in the appropriate `policies/` file. The two layers reinforce each other; they don't duplicate.

## Related

- `AGENTS.md` "Project-specific values" — structured field summary linking to policies/
- `docs/operator-discipline.md` — expectations for the human operator
- `docs/tradeoffs.md` — key tensions to manage
- `policies/*.yml` — machine-readable enforcement
- `FLOW_RULES.md` — FR-01..FR-18 (always-on rules)
