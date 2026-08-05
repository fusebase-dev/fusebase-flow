# Implement handoff — v3.30.6 gate wall-time optimization (F2 FF_ONLY, F4 preflight batch, F5 micro-cuts, F3 adaptive poll)

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.5. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-25, FR-27 (bounded-run/liveness — F3 touches the hottest safety code), FR-22. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; STOP at gate (do NOT bump VERSION/push/tag/deploy). If you hit a server-side rate-limit/session-limit mid-task, STOP and report exactly where you are (committed vs WIP) — do not loop.** FOUR coherent commits (one per optimization), stacked on HEAD `d43f2f3` (v3.30.5). This is a PERFORMANCE release — the OVERRIDING constraint is: **NO optimization may reduce test coverage or weaken any fail-closed / bounded-run (FR-27) / security behavior.** A speedup that lets a hang look like a pass, or scopes a security suite away by default, is a REGRESSION, not a win.

## Mandatory reads (FIRST, in full)
1. `docs/tmp/handoff/2026-07-03-v3306-fable-optimization-spec.md` — the Fable analysis spec (findings F2/F4/F5/F3 with file:line targets, designs, non-goals, REJECT list, and the T1–T6 test plan). This is your source of truth.
2. `hooks/tests/run-tests.sh` (whole file — the 20 phases + summary/report + EXIT-trap reaper) · `hooks/local/lib/run-with-timeout.sh` (the bounded-run engine — `ffhc_msys_wait_reap`, `_ffhc_reap`, rc normalization, the strict PASS classifiers :536-564) · `hooks/local/preflight.sh` (:78-118 mirror hashing) · a skim of `test-liveness-bounded-run.sh` + `test-msys-tree-cleanup.sh` (the F3 regression net).

## Scope — FOUR commits in this order (ranked by ROI/safety). Implement F2 FIRST so you can scope the LATER gates with it.

### Commit 1 — F2: `FF_ONLY` scoped gates (`hooks/tests/run-tests.sh`)
Per spec §2. Opt-in `FF_ONLY="tag1,tag2"`; UNSET ⇒ byte-identical to today. Scoped ⇒ loud banner + `SKIP (FF_ONLY): <tag>` per skipped phase + summary `[run-tests] N/M PASS (SCOPED FF_ONLY=… — subset, not a full gate)` + results to `state/audit/hook-test-results-scoped.md` (NEVER touches `hook-test-results.md`). Unknown/empty tag ⇒ exit 2. The scoped summary MUST fail the anchored `^\[run-tests\] N/N PASS$` regex in `ffhc_run_tests_pass_ok`/`ffhc_count_pass_lines` (do NOT loosen those). Add `FF_LIST=1` (print 20 tags RUN/SKIP, exit 0). 20 canonical tags per spec. Also add the **process rule** durably — PREFER a non-protected home (a `## Gate scoping` note in the run-tests.sh header comment + the `validation-and-qa` skill or `docs/`), NOT FLOW_RULES.md, to avoid a protected-path edit; if you judge FLOW_RULES.md the only correct home, mint ONE sanctioned single-use bootstrap approval for it. Rule text: "FF_ONLY is implement-loop only; the FINAL pre-commit/pre-deploy gate MUST be a full unscoped run; a gate report may only cite hook-test-results.md."
Gate this commit with T1 + T2 (see below). **After this commit lands, use `FF_ONLY` to scope the gates for commits 2–4** (e.g. `FF_ONLY=fixtures,ff-only,liveness` for the reap-loop work), then run ONE full unscoped gate at the very end (T6).

### Commit 2 — F4: preflight batch hashing (`hooks/local/preflight.sh:78-118`)
Per spec §F4. One `sha256sum` invocation per root (args list) writing to tempfiles via FILE REDIRECTS; keep the `shasum -a 256` per-file fallback when sha256sum is absent; join on relative path in one awk pass; emit IDENTICAL warn strings in canonical-list order. Same file set + comparison + warn/err text. Gate with T4.

### Commit 3 — F5: spawn micro-cuts (`run-with-timeout.sh:459`, `run-tests.sh:75-90,117-118`)
Per spec §F5: (a) `$(<"$_tf")` builtin file read (regular file, not pipe); (b) fixture meta via builtin `read` from `<<<`; (c) one pre-pass python TSV of all fixture metadata (file-redirect) read with builtin `read`. Plumbing only — handler runs/fixtures/assertions/bounded-wrapping unchanged. Gate with T5.

