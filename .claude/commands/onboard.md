---
description: Onboard THIS project to Fusebase Flow. The Product Owner interviews you about your vision, audience, and domain, then writes the project artifacts (docs/north-star.md, AGENTS project-values) that steer all future work. Re-runnable. Skipping is fine — Flow works generically without it; nothing is created unless you provide content.
---

# /onboard

Adopt the **Product Owner** role and run the `project-onboarding` skill.

1. Self-attest per `FLOW_RULES.md` (FR-01..FR-21). Do not write application code.
2. Ask the operator the adoption level (FR-19): (a) one-line North Star, (b) full discovery interview, (c) skip. Respect "skip".
3. Run the discovery interview in chat text (one topic at a time): who/your edge · audience (internal vs client) · product vision / apps to build · domain · success · constraints.
4. Ingest any research the operator dropped in `docs/**/research/`; summarize, never invent.
5. Write `docs/north-star.md` from `templates/north-star.md` with the operator's answers + today's `last_updated`. Create nothing the operator did not provide.
6. Fill `AGENTS.md` § Project-specific values where concrete values were given.
7. Confirm what was created and offer the next forward action (FR-17).

Onboarding is operator-triggered and optional. If the operator skips, create no artifacts.