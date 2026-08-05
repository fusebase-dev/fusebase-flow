# Implement handoff — v3.30.6 review corrections (F5 TSV parse, F3 cap-assert, fixture-leak) — one commit

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.5. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-10 (reproduce-before-fix), FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; STOP at gate; do NOT bump VERSION/push/tag/deploy.** ONE coherent correction commit stacked on HEAD `566085f` (v3.30.6 F3). These are TEST/plumbing fixes from the adversarial review — **none touch F3's production reap-loop code** (both reviewers cleared it: no F3 code regression; the 13 T6 FAILs are host-saturation artifacts, reap-loop scenarios reproduce identically on baseline d43f2f3 AND HEAD 566085f). Do NOT re-touch the F3 loop logic, FF_ONLY, F4, or the pre-commit chain.

## Context — the review findings (BLOCK from Codex + SHIP-WITH-FIXES from the Opus panel)
The v3.30.6 optimizations (F2 FF_ONLY, F4 preflight-batch, F5 micro-cuts, F3 adaptive-poll) are SOUND — verified: FF_ONLY unset byte-identical + scoped fail-closed; F4 byte-identical; F3 deadline-floor preserved, no early reap, true-124, timing baseline-equivalent; pre-commit UNTOUCHED. Three fixable issues remain before deploy.

## Scope — ONE commit, three fixes (plus remove the leaked fixture)

### Fix 1 — F5 TSV empty-field collapse (`hooks/tests/run-tests.sh:~195`)
`IFS=$'\t' read -r test_name handler expected_decision expected_rule_id expected_rule_contains` collapses an EMPTY middle TSV field because tab is an IFS-whitespace char. For fixture 10 (`_expected_rule_id` empty, `_expected_rule_id_contains: FR-12`) this SHIFTS fields left → parses `expected_rule_id=FR-12 / contains=empty`, silently converting the authored SUBSTRING assertion into EXACT-equality (baseline python-print+sed correctly parsed `rule_id=empty / contains=FR-12`). Currently benign (handler emits rule_id exactly 'FR-12' so fixture 10 still PASSes; it's stricter, cannot mask a failure) — but a real divergence from the F5 "identical per-fixture rows/assertion semantics" invariant. FIX: preserve empty fields — e.g. `mapfile -td $'\t' _f < <(printf '%s' "$meta")` then index the array, or split manually, or a sentinel — so an empty `_expected_rule_id` no longer shifts `_expected_rule_id_contains` left. Verify fixture 10 now parses rule_id=empty / contains=FR-12 (matching baseline) and the substring assertion is honored.

### Fix 2 — F3 cap-bound assert too loose (`hooks/tests/test-liveness-bounded-run.sh:~188`)
The F3 no-early-reap assert accepts an over-cap hang as PASS whenever rc is 124/137 AND wall ≥ deadline — it checks the FLOOR (never reap EARLY) but NOT the CEILING. A late-past-cap reap (the exact bounded-run regression this release must be able to catch) would wrongly PASS. FIX: ADD an upper-bound check so the assert also verifies the reap happened within a bounded time — but calibrate the tolerance so it does NOT flake under host saturation (the legitimate host artifact is a reap a few seconds late; the REGRESSION to catch is "child never killed / reap tens of seconds late"). Keep the strict FLOOR assert (wall ≥ deadline — the critical safety property). For the ceiling, assert wall ≤ a GENEROUS bound (e.g. `secs + grace + a documented host-jitter margin`, sized to catch a gross late-reap / never-killed regression while tolerating the measured ~8s-late saturation jitter — pick a margin like cap+30s or 3×cap and DOCUMENT why). Reproduce-before-fix (FR-10): confirm the strengthened assert PASSES on 566085f (F3 reaps within the bound) and would FAIL a simulated never-killed child.

### Fix 3 — leaked injected-fail fixture (`hooks/tests/test-ff-only.sh:~98`)
The T2 injected-failing-fixture assert writes `hooks/tests/fixtures/zz-ff-only-injected-fail.json` with NO cleanup trap → it persists untracked and POISONS future full-gate fixture runs (the fixture loop picks it up and FAILs). FIX: either write the injected fixture to an ISOLATED temp dir (preferred), or add a `trap 'rm -f hooks/tests/fixtures/zz-ff-only-injected-fail.json' EXIT` (and remove it inline after the assert). ALSO: **remove the currently-leaked `hooks/tests/fixtures/zz-ff-only-injected-fail.json` from the working tree NOW** (it is present + untracked; delete it before gating so the fixture phase is clean).

## Do NOT
- Do NOT touch F3's `ffhc_msys_wait_reap` production loop, `run-with-timeout.sh` classifiers (:591-646), FF_ONLY logic, F4 preflight logic, or `hooks/git/pre-commit`. These are cleared. Only the TEST files + the run-tests.sh:195 parse line change.
- Do NOT weaken any assert to make a FAIL pass. Fix 2 STRENGTHENS coverage (adds the ceiling); Fix 1 restores baseline parse semantics; Fix 3 is hygiene.
- Do NOT bump VERSION/push/tag. Do NOT `--no-verify`.

## Tests / gate (SCOPED — use FF_ONLY now that it exists)
- Fix 1: fixture phase (`FF_ONLY=fixtures`) — fixture 10 PASSes with the corrected parse; all 16 fixture rows correct; add/keep an assertion that an empty `_expected_rule_id` + non-empty `_contains` is parsed as substring (not exact).
- Fix 2: `FF_ONLY=liveness` (test-liveness-bounded-run) GREEN with the strengthened cap assert; document the tolerance; confirm floor + ceiling both checked.
- Fix 3: `FF_ONLY=ff-only` + `FF_ONLY=fixtures` GREEN, and confirm NO `zz-ff-only-injected-fail.json` remains after the run (`git status` clean of it).
- Then a FINAL check: `git status` shows only the intended edits (run-tests.sh, test-liveness-bounded-run.sh, test-ff-only.sh) + NO leaked fixture; `check-module-size.sh --all` exit 0; `bash -n` the 3 files; preflight green; SINGLE `mirror-skills.sh --check` 0 drift. You do NOT need a full unscoped gate for these test-only fixes — the scoped gates for the 3 affected suites + the clean git status are sufficient; note that the full-gate FAIL set is the pre-existing host-saturation artifact class (unchanged by these fixes). Emit FR-22 marker; gate report; HALT.

## Per-commit pre-attestation
```
☐ ONE coherent commit  ☐ no TODO/FIXME/WIP  ☐ FR-22  ☐ FR-25 <ceiling  ☐ no --no-verify  ☐ VERSION 3.30.5
☐ Fix1 fixture-10 parses rule_id=empty/contains=FR-12 (substring honored)  ☐ Fix2 ceiling+floor both asserted, tolerance documented, not flaky  ☐ Fix3 isolated/trap + leaked file removed + git clean
☐ F3 loop / FF_ONLY / F4 / pre-commit UNTOUCHED  ☐ scoped gates (fixtures/liveness/ff-only) GREEN  ☐ module-size 0 / mirror 0-drift
```

## Return
Gate report: correction commit SHA + one-line per fix; evidence (fixture-10 corrected parse; the cap-assert floor+ceiling + tolerance rationale + a simulated-never-killed FAIL proof; fixture-leak isolated/trapped + working-tree clean); confirmation F3-loop/FF_ONLY/F4/pre-commit untouched; scoped-gate results; module-size + mirror clean. Note that the pre-existing host-saturation FAIL class is unchanged (these are test/plumbing fixes). Do NOT push/tag/deploy.