### Commit 4 — F3: adaptive poll (`run-with-timeout.sh` `ffhc_msys_wait_reap` loop only) — HIGHEST CARE, DO LAST
Per spec §F3. Add `_ffhc_nap` (Tier1 FIFO `read -t` PROBED at init — accept only if a 0.05s nap blocks ≥0.04s; Tier2 external sleep). Rewrite the LOOP ONLY: exponential nap ladder 0.05→0.1→0.25→0.5→1; `waited` from **EPOCHREALTIME integer-microseconds (NOT $SECONDS** — $SECONDS can reap EARLY before GNU timeout's TERM = a behavior change). PRESERVE VERBATIM: `_ffhc_reap`, trigger-file touch, taskkill PID-reuse re-verify, `wait "$bpid"`, `reaped=1 && !ffhc_timed_out ⇒ rc=124` (:171-180), cap=secs+grace+2. FALLBACK (EPOCHREALTIME unavailable OR nap-probe fails) ⇒ else-branch is LITERALLY today's `sleep 1; waited=$((waited+1))`. Gate with T3 (the full lib-behavior suite matrix + the new no-early-reap asserts).

## Test plan — implement ALL of T1–T6 (spec §6). Coverage-preservation is the point.
- **T1** FF_ONLY default-identity (THE coverage proof): FF_LIST unset == canonical 20; pre/post diff FF_ONLY-unset ⇒ identical `starting <label>` sequence + identical final `N/N PASS` N + same hook-test-results.md rows/cols; unscoped summary byte-identical.
- **T2** new `test-ff-only.sh` (tag `ff-only`, wired into run-tests.sh — this ADDS a 21st tag; update the canonical list to 21 and T1 accordingly): scoped=1-marker/19-SKIP/scoped-summary + `ffhc_count_pass_lines`⇒0; bogus⇒rc2; `" , "`⇒rc2; writes scoped file, leaves full file untouched; scoped-with-injected-failure exits non-zero.
- **T3** adaptive poll: full green matrix (liveness-bounded-run, msys-tree-cleanup incl. job-object/sibling/PID-reuse, ws5-upgrade-bounded, health-check-timeout) UNMODIFIED; NEW: fast-child <2s wall; hang-child (sleep 30 bounded at 2) timeout rc in ≥2s and ≤2+grace+2s (NO early reap — deadline is a FLOOR); FFHC_NAP_OK off ⇒ still passes; mkfifo-absent stub ⇒ FFHC_NAP_OK!=1 + behavior==v3.30.5.
- **T4** preflight byte-diff (warn/err canonical-sorted) vs v3.30.5 on clean/deleted-mirror/drifted-mirror/sha256sum-absent ⇒ identical text+exit all four; wall <60s.
- **T5** fixture rows + report table byte-identical pre/post (green + broken-fixture); msys-tree-cleanup capture scenarios still assert FFHC_LAST_OUT both modes.
- **T6** one full UNSCOPED gate at the end: test count ≥ pre-change (≥ ~230 incl. the new ff-only suite), 0 new INCONCLUSIVE, record wall-time delta.

## DO-NOT-TOUCH / REJECT (spec §5 — enforce)
rc contract 124/137, ffhc_timed_out, -k grace; _ffhc_tempfile_capture launch semantics (T17/T18 stdin modes, winpid capture, mktemp-fail⇒125); taskkill strict scoping + PID-reuse; deadline-reap⇒124; EXIT-trap reaper; strict PASS classifiers (:536-564 — NEVER loosen); INCONCLUSIVE/visible-skip semantics; `hooks/git/pre-commit` in ENTIRETY (the v3.30.5 fail-closed FR-07/FR-12 chain — do NOT touch it, do NOT add any test-mode skip knob); health-check verdict precedence. REJECT: any pre-commit §2/§3 skip knob; auto-skip hook-tests on "recent green"; changing any FFHC_*/FF_* timeout budget as a speedup; removing any suite/scenario/RED-proof/hang-child; the F6 load-bearing "duplicates" (msys-tree sleep-20 contexts, triple refresh-overlays, RED baselines) — KEEP.

## FR-22 / FR-25
FR-22: tripwire+pointer comments only; emit `comment-policy review: applied (FR-22)`. FR-25: keep modules < 800-line ceiling (run-tests.sh + run-with-timeout.sh are large — check `check-module-size.sh --all` stays exit 0 after edits; if an edit would breach, factor minimally, do NOT bloat).

## Per-commit pre-attestation (each of the 4)
```
☐ preflight (green) ☐ ONE coherent commit ☐ no TODO/FIXME/WIP ☐ FR-22 ☐ FR-25 <ceiling ☐ scoped gate GREEN (T# for this commit) ☐ do-not-touch respected ☐ default/unset path byte-identical where claimed ☐ no --no-verify
```

## Gate (STOP, report, HALT) — after all 4 commits
Run the FULL UNSCOPED gate (T6) once: `preflight.sh` green · `bash -n`/`py_compile` changed files · the FULL `run-tests.sh` (unscoped) 0-FAIL with test count ≥ pre-change and 0 NEW INCONCLUSIVE (pre-raise FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900; this is the one place you DO run the full suite — the whole point is to prove coverage is preserved) · `check-module-size.sh --all` exit 0 · SINGLE `mirror-skills.sh --check` 0 drift · FR-27 no-runaways. Plus per-optimization evidence T1–T5. Emit FR-22 marker; produce the gate report; HALT (do NOT deploy — a separate deploy handoff follows).

## Return
Gate report: the 4 commit SHAs (F2/F4/F5/F3) + one-line each; T1–T6 evidence (esp. T1 default-identity byte-match, T2 scoped-fail-closed `ffhc_count_pass_lines⇒0`, T3 no-early-reap floor + fallback, T4 preflight byte-identical + <60s, T6 full-gate test-count ≥ pre-change + wall-time delta); confirmation NO coverage/fail-closed/security regression; the FF_ONLY process-rule home; do-not-touch respected; module-size + mirror clean. Do NOT push/tag/deploy.
