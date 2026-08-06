# Adversarial reviews — 2026-08-05 (Codex gpt-5.6-sol, reasoning effort xhigh)

Persisted because review 3 could not verify review 2's findings: no review artifact existed. A verdict that cannot be re-checked is a claim without evidence.

Condensed to verdict + findings. Full stdout was written to `c:/tmp/codex-{review,c0,m1a}.out` (host-local, not retained).

## Summary

| # | Target | Verdict | Outcome |
|---|---|---|---|
| 1 | Three implemented backlog fixes (`cb0ff8b` `b7d8428` `235f4a3` `0e29ed5` `10b79f7`) | `STOP-AND-ZOOM-OUT` | All reverted (`5f8004f`), 2 carve-outs kept |
| 2 | C0 decision packet (`089789a`) | `WRONG-SEQUENCE` | Not locked |
| 3 | M1A baseline plan + the loop risk itself | `SHIP-SMALL-FIRST` | M1A not started; hard-surface router shipped instead |

Reviews 2 and 3 disagree on the next action (measure vs ship). They converge on: **do not build the 11-trigger classifier, and do not lock C0 as drafted.**

## Review 1 — the three fixes

Verified by hand before acceptance; all held.

| # | Sev | Finding | Verified how |
|---|---|---|---|
| 1 | BLOCKER | `test-health-check-timeout.sh:412` greps `"Approval age warnings (1"`; the heading was renamed → full suite red while a scoped run reported green | Ran the phase: 21/22, exit 1 |
| 2 | BLOCKER | `hook_manifest.py --out`: `Path('/c/tmp/x').is_absolute()` is **False** on Windows Python → writes to `C:\c\tmp\x` while reporting the requested path | Ran it |
| 5 | MAJOR | `deferred_checks` never required to be an array; a JSON object iterates its keys → `{"deferred_checks":{"claude_md_overlay":true}}` is ACCEPTED. The fix did not close the defect it named | Ran the shipped predicate |
| 6 | MAJOR | The behavioural test exercised a *copy* of the extractor, not the shipped lib — a specification test, not a regression test; it missed finding 5 | Read the test |
| 11 | MINOR | The change-note claimed `cb0ff8b` modified `hook_manifest.py`; it modified only `run-tests.sh` | `git show --stat` |

Root-cause findings, not defect findings:

- **`cb0ff8b` was a symptom patch.** The real cost driver is `test-cli-flow-recovery.sh` copying `$PROJECT` **7 times** among 24 `cp -R` calls — **not** skill-tree growth. The copied `flow-skills` tree stayed flat at 49 files / ~441 KB across the 542s→1813s change. The ticket's own stated cause was wrong.
- **No single scalar wall works** once the healthy path is ~30 min: 5400s satisfies FR-27 but wastes an hour on a genuine hang. Correct design is cheap fixtures + a stall deadline + an absolute ceiling.
- **`235f4a3` is maintainer tooling in the default product** — CI already detects the drift. Belongs in the S9 maintainer pack.
- **`0e29ed5`'s security framing is overstated.** Under K3 the artifact author and operator are the same OS principal; this is record-integrity correctness, not an authorization boundary.
- All three were **mis-tiered Lightweight** when FR-21 and draft F05 make these surfaces Full.

## Review 2 — C0

Five BLOCKERs; three are self-contradictions inside the packet, verified directly.

| # | Sev | Finding | Verified how |
|---|---|---|---|
| 1 | BLOCKER | C0 blocks all roadmap work before testing the roadmap's own premise falsifier; no M1 baseline exists | `north-star.md:43-45` |
| 2 | BLOCKER | A5/A6 are directions, not contracts — no fields, schema version, validity rules, reader precedence, or failure semantics | Compared against the six seq-0 names |
| 3 | BLOCKER | "Only the operator may waive" is unenforceable under K3 — recreates the `approval_authors` theatre C0 claims to remove | No identity-bearing carrier exists |
| 4 | BLOCKER | `artifact_v2` called **signed**; nothing signs anything, and the policy says authorship would need "a host-signed event or a key the agent cannot read" | grepped every approval writer/validator: zero signature/HMAC/key code |
| 5 | BLOCKER | A1 (no trigger ⇒ LIGHTWEIGHT, three outcomes) contradicts A8 (`default_lane: full`) | Direct textual read |
| 10 | MAJOR | Roadmap S6 requires artifact-v2 to reject wrong **SHA**; the packet defers HEAD binding as "not required by any seq-0 item" | Roadmap line 14 |
| 12 | MAJOR | The three-revert pre-lock test is circular — all three touch paths written into F05, so it proves membership, not accuracy | Inspected the three commits |
| 14 | MINOR | The packet cited the prior reviewer's "lock C0 first" as lock support — argument from authority | Fair hit; the citation was removed |

Also: the classifier is "the North Star being used to justify a bigger machine." Cheaper alternative named — a **hard-surface router**: a short non-waivable path set, everything else falls through, no declarations, thresholds, overrides or CI recomputation. Add a trigger only after an observed escape.

## Review 3 — M1A, and whether reviewing had become the failure mode

Seven BLOCKERs on the measurement design.

| # | Sev | Finding |
|---|---|---|
| 1 | BLOCKER | No sample frame. "Whatever real projects there are" is not a selection rule; both known consumers are excluded, so it can yield zero data after 14 days |
| 2 | BLOCKER | M1A gates decisions it collects no evidence for (A7 control severity, A9 bounds) — delay without information |
| 3 | BLOCKER | It **cannot measure the known bottleneck**: it records active minutes but not elapsed wait-for-ruling. One decision after a 52h wait scores as ideal |
| 4 | BLOCKER | Artifact cost mis-counted — only new files under `docs/`; inline change-notes, approval artifacts elsewhere, and edits to existing files all count as zero |
| 5 | BLOCKER | `lane_by_final_diff` is circular: judged against a rubric that is itself the thing under evaluation |
| 6 | BLOCKER | The outcome table pre-commits each result to a roadmap build (A5/A6) with no intervention arm to justify it |
| 7 | BLOCKER | M1A records none of A2's three threshold quantities, so finishing it leaves F09 exactly as unsupported |
| 9 | MAJOR | The current lane contract **already** promises one artifact and one go-ahead. The observed defect is enforcement, not the contract |

**The ordinary-user population is not established.** Both known consumers are explicitly atypical; nothing verifies any other repo is an active ordinary consumer. If the count is zero, the roadmap's 75%/30% thresholds and the breaking S5–S9 program cannot be described as user-evidenced. The North Star remains a legitimate product hypothesis; the empirical case for the large rebuild does not currently exist.

## What was actually shipped as a result

`hooks/local/lane-router.sh` + `hooks/tests/test-lane-router.sh` — the hard-surface router review 2 named and review 3 prioritised. Path-only, no declarations, no thresholds, no overrides. Its FULL fixtures are the real changed paths of the three reverted commits.
