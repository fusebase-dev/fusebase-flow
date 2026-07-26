# Verification gate — token-floor-remediation

**Spec:** spec.md · **Tasks:** tasks.md · **Decisions:** A1–A10 LOCKED (A2 twice-amended; A3/A5/A8 extended in the 2026-07-26 correction round)
**Gate owner:** AI Developer runs it and halts; PO reviews. No deploy before a PASS verdict.

## Acceptance-criterion → task mapping

| AC | Task | Evidence required in the gate report |
|---|---|---|
| AC1 boot floor: per-artifact ceilings + ≤42,200-byte total (A2 thrice-amended — T7, correction round, T19-gate) | T6,T7,T8,T13,T18,T22 | `bash hooks/tests/test-boot-size.sh` output showing each 3rd-amendment per-artifact ceiling + the measured total |
| AC2 zero rule loss + residency (amended, T14) | T5,T6,T7,T8,T14 | `diff <(bash hooks/local/rule-inventory.sh) docs/specs/token-floor-remediation/rule-inventory-baseline.txt` → empty, plus the deliberate-removal control **and** both T14 red controls (resident→lazy move FAILS; cross-role don't-list move FAILS); rows show `ID + text + source path + resident\|lazy` |
| AC3 prohibitions resident | T6,T7,T8 | grep proof that each of the 5 protocol stubs + the FR-24 digest are in the canonical `SKILL.md`, not only in `references/` |
| AC4 anchors resolve | T7 | grep for the 6 `§` anchor headings in canonical files |
| AC5 missing-reference detection | T5,T8 | RED/GREEN: delete a required reference → test FAILS; restore → PASSES; `test-rule-inventory.sh` RED/GREEN (rule-row deletion detected, Enforcement reword ignored) |
| AC6 history content-equivalent except a normalized final newline (amended, MINOR 14) | T4,T18 | `diff` of extracted body vs the pre-change `FLOW_RULES.md:135-611` — empty modulo one final LF; gate test asserts that exact contract |
| AC7 stub keeps sweep anchor | T4 | `bash hooks/local/sync-version-strings.sh --dry-run` (or equivalent) still stops at the stub; `test-newline-preserve.sh` green |
| AC8 distribution/publication | T4 | CI allowlist diff · `PUBLISHING.md` diff · `CONTENT_FILES` diff · protected-paths + ownership diff |
| AC9 sync-allowlist classification | T4 | `bash hooks/tests/test-sync-allowlist.sh` green with the new file classified as dated history |
| AC10 frontmatter-safe placement | T3 | `head -c 3` of both skills = `---`; preflight frontmatter check green |
| AC11 per-surface matrix correct (amended, T15 — descriptions injected, bodies not) | T3,T15 | table in the gate report: surface → what is injected (descriptions vs body) → file:line asserting it; fresh-session proof for any eager-body claim; test assertion that no surface row claims eager body loading unproven |
| AC12 return cap (lines+chars) | T1 | contract text quoted from all 3 carriers |
| AC13 gate/deploy exempt | T1 | quoted exemption sentence |
| AC14 supersede both dimensions | T2 | quoted text from `FLOW_RULES.md` FR-18, the `role-discipline` resident stub, `references/shared-protocols.md`, `handoff/SKILL.md`, and `token-economy` TE-06 — verify no residual contradiction across all five |
| AC15 conjunctive tail rule | T9 | fixture test: size-differs-only → **retained**; full conjunction → auto-classified |
| AC16 triple labeled not dismissed | T9 | fixture test: 3 non-probe runs → retained with label; 3 probe-shaped → dismissed with label |
| AC17 visible evidence | T9 | sample report lines showing rule + evidence |
| AC18 separate dismissal section | T9 | sample report section headers + counts |
| AC19 three terminal states | T9 | three runs: with candidates · all-auto-classified · no-transcripts |
| AC20 mirror drift zero | all | `bash hooks/local/preflight.sh` mirror section clean |
| AC21 command/overlay parity | T2,T3,T9 | preflight parity section clean |
| AC22 preflight + suite green | all | full command output |
| AC23 hook manifest stamped | T1,T2,T4,T5,T8,T9,T13,T14,T16,T17,T18 | `bash hooks/local/verify-hook-manifest.sh` green |
| AC24 prohibition residency (T13) | T13 | `bash hooks/tests/test-prohibition-residency.sh` green + red-arm proof (planted lazy normative marker → FAIL); grep proof that B3–B8/B11–B12 normative clauses and the Mode-A width/alignment obligation are resident |
| AC25 verb-anchored probe matching (T16) | T16 | fixture runs: `echo status` ×3 and `deploy --message status` ×3 → **retained-live**; probe + extra mutating commands → retained-live; documented probe under normalized equality → dismissed with label |
| AC26 path canonicalization (T16) | T16 | path-alias fixture (`C:/Repo/a.txt` vs `c:\repo\a.txt`): intervening write detected as contradictory event → candidate retained |
| AC27 non-vacuous test arms (T17) | T17 | exact live row + evidence string asserted for fixtures 02–05, 07, 08 with per-fixture mutation controls failing under unsafe classifiers; `test-sync-allowlist.sh` omission arm runs the production missing-set calculation and reports `FLOW_RULES.md` missing |
| AC28 bounded retry exception (T17) | T17 | quoted contract from all three carriers: max attempts + max wall-time + labeled backoff + successor-or-blocked transition; no residual contradiction with `token-economy:33,36` |

## Required gate-report fields

Per `templates/gate-report.md`. Additionally, per task: commit SHA, files touched, approval artifact id (T1/T2/T4/T5/T8/T9/T13/T14/T15/T16/T17/T18), and the AC evidence rows above.

## Lint / typecheck / test commands

```bash
bash hooks/local/preflight.sh                     # structural: frontmatter, mirrors, overlay/command parity, policy keys
bash hooks/tests/run-tests.sh                     # full hook/test suite
bash hooks/local/mirror-skills.sh                 # after any flow-skills/ edit; expect zero drift on re-run
bash hooks/local/mirror-agents.sh                 # only if agents/ changed
bash hooks/local/check-module-size.sh --all       # FR-25 ratchet
bash hooks/local/verify-hook-manifest.sh          # hook-layer integrity
bash hooks/local/check-cli-flow-conflicts.sh      # CLI/Flow ownership
bash hooks/local/fusebase-flow-health-check.sh    # end-to-end read-only verdict
git status --short                                # must be clean at each task boundary
```

**Windows/MSYS note:** the full suite is slow. While developing use `FF_ONLY=<tag> bash hooks/tests/run-tests.sh`; run the full suite once at the gate. Never launch it bare — bound it (FR-27).

## Worker-undisturbed paths (this ticket)

None configured (`policies/protected-paths.yml: worker_undisturbed` = none). N/A — record as `N/A` in the gate report, do not fabricate a diff check.

## Smoke prompts (post-deploy)

Smoke = prove the operator-visible outcome on the released surface, with a ground-truth diagnostic and a falsification check (`smoke-testing`).

### S1: A fresh session's boot floor actually dropped

- **Operator-visible outcome:** a new session on a clean clone of the released tag loads the mandatory floor; each AC1 per-artifact ceiling holds and the measured byte total (`wc -c`) is ≤42,200 (A2 3rd amendment).
- **Ground truth:** `bash hooks/tests/test-boot-size.sh` on the clean clone, printing the per-artifact breakdown.
- **Falsification:** re-run against the previous tag — it must FAIL the budget. A test that passes on both versions is measuring nothing.
- **Evidence:** both outputs pasted into the deploy report.

### S2: No rule was lost in the compression

- **Operator-visible outcome:** every FR-01..FR-27 statement and every role don't-list row is still reachable from a session that loads only the resident core plus its own role reference.
- **Ground truth:** `bash hooks/local/rule-inventory.sh` diff (pre-tag vs post-tag) showing zero removed statements.
- **Falsification:** confirm the diff tool reports a removal when one is deliberately introduced in a scratch copy.
- **Evidence:** diff output + the deliberate-removal control.

### S3: The Amendment log is unreachable by accident

- **Operator-visible outcome:** reading `FLOW_RULES.md` end-to-end no longer pulls dated history; the stub points to `FLOW_RULES_HISTORY.md`.
- **Ground truth:** `wc -c FLOW_RULES.md` on the released tag ≈ operative size; history file holds the log.
- **Falsification:** confirm `FLOW_RULES_HISTORY.md` is actually distributed — install into a scratch dir via the documented path and assert the file arrives (guards the `CONTENT_FILES` omission risk R2).
- **Evidence:** both file sizes + the scratch-install listing.

### S4: The audit tool labels rather than hides

- **Operator-visible outcome:** running `/token-waste-audit` (or the parser directly) on the synthetic fixtures produces a report where every auto-classification names its rule and evidence, dismissals are counted separately, and the three terminal states are distinguishable.
- **Ground truth:** the three fixture runs from AC19.
- **Falsification:** a fixture with a size-differs-only re-read must still appear as a **live candidate** — proving the tool did not over-dismiss.
- **Evidence:** the three report outputs.

## Probes (post-deploy)

| # | Probe | Pass condition |
|---|---|---|
| P1 | `bash hooks/local/fusebase-flow-health-check.sh` on the released tag | Verdict `HEALTHY`; mirror counts match; hook-layer integrity matches the new version |
| P2 | GitHub Actions run for the `v4.6.0` tag | verify + release workflows green (public-surface allowlist admits `FLOW_RULES_HISTORY.md`) |
| P3 | `bash hooks/local/upgrade.sh --dry-run` from a consumer clone | lists `FLOW_RULES_HISTORY.md` among content files |

## Manifest version bump

`VERSION` → `4.6.0`; `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, README badge synced via `bash hooks/local/sync-version-strings.sh`. Parity is checked by preflight.

## Rollback procedure

Single-commit-per-task means per-task revert. Full rollback: `git revert` the task commits in reverse order (T20→T1; within the correction round, reverse of T15→T13→T14→T16→T17→T18), then `bash hooks/local/mirror-skills.sh` and `bash hooks/local/preflight.sh` to restore mirror/manifest consistency. The released tag stays; a corrective release supersedes it. Never force-push.

## Cross-artifact consistency check (mandatory before approving deploy)

| Check | How |
|---|---|
| Every AC has evidence in the gate report | walk the AC table above |
| Every task commit cites its `T<n>` | `git log --oneline` for the ticket range |
| No task bundled two slices | one commit per T# |
| Decisions honored | A2 3rd-amendment ceilings + ≤42,200-byte total · A3 prohibitions resident (residency test green) · A4 stub kept · A5 amended matrix truthful · A6 both caps · A8 verb-anchored + canonicalized, label-don't-delete · A9 staged-then-mint order |
| Budget literal consistent everywhere | T18 cross-artifact literal-budget assertion green; no stale pre-3rd-amendment total survives in any live carrier — every live budget statement reads 42,200 |
| Protected-path edits each carry an approval | approval artifact id per T1/T2/T4/T5/T8/T9/T13/T14/T15/T16/T17/T18 |
| Mirror + manifest drift zero | preflight output |
| Spec status flipped DRAFT→DONE in the single FR-14 docs commit | `git show` of that commit |
