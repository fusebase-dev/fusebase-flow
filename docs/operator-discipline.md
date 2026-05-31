# Operator discipline

> Expectations for the **human operator** (you) when running Fusebase Flow. This document is for humans, not AI agents — the agent enforces FR-01..FR-20 from `FLOW_RULES.md` on its side; you carry the operator side.
>
> AGENTS.md links to this doc; rules here are not auto-enforced (you're the human, not the AI).

## OD-1. One handoff per session

Each cross-session prompt at `docs/handoff/<date>-<slug>-<stage>.md` belongs in exactly one fresh AI agent session. Do not:

- Paste two handoff files into the same session — context pollutes.
- Fork a session to run two stages in parallel — state diverges.
- Resume an old session by pasting an additional handoff — the old context skews the new work.

Open a fresh chat / agent session for each handoff. The flow is built around single-purpose sessions.

## OD-2. Paste full reports back

When the AI Developer or Deploy session produces a gate report or deploy report, paste **the entire report** into the originating Product Owner session. Do not:

- Truncate to "the important parts" — the cross-artifact consistency check needs every field.
- Paraphrase — exact phrasing matters for grep / audit later.
- Skip the self-attestation header — the PO verifies role attestation before trusting the rest.

If the report is long, paste it in full anyway. The PO session is built to digest dense reports.

## OD-3. Don't bypass the Product Owner

The Product Owner session is the only session that:

- Drafts spec / decisions / tasks / verification-gate artifacts
- Runs the cross-artifact consistency checker before deploy
- Locks decisions after operator confirms
- Drafts handoffs to the AI Developer / Deploy / Architect

Do not:

- Skip directly from "let's ship X" to "deploy now" — the PO's investigation + decisions step is what catches scope creep, constitution violations, and missed acceptance criteria.
- Have the AI Developer make architectural decisions on its own — those belong in `decisions.md` with a letter-prefix and your lock.
- Approve a deploy from a chat that wasn't the PO session — you'd lose the audit trail.

## OD-4. Don't pass partial information between sessions

When the AI Developer reports back, give the **full** gate report to the PO. When the PO drafts a handoff, save it to disk and paste **the entire saved file** into the next session — not a summary, not the chat-rendered version, the saved file at `docs/handoff/<date>-<slug>-<stage>.md`.

Why: cross-session contracts depend on every field. Summary loss is hard to detect later.

## OD-5. Don't approve deploys when you're tired

This is operator-side discipline that can't be enforced by hooks. The deploy approval artifact (`state/approvals/production_deploy-*.json`) is your signature on a production change.

If you find yourself:

- Approving without reading the gate report
- Skipping the cross-artifact consistency check ("the PO already ran it")
- Hand-waving probe failures ("we'll fix in next deploy")
- Approving past 22:00 on a Friday

Stop. Approve in the morning. The flow is fast enough that one night's delay rarely costs more than the recovery effort from a botched deploy.

## OD-6. Don't reject the architect-first cadence for "small" features

Direct-to-main + spec-before-code feels heavy for a one-line tweak. It isn't, in practice — the spec for a small fix is two paragraphs. The discipline matters because:

- Most "small" tickets surface non-trivial constitution-invariant questions during clarify (worker-undisturbed paths, mixed-fleet, auth gates).
- Bypassing the spec means bypassing the verification gate — you ship without an explicit pass criterion, and discover regressions in production.
- Once the team has bypassed once, the second bypass is easier; rules erode by exception.

If the ticket truly needs no architectural decision, the spec is two paragraphs. If you can't write two paragraphs, the ticket is bigger than you thought.

## OD-7. Don't bury the parking lot

When the agent (PO or AI Developer) surfaces a related-but-out-of-scope concern mid-flow, it gets filed as a backlog ticket at `docs/backlog/<slug>/README.md`. Don't:

- Discard the concern with "we'll come back to that" — write the ticket while it's fresh.
- Conflate it with the current ticket — scope creep destroys the cross-artifact consistency check.
- Promise "next sprint" without a parked ticket — the parking lot IS the durable promise.

Backlog tickets are 5 lines: title, why-now, rough acceptance criteria, out-of-scope, related links. File them inline with the conversation; the PO session helps draft.

## When you violate operator discipline

The agent will not refuse — it can't enforce these against you. But the gate report or handoff will be lower-quality. Symptoms to watch for:

| Symptom | Likely violated |
|---|---|
| The AI Developer keeps asking for clarification mid-task | OD-4 (partial info passed) |
| The PO can't run the consistency check (missing fields) | OD-2 (report truncated) |
| Deploy probes fail and the cause is "we forgot to test X" | OD-5 (approved tired) |
| Backlog grows but no tickets are filed | OD-7 (parking lot buried) |
| Two parallel sessions argue about the same decision | OD-1 (forked session) |

The fix is always: stop, file the missing artifact (full report / parked ticket / new handoff), restart cleanly.

## Related

- `FLOW_RULES.md` — FR-01..FR-20 (the agent-side rules)
- `skills/role-discipline/SKILL.md` — agent-side don't-list per role
- `AGENTS.md` — always-on baseline that links here
