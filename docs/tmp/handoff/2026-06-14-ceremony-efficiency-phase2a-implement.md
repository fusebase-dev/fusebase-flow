# Implement handoff — ceremony-efficiency-middle-lane Phase 2A

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.22.0. Self-attest per FLOW_RULES.md (FR-01..FR-26), naming AI Developer + IM.1..IM.18.
Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-13 (preflight per commit), FR-22 (comments), FR-23 (doc budget), FR-25 (module<800), FR-26 (token-efficient).

## Mandatory reads (in order)
1. `FLOW_RULES.md` FR-01..FR-26 (stop at Amendment log)
2. `docs/specs/ceremony-efficiency-middle-lane/spec.md` — esp. **A2 (Output paragraph)**, **D7**, **AC2 (Phase-2A clause)**, **AC2b** (the DEFERRED gates — NOT this handoff), Implementation order
3. `docs/specs/ceremony-efficiency-middle-lane/tasks.md` — **T24 (Phase 2A detail)**, T25 gate
4. The current analyzer: `hooks/local/find_wasted_effort/{constants,evidence,rules,selftest,selftest_e2e,__init__}.py` + `hooks/local/find-wasted-effort.py` (read-only containment you must preserve)
5. `flow-skills/find-wasted-effort/SKILL.md` + `references/`
6. `flow-skills/role-discipline/references/ai-developer.md`

## Ticket header
| Field | Value |
|---|---|
| Slug | `ceremony-efficiency-middle-lane` (Phase 2A) |
| Task range (this handoff) | **T24 → T25 (stop at gate)** |
| T-counter going in | T23; first task T24 |
| Last shipped | Phase 1, v3.22.0 (deploy `eb1991a`) |
| Lane | Lightweight (additive, read-only-safe) |

## Scope — T24 (the ONLY task here)
Add **proposal output** to `/find-wasted-effort`. **CRITICAL: this is NOT the read-only→write flip.** The analyzer stays **read-only to the project** — it must continue to write **nothing outside the gitignored `state/audit/`** directory. You are only enriching the *output*.

1. **Proposal schema** (define once, e.g. in `constants.py`): each proposal carries `proposal_id`, `rule`, `verdict`, `raw_evidence_refs` (pointers to the on-disk artifacts that justify it — NEVER prior audit-authored output), `target_kind`, `target_path`, `exact_patch` (the change a human *could* apply), `operator_confirmation_required: true`, `source: "audit"`.
2. **Emit proposals** derived from the rules' findings: a `confirmed` rule finding → a proposal recording the recommendation (e.g. lane reclassification, baseline+end policy); a rule-6 review-candidate → a `prune_review_candidate` proposal. **`prune_review_candidate` only — NEVER an auto-prune or a recorded prune decision** (PO owns subtraction; `policies/ratchet-governance.yml`). `inconclusive`/`dismissed` findings emit no proposal.
3. **Output surfaces:** a new **"Proposed memory entries"** section in the `state/audit/<date>.md` report, AND an optional sibling gitignored `state/audit/find-wasted-effort-proposals-<date>.json`. Both under `state/audit/` only.
4. **Self-output quarantine (Codex finding 5):** proposals must cite raw artifacts as evidence, never a prior audit report/proposal — and the evidence collectors must NOT read `state/audit/` (so the audit can't cite itself). Confirm/assert this.
5. **Tests:** golden-proposal fixtures (a confirmed finding → expected proposal JSON; a review-candidate → expected proposal; an inconclusive → no proposal); and a **hard test that a full run modifies NOTHING outside `state/audit/`** (no memory/overlay/spec/provider/policy file touched). Keep `--selftest` green; report passed/skipped separately.

**Explicitly NOT in scope (these are Phase 2B / deferred — do NOT build):** any write to project memory, overlays, specs, or provider files; any apply/confirm path; any FLOW:PRESERVE overlay edit (diff-in-report only); any read-only→write flip.

## Module size (FR-25)
Keep every `find_wasted_effort/` module < 800. If proposal logic would push one over, extract a `proposals.py` along the seam.

## Worker-undisturbed
Zero diff to: FLOW_RULES.md FR rows; the 3 deploy policies (approval/required-artifacts/command); `ratchet-governance.yml`; existing skills other than `find-wasted-effort`. Bounded-additive: `hooks/local/find_wasted_effort/`, `flow-skills/find-wasted-effort/` (+ mirrors), fixtures.

## Stop at gate (T25)
Per FR-05, stop at the gate. Produce the gate report (`templates/gate-report.md`; fields per `policies/gate-contracts.yml: gate_report`), assert **nothing outside `state/audit/` was modified by a run**, then HALT. Do NOT push, do NOT deploy.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ analyzer still READ-ONLY (writes only state/audit/; no memory/overlay/spec write)  ☐ FR-25 < 800  ☐ commit cites T24
```

## Notes
- Reshaped per the Codex Phase-2 design review (2026-06-14): Phase 2A = proposal *output* only; the write-apply (Phase 2B) is deferred to the consumer repo behind AC2b.
- Deploy (T26 → v3.23.0) is a separate deploy handoff after the gate + an independent Codex review.
