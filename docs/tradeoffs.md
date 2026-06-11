# Key tensions to manage

> The Fusebase Flow design balances several pairs of competing pressures. None is fully resolvable; each has to be navigated case-by-case. This document names the tensions so they're easier to discuss in clarify conversations and decisions.md alternatives.

## Speed vs safety

| Pressure | Source |
|---|---|
| **Speed** | Direct-to-main, one-task-one-commit, fast deploy cadence, minimum ceremony |
| **Safety** | Verification gate, approval artifacts, worker-undisturbed list, smoke prompts, post-deploy probes |

**How the flow balances:** speed is the default for the happy path (clean spec → fast implement → gate passes → deploy). Safety kicks in at specific gates. The cost of safety is paid only when needed; the cost of speed is paid only when nothing's at stake.

**When to lean toward speed:** small tickets, clear specs, no shared/protected surfaces touched, low operator workload.

**When to lean toward safety:** anything touching auth, secrets, deploy config, customer data, worker-undisturbed paths, mixed-fleet clients, or regulatory surfaces.

## Depth vs breadth

| Pressure | Source |
|---|---|
| **Depth** | Architect escalation, detailed clarify conversations, multi-decision matrices, exhaustive verification gates |
| **Breadth** | Backlog parking lot, "let's ship 5 things today" cadence, single-decision lock per ticket |

**How the flow balances:** the merged Product Owner does default-depth investigation; the architect-escalation path is opt-in for tickets that warrant it.

**When to lean toward depth:** cross-cutting refactors, platform blockers, vendor-API integrations, anything that will live for years.

**When to lean toward breadth:** stack of similar tickets (parallel exporters, similar UI screens, repeated migrations), exploration mode with low confidence.

## Architect-first vs immediate-fix

| Pressure | Source |
|---|---|
| **Architect-first** | Spec before code, decisions locked, clarify resolved, verification-gate drafted upfront |
| **Immediate-fix** | "It's a one-line change, just fix it", hot-fix pressure, on-call urgency |

**How the flow balances:** architect-first is the default. Hot-fix is an explicit exception that still requires a backlog ticket filed *after* the fix lands.

**When to lean toward architect-first:** even one-line changes that touch security/auth/data-flow.

**When to lean toward immediate-fix:** production-down incident, regression introduced same-day. File the post-hoc ticket within the same session, immediately after rollback.

## Structure vs flexibility

| Pressure | Source |
|---|---|
| **Structure** | T-numbered tasks, letter-prefixed decisions, predictable section headers, fixed handoff format |
| **Flexibility** | Custom workflows per project, override policies via `.local.yml`, project-internal skills |

**How the flow balances:** structure is the foundation; flexibility is layered on top via local overrides. The framework's templates and policies are the default; projects customize via `.local.yml` and `docs/skills/<slug>/`.

**When to lean toward structure:** new project, multiple operators, audit/compliance requirements.

**When to lean toward flexibility:** mature single-operator project with strong personal conventions.

## Comprehensive instructions vs context budget

| Pressure | Source |
|---|---|
| **Comprehensive** | Detailed skill content, per-rail refusal patterns + recovery, full pattern libraries |
| **Context budget** | Provider context limits, every file loaded on every session |

**How the flow balances:** Mode-B-lite for AI-loaded files (concise, structured, predictable headers); detailed reference content lives in `docs/` (loaded on demand by the human, not by every session); mandatory skills stay focused on what must apply every session.

**When to lean toward comprehensive:** the content materially changes agent behavior; would be ignored without explicit per-step guidance.

**When to lean toward context budget:** the content is reference-only and a one-line link is enough.

## Determinism vs judgment

| Pressure | Source |
|---|---|
| **Determinism** | Hooks that block destructive commands, policies that machine-check approval artifacts, regex secret detection |
| **Judgment** | Stop-and-ask on ambiguity, skill anti-patterns that need context, role-discipline that depends on intent |

**How the flow balances:** deterministic enforcement covers what can be checked algorithmically (banned commands, secret patterns, missing artifacts). Judgment-bound discipline is documented in skills + workflows; the agent's self-attestation + state-announcement footer are the operator's signal that the agent is honoring it.

**When to lean toward determinism:** anything checkable. Add a hook + policy.

**When to lean toward judgment:** anything that depends on intent ("does this commit message describe the change?"). Document in a skill.

## Provider-specific vs portable

| Pressure | Source |
|---|---|
| **Provider-specific** | `.claude/settings.json.example`, `.codex/hooks.json.example`, provider hook event names |
| **Portable** | `AGENTS.md`, the canonical framework at root (`flow-skills/`, `policies/`, `workflows/`, `hooks/`, `templates/`), git fallback hooks |

**How the flow balances:** the canonical framework lives at root, portable across providers. Provider-specific files are thin adapters that wire the same canonical handlers into provider lifecycle events.

**When to lean toward provider-specific:** activating native lifecycle hooks. Only providers that expose a project-local lifecycle-hook surface can run the Python handlers (currently Claude Code and Codex per `docs/hook-coverage.md`); other surfaces (Cursor, Copilot/VS Code, Gemini-style, generic) fall back to git hooks plus operator vigilance. Use the relevant provider's `.example` configuration when activating native hooks.

**When to lean toward portable:** core framework changes (skills, policies, workflows). They land in canonical paths; mirrors regenerate.

## How to use this doc in practice

When drafting decisions in `docs/specs/<slug>/decisions.md`, the alternatives section should explicitly identify which tension is in play. For example:

> **D2 — Direct-to-main vs feature branch for this ticket**
>
> Recommendation: feature branch.
>
> Tension: speed vs safety. This ticket touches auth middleware (worker-undisturbed list). The faster default (direct-to-main) is wrong here because rollback after a deploy is harder for auth-side regressions.

Naming the tension makes the alternative explicit. Two months later, a code reviewer or auditor reads the decision and sees both why it was made and what was given up.
