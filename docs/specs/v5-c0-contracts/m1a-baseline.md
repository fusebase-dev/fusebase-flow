# M1A — minimum honest baseline, before any C0 lock

**Status:** NOT STARTED, and NOT the next action. Adversarial review returned `SHIP-SMALL-FIRST` with 7 BLOCKERs on this design — it cannot measure the known bottleneck (it omits wait-for-ruling elapsed time), mis-counts artifacts, and `lane_by_final_diff` is circular. Retained as a record of what a baseline would need to fix, not as a plan. See `reviews.md`. **Supersedes nothing.** Gates: A1–A3, A5–A9 of `decisions.md`.
**Origin:** adversarial review 2026-08-05 returned `WRONG-SEQUENCE` on C0 — the roadmap's own premise falsifier ([v5-roadmap.md:357](../../tmp/handoff/2026-08-05-v5-roadmap.md)) has never been tested.

## The one question

> For an **ordinary** change, how many human decisions and persistent artifacts does Flow actually cost today?

If the answer is already "one and one" for most changes, the roadmap's premise is falsified: the problem is activation/documentation, not product structure, and A2/A5/A6 should not be built.

## Deliberately NOT building instrumentation

Roadmap M1 proposes opt-in JSONL event recording. **M1A does not build it.** A tally sheet filled in per change costs zero engineering and answers the one question. Building telemetry to decide whether to build a classifier is the same trap one layer up.

## What is recorded, per change

| Field | Definition (deliberately mechanical) |
|---|---|
| `change_id` | date + one-line description |
| `repo` | which project |
| `human_decisions` | count of times the operator had to decide/approve/answer before the change was live. Retries of the same question count once |
| `artifacts_created` | count of NEW persistent files under `docs/` created for this change |
| `handoffs` | count of handoff/session-restart documents written |
| `lane_declared` | Full / Lightweight, as chosen at the start |
| `lane_by_final_diff` | what the final diff SHOULD have been, judged after, against the existing hard-surface list |
| `flow_active_min` | rough minutes spent on Flow artifacts/process, excluding the actual coding |
| `control_that_mattered` | any Flow control that changed the outcome (blocked something, caught something). Usually empty — record it honestly |
| `escape` | anything that broke afterwards and which control should have caught it |

## Sample — scaled to what exists, and labelled as such

The roadmap assumes four ordinary repositories. **That pool may not exist.** The sample is whatever real Flow-using projects there are, stated plainly in the result. WorkHub and Paperclip are excluded — both are explicitly atypical.

| If the real pool is… | Then M1A is… | And it can… |
|---|---|---|
| 4+ ordinary repos | the roadmap's design, 2 changes each | apply the 75% falsifier as written |
| 1–2 repos | 3 changes per repo | show a **direction**, not a rate |
| 0 ordinary repos | **not runnable** | → the honest finding is that Flow has no measurable ordinary users, which is itself decisive for the roadmap |

## What a small sample can and cannot conclude

Stated up front so the result is not over-read later:

- **Can falsify by extremity.** If every observed ordinary change needs ≥3 decisions and ≥3 artifacts, the premise holds and structural work is justified. If every one needs 1 and 1, the premise is falsified.
- **Cannot establish a rate.** With N<8, "75%" is arithmetic theatre. Report raw counts, never a percentage.
- **Cannot compare against a changed Flow.** M1A is baseline only; the paired arm belongs with whatever is eventually built.

## Stop rule

M1A ends after the sampled changes, or after **14 days**, whichever comes first. A measurement with no stop rule becomes the new rabbit hole.

## What happens with each outcome

| Result | Next action |
|---|---|
| Ordinary changes already cost ~1 decision / ~1 artifact | **Roadmap premise falsified.** Drop A2/A5/A6. Fix activation and docs instead |
| Cost is high, and it comes from **lane misclassification** | Build only the cheap hard-surface router. No declaration schema, no thresholds, no overrides |
| Cost is high, and it comes from **artifact count** | A5 (one `ticket.md`) is justified; A2 is not |
| Cost is high, and it comes from **approval friction** | A6 is justified; A2 and A5 are not |
| Cost is high, cause unclear | Sample more before designing anything |

## Not blocked by this

`A4` (exact-candidate-SHA release contract) is a narrow safety contract independent of the cost question and may proceed separately. The review that produced M1A said so explicitly.
