# Gate report — token-floor-remediation (T19 re-run)

> **Supersedes the first T19 gate body in place (FR-18).** That body — verdict FAIL on AC14/AC22/AC28, A2 2nd-amendment budget 40,700, task range ending at T21 — is replaced, not appended. This report is the current contract: task range T1–T18 + T21–T24, AC1–AC28, A2 **3rd-amendment** budget **42,200**. (The T11 pre-correction body was itself superseded here at the first T19 run.)

**Status:** Gate reached; **halted per FR-05 / IM.8**. No deploy, no tag, no push. T20 not started.
**Slug:** `token-floor-remediation` · **Branch:** `fix/msys-v3307-hardening`
**HEAD at gate:** `a2214b3` · **Task range:** T1–T10, T13–T18, T21–T24 (20 task commits) + T19 (this gate, evidence-only)
**Reporting session:** AI Developer (Fusebase Flow v4.5.0, FR-01..FR-27)
**Date:** 2026-07-26 (re-run after the T22/T23/T24 repair round)

## VERDICT: **PASS** — 28/28 AC PASS

The three failures of the first T19 run are repaired and re-evidenced:

| AC | Was | Now | Repaired by |
|---|---|---|---|
| AC14 | FAIL — no Write-primitive subsection in canonical `role-discipline` | **PASS** — `### Write primitive — Edit is the default, Write is for structure changes` resident at `flow-skills/role-discipline/SKILL.md:99`; `test-supersede-primitive` **21/21** | T22 `2e8d6aa` |
| AC28 | FAIL — unqualified "retry until it starts" in 5 live carriers | **PASS** — zero occurrences in every framework carrier, mirror, and knowledge artifact (grep § AC28) | T23 `3cd06e7` |
| AC22 | FAIL — suite 617/619 (1 FAIL + 1 INCONCLUSIVE) | **PASS** — see § 3 | T22 + T24 `a2214b3` |

**One item needs a PO ruling before deploy** (recorded, not fixed — § 6 D5): the AC2 rule-inventory diff against the `cfac6c0` baseline is **non-empty by design** — T23 deliberately reworded the FR-27 statement in `FLOW_RULES.md` and its digest twin, as `tasks.md` § T23 instructs. 2 rows **modified**, 0 removed, 0 residency flips, row count unchanged at 170. The baseline was **not** edited (that is forbidden). AC2's own criterion — zero rule *loss* — holds; the literal "diff is empty" evidence shape does not.

---

## 1. Per-task commit table

All times UTC. `started_at` was not recorded by the T1–T18 implementing sessions (IM.11 gap, carried forward from the T11 report); committed-at deltas stand in.

| Task | Title | SHA | Committed | FR-07 approval | Preflight |
|---|---|---|---|---|---|
| T1 | delegated chat-return budget | `1198168` | 05:48:58 | none needed | ✓ 0/0 |
| T2 | supersede vs write-primitive | `8ce1901` | 05:53:53 | bootstrap digest `30f997da8bb9` | ✓ 0/0 |
| T3 | anti-reread + per-surface matrix | `aeb66cf` | 05:58:14 | none needed | ✓ 0/0 |
| T4 | Amendment-log extraction + stub | `cfac6c0` | 06:21:13 | minted+consumed; **id not in commit body** (F1) | ✓ 0/0 |
| T5 | rule-inventory instrument + baseline | `de06ec0` | 06:35:12 | none needed | ✓ 0/0 |
| — | instrument fix (range-heading phantom) | `0a3ead2` | 06:48:44 | none needed | ✓ 0/0 |
| T6 | `communication` compression | `9830092` | 06:49:57 | none needed | ✓ 0/0 |
| T7 | `role-discipline` compression | `e43090b` | 07:24:38 | none needed | ✓ 0/0 |
| T8 | `FLOW_RULES.md` compression + boot gate | `5a78a52` | 07:38:53 | bootstrap digest `74dd66502a4b` | ✓ 0/0 |
| T9 | audit-tool labeled auto-classification | `13f2486` | 08:01:48 | none needed | ✓ 0/0 |
| T10 | zero-trust liveness recipe | `9b6c152` | 08:04:27 | none needed | ✓ 0/0 |
| T15 | truthful auto-load matrix | `bae92bc` | 08:58:37 | `hooks/tests/**` — not protected | ✓ 0/0 |
| T13 | resident prohibitions + residency gate | `d814539` | 09:14:52 | `hooks/tests/**` — not protected | ✓ 0/0 |
| T14 | inventory residency schema + red controls | `9fde710` | 09:24:50 | `hooks/local/*` not protected | ✓ 0/0 |
| T16 | verb-anchored probe + path canonicalization | `4027f1b` | 09:37:50 | `hooks/local/*` not protected | ✓ 0/0 |
| T17 | non-vacuous arms + bounded retry envelope | `65003ed` | 09:49:17 | `hooks/tests/**` — not protected | ✓ 0/0 |
| T18 | documentation truth-up + literal budget | `be4c511` | 10:07:13 | `hooks/tests/**` — not protected | ✓ 0/0 |
| **T21** | **phantom FF_TAGS + hermetic FF_LIST** | **`7c5f78a`** | **10:20:44** | none needed (`hooks/tests/**` not in `fusebase_flow_internals`, `policies/protected-paths.yml:84-99`) | ✓ 0/0 |
| **T22** | **resident `### Write primitive` + A2 3rd-amendment ceilings** | **`2e8d6aa`** | **11:06:24** | none needed (`flow-skills/**`, `hooks/tests/**`, `audit/**` are not in `fusebase_flow_internals`) | ✓ 0/0 |
| **T23** | **bound every "retry until it starts"** | **`3cd06e7`** | **11:15:21** | **`protected_path_edit-flow-bootstrap-20260726`**, digest `cffed9f0b6aa`, minted AFTER staging (A9), consumed after commit | ✓ 0/0 |
| **T24** | **re-bound `cli-flow-recovery` 240s → 480s** | **`a2214b3`** | **11:27:37** | none needed (`hooks/tests/**` not protected) | ✓ 0/0 |
| T19 | verification gate (re-run) | (no commit — this file) | 12:0x | n/a | ✓ 0/0 |

`comment-policy review: applied (FR-22)` — T22 updated one existing header comment (ceiling provenance, kept accurate); T23 is prose-only (`… N/A (FR-22; no code diff)`); T24 added exactly **one** TRIPWIRE block (`run-tests.sh:296-299`) recording the non-obvious constraint that the bound tracks repo SIZE, not test correctness. No WHAT-restating, changelog, or rationale-recorded-elsewhere comments. T19 is evidence-only.

## 1b. Time totals

