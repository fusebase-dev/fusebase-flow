# Verification gate — ceremony-efficiency-middle-lane (Phase 1)

**Linked spec:** `docs/specs/ceremony-efficiency-middle-lane/spec.md`
**Linked tasks:** `docs/specs/ceremony-efficiency-middle-lane/tasks.md`
**Gate task:** T22 (Phase 1) · **Pass threshold for smoke:** 1/1 PASS
**Scope:** This gate covers **Phase 1** (T18–T23). Phase 2 (T25) and Phase 3 (T31, + security-permissions-review) get their own gates at their time.

## Acceptance-criterion → task mapping (Phase 1)
| AC | Implemented in | Test coverage |
|---|---|---|
| AC2 (`/find-wasted-effort` read-only, 6 rules, FP discipline, reuse substrate) | T19, T20, T21 | per-rule unit fixtures; clean-repo run produces well-formed `state/audit/` report; no writes asserted |
| AC3 (`prevents:` annotations on scoped set + coverage stated) | T18 | annotation-parser fixture; coverage map present in `policies/ratchet-governance.yml` |
| AC5 (docs + sweep) | T21 | mirror drift 0; plugin validate clean; skill-count consistent across adapters |
| AC6 (standard gate) | T22 | this gate |
| AC7 (first-consumer run) | T23 (smoke S1) | `/find-wasted-effort` run once against this repo |
> AC1 / AC4 are Phase-3 (Middle Lane / `middle_deploy`) — not in this gate.

## Lint / typecheck / test commands (framework repo)
| Layer | Command |
|---|---|
| Preflight | `bash hooks/local/preflight.sh` → errors 0, warnings 0 |
| Hook tests | `bash hooks/tests/run-tests.sh` → all PASS |
| Recovery sim | `bash hooks/tests/recovery-sim.sh` (or current path) → all PASS |
| Health | `bash hooks/local/fusebase-flow-health-check.sh` → HEALTHY |
| Mirror drift | `bash hooks/local/mirror-skills.sh` + preflight → drift 0 |
| Plugin validate | plugin manifest validates clean |
| Analyzer unit | `python hooks/local/find-wasted-effort.py --selftest` (or fixture runner added in T20) |

## Worker-undisturbed paths (this ticket, Phase 1)
Empty diff required unless declared:
- `FLOW_RULES.md` FR-01..FR-26 **rule rows** — Phase 1 adds NO rule (FR work is Phase 3 / T27). Annotation taxonomy lives in `policies/`, not the rule rows.
- Existing skills under `flow-skills/` other than the new `find-wasted-effort/` (and the cited reuse of `token-economy` — read-only reference, no edit).
- `policies/approval-policy.yml`, `required-artifacts.yml`, `command-policy.yml` — **no deploy-authority change in Phase 1** (that is Phase 3 / T28).
- Bounded-additive allowed: `templates/`, `workflows/` (annotation comments only, T18); adapter docs (skill-count, T21).

## Smoke prompt (post-deploy) — define per `flow-skills/smoke-testing`
| ID | Scenario | Surface | Operator-visible success | Ground-truth diagnostic | Auth/data | Adversarial check | Evidence |
|---|---|---|---|---|---|---|---|
| S1 | First-consumer run of the new audit (AC7) | `/find-wasted-effort` in Claude Code on THIS repo | A `state/audit/find-wasted-effort-<date>.md` report is produced, listing per-rule confirmed/dismissed/inconclusive findings with the FP header | the written report file + its rule sections | no-auth; reads existing repo artifacts; report is gitignored | run on a repo with a known clean round → that round must NOT be flagged as waste (FP discipline holds) | the report file excerpt |

### S1 steps
1. In a fresh Claude Code session on this repo, run `/find-wasted-effort`.
2. Confirm it writes `state/audit/find-wasted-effort-<date>.md` and makes **no** edits to specs/memory/overlays (read-only).
3. Confirm each finding is labelled confirmed/dismissed/inconclusive and the FP header is present.
4. Adversarial: confirm a known-clean round is not reported as waste.
Pass criterion: report produced, read-only respected, FP discipline visible. Evidence dir: `docs/tmp/handoff/2026-06-13-ceremony-efficiency-middle-lane-smoke/`.

## Probes (post-deploy)
| ID | Probe | Pass criterion | Evidence |
|---|---|---|---|
| G-M | release commit + push + tag | push fast-forward; tag `v<next>` on origin | `git log` / `gh release` |
| G-N | preflight on shipped tree | errors 0 / warnings 0 | transcript |
| G-O | new skill discoverable | `find-wasted-effort` present in `.claude/skills/` + `.agents/skills/`; command resolves | `ls` / matcher |
| G-P | analyzer runs on consumer | `/find-wasted-effort` produces a report (S1) | report excerpt |
| G-Q | spec/tasks/CHANGELOG updated | single docs commit; skill-count consistent | `git log` |

## Rollback
1. `git revert <deploy hash>` (Phase 1 is additive — a new skill + annotations; fully reversible, no schema/data).
2. Re-push; re-mirror.
3. File follow-up backlog ticket; spec Phase-1 status note reverts.

## Cross-artifact consistency check (before approving Phase-1 deploy)
```
☐ Worker-undisturbed — FR rule rows untouched; deploy policies untouched (Phase 1)
☐ Every Phase-1 AC (AC2,AC3,AC5,AC6,AC7) exercised in ≥1 task
☐ Every cited decision (D5,D7) cited in ≥1 task
☐ Analyzer is read-only (no memory/overlay/spec writes; no prune recs) — P2 only
☐ rule 4 absent (cut); rule 7 scoped to cross-session layer
☐ All T18..T21 SHAs filled; no TODO/FIXME/WIP
☐ Spec Phase-1 status note pending flip in deploy
```
If any item fails, redirect AI Developer. Do NOT bypass.
