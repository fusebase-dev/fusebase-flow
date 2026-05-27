---
name: app-business-docs
description: "Maintain docs/en/business-logic.md in English — human-readable business logic, main user flows, scenarios, and edge cases. Use after domain or workflow code changes, or when revalidating the app during debugging."
---

# App business logic documentation (English)

## Purpose

Keep a single **English** narrative so humans (and future LLM turns) can understand **what the app does** and **why**, without reading every file.

**Canonical file:** `docs/en/business-logic.md`  
Create `docs/en/` if it does not exist.

## When to use this skill

1. **After business-logic changes** — routes, validation, state machines, permissions, multi-step flows, integrations, or copy that reflects real rules.
2. **Revalidation** — the user asks to refresh the doc from the codebase, or debugging shows the doc (or mental model) is wrong or stale.
3. **Onboarding** — initial fill after an app or app reaches a coherent shape.

Do **not** treat this as API reference: no exhaustive endpoint lists unless they carry domain meaning. Prefer flows, invariants, and “if user does X then Y”.

## Document structure (adapt as needed)

Use clear headings, for example:

- **Product overview** — who uses it, primary job-to-be-done.
- **Glossary** — domain terms.
- **Actors & roles** — visitor, member, admin, system, etc., aligned with real authz.
- **Main scenarios** — numbered happy paths (step-by-step).
- **Edge cases & failure behavior** — errors, empty states, retries, idempotency.
- **Data & ownership** — what lives in dashboards vs Gate vs isolated stores (if any), at a conceptual level.
- **Code map** — short table: scenario or area → primary paths (`apps/...`, `backend/...`).

## Workflow

1. **Read** the current `docs/en/business-logic.md` if present.
2. **Inspect** the code that implements the changed or unclear behavior (apps, `backend/`, shared libs).
3. **Update** the doc so it matches **observable** behavior, not intentions that are not implemented.
4. If behavior is ambiguous, **state the ambiguity** and what you verified in code or runtime.

## Quality bar

- Short paragraphs, concrete examples, no filler.
- A new teammate should follow main scenarios without opening the repo.
- When revalidating during debug, add a **“Debugging notes”** subsection with dated bullets if it helps (optional).

## Flag

This skill is copied into the project only when the global CLI flag `app-business-docs` is enabled (`fusebase config set-flag app-business-docs` then `fusebase update --skip-mcp --skip-deps --skip-cli-update --skip-commit`).
