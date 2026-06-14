---
name: find-wasted-effort
description: Use when the operator runs "/find-wasted-effort" or asks about "wasted effort", "ceremony overhead", "process overhead", "outcome-neutral steps", "are our gate stops worth it", "is the Full lane overkill here", or wants the process-per-outcome sibling of /token-waste-audit. Audits Flow ARTIFACTS ON DISK (gate reports, deploy reports, handoffs, approval artifacts, git log, prevents: annotations) for ceremony that bought no safety outcome — distinct axis from token-waste-audit (tokens-per-rule, from transcripts). Read-only to the project (Phase 1 + Phase 2A: writes only the gitignored state/audit/; Phase 2A adds proposal OUTPUT — a Proposed memory entries report section + optional state/audit/ JSON — but applies nothing; no prune / no overlay edits). Do NOT use for token/transcript economy (token-economy + /token-waste-audit own that), for execution-layer polling/record-then-read economics (smoke-testing § Verification cost discipline owns that), for doc budgets (documentation-budget owns that), or to auto-remove any ceremony element (pruning is PO-owned, never automatic, never this audit's job).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: "3.21"
risk_level: low
invocation: automatic
expected_outputs:
  - a Mode-A chat summary plus a gitignored report at state/audit/find-wasted-effort-<date>.md
  - per-rule findings, each labelled confirmed / dismissed / inconclusive with the required contrary-evidence
  - a stated coverage section (which prevents:-annotated controls were in scope) — silence is not safety
  - (Phase 2A) a Proposed memory entries report section + an optional gitignored state/audit/find-wasted-effort-proposals-<date>.json; both under state/audit/ only, nothing applied
related_workflows:
  - greenlight-implement.md
  - lightweight-lane.md
hook_dependencies:
  - none
---

# Find Wasted Effort (A2 — process-per-outcome ceremony audit)

The **process-per-outcome** ceremony audit — the sibling of the **tokens-per-rule** `/token-waste-audit` (FR-26). Different axis, different inputs, **shared discipline**.

| | `/find-wasted-effort` (this) | `/token-waste-audit` (FR-26) |
|---|---|---|
| Axis | process-per-outcome (ceremony) | tokens-per-rule (consumption) |
| Inputs | Flow artifacts ON DISK: gate/deploy reports, handoffs, approval artifacts, git log, round structure, `prevents:` annotations | Claude Code transcripts (`~/.claude/projects/.../*.jsonl`) |
| Question | "Which ceremony step bought no safety outcome?" | "Which tokens bought no information?" |
| Shared | candidate/false-positive header · read-only-first posture · `state/audit/<date>.md` gitignored output | (same) |

It is **not** standalone-with-no-sibling. It **reuses the shipped substrate** — see `flow-skills/token-economy/SKILL.md` and `hooks/local/token-waste-audit.py` for the FP-header text, the read-only posture, and the `state/audit/` output convention. Do **not** reinvent or duplicate token-waste-audit's detection.

## Guardrail first (same floor as FR-21 / FR-26)

**Ceremony drops, safety never.** This audit flags ceremony that is *outcome-neutral in the observed window* — that is a **review candidate**, not a remove instruction. A clean window is **not** proof a control is worthless: a gate stop can be low-frequency/high-severity (`catastrophic-low-frequency`, `policies/ratchet-governance.yml`). Every finding states the contrary evidence that would dismiss it; absence of contrary evidence in a short window is `inconclusive`, never `confirmed`.

## Read-only-to-the-project is load-bearing (D4)

The analyzer writes **only** inside the gitignored `state/audit/` directory — NO memory writes, NO overlay/spec/decisions/provider/policy edits, NO prune/remove **application**. This holds in Phase 1 (read-only) AND Phase 2A (proposal-output): Phase 2A enriches the *output* (a *Proposed memory entries* report section + an optional gitignored `state/audit/` proposals JSON) but applies NOTHING. The audit *describes* candidates and *proposes* changes a human could apply; the **PO owns subtraction** (A3 prune protocol). The actual memory **write-apply** is Phase 2B (DEFERRED, consumer-repo prototype, AC2b). If asked to "just remove the dead gate" or "apply the proposal," refuse: "Per the A2 read-only-to-the-project posture (D4), I surface review candidates and propose patches; removal/apply is Phase 2B + the PO's call via the `policies/ratchet-governance.yml` prune protocol."

## Verdict vocabulary (every rule emits one)

| Verdict | Meaning | Requires |
|---|---|---|
| **confirmed** | the waste signature held AND the required contrary evidence was searched for and not found | the contrary-evidence search, stated |
| **dismissed** | contrary evidence found — the ceremony bought a real outcome (a gate that blocked, a control that fired, a deliberate exception) | the contrary evidence, cited |
| **inconclusive** | signature present but the window is too small / ambiguous / a `catastrophic-low-frequency` control | why it can't be confirmed |

## The 6 active rules (rule 4 is CUT)

> Per-rule input shapes, signatures, and false-positive examples: `references/rule-signatures.md` and `references/false-positive-examples.md`. Cite them; don't restate.

| # | Rule | Signature | Required contrary evidence (→ dismissed) |
|---|---|---|---|
| 1 | **Unused gate stops** | N rounds where the gate approved every deviation, no deviation blocked | ANY blocked-gate counterexample in the window ⇒ dismissed (never suggest Middle eligibility for that class). Suggestion is *eligibility for review*, never auto-reclassify. |
| 2 | **Per-commit full-suite habit** | full-suite runs ≫ 2/round with identical fail-sets each run | a run whose fail-set DIFFERED (the suite caught a real regression mid-round) ⇒ dismissed for that round |
| 3 | **Artifact duplication** | the same rule/evidence block copied verbatim in ≥3 round artifacts | intentional self-bootstrapping (handoff role-prelude, template scaffolding) ⇒ dismissed |
| ~~4~~ | ~~Context-rebuild overhead~~ | **CUT — net-new** | already shipped in `/token-waste-audit`'s v3.21.0 cross-session aggregate. POINT at that report; do not re-implement the signature. |
| 5 | **Lane misclassification** | small diff + zero design decisions but Full ceremony was run | any design decision / risk surfaced in the round ⇒ dismissed. Ambiguous size/risk ⇒ inconclusive; **never auto-reclassify** a lane. |
| 6 | **Ratchet inventory** | a ceremony element with NO `prevents:` annotation (A3) AND no firing in the window | a `prevents:` annotation present, OR a firing in the window, ⇒ dismissed. `catastrophic-low-frequency` element on a clean window ⇒ **inconclusive** (expected to sit idle), never confirmed. Output = a *review candidate*, never "remove". |
| 7 | **Watch-vs-read waste (cross-session ceremony layer ONLY)** | cross-session ceremony where a later session re-watched/re-derived what an earlier session already recorded durably | the durable record was absent (a real observability gap, not waste) ⇒ dismissed. **Scoped to the cross-session ceremony layer** — do NOT duplicate FR-26's execution-layer record-then-read/polling signature (`token-economy` / `smoke-testing` own that). |

## Inputs (already on disk — read-only)

- `docs/specs/*/verification-gate.md`, gate reports, deploy reports (`docs/tmp/handoff/*`, `docs/handoff/*`)
- approval artifacts (`state/approvals/*.json`), `git log` (per-task/per-round commit shape)
- round structure (change-notes `docs/changes/*`, future round-files)
- `prevents:` annotations + `policies/ratchet-governance.yml` (A3 taxonomy + coverage map)

## Output

- Mode-A chat summary (totals + per-rule confirmed/dismissed/inconclusive + coverage + proposal count).
- Gitignored report `state/audit/find-wasted-effort-<date>.md` carrying the FP header (reuse token-economy's), the per-rule findings, a **coverage section** naming which `prevents:`-annotated controls were in scope (D5 — silence is not safety), and (Phase 2A) a **Proposed memory entries** section.
- **Phase 2A (read-only-safe):** a *Proposed memory entries* report section + an optional gitignored `state/audit/find-wasted-effort-proposals-<date>.json` sibling (skip with `--no-proposals-json`). Both live **only** under `state/audit/`.
- **NO writes beyond `state/audit/`** in any phase here: no memory, no overlay, no spec/decisions/provider/policy edits, no prune **application**. The write-apply is Phase 2B (DEFERRED, consumer-repo, AC2b).

### Proposal schema (Phase 2A)

A proposal is a change a **human could** apply — the audit emits it, never applies it. Emitted from `confirmed` findings (rules 1,2,3,5,7) and rule-6 per-element review candidates; `inconclusive`/`dismissed` emit none.

| Field | Meaning |
|---|---|
| `proposal_id` | stable `<rule>-<verdict-kind>-<hash>` id (deterministic) |
| `rule` | source rule number |
| `verdict` | `confirmed` (rules 1,2,3,5,7) or `prune_review_candidate` (rule 6 — **never** an auto-prune) |
| `raw_evidence_refs` | pointers to **raw on-disk artifacts** — never a prior audit report/proposal (self-output quarantine) |
| `target_kind` / `target_path` | what / where a human could change (often an `(operator decision)`) |
| `exact_patch` | the concrete change text a human *could* apply (description, not an applied diff) |
| `operator_confirmation_required` | always `true` |
| `source` | always `"audit"` |

**Self-output quarantine (Codex #5):** the evidence collectors do NOT read `state/audit/`, so the audit can never cite its own prior output as evidence. Proposals cite only raw artifacts.

## Coverage statement (mandatory in every report)

The report states its own coverage: which artifacts it read, which rules it could evaluate, and which `ratchet-governance.yml` coverage entries were in scope. An un-annotated control NOT in the coverage map is reported as *coverage gap*, not as *safe*.

## Growth rule

A ceremony-waste pattern that recurs across audits and matches no rule above → add one rule row (with its required contrary evidence + an FP example in `references/`) via `skill-authoring`. Project-specific ceremony patterns stay in project docs/skills, not here.

## Anti-patterns

- Treating a finding as a verdict to act on — they are candidates; the PO prunes (A3), gated on FP fixtures (P2).
- Confirming a `catastrophic-low-frequency` control as waste on a clean window — that inverts the guardrail.
- Duplicating `/token-waste-audit`'s execution-layer signatures (rule 4 cut; rule 7 scoped to cross-session ceremony) — different axis, no overlap.
- Auto-reclassifying a lane or auto-removing a gate — out of scope in every phase of this skill.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. Reuses the in-repo `token-economy` substrate by reference. See `docs/source-map.md`.
