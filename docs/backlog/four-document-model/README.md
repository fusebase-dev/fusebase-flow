# four-document-model

**Status:** open — 6.0.0 rebuild, **wave 1** (grammar review, templates, parser); template removal deferred. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 2 (R §2). **Surface:** `templates/` (25 files today → 4), `hooks/local/lib/flow_docs.py` (new, core row 30). **FR-07:** no (`templates/**` and `hooks/local/**` are outside `policies/protected-paths.yml:84-101`).

## Delivers

- Four templates replace 25 (H WP 2; D §2 row 1):
  - `templates/backlog.md`: items `B<n>` with source slice, acceptance criterion or test id, inputs, risk tag, status; the owner's answers live here.
  - `templates/phases.md`: phases, slices, tasks `T<n>` unique across the file, the backlog item each task serves, directories or globs, estimate in minutes and files, the reference project.
  - `templates/evidence.md` (one per phase): one PASS or FAIL row per criterion with its capture, sha256 and run id.
  - `templates/ledger.md`: first line `status: state/status.line`, then next, alerts, handoff and deploy records. `committed` is derived (`done-check`), `done` is the validator's verdict; neither is hand-written.
- `hooks/local/lib/flow_docs.py`: the one parser for the four documents, imported by the slicer, the DONE check, the validator, the checks and `commit-msg`, so the grammar has one home. It reuses the markdown table parser of `hooks/local/lib/gate_contract_check.py` (R §6, T144 row) before that file retires (`slice-gate`).
- **The grammar is reviewed before any code** (R §2; premise review per `docs/maintainer-execution.md:10`, step 4). Wave 2 packages depend on this interface, not on finished code (R §2).

## What the grammar must carry (from the accepted decisions)

| Source | Grammar consequence |
|---|---|
| Decision 2 (slicer specification) | An `inputs` entry may be `path#anchor`; the slicer prints the anchored section inline under a byte cap (cap value: plan proposal) |
| Decision 6 | A `plan:` or `ship:` commit may stage the four documents plus `state/flags/*.tsv` and `state/gate/*.txt` |
| Decision 10c | A standing housekeeping task per phase for trivial commits; ids resolve in `phases.md` at HEAD. Plan proposal: a task's backlog field may be blank only when every commit citing it is trivial-tier |
| Decision 11 | The finding marker and the row-status pattern are constants in `policies/evidence-classes.yml`, not template text |
| Decision 8 (no `--seed-backlog`) | No importer from 5.x `tasks.md`; the migration report lists open ids instead |
| H WP 2 | The four documents are never trivial-tier paths |
| H WP 7c | `evidence.md` rows carry what the validator checks: criterion id, status, capture path, run id, and for test-id rows the test id and the SHA |
| Confirmed drops (R §1) | `templates/smoke-test-playwright.md` is not a document: about 10 tool-neutral lines move into verify (`six-skills-and-optional-pack`); the rest is CLI-owned |
| Ask 5 | `templates/deploy-report.md` goes, so production deploy receipts go with it (`core-hook-inventory`) |

## Decisions and asks carried

Decisions 2, 6, 8, 10c, 11; ask 5; the confirmed drop of the smoke template. Non-negotiable 6 (H): no design tool, ticket system or model named in any template.

## Estimate

R §2: 4 to 6 agent-h (mid 5): grammar 1.5, parser 2, removals and sweep 1.5. On the critical path as its first step (7.5 h with the premise review, R §2).

## Depends

The decision table (answered; decision 11 fixes where the constants live). Blocks: `done-check`, `evidence-row-validator`, `slice-gate`, `overbuilding-flags` (flags 1 and 3), `task-slicer`, `trivial-tier-and-task-ids`; `one-lifecycle-page` (document names).

## Acceptance

1. The grammar note is reviewed and frozen before `flow_docs.py` is written; later changes need a new review.
2. Each template round-trips through `flow_docs.py`; a duplicate `T<n>` and a malformed id are rejected (fixture).
3. The four parse with the validators of WP 7 and WP 8 (H WP 2).
4. No template field exists that no script or phase step reads (field-inventory fixture, H WP 2).
5. The 21 removed templates are gone from the core (deferred commit below).

## Wave split

- **Wave 1:** (a) the grammar note and its premise review; (b) the four templates plus `flow_docs.py` and its fixtures (Python, run locally; a hosted tag for the record). Planned as two commits; the design pass's WP 2 plan names the fixture file.
- **Deferred to wave 3** (plan proposal): removing the 21 old templates and sweeping their references, together with `one-lifecycle-page` and the final `six-skills-and-optional-pack`, because live 5.11 skills, workflows and tests still cite them until then.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
