# Problem: enabling FR-25 on an existing repo hard-blocked the first monolith touch, and the remedy self-collided with FR-07

**Slug:** `fr25-upgrade-adoption-collision`
**Filed:** 2026-07-10
**Severity:** high
**Status:** resolved
**Filed by:** operator (per FR-15) — surfaced by a consumer product session after its v4.2.0 upgrade

## Symptom

A consumer product repo (pre-existing `helpers.ts` ~11.5k lines, `workflow.ts` ~18.6k lines — monoliths predating FR-25) upgraded to Fusebase Flow **v4.2.0**, which turned the FR-25 module-size ratchet on. The **first commit touching either monolith hard-blocked** (over the 800 ceiling, not in the baseline). The block message's remedy — "re-key the baseline (`--write-baseline`)" — then hit a **second wall**: `policies/module-size-baseline.txt` is an FR-07 **protected path**, so committing the re-keyed baseline was itself blocked. The two guardrails composed into a circular dead-end.

## Root cause

Two compounding gaps:

1. **The upgrade ships a non-empty baseline, defeating the warn-only adoption grace.** `module_size.py` granted warn-only ONLY when `baseline is None`. But v4.2.0 ships a **non-empty** `policies/module-size-baseline.txt` (Flow's own two over-ceiling files: `fusebase-flow-health-check.sh`, `test-cli-flow-recovery.sh`). On a consumer repo the baseline is therefore "present but incomplete" — warn-only never fires, and a consumer monolith not listed in it (`allowed is None`) hard-blocks on ANY touch, regardless of whether the change grew the file.
2. **The FR-25 remedy self-collides with FR-07.** The block message said "re-key the baseline", but the baseline is FR-07-protected and the message never mentioned the approval prerequisite — following the remedy hit a wall with no sanctioned path shown.

## Why it matters

- A consumer doing normal product work after a routine upgrade gets stopped by framework bookkeeping with a **circular remedy** — exactly the upgrade-friction class the framework must not create.
- The ratchet's intent is to prevent monolith *growth*, not to freeze all edits to pre-existing monoliths — blocking a non-growing touch (even a refactor that *shrinks* the file) over-reached.

## Permanent fix (v4.3.0)

| Status | Detail |
|---|---|
| Shipped | **Delta-aware change gate.** In `--staged`/`--worktree`, a PRE-EXISTING over-ceiling file (over ceiling at HEAD, not baselined) may be **touched or shrunk** without blocking — only a file that NEWLY crosses the ceiling, or GROWS while already over it, is a violation. `--all` stays an absolute audit (reports every over-ceiling not-baselined file). Zero impact on Flow's own gating (its two over-ceiling files are baselined). `hooks/shared/module_size.py` `_head_line_count` + the delta branch. |
| Shipped | **Smooth FR-07-sanctioned adoption.** `check-module-size.sh --write-baseline` now stages the baseline and **auto-mints a single-use FR-07 approval** bound to that change, then prints the commit → `--consume` steps. The FR-25 block message flags that the baseline is FR-07-protected and points to this path (never `--no-verify`). |

## Recurrence triggers (so future sessions recognize this)

- A consumer reports "FR-25 blocks any touch of `<pre-existing monolith>`" right after a Flow upgrade.
- The FR-25 block cites a not-baselined over-ceiling file the consumer did not just create.
- "The re-key remedy is itself blocked by FR-07 / the module-size baseline is protected."

## Guardrail (the lesson)

A ratchet adopted on an existing repo must **grandfather pre-existing state without a hard gate** — gate the *delta* (new-over-ceiling + growth), not the mere existence of a pre-existing monolith. And when one guardrail's remedy touches another guardrail's protected surface, the tool must **hand the operator the sanctioned cross-guardrail path** (auto-mint the approval), never leave a circular dead-end.

## Related

- `hooks/shared/module_size.py` · `hooks/local/check-module-size.sh` · `flow-skills/module-size-discipline/SKILL.md` · FR-25 (`FLOW_RULES.md`)
- `hooks/local/write-bootstrap-approval.sh` — the single-use FR-07 approval the adoption reuses
- `hooks/tests/test-module-size.sh` — the delta-aware scenarios (S9a–S9d)
