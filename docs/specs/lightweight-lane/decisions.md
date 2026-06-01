# Decisions — lightweight-lane

**Letter prefix:** L
**Approval status:** Locked by operator directive ("update Fusebase Flow so it doesn't do paperwork where it's not necessary — do it yourself"), 2026-06-01, against the production proposal.
**Linked spec:** `docs/specs/lightweight-lane/spec.md`

| ID | Title | Decision | Lock |
|---|---|---|---|
| L1 | Anchor as an always-on rule | Add **FR-21 — ceremony proportional to change size** rather than only conditionalizing existing rules. FR-21 authorizes the two-tier model, names the retained safety floor, and the mid-flight promotion rule. It is the durable anchor so the lane is honored even with hooks off / on non-Claude agents. | LOCKED |
| L2 | One dedicated skill owns the predicate | Add a single `lightweight-lane` skill (24th canonical) as the single source of truth for the eligibility gate, the change-note, the one-pass procedure, and promotion. Other skills/agents reference it (DRY) instead of each re-stating the predicate. | LOCKED |
| L3 | Tier field + minimal telemetry | `change_tier: full \| lightweight` set at classification — in the change-note header for LL, in spec.md for Full. Tier and any mid-flight promotion are recorded in a minimal ledger (`docs/changes/index.md`) so mis-tiering is auditable (proposal item 5). | LOCKED |
| L4 | Change-note artifact | New `templates/change-note.md`: problem · the change · how it's verified · rollback · tier · commit SHA. Usable inline in the commit body (smallest changes) or saved as `docs/changes/<date>-<slug>.md`. Replaces the spec/decisions/tasks/gate chain + two handoff docs for LL. | LOCKED |
| L5 | LL deploy approval = plain go-ahead | For LL-eligible changes, replace the DP.1 JSON artifact + DP.6 literal magic phrase with **one explicit plain operator go-ahead** in chat ("ship it"/"deploy it"/"go"). Never auto-deploy. No separate deploy session. This is the proposal's core ask. | LOCKED |
| L6 | One agent pass | LL runs build → live-verify → deploy in a single AI Developer session (no stop-at-gate handoff to a second deploy session; no redundant rebuild). The Full lane's two-phase split is unchanged. | LOCKED |
| L7 | Verification compressed, not skipped | LL keeps live verification/proof and still applies the 3-question empirical test to the (one) acceptance criterion; the report is 1–3 lines instead of a full gate-report doc. `validation-and-qa` gains an LL mode. | LOCKED |
| L8 | Hook layer stays safe + tier-aware | Hooks are opt-in (off by default since v3.6.0); in that default the chat go-ahead is the gate. When hooks ARE wired, `before_deploy_command` accepts EITHER `production_deploy-*` (Full) OR a one-command `lightweight_deploy-*` stamp (LL) — `approve-local.sh lightweight_deploy <slug>` writes it from the operator's plain go-ahead (no magic phrase, no hand-authored JSON). Full lane's requirement is unchanged. | LOCKED |
| L9 | Promotion is mandatory and fail-safe-up | In doubt at classification → Full. Mid-flight, if an LL change touches more than a couple files, surfaces a risk, needs a real decision, or reveals a deeper bug → STOP and promote to Full (logged). | LOCKED |

## L1 — why a new FR (not just skill text)
The proportionality principle is a behavioral default of the same class as FR-17 (forward momentum) and FR-20 (zoom out) — it must hold in every session, including hooks-off and non-Claude agents that read only the always-on layer. Encoding it as FR-21 makes "scale ceremony to risk" a contract, with the skill (`lightweight-lane`) holding the operational detail. Cost: the self-attestation range `FR-01..FR-20` → `FR-01..FR-21` is swept across live-attestation surfaces (context-anchored; historical FR refs untouched), then re-mirrored.

## L5/L6 — why this is safe (the retained floor)
Everything LL drops is **planning + traceability overhead** that de-risks *uncertain* work. For a change that is small, reversible, security-neutral, and has a one-sentence verifiable outcome, that uncertainty is near zero, so the artifacts add cost without reducing risk. Everything that **actually controls risk** is retained in both lanes: live proof, an explicit human deploy go-ahead, the FR-07 protected-path check, a documented rollback, and one-commit-per-change with the SHA recorded. Net: same safety floor, a fraction of the overhead. The DP.6 magic phrase and the two-agent split were the disproportionate parts for trivial reversible work — and the split itself *added* risk (the measured redundant rebuild).

## L8 — the one refinement beyond the proposal
The proposal says "the JSON artifact is dropped." Honored at the rule/agent layer (the real gate in the default hooks-off setup): LL deploy needs only the chat go-ahead. For hook-wired projects, rather than leave an artifact-free hole, the go-ahead is recorded by a **single command** (`approve-local.sh lightweight_deploy <slug>`) — that is friction removal (no magic phrase, no hand-authored JSON, no separate relay), not ceremony, and it doubles as the tier telemetry. Revisitable if the operator prefers fully artifact-free even with hooks wired.

## Lock confirmation
L1..L9 LOCKED 2026-06-01 (operator delegated execution against a detailed production proposal). Implementation authorized.
