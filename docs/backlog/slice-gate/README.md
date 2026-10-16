# slice-gate

**Status:** open — 6.0.0 rebuild, **wave 2** (with `done-check`, one writer). **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 7d (R §2). **Surface:** `hooks/local/lib/gate.py` (new core file, row 32; this entry owns the file and its default mode), `state/gate/<slice>.txt`; retires `hooks/local/lib/gate_contract_check.py`, `hooks/local/verify-gate.sh`, `hooks/tests/test-gate-contract.sh` (tag `gate-contract`, `hooks/tests/run-tests.sh:82, 663`) and `policies/gate-contracts.yml`. **FR-07:** the gate commit no; the retirement commit yes (`policies/*.yml`, `policies/protected-paths.yml:89`).

## Delivers

- **`gate <slice>`** runs the DONE check (`done-check`), the four flags (`overbuilding-flags`) and the validator (`evidence-row-validator`), and writes `state/gate/<slice>.txt`, the first block of the verdict brief (H WP 7d). The slicer's `--brief` prints it inline (`task-slicer`).
- **The `gate_rounds` count** (decision 3): the key `gate_rounds: 2` lives in `policies/approval-policy.yml` (`seven-policies` adds it); the gate script computes the count from the verdicts the planner records in `ledger.md` (D §6), never from a line the agent keeps.
  - A round is one verdict dispatch after the gate script passes; a DONE, validator or missing-field failure costs no round (3c).
  - Review rounds share the limit and keep their own counter (3d).
  - At the limit the gate returns `BLOCKED-AT-gate-budget` with the numbered carry-over list, security, privacy, data-loss and owner-answer contradictions first; the planner drafts it and the operator closes, unless an unattended close was authorized beforehand (3e). FAIL stays FAIL.
- **Holds, not blocks** (decision 6): flags never stop a slice; the only holds are a rubric "yes" on a risk-tagged item and the DONE send-back. Plan proposal: exit 0 = review may start (flags may exist), 3 = held for a ruling, 4 = DONE send-back; validator FAIL rows are verdict content, not an exit code.
- **Retires the 5.11 field-name gate** (H WP 7d; R §6 T144): `gate_contract_check.py` (its table parser already moved into `flow_docs.py` by `four-document-model`), `verify-gate.sh`, their test and tag, and `policies/gate-contracts.yml`, whose only readers they are. The tag also leaves `docs/maintainer-testing.md` (the `gate-contract` row).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 3 (a) to (e) | The computed count and its exhaustion |
| R §4 lock (`gate_rounds` defaults to 2; only the owner raises it; FAIL stays FAIL) | Fixtures below |
| Decision 6 (flags only; two holds) | Exit contract |
| Addition 3 and the second message | The release note reports `gate.py`'s total line count, with the DONE and validator spans against D's 20 and 80 |

## Estimate

Share of R §2 WP 7 (16 to 21.5 agent-h for 7a to 7d): 2.5 to 3.5, including the round count (decision 3's 2 to 3 agent-h is shared with `seven-policies`). On the critical path (R §2: 2.5 h step).

## Depends

`done-check`, `evidence-row-validator`, `overbuilding-flags` (the checks), `seven-policies` (the `gate_rounds` key and its tighten-only rule). Blocks: `reader-agent-and-dispatch-check`, `six-skills-and-optional-pack` final, `task-slicer --brief`.

## Acceptance

1. The gate output lists DONE, flags and validator results in a fixed order and carries the brief block (fixture).
2. Rounds 1 and 2 proceed; round 3 returns `BLOCKED-AT-gate-budget` with the numbered carry-over list, fixed-first classes first (fixture).
3. A local override that raises `gate_rounds` is rejected with a policy error; one that lowers it is honoured.
4. A DONE or validator failure leaves the round count unchanged.
5. No flag turns the exit into a hold or block unless it is a rubric "yes" on a risk-tagged item.
6. After the retirement commit, nothing reads `policies/gate-contracts.yml` and the `gate-contract` tag is gone from `FF_TAGS` and from `docs/maintainer-testing.md`.

## Wave split

Wave 2, two commits planned: (a) `gate <slice>` with the round count and fixtures (not FR-07); (b) the retirement of the 5.11 gate files and the policy (one FR-07 approval). Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