| Metric | Value |
|---|---|
| First task committed | 05:48:58 (T1) |
| Last task committed | 11:27:37 (T24) |
| Total elapsed T1→T24 | 5:38:39 |
| Task commits | 21 (20 T-tasks + 1 `flow(fix)`) |
| T22 wall-clock | ~12m (started ≈10:54, committed 11:06:24) |
| T23 wall-clock | ~9m (started ≈11:06, committed 11:15:21) |
| T24 wall-clock | ~12m (started ≈11:15, committed 11:27:37) — dominated by the two 5-minute proof runs |
| T19 re-run wall-clock | ~35m (11:28 → 12:0x); full suite alone ~21m (the +5m is T24's now-completing recovery phase) |

---

## 2. Test counts (before / after / delta)

Before = T11 gate (`9b6c152`). After = this gate (`7c5f78a`).

| Suite | Before | After | Delta |
|---|---:|---:|---:|
| `test-return-budget.sh` | 14 | 14 | 0 |
| `test-supersede-primitive.sh` | 21 | 21 (**21 PASS**, T22) | 0 |
| `test-sync-allowlist.sh` | 7 | 7 | 0 |
| `test-rule-inventory.sh` | 17 | 25 | +8 (T14 residency + red controls) |
| `test-boot-size.sh` | 20 | 22 | +2 (T15 body-eager arms) |
| `test-token-waste-classify.sh` | 31 | 49 | +18 (T16 fixtures, T17 mutation controls) |
| `test-prohibition-residency.sh` | 0 | 39 | +39 (T13, new) |
| `test-budget-literals.sh` | 0 | 6 | +6 (T18, new) |
| `test-history-extraction.sh` | 0 | 9 | +9 (T18, new) |
| `test-ff-only.sh` | 11 (10 PASS / 1 FAIL) | 11 (**11 PASS**) | 0 assertions, **+1 PASS** (T21) |
| **Ticket-owned total** | 121 | 203 | +82 |
| **Full suite** | **537/537** | **619/619** | +82 total, **all green** |

No assertion counts changed in the T22–T24 round: T22 flipped one existing FAIL to PASS, T23 is prose-only, T24 changed a bound. Verdict moved 617/619 → **619/619**.

---

## 3. Lint / typecheck / suite

```
$ bash hooks/local/preflight.sh
[preflight] preflight finished — errors: 0, warnings: 0                       exit 0

$ bash hooks/local/check-module-size.sh --all
(no output)                                                                   exit 0
  hooks/local/token-waste-audit.py = 792 lines <= 800 (FR-25) — 8 lines headroom (F3)
  hooks/tests/run-tests.sh unchanged in size class after T24 (3-line tripwire + 3 literals)

$ bash hooks/local/verify-hook-manifest.sh
[hook-manifest] verify: MATCH (listed=121 matched=121 modified=0 missing=0 extra=0; flow_version=4.5.0)

$ bash hooks/local/mirror-skills.sh
[mirror-skills] mirrored 98 files (across 2 mirrors); 0 had pre-existing drift.

$ bash hooks/local/fusebase-flow-health-check.sh
Verdict: HEALTHY                                                              exit 0

$ bash hooks/local/check-cli-flow-conflicts.sh
No write conflict detected. / No action required.                             exit 0

$ bash hooks/tests/run-tests.sh          # bounded per FR-27 (timeout 3300s, backgrounded, polled)
[run-tests] 619/619 PASS                                                      exit 0
  ZERO FAIL · ZERO INCONCLUSIVE
  33 phases; wall 1298s (21m38s) on MSYS; full UNSCOPED run.
  Results: state/audit/hook-test-results.md (the full-gate file, not -scoped.md)
  Slowest: cli-flow-recovery 327s(PASS) · bootstrap-exception 142s · trusted-enforcer 117s ·
           liveness 92s · health-check-timeout 86s · rule-inventory 85s · secret-scan-staged 76s
```

**`cli-flow-recovery` runtime, recorded (T24 / AC22):**

| Run | Bound | Result | Runtime |
|---|---:|---|---:|
| First T19 gate, full suite | 240s | rc 124 TIMEOUT | ≥240 (241s to bound-hit) |
| First T19 gate, scoped, quiet host | 240s | rc 124 TIMEOUT | ≥240 (2/2 reproduced) |
| T11 gate, full suite | 240s | PASS | 199s |
| **T24 proof — direct script** | none | **exit 0, 31/31 assertions, 0 FAIL** | **304s** |
| **T24 proof — harness scoped** | 480s | **PASS (exit 0)** | **310s** |
| **T19 re-run — full suite** | 480s | **PASS (exit 0)** | **327s** |

Not a masked hang: the direct run emitted **31 `[test-cli-flow-recovery] PASS:` assertions and zero FAIL** before exiting 0 — the phase completes and asserts, it does not merely run longer. New bound 480s leaves **153s (47%) headroom** over the full-suite 327s, deliberately above the measured edge (240s *was* the measured edge, which is why one ticket's growth crossed it). Still under `FF_PHASE_TIMEOUT=600`. `FF_SKIP_CLI_RECOVERY=1` and INCONCLUSIVE-is-not-green reporting are unchanged — a bound-hit still never goes silently green.

---

## 4. Worker-undisturbed verification (FR-07)

`policies/protected-paths.yml: worker_undisturbed` = none configured. **N/A** — not fabricated, per `verification-gate.md` § Worker-undisturbed paths.

Protected-path re-check at gate: `git status --short` shows only ` M ROADMAP.md` and ` M docs/tmp/handoff.md` — neither is an FR-07 protected path. See § 6 D1.

---

## 5. Manifest version

| Field | Before | After |
|---|---|---|
| `VERSION` | 4.5.0 | 4.5.0 (unchanged — T20 bumps to 4.6.0) |
| `audit/hook-layer-manifest.json` assets | 114 (T11) | 121 |
| Hook-layer `flow_version` | 4.5.0 | 4.5.0 |

---

## 6. Deviations from the locked plan

| # | Deviation | Why | Approved? |
|---|---|---|---|
| D1 | Working tree not clean at gate: `ROADMAP.md` (+1 roadmap row for this ticket) and `docs/tmp/handoff.md` uncommitted, inherited from the pre-T21 session | Pre-existing at `be4c511`; both are T20 release-bookkeeping surfaces. Not touched, not committed, not reverted — dispatch said produce evidence, do not fix | Recorded, not approved — PO call |
| D2 | T21 required **two** edits, not the one-line fix the handoff scoped | The handoff's single-cause diagnosis was incomplete (§ 8). The stated acceptance — green standalone **and** nested — is unreachable with only the `FF_TAGS` fix | Self-approved: both edits are the same defect class in the same FR-27 harness, one commit (FR-03) |
| D3 | T21 is a task number absent from `tasks.md` | Introduced by the dispatch handoff after `tasks.md` was locked | Per operator dispatch |
| D4 | T22 touched three planning artifacts (`decisions.md`, `tasks.md`, `verification-gate.md`) to sync the budget literal to 42,200 | The A2 3rd amendment **half-landed**: the PO amended `spec.md` and added the 3rd-amendment table to `decisions.md`, but A2's headline/summary lines and the gate's AC1 row still stated 40,700. `test-budget-literals.sh` (built at T18 for exactly this failure mode) went red the moment the enforced ceilings moved. Live statements were replaced (FR-18); records of the 1st/2nd amendments were annotated `since raised`, never rewritten. **No decision semantics were changed** — the numbers transcribed are the PO's own 3rd-amendment table (`decisions.md:47-55`) | Recorded — PO call. IM.2 was weighed: this is transcription of an amendment the PO authored, not a redirection of one. Flagged for confirmation |
| D5 | **AC2 rule-inventory diff is non-empty** — 2 rows modified (`FR-27` in `FLOW_RULES.md`, `WT.FR-27` in the digest), 0 removed | T23's mandate (`tasks.md:264`) is to reword the FR-27 rule row. Rewording a rule statement necessarily moves its normalized inventory text. The first T19 report anticipated this exactly (`§ AC28`: "location 5 is an FR rule statement, which AC2 forbids rewording — so a fix there is a decision"). The PO then scoped T23 to include `FLOW_RULES.md:34`. **The baseline was NOT edited** — that is explicitly forbidden and would have hidden the change | **Needs a PO ruling:** re-baseline at `a2214b3` (and record why), or accept the annotated 2-row delta as the AC2 evidence |
| D6 | T23 also bounded 5 occurrences outside the 5 canonical locations `tasks.md` § T23 names | The dispatch rule is "no unqualified 'until it starts' may remain **anywhere**". `docs/problem-catalog/transient-subagent-retry-discipline/problem.md` (×3) and `docs/specs/windows-msys-hardening/roadmap.md` (×2) are live, agent-read guidance carriers stating the same unbounded protocol | Self-approved: same defect class, same commit (FR-03), zero semantic drift |
| D7 | `decisions.md:122` (A10) and `tasks.md:158` keep the phrase, annotated with a pointer to the T17 envelope rather than rewritten | A10 is a **LOCKED** decision (IM.2). The dispatch rule allows "carries the envelope **or points to it**" — a cross-reference to the later refinement satisfies it without editing the decision's substance | Recorded, not approved — PO call |

---

## 7. AC evidence — AC1..AC28

### AC1 — boot floor, per-artifact ceilings + total ≤42,200 · **PASS**

`bash hooks/tests/test-boot-size.sh` → **22/22 PASS**, incl. 9 red arms (`red-ceiling-*`, `red-total-boot-floor`, `red-frontmatter-first`, `red-anti-reread`, `red-missing-required-reference`, `red-body-eager-claim`), plus `red-fixture-baseline-green` proving non-vacuity and `ceilings-sum-to-total` (7,000+14,500+11,500+9,200 = 42,200 exactly — the arithmetic guard T18 added so a ceiling amendment can never forget the total; it caught nothing this round because T22 moved both).

Measured (`wc -c`) against A2 **3rd-amendment** ceilings (T22 `2e8d6aa`):

| Artifact | Measured | Ceiling | Headroom | Δ vs first T19 run |
|---|---:|---:|---:|---:|
| `flow-skills/communication/SKILL.md` | 6,867 | 7,000 | 133 | 0 |
| `flow-skills/role-discipline/SKILL.md` | 14,167 | 14,500 | **333** | +672 (T22 subsection + T23 qualifier) |
| `FLOW_RULES.md` operative (whole file; history extracted) | 11,126 | 11,500 | **374** | +132 (T23 FR-27 qualifier) |
| largest `references/<role>.md` (`ai-developer.md`) | 9,161 | 9,200 | 39 | 0 |
| **Total role-aware boot floor** | **41,321** | **42,200** | **879** | +804 |

41,321 vs the measured 78,148-byte pre-change floor = **47.1% cut**. Headroom went from 5/6 bytes to 333/374 — F5 (the coupling that blocked both repairs) is **resolved**.

`test-budget-literals.sh` **6/6**: `no-divergent-budget-literal (enforced: 11500 14500 42200 7000 9200)`; `enforced-total-stated-in-prose (4 carrier(s) say 42,200)`; `red-stale-literal-detected` still bites.

### AC2 — zero rule loss + residency dimension · **PASS on the criterion; evidence shape changed — see D5**

```
$ diff <(bash hooks/local/rule-inventory.sh) docs/specs/token-floor-remediation/rule-inventory-baseline.txt
85c85     FR-27      (FLOW_RULES.md, resident)                          — text CHANGED
170c170   WT.FR-27   (flow-skills/role-discipline/SKILL.md, resident)   — text CHANGED
                                                                          rc=1
```

**Both hunks are `c` (change), not `d` (delete).** Row count unchanged at **170**; both rows keep their ID, their canonical source path, and `resident`. The only delta is the FR-27 sentence T23 was instructed to rewrite:

```
- … re-dispatch or sendmessage-resume (wait ~60s and retry until it starts); …
+ … re-dispatch or sendmessage-resume only inside the bounded delegate-retry envelope
+   (max 3 attempts / 5 min, labeled backoff, then successor-or-blocked-at-delegate-no-start
+   — liveness-discipline); …
```

Zero rules lost, zero residency demotions, zero cross-file moves — which is what AC2 exists to detect. The baseline (taken at `cfac6c0`) was **not** touched. PO ruling needed on whether to re-baseline at `a2214b3` (D5).

Schema: 4 tab-separated columns (`ID · normalized text · canonical source path · resident|lazy`), **170 rows** (94 under the pre-T14 two-column schema), 142 `resident` / 28 `lazy`.

`bash hooks/tests/test-rule-inventory.sh` → **25/25 PASS**, including both T14 red controls. Reproduced by hand on scratch trees to show them biting:

**Red control (a) — resident→lazy** (`m_move_resident_to_lazy`: delete only the *resident* OD-3 copy; the lazy `shared-protocols.md:255` copy stays alive, so the rule TEXT is still in the tree):
```
115d114
< OD-3	don't bypass the product owner	flow-skills/role-discipline/SKILL.md	resident
```
**Red control (b) — cross-role move** (`m_move_dont_between_roles`: IM.4 row moved verbatim from `ai-developer.md` to `deploy.md`; ID and text unchanged):
```
98c98
< IM.4	don't squeeze multiple tasks into one commit...	.../references/ai-developer.md	resident
---
> IM.4	don't squeeze multiple tasks into one commit...	.../references/deploy.md	resident
```
Both diffs non-empty → both bite. The `mutate()` harness carries a no-op guard (`mutator changed nothing — the case proves nothing`) so a stale mutator fails instead of passing vacuously. Fail-closed arms green: `fail-closed-zero-fr-rows`, `fail-closed-missing-sources`.

**Observation (F4):** in both controls the *path* column is what makes the diff non-empty; the `resident|lazy` column is not independently load-bearing for detection under the current layout. Detection is correct either way — noted, not a failure.

### AC3 — prohibitions resident · **PASS**

All 5 shared-protocol stubs + the FR-24 digest are in canonical `flow-skills/role-discipline/SKILL.md`, not only in `references/`. Anchors after T22/T23 (`grep -n '^## \|^### Write primitive'`): `:51` Operator Relay · `:55` Chat-Text Questions · `:61` Operator Gate · `:69` Forward Momentum · `:75` Write-time discipline digest · `:93` Supersede Convention · **`:99` Write primitive (new, T22)**. Per-prohibition proof is the `test-prohibition-residency.sh` ledger — see AC24.

### AC4 — anchors resolve · **PASS**

| Anchor | `role-discipline/SKILL.md` |
|---|---|
| `## Operator Relay Protocol` | :51 |
| `## Chat-Text Questions Protocol` | :55 |
| `## Operator Gate Protocol` | :61 |
| `## Forward Momentum Protocol` | :69 |
| `## Write-time discipline digest` | :75 |
| `## Supersede Convention` | :93 |

All 6 resolve.

### AC5 — missing-reference detection · **PASS**

`test-boot-size.sh` `required-references` + `red-missing-required-reference` both PASS (delete a required reference → FAILS; restore → PASSES). `test-rule-inventory.sh`: `drop-fr-row` / `drop-dont-row` / `drop-principle` RED, `reword-enforcement` GREEN — an Enforcement reword correctly does not register as rule loss.

### AC6 — history content-equivalent except a normalized final newline · **PASS**

`bash hooks/tests/test-history-extraction.sh` → **9/9 PASS**:
```
PASS: history-extraction extraction-commit-resolved (cfac6c0)
PASS: history-extraction content-equivalent-modulo-final-newline
PASS: history-extraction only-difference-is-the-final-newline (raw delta 1B)
PASS: history-extraction red-truncated-payload-detected
PASS: history-extraction red-edited-payload-detected
```
The exact amended contract (MINOR 14) is asserted, with two red arms.

### AC7 — stub keeps sweep anchor · **PASS**

`stub-heading-retained` + `stub-carries-no-dated-entries` PASS. `FLOW_RULES.md:71-74` keeps `## Amendment log` with a 2-line pointer and an explicit tripwire naming `sync-version-strings.sh` as the sweep anchor. `newline-preserve` phase green in the full suite.

### AC8 — distribution / publication · **PASS**

| Surface | Line |
|---|---|
| CI public-surface allowlist | `.github/workflows/fusebase-flow-verify.yml:88` |
| Publishing doc | `PUBLISHING.md:78` |
| Consumer distribution | `hooks/local/upgrade.sh:235` `CONTENT_FILES` |
| Protected-path classification | `policies/protected-paths.yml:88` |
| Surface ownership | `agent-surface-ownership.json:251` |

All five admit `FLOW_RULES_HISTORY.md`.

### AC9 — sync-allowlist classification · **PASS**

`bash hooks/tests/test-sync-allowlist.sh` → **7/7 PASS**, incl. `history-not-in-allowlist (carries live-looking tokens; excluded as dated history)` and `history-never-synced`.

### AC10 — frontmatter-safe placement · **PASS**

`head -c 3` = `---` on both `flow-skills/communication/SKILL.md` and `flow-skills/role-discipline/SKILL.md`. `test-boot-size.sh` `frontmatter-first-*` + `anti-reread-*` PASS for both; `red-frontmatter-first` and `red-anti-reread` prove the arms bite. Preflight frontmatter check: 0 errors.

### AC11 — per-surface matrix correct (descriptions inject, bodies do not) · **PASS**

Matrix as shipped (`AGENTS.md:153-160`; byte-identical overlay twin verified by preflight):

| Surface | What is auto-injected | Claims eager body? |
|---|---|---|
| Claude Code | description/metadata only (`.claude/skills/`) — **not** the body | no |
| Codex | description/metadata only, and only when the optional `skills_dir` is set — **not** the body | no |
| Gemini | **nothing** | no |
| Copilot | **nothing** | no |
| Cursor | `.cursor/rules/fusebase-flow-always.mdc` rule text — **not** the skill bodies | no |
| Delegated sub-agent (any surface) | **nothing** — `session_start` doesn't fire | no |

Machine check: `test-boot-size.sh` `body-eager-claim` PASS across **10** carriers (`AGENTS.md`, `CLAUDE.md`, both overlay twins, `.codex/config.toml.example`, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules/fusebase-flow-always.mdc`, both mandatory SKILL.md). The detector is semantic, not a phrase blacklist — three claim shapes (bare presence assertion / unnegated auto-load verb over a body noun / unconditional "do not Read"), and a surface NAME is explicitly rejected as a valid condition (`test-boot-size.sh:74-99`). `red-body-eager-claim` PASS → the arm bites. **No carrier asserts eager body loading.**

### AC12 — return cap (lines **and** chars) · **PASS**

Quoted from all 3 carriers:
- `flow-skills/task-delegation/SKILL.md:167` — "≤80 lines **and** ≤6,000 characters… Both limits bind together — one 32,000-character line satisfies a line-only cap and still costs the orchestrator the full read."
- `templates/handoff-implement.md:105` — "chat return ≤80 lines and ≤6,000 characters — longer → write a sanctioned durable artifact and return its path"
- `templates/handoff-deploy.md:27` — same clause.

`test-return-budget.sh` → **14/14 PASS**, incl. `red-line-only-cap-rejected`.

### AC13 — gate/deploy exempt · **PASS**

`templates/handoff-implement.md:187` and `templates/handoff-deploy.md:159`, verbatim: *"**Exempt from the delegated chat-return budget** (≤80 lines / ≤6,000 characters): evidence completeness outranks the cap here. Never drop a required field or truncate evidence to fit."* Arms `ac13-implement-gate-exempt`, `ac13-deploy-report-exempt`, `ac13-skill-exemption` PASS.

### AC14 — supersede both dimensions, no residual contradiction · **PASS** (repaired, T22 `2e8d6aa`)

```
$ bash hooks/tests/test-supersede-primitive.sh
[test-supersede-primitive] 21/21 PASS                                          exit 0
  PASS: supersede-primitive ac14-role-discipline-write-primitive-section
```

The subsection is restored **resident** in canonical `flow-skills/role-discipline/SKILL.md:99-101`, carrying T2's Edit-vs-Write rule (never pre-T2 wording) with the case table left lazy in `references/shared-protocols.md` § Write primitive detail:

> ### Write primitive — Edit is the default, Write is for structure changes
>
> **Supersede replaces stale *semantics*, not the file.** FR-18 governs authoritative content, never the write tool: most sections unchanged → targeted `Edit` (default); structure/mode/ticket changed, or most sections changed → full `Write` — correct there, **not** token waste (`token-economy` TE-06 agrees). Regenerating a mostly-unchanged file to "supersede" it is the waste, and FR-18 never asked for it. Case table: `references/shared-protocols.md` § Write primitive detail.

All five AC14 sources now carry both dimensions on one line (`both_dimensions()` — the assertion that half the rule alone is what caused the contradiction):

| Source | Line | Both dimensions? |
|---|---|---|
| `FLOW_RULES.md` FR-18 | :25 | yes |
| `role-discipline` FR-24 digest row | :83 | yes |
| `role-discipline` **§ Supersede Convention → ### Write primitive** | **:99-101** | **yes — restored** |
| `handoff/SKILL.md` | :61, :72, :93-94 | yes |
| `token-economy` TE-06 | :34 | yes — old contradiction gone (`ac14-te06-contradiction-gone` PASS) |

The ABSENT arm (the one that bites) stays green: `ac14-te06-contradiction-gone`, `ac14-audit-contradiction-gone`, `ac14-te-antipattern-qualified`. Both overlay twins byte-identical (`ac21-*-twin-byte-identical`).

**This report practiced the rule it ships:** superseded by targeted `Edit`s on the changed regions, not a full `Write` — structure is unchanged and most sections were re-verified rather than rewritten.

### AC15 — conjunctive tail rule · **PASS**

`ac15-size-differs-only-not-dismissed`, `ac15-intervening-write-not-dismissed`, `ac15-compaction-not-dismissed`, `ac15-error-result-not-dismissed`, `ac15-size-differs-only-evidence`, `ac15-contradictory-write` / `-compaction` / `-error` — all PASS. Full conjunction (fixture 01) auto-classifies; size-differs-only stays live.

### AC16 — triple labeled not dismissed · **PASS**

`ac16-nonprobe-triple-not-dismissed`, `ac16-nonprobe-quad-not-dismissed`, `ac16-probe-triple-dismissed`, `ac16-triple-label-kept-live`, `ac16-since-last-write-noted`, `ac16-probe-command-branch`, `ac16-probe-command-evidence` — all PASS.

### AC17 — visible evidence · **PASS**

Live report rows (`state/audit/token-waste-audit-2026-07-26.md`) render rule + evidence:
```
| polling | Bash x3 (no intervening Edit/Write): echo status | possible-FR-10-triple
| FR-26 TE-08 — record-then-read | exactly 3 runs since the last write (not necessarily
  consecutive); command is NOT probe-shaped — 3 failed retries and 3 polls are
  count-identical to a genuine FR-10 reproduction triple, so this stays live |
```

### AC18 — separate dismissal section · **PASS**

Report headers: `## Findings — LIVE candidates that MAY indicate an FR-26 rule` … "Live: 4." and `## Auto-classified (dismissed — counted separately, never silently dropped)`. `ac18-live-section`, `ac18-dismissed-section`, `ac18-live-table-has-no-dismissals` PASS.

### AC19 — three terminal states · **PASS**

Five states asserted and green: `ac19-state-candidates-found`, `ac19-state-all-classified`, `ac19-state-clean`, `ac19-state-parse-failure`, `ac19-state-no-transcripts`. Live run printed `TERMINAL STATE: candidates found (live candidates need adjudication)`.

### AC20 — mirror drift zero · **PASS**

```
[mirror-skills] mirrored 98 files (across 2 mirrors); 0 had pre-existing drift.
```
`git status --short -- .claude .agents audit/` → empty. Preflight mirror section: 0 errors.

### AC21 — command/overlay parity · **PASS**

Preflight parity section: 0 errors / 0 warnings. `ac21-handoff-twin-byte-identical` and `ac21-audit-twin-byte-identical` PASS.

### AC22 — preflight clean + suite green · **PASS** (repaired, T22 + T24)

```
$ bash hooks/local/preflight.sh
[preflight] preflight finished — errors: 0, warnings: 0                        exit 0

$ bash hooks/tests/run-tests.sh                       # full UNSCOPED gate run
[run-tests] 619/619 PASS                                                       exit 0
```

Zero FAIL, zero INCONCLUSIVE, 33/33 phases. The two causes are both closed:

| Cause at the first T19 run | Closed by |
|---|---|
| `FAIL: supersede-primitive ac14-role-discipline-write-primitive-section` | T22 `2e8d6aa` — subsection restored resident (§ AC14) |
| `INCONCLUSIVE: cli-flow-recovery` rc 124 at 240s, reproduced 2/2 | T24 `a2214b3` — bound raised to 480s **and proved to PASS at 327s with 31/31 assertions** (§ 3 table) |

The T24 fix is a re-bound, not a mask: the phase was never failing an assertion — it was exceeding a deadline that no longer fits a repo grown by this ticket's own tests, skills, and fixtures (199s at T11 → 327s now, +64%). A `TRIPWIRE` at `run-tests.sh:296-299` records that the bound tracks repo size and must always be set with headroom.

### AC23 — hook manifest stamped · **PASS**

```
[hook-manifest] verify: MATCH (listed=121 matched=121 modified=0 missing=0 extra=0; flow_version=4.5.0)
```

### AC24 — prohibition residency · **PASS**

`bash hooks/tests/test-prohibition-residency.sh` → **39/39 PASS**.

Resident-ledger arms green for the B-principle normative clauses (`ledger-modeb-b3/b4/b5/b6/b7/b8/b11/b12`), the Mode-A obligations (`ledger-modea-decoration`, `ledger-modea-width`), the Mode-B visuals prohibition (`ledger-modeb-visuals`), the gate / momentum / supersede prohibitions and their exact refusal phrasings, the operator don't-list, the STOP responses, and `ledger-no-prohibition-demotion`. `lazy-normative-clean` PASS → no lazy reference carries an uncovered normative marker.

Both red arms bite, with a non-vacuity guard:

| Arm | Mutation | Required outcome |
|---|---|---|
| `red-fixture-baseline-green` | none | unmutated fixture has **0** `bad` rows — otherwise the red arms would be vacuous |
| `red-planted-lazy-prohibition` | append *"Never reconfigure the quarantine partition without a witness manifest."* to `references/shared-protocols.md` | row `lazy-normative-shared-protocols.md` goes `bad` |
| `red-demoted-prohibition` | delete *"Never hand the operator a terminal"* from the resident SKILL.md | row `ledger-gate-no-terminal` goes `bad` |

The `red()` helper fails the arm if the named row does *not* go bad ("that arm does not bite") — the controls cannot pass vacuously.

### AC25 — verb-anchored probe matching · **PASS**

Ground-truth run of the production parser over the four retained-live fixtures:

```
$ python hooks/local/token-waste-audit.py --dir <fixtures 11..14>
LIVE candidates: re-read 1 | polling 3 | whole-file-rewrite 0 | large-output 0 | repeat-output 0
Auto-classified (dismissed, NOT counted above): 0
TERMINAL STATE: candidates found (live candidates need adjudication)
```

| Fixture | Command / path | Verdict |
|---|---|---|
| 11 `arg-position-status` | `echo status` ×3 | **LIVE** — `possible-FR-10-triple`, "command is NOT probe-shaped" |
| 12 `mutating-arg-status` | `deploy --message status` ×3 | **LIVE** — same label |
| 13 `probe-plus-mutation` | `bash hooks/local/preflight.sh && rm -rf build && git push origin main` ×3 | **LIVE** — documented probe + extra mutating commands, not dismissed |
| 14 `path-alias-write` | `Read C:/Repo/a.txt` ×3 | **LIVE** (see AC26) |

**Zero dismissals.** All four Codex PoCs stay live. Test arms `ac25-falseneg-none-dismissed`, `ac25-falseneg-all-stay-live`, `ac25-echo-status-not-dismissed`, `ac25-message-status-not-dismissed`, `ac25-probe-plus-mutation-not-dismissed` PASS.

### AC26 — path canonicalization · **PASS**

Fixture 14 live row, verbatim:
```
| re-read | Read x3 identical window: C:/Repo/a.txt | — | FR-26 TE-02 — no re-reads of
  unchanged in-context files | growth signal present but contradicted — intervening
  write to the read path at event 10 |
```
The intervening write was recorded as `c:\repo\a.txt`; canonicalization (absolute resolution + separator normalization + Windows case-folding) matched it to `C:/Repo/a.txt`, so the contradictory event fired and the candidate was **retained**. `ac26-path-alias-not-dismissed` PASS.

### AC27 — non-vacuous test arms · **PASS**

`bash hooks/tests/test-token-waste-classify.sh` → **49/49 PASS**.

Exact-row arms `ac27-row-02/03/04/05/07/08` assert the exact live row **and** evidence string. Mutation controls `ac27-mutctl-02/03/04/05/07/08` each patch exactly the predicate keeping their fixture live and **require the fixture to then be DISMISSED**:

| Control | Unsafe predicate substituted |
|---|---|
| 02 | `if not (grew or all_differ):` → `if not (len(set(sizes)) > 1):` (size-difference-only dismissal) |
| 03 | intervening-write check → `if False:` |
| 04 | compaction check → `if False:` |
| 05 | error-result check → `if False:` |
| 07 | `shape = probe_shaped(cmd, probe_cmds)` → `"unsafe: exactly-3 dismissal"` |
| 08 | `if n != FR10_TRIPLE:` → `if n < FR10_TRIPLE:` + `"unsafe: any-repeat dismissal"` |

A missing patch anchor **fails** the control (`MUTATION-ANCHOR-MISSING` → "patch anchor missing — control would pass vacuously"), so a stale control cannot pass silently.

`test-sync-allowlist.sh` omission arm (`guard-detects-omission`, PASS) runs the **production** `missing_set()` against a reachable set with `FLOW_RULES.md` dropped, and carries three anti-vacuity guards (`:98-111`): target-membership precondition, mutation-took-effect check, and a false-positive check that the *unmutated* set does not report it missing.

### AC28 — bounded retry exception · **PASS** (repaired, T23 `3cd06e7`)

**Grep proof — zero unqualified occurrences in any framework carrier, mirror, or knowledge artifact:**

```
$ grep -rn "until it starts" flow-skills/ .claude/skills/ .agents/skills/ FLOW_RULES.md \
         hooks/ templates/ workflows/ policies/ docs/problem-catalog/
(no output — exit 1)
```

All 5 canonical locations the first T19 run listed now carry the envelope inline:

| # | Location | Now reads |
|---|---|---|
| 1 | `liveness-discipline/SKILL.md:132` | "re-dispatch \"try again\", retrying only inside § Bounded delegate-retry envelope above (max 3 attempts / 5 min), then judge" |
| 2 | `task-delegation/SKILL.md:198` | "on a repeat limit retry only inside the bounded delegate-retry envelope (max 3 attempts / 5 min, then successor-or-`BLOCKED-AT-delegate-no-start`)" |
| 3 | `task-delegation/SKILL.md:219` | "retrying only inside the bounded delegate-retry envelope (max 3 attempts / 5 min; `liveness-discipline`) — never unbounded" |
| 4 | `role-discipline/SKILL.md:87` (FR-24 digest) | "re-dispatch a transient stall only inside the **bounded delegate-retry envelope** (max 3 attempts / 5 min, labeled backoff, then successor-or-`BLOCKED-AT-delegate-no-start`)" |
| 5 | `FLOW_RULES.md:34` (FR-27 rule row) | "re-dispatch or SendMessage-resume only inside the **bounded delegate-retry envelope** (max 3 attempts / 5 min, labeled backoff, then successor-or-`BLOCKED-AT-delegate-no-start` — `liveness-discipline`)" |

Plus 5 beyond the named set (D6): `docs/problem-catalog/transient-subagent-retry-discipline/problem.md:21,36,58` and `docs/specs/windows-msys-hardening/roadmap.md:78,167`.

**Remaining tree-wide occurrences — all dated records or annotated, none an instruction to retry unboundedly:**

| File | Class |
|---|---|
| `decisions.md:122` (A10) | LOCKED decision; annotated `— **bounded at T17** to max 3 attempts / 5 min …` (D7) |
| `tasks.md:158` | record of what T10 added; annotated `(bounded at T17: …)` (D7) |
| `tasks.md:259,263,265` | T23's own title/spec, which must name the defect it removes |
| `gate-report.md` (this file) | the evidence record of the FAIL and its repair |
| `docs/tmp/handoff/*.md` ×3 | dated relays — never a session read (`AGENTS.md` § Where things live) |

The envelope itself remains correctly stated in all three carriers, with all four required elements:

| Element | `liveness-discipline:100-114` (canonical) | `task-delegation:97` | `token-economy:33,36` |
|---|---|---|---|
| Max attempts | **3** re-dispatches | "max **3** attempts" | "3 attempts" (TE-08) |
| Max wall-time | **5 minutes** total | "**5 minutes** total" | "5 min" (TE-08) |
| Labeled backoff | "~60s → ~90s → ~120s… stated in chat each time" | "labeled ~60s → ~90s → ~120s backoff" | "one progress read per interval" |
| Successor-or-blocked | "STOP retrying… re-brief a SUCCESSOR… or return `BLOCKED-AT-delegate-no-start`… Never `FAILED-<reason>`" | identical transition | — |
| Two-strike carve-out | ":114 — not two-strike attempts" | — | TE-05 `:33` excludes envelope re-dispatches |
| Record-then-read override | ":112 — the override ends the moment the delegate IS producing progress" | — | TE-08 `:36` names it one of exactly two exceptions |

`token-economy:33,36` remains consistent, so AC28's literal criterion ("no residual contradiction with `token-economy:33,36`") holds; the broader T17 reading — all three carriers agree without contradiction — now holds too, in both the canonical files and their `.claude/skills/` + `.agents/skills/` mirrors. `FF_ONLY=liveness` phase green.

---

## 8. T21 — misdiagnosis correction (detail)

The handoff scoped T21 as a one-line fix with one root cause. Field evidence: **two** independent defects, and the standing "known non-defect" note was wrong on both of its claims.

| Claim carried through the run | Reality |
|---|---|
| "`ff-only scoped-skip-count` fails only when nested" | False — it failed **standalone** too |
| "Standalone it is 11/11" | False — `[test-ff-only] 10/11 PASS` |
| "Pre-existing harness nesting quirk — do not chase it" | A real, reproducible defect with a second real defect behind it |

**Defect 1 — phantom tag.** `run-tests.sh:49` held a literal two-character `\n` inside `FF_TAGS`; unquoted `\n` in bash is an escape of `n`, minting a phantom tag.
```
$ FF_LIST=1 bash hooks/tests/run-tests.sh | grep -n '^RUN' | sed -n '32,34p'
32:RUN  history-extraction
33:RUN  n                      <-- phantom
34:RUN  cli-flow-recovery
$ FF_ONLY=n bash hooks/tests/run-tests.sh
[run-tests] 0/0 PASS (SCOPED FF_ONLY=n — subset, not a full gate)      exit 0
```
That last line is exactly the silent "scoped to nothing green" the harness's own comment (`run-tests.sh:52-53`) says must never happen — a bogus selection must exit 2. The phantom also made `scoped-skip-count` permanently off by one (32 SKIPs vs 33 expected), because it guards no phase.

**Defect 2 — non-hermetic discovery probe.** `test-ff-only.sh:34` computed `TAG_COUNT` via `FF_LIST=1 bash "$RT"` without clearing `FF_ONLY`. Nested under a scoped run it inherited the outer scope and discovered **1** tag. Every other child spawn in that file (`:43,74,88,92,109`) sets `FF_ONLY` explicitly; this one did not. Fixing only defect 1 leaves the nested run at 9/11 — the handoff's stated acceptance is unreachable without both.

**Before → after:**

| Check | Before (`be4c511`) | After (`7c5f78a`) |
|---|---|---|
| `bash hooks/tests/test-ff-only.sh` (standalone) | 10/11 | **11/11** |
| `FF_ONLY=ff-only bash hooks/tests/run-tests.sh` (nested) | 9/11 | **11/11** |
| Full-suite `ff-only` phase | — | **11/11** |
| `FF_ONLY=n` | accepted, `0/0 PASS`, exit 0 | rejected: `ERROR: FF_ONLY unknown tag 'n'`, exit 2 |
| `FF_LIST` tag count | 34 | 33 |

Diff: 2 changed lines across `hooks/tests/run-tests.sh` and `hooks/tests/test-ff-only.sh`, plus a manifest restamp. One tripwire comment added (FR-22).

---

## 9. Gate satisfaction

| Gate item (`verification-gate.md`) | Required | Actual | Pass? |
|---|---|---|---|
| Every AC has evidence | AC1–AC28 | 28/28 evidenced; **28 PASS** | ✓ |
| Every task commit cites `T<n>` | all | 20/20 (+1 `flow(fix):` prefix, exempt) | ✓ |
| No task bundled two slices | one commit per T# | confirmed (T22/T23/T24 each one commit) | ✓ |
| A2 **3rd-amendment** ceilings + ≤42,200 total | yes | 41,321 (879 headroom) | ✓ |
| A3 prohibitions resident | residency test green | 39/39 | ✓ |
| A4 stub kept | yes | `FLOW_RULES.md:71-74` | ✓ |
| A5 amended matrix truthful | yes | AC11, 10 carriers | ✓ |
| A6 both caps | yes | AC12 | ✓ |
| A8 verb-anchored + canonicalized, label-don't-delete | yes | AC25/AC26, 0 dismissals | ✓ |
| A9 staged-then-mint order | yes | T2/T8 digests recorded; **T23 digest `cffed9f0b6aa` recorded in the commit body**; T4 id missing (F1) | ~ |
| Budget literal consistent everywhere | 42,200 in every live carrier | `test-budget-literals.sh` 6/6; 4 carriers say 42,200; `red-stale-literal-detected` green | ✓ |
| Mirror + manifest drift zero | yes | 0 drift; 121/121 match | ✓ |
| Preflight clean | 0 errors | 0 errors / 0 warnings | ✓ |
| **Full suite green** | **0 FAIL** | **619/619 — 0 FAIL, 0 INCONCLUSIVE** | **✓** |
| Spec DRAFT→DONE in the FR-14 docs commit | at deploy | not started (T20) | n/a |

## 9b. Findings (non-blocking)

| # | Finding |
|---|---|
| F1 | T4's bootstrap approval id is not recorded in its commit body (carried from the T11 report; the artifact was minted and consumed, so it is unrecoverable now). Ledger gap, not a rail breach. |
| F2 | `flow-skills/role-discipline/references/shared-protocols.md` is **21,233 bytes** — 2.3× the largest role reference, and outside the AC1 ceiling set, which measures only `<role>.md` files. A session that reads a protocol body pays it on top of the 41,321 floor. Correct per AC1 as written; worth an A2 note before the release note claims "47% cut" unqualified (A2's 3rd amendment now says "re-tiered, not deleted" — carry that wording). |
| F3 | `hooks/local/token-waste-audit.py` is **792/800** lines (FR-25) — 8 lines of headroom after T16/T17. The next change to that file likely needs a seam extraction. |
| F4 | The rule-inventory `resident|lazy` column is not independently load-bearing for detection (the path column catches both T14 red controls first). Detection is correct; the column is defensive redundancy. |
| F5 | **RESOLVED** by the A2 3rd amendment (T22). Headroom is now 333 B (`role-discipline`) and 374 B (`FLOW_RULES.md`), 879 B on the total. Both coupled repairs landed. |
| F6 | The A2 3rd amendment **half-landed in prose** — `spec.md` and the `decisions.md` amendment table carried 42,200, while A2's own headline, the AC1 gate row, and two `tasks.md` rows still said 40,700. `test-budget-literals.sh` (T18, MAJOR 9) caught it the instant the enforced ceilings moved — the guard works, but the third amendment reproduced the exact failure mode the second one taught. **Suggested standing rule:** an A2 amendment is not done until `test-budget-literals.sh` is green in the same pass. |
| F7 | `cli-flow-recovery` has grown 199s → 327s (**+64%**) across this one ticket, and it is now 25% of total suite wall-clock (327s of 1298s). The cost driver is that it copies the whole skill tree per scenario. Not a defect; worth a backlog ticket before the next skill-heavy ticket pushes it past 480s too. |
| F8 | The AC2 rule-inventory baseline is now **stale by 2 rows** against `a2214b3` (D5). Until the PO rules, the "diff is EMPTY" rail cannot be satisfied literally by any future task — the next implementer will hit the same wall. |

---

## 10. Operator-side actions still pending

| Action | Owner | Why pending |
|---|---|---|
| **Rule on D5** — re-baseline `rule-inventory-baseline.txt` at `a2214b3`, or accept the annotated 2-row delta as AC2 evidence | PO | T23 was scoped to reword an FR statement; the baseline was deliberately not edited. Blocks nothing mechanically, but the "diff EMPTY" rail is unsatisfiable until ruled (F8) |
| **Confirm D4** — T22's budget-literal sync touched `decisions.md` / `tasks.md` / `verification-gate.md` | PO | Transcription of the PO's own 3rd amendment, not a redirection; flagged because IM.2 governs `decisions.md` |
| Decide the `ROADMAP.md` / `docs/tmp/handoff.md` uncommitted state (D1) | PO | Pre-existing at `be4c511`; belongs to T20 release bookkeeping |
| Commit the untracked `docs/specs/token-floor-remediation/` artifacts | PO → T20 | The whole spec dir (spec/decisions/tasks/gate/baseline/this report) is untracked at `a2214b3`; T20's FR-14 docs commit is where it lands. Consequence: **git history is not yet the audit trail for this file** — the superseded T19 body is not recoverable |
| T20 release + deploy | PO → Deploy phase | Unblocked by this verdict; needs a deploy handoff (FR-05 / IM.1) |

---

## 11. For operator: paste this in PO chat

````
T19 gate RE-RUN for token-floor-remediation. AI Developer halted at the gate per FR-05 / IM.8. No deploy, no tag, no push.

VERDICT: PASS — 28 of 28 acceptance criteria PASS. Full unscoped suite 619/619, exit 0, zero FAIL and zero INCONCLUSIVE. T20 is unblocked.

The three failures from the last run are repaired, one commit each:

1. AC14 — T22 (2e8d6aa). Restored the named "### Write primitive — Edit is the default, Write is for structure changes" subsection into the canonical role-discipline skill, carrying T2's Edit-vs-Write rule with the case table left lazy. test-supersede-primitive is now 21/21. Same commit landed your 3rd A2 amendment in the enforcing gate (role-discipline 14,500 / FLOW_RULES 11,500 / total 42,200).

2. AC28 — T23 (3cd06e7). Every "retry until it starts" now carries the 3-attempt / 5-minute envelope or points at it. Grep across flow-skills, both mirror trees, FLOW_RULES, hooks, templates, workflows, policies and the problem catalog returns nothing. I also fixed 5 occurrences beyond the 5 tasks.md named — the problem-catalog entry and the msys roadmap stated the same unbounded protocol.

3. AC22 — T24 (a2214b3). cli-flow-recovery was never failing; it was exceeding a deadline that no longer fits the repo this ticket grew. I did NOT just raise the number and walk away: I ran it to completion twice and recorded it — 304s direct with 31/31 assertions and exit 0, 310s through the harness, 327s in the full gate suite. New bound 480s = 47% headroom, deliberately above the measured edge, since 240s WAS the measured edge and one ticket's growth crossed it.

Boot floor now 41,321 bytes against the 42,200 ceiling — a 47.1% cut from the measured 78,148-byte starting floor, with 879 bytes of headroom instead of the 5 and 6 bytes that blocked both repairs last time. Preflight 0/0, mirrors 0 drift, manifest 121/121, module-size clean, health check HEALTHY, CLI/Flow conflicts none.

TWO THINGS NEED YOUR RULING BEFORE T20 — neither blocks the verdict:

A. The rule-inventory diff against the baseline is NON-EMPTY, by design. T23's own task spec told me to reword the FR-27 rule statement in FLOW_RULES.md, and rewording a rule necessarily moves its inventory row. The diff is 2 rows CHANGED, 0 removed, row count still 170, no residency flips — so zero rule loss, which is what AC2 exists to catch. I did NOT edit the baseline; that is forbidden and would have hidden it. Your call: re-baseline at a2214b3, or accept the annotated 2-row delta as the AC2 evidence. Until you rule, the "diff must be EMPTY" rail is unsatisfiable for the next task too.

B. Your 3rd A2 amendment half-landed in prose: spec.md and the decisions.md amendment table said 42,200, but A2's own headline, the gate's AC1 row and two tasks.md rows still said 40,700 — and test-budget-literals.sh (which T18 built for exactly this) went red the moment the ceilings moved. I synced them: live statements replaced, records of the 1st/2nd amendments annotated "since raised". No decision semantics changed — the numbers are transcribed from your own 3rd-amendment table. Flagging it because IM.2 governs decisions.md and I'd rather you confirm than assume.

Also worth knowing: the spec directory (spec/decisions/tasks/gate/baseline/this report) is still UNTRACKED in git. T20's FR-14 docs commit is where it lands — until then git history is not the audit trail for the gate report, so the superseded body is genuinely gone, not recoverable.

Eight findings in § 9b. F5 is now resolved. The new ones: F6 (an A2 amendment isn't done until test-budget-literals is green in the same pass), F7 (cli-flow-recovery grew +64% in one ticket and is now 25% of suite wall-clock — worth a backlog ticket), F8 (baseline staleness, see A above).

Full gate report: docs/specs/token-floor-remediation/gate-report.md

PO: please follow Operator Relay Protocol — brief me in Mode A, recommend next steps with #1 marked, then give me the verbatim prompt to paste back.
````

---

📍 Phase: Implement (gate reached)
🎯 Ticket: `token-floor-remediation`
✅ Completed: T1–T10, T13–T18, T21–T24 (20 task commits) · T19 gate re-run, verdict PASS 28/28
⏭️ Next: PO rules on D5 (re-baseline vs accept) and confirms D4, then drafts the T20 release/deploy handoff
