# Clarify conversation — flow-performance-and-recovery-hardening

**Status:** resolved
**Linked spec:** `docs/specs/flow-performance-and-recovery-hardening/spec.md`
**Resolution source:** operator instruction, 2026-09-05

## Resolved

| ID | Question | Locked answer | Basis |
|---|---|---|---|
| Q-A | Scope | Execute R1–R5 and P1–P7 in the recommended order, end to end | “proceed to execute all of them” |
| Q-B | CLI boundary | Do not harm CLI behavior; restore Flow after CLI/update overwrite | explicit main requirement |
| Q-C | UI/audience | N/A: repository scripts, hooks, instructions, tests, and reports only | no visual/app surface in scope |
| Q-D | Side effects | Migration/deploy authorized if needed; no data, schema, app, or deploy target exists in this ticket | operator authorization plus repository constitution |
| Q-E | Decisions | Recommendations are approved for execution; use GPT-6 Astra Medium review and GPT-5.6 Sol xhigh implementation roles | explicit execution rules |
| Q-F | Liveness | Poll delegated work proactively; retry transient API-limit failures on the same agent within the bounded envelope | explicit execution rules + FR-27 |

## Unresolved

None.
