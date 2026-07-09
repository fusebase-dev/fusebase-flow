# Tasks — hook-manifest-verify (v3)

One task = one commit (`<type>(scope): T<n> …`, FR-03). Decisions LOCKED in
decisions.md (D1–D15, v3). Each task is independently verifiable; run its
verification before committing. (T9 may produce 0..N commits per D14.)

## Standing rules (apply to every task)

- **R1 (manifest freshness):** any task that touches a covered path (spec § covered
  set) ends with `bash hooks/local/stamp-hook-manifest.sh` + `git add
  audit/hook-layer-manifest.json` in the SAME commit (applies from T2 onward).
- **R2 (FR-07):** NEVER modify `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`,
  `policies/*.yml`, `FLOW_RULES.md`. Tamper tests use uncommitted edits reverted
  immediately (`git checkout -- <file>`) or temp copies.
- **R3 (approval artifact, D15):** T6 edits `.github/workflows/**` (protected,
  ci_cd_config) ⇒ author `state/approvals/protected_path_edit-hook-manifest-ci-<YYYYMMDD>.json`
  (fields per policies/protected-paths.yml § exception_artifact; `paths` lists BOTH
  workflow files — fusebase-flow-verify.yml AND fusebase-flow-release.yml, one
  artifact for the one T6 commit) IMMEDIATELY before
  the T6 commit, and DELETE it IMMEDIATELY after the commit lands (same task step —
  see T6). It is gitignored (`.gitignore:5`), so deletion is a plain `rm <file>`.
- **R4 (liveness, FR-27):** any run expected > 3 min runs backgrounded/bounded —
  never launched bare, never waited on with a foreground sleep. The exact
  launch/poll/deadline protocol for full-suite runs on this box is T9 Steps 1–3;
  bound heavy phases via `FF_PHASE_TIMEOUT` / `FF_CLI_RECOVERY_TIMEOUT`.
- **R5 (module size):** new files stay under the 800-line ceiling; run
  `bash hooks/local/check-module-size.sh --staged` before each commit (pre-commit
  enforces it anyway).
- **R6 (zero-artifact pre-test guard, D15):** from T6 onward, BEFORE every
  `run-tests.sh`, `fusebase-flow-health-check.sh`, or gate invocation run:
  ```bash
  find state/approvals -maxdepth 1 -name 'protected_path_edit-*.json' -print
  ```
  It must print NOTHING. If it prints a path, `rm` that file first (this ticket
  authors exactly one, in T6) — an active artifact makes fixture 07
  (expects deny/FR-07) fail deterministically.

---

## T1 — Pin `.jsonl` to LF (byte-determinism prerequisite, D12)

Files: `.gitattributes`.
Ops: add under the "Config / data formats" block: `*.jsonl     text eol=lf`.
Then `git add --renormalize hooks/tests/fixtures` (expect no content change on this
LF-committed tree — the pin protects Windows checkouts).
Verify:
```bash
git check-attr eol -- hooks/tests/fixtures/18_stop_native_transcript_doneclaim_transcript.jsonl   # → eol: lf
git ls-files --eol hooks/tests/fixtures/ | grep jsonl    # index side i/lf
git status --porcelain                                    # only .gitattributes staged
```
Commit: `fix(repo): T1 pin *.jsonl to LF for hash-stable Windows checkouts`.

## T2 — Manifest lib + stamp/verify scripts + initial committed manifest (D1–D3)

Files (new): `hooks/local/lib/hook_manifest.py` (single module: `collect_assets(root)`
per D2; `sha256_of`; `self_hash(payload)` per D1; **byte-stable stamp** per D1 — no
`generated_at`, fixed key order, `indent=2`, trailing `\n`, `newline="\n"`; CLI
`stamp` / `verify [--json]`, both accepting `--root <dir>` defaulting to
`git rev-parse --show-toplevel`; verify exit codes **0/1/2/4** per D3 — exit 3
reserved-unused; extra-file Scans A+B per D3);
`hooks/local/stamp-hook-manifest.sh`, `hooks/local/verify-hook-manifest.sh` (thin bash
wrappers modeled on stamp-cli-provenance.sh: git-root resolve, python3|python
fallback, invoke the lib; chmod +x). Generated: `audit/hook-layer-manifest.json`.
Verify:
```bash
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/verify-hook-manifest.sh --json   # verdict MATCH, rc 0
# BYTE idempotence (D1 — no "modulo generated_at" allowance):
TMP="${TMPDIR:-/tmp}"
cp audit/hook-layer-manifest.json "$TMP/m1.json"
bash hooks/local/stamp-hook-manifest.sh
cmp audit/hook-layer-manifest.json "$TMP/m1.json" && echo BYTE-STABLE               # identical bytes
grep -c generated_at audit/hook-layer-manifest.json                                 # 0 — schema has no timestamp
# tamper detection (uncommitted, reverted — R2):
printf '\n' >> hooks/shared/git_utils.py
bash hooks/local/verify-hook-manifest.sh; echo "rc=$?"          # rc=1; names hooks/shared/git_utils.py modified
git checkout -- hooks/shared/git_utils.py
# extra-file scans (temp files, deleted after; NOT sitecustomize in the live tree root — Scan B test):
touch hooks/shared/evil_extra.py
bash hooks/local/verify-hook-manifest.sh; echo "rc=$?"          # rc=1; extra hooks/shared/evil_extra.py (Scan A)
rm hooks/shared/evil_extra.py
touch hooks/tests/fixtures/sitecustomize.py
bash hooks/local/verify-hook-manifest.sh; echo "rc=$?"          # rc=1; reason python-startup-file (Scan B, deep path)
rm hooks/tests/fixtures/sitecustomize.py
# self-hash / absent classes:
python3 - <<'PY'
import json,pathlib; p=pathlib.Path("audit/hook-layer-manifest.json"); d=json.loads(p.read_text())
d["manifest_self_sha256"]="0"*64; p.write_text(json.dumps(d,indent=2)+"\n")
PY
bash hooks/local/verify-hook-manifest.sh; echo "rc=$?"          # rc=2 BROKEN
git checkout -- audit/hook-layer-manifest.json 2>/dev/null || bash hooks/local/stamp-hook-manifest.sh
mv audit/hook-layer-manifest.json "$TMP/m.json"; bash hooks/local/verify-hook-manifest.sh; echo "rc=$?"   # rc=4 ABSENT (NOT 3 — SF8)
mv "$TMP/m.json" audit/hook-layer-manifest.json
```
Commit: `feat(manifest): T2 hook-layer manifest lib + stamp/verify + committed manifest`.

## T3 — Single-process runner + rewire fixture phase (D6, D7)

Files: NEW `hooks/tests/run_hook_tests.py` (per D6: per-fixture reset_cache, stdin
TextIOWrapper over raw bytes, redirect_stdout, discard stderr, SystemExit capture
with rc normalization None→0 / int→value / other→1, BaseException⇒FAIL, exact
assertion semantics + `_parse-invariant` synthetic row, PASS:/FAIL: line shapes
byte-compatible, exit = fail count; `--compare-subprocess` mode compares the TRIPLE
**(exit_code, decision, rule_id)** per fixture per D6 — in-process rc from the
SystemExit capture, subprocess rc from `proc.returncode`).
EDIT `hooks/tests/run-tests.sh`: replace ONLY the fixture-phase internals (lines
~143–289: TSV pre-pass, per-fixture bounded handler run, JSON parse, bash invariant)
with ONE bounded phase: `run_bounded_phase "fixture handler tests (single-process)"
"$python_bin" "$ROOT/hooks/tests/run_hook_tests.py"` + count `^PASS:`/`^FAIL:` lines
into pass/fail/total/report_rows (run_shell_phase parse pattern). `ff_selected
fixtures` gate + skip note unchanged. ALL OTHER PHASES UNTOUCHED (D7 superset
invariant).
Verify:
```bash
python3 hooks/tests/run_hook_tests.py; echo "rc=$?"                      # 22 PASS lines (21 fixtures + _parse-invariant), rc=0
python3 hooks/tests/run_hook_tests.py --compare-subprocess; echo "rc=$?" # 21/21 identical (exit_code,decision,rule_id), rc=0  ← D6 gate
FF_ONLY=fixtures bash hooks/tests/run-tests.sh; echo "rc=$?"             # scoped banner + non-strict summary + scoped results file (unchanged contracts)
time ( FF_ONLY=fixtures bash hooks/tests/run-tests.sh )                  # MSYS: seconds, not minutes
grep -n "run_shell_phase test-newline-preserve" hooks/tests/run-tests.sh # existing phase list untouched
```
Commit: `feat(tests): T3 single-process fixture runner + exit-code parity mode` (+R1 restamp).

## T4 — Git-wrapper smoke (new default-suite phase, D9)

Files: NEW `hooks/tests/test-git-hooks-smoke.sh` (tag `git-smoke`; single temp repo;
5 scenarios per D9; `PASS: git-smoke <name>` / `FAIL: git-smoke <name>` lines;
cleanup trap on its own mktemp dir; bounded-friendly — no unbounded waits).
Verify:
```bash
bash hooks/tests/test-git-hooks-smoke.sh; echo "rc=$?"    # 5 PASS lines, rc=0
time bash hooks/tests/test-git-hooks-smoke.sh             # MSYS target ≤ ~30s (recheck at T9)
```
Commit: `feat(tests): T4 single-pass git-wrapper smoke` (+R1 restamp).

## T5 — Integrate new phases + timing instrumentation + manifest self-test (D7, D14.1)

Files: `hooks/tests/run-tests.sh` — ADDITIVE only (no tier flags exist; D7):
- FF_TAGS (:44–47): insert `git-smoke` and `hook-manifest` after
  `health-check-timeout` (run order preserved).
- Insert `run_shell_phase test-git-hooks-smoke.sh "git-smoke"` and
  `run_shell_phase test-hook-manifest.sh "hook-manifest"` BEFORE
  `run_shell_phase test-newline-preserve.sh` (:373).
- Timing instrumentation (D14.1): in `run_bounded_phase` and `run_exitcode_phase`,
  record `local _t0=$SECONDS` before the bounded run and emit
  `printf '[run-tests] %s took %ss\n' "$label" "$((SECONDS-_t0))" >&2` after it —
  STDERR only (progress() precedent :112); stdout contracts byte-unchanged.
- NO other changes: strict summary, results-file shape, FF_ONLY/FF_LIST, exit $fail
  all untouched. NO `Tier:` line, NO header gate-rule change.
Files: NEW `hooks/tests/test-hook-manifest.sh` (tag `hook-manifest`): scenarios,
operating on a TEMP COPY of the covered tree via `hook_manifest.py --root` (R2 —
never mutate the live tree except transient touch/rm of UNTRACKED files):
1. stamp byte-idempotence (`stamp; stamp; cmp`) — rc 0, identical bytes
2. verify MATCH rc 0
3. tampered covered file in temp copy ⇒ rc 1 + path named
4. extra `hooks/shared/x.py` in temp copy ⇒ rc 1 (Scan A)
5. `sitecustomize.py` nested under `hooks/tests/` in temp copy ⇒ rc 1, reason
   python-startup-file (Scan B)
6. corrupt self-hash ⇒ rc 2; manifest absent ⇒ rc 4
Verify:
```bash
bash hooks/tests/test-hook-manifest.sh; echo "rc=$?"      # 6 PASS lines, rc=0
FF_LIST=1 bash hooks/tests/run-tests.sh                   # 24 tags, all RUN (22 existing + git-smoke + hook-manifest)
FF_ONLY=hook-manifest bash hooks/tests/run-tests.sh       # scoped run of the new phase
bash hooks/tests/test-ff-only.sh; echo "rc=$?"            # ff-only self-test green with the new tags
# Full unscoped run — use T9's launch/poll/deadline protocol (Steps 1–3), NOT a
# bare foreground run (R4; MSYS; may pre-date T9 optimization). Expected:
# strict "[run-tests] N/N PASS", rc 0; stderr shows "[run-tests] <label> took Ns" per phase
```
Commit: `feat(tests): T5 git-smoke + hook-manifest phases + per-phase timings` (+R1 restamp).

## T6 — Release gate: reusable verify + gated release workflow (D10) — PROTECTED PATHS (R3/D15 artifact lifecycle)

Files: `.github/workflows/fusebase-flow-verify.yml`:
- `on:` → keep `push: {branches: [main]}` + `pull_request` + `workflow_dispatch`;
  ADD `workflow_call:` (the release workflow calls this job — ONE definition of
  the gate). Do NOT add `push.tags` or `release:` triggers (v2 approach
  superseded, v3/B4: `release: published` fires after publication; a bare tag
  trigger verifies but gates nothing — and would double-run next to the release
  workflow's call).
- "Hook tests (deterministic fixtures)" step: UNCHANGED text
  (`bash hooks/tests/run-tests.sh` — the default run IS the full suite, D7).
- After it, ADD "Runner parity (in-process == subprocess)":
  `python3 hooks/tests/run_hook_tests.py --compare-subprocess`.
- Then ADD "Hook-layer manifest freshness":
  `bash hooks/local/stamp-hook-manifest.sh`,
  `git diff --exit-code -- audit/hook-layer-manifest.json || (echo "Stale hook-layer manifest; run stamp-hook-manifest.sh and commit." && exit 1)`,
  `bash hooks/local/verify-hook-manifest.sh`.
- Existing working-tree-clean step stays LAST (backstop).
Files (NEW): `.github/workflows/fusebase-flow-release.yml` — exact content per
D10.3 (LOCKED): `on: push: tags: ["v*"]`; job `verify:` =
`uses: ./.github/workflows/fusebase-flow-verify.yml`; job `publish:` with
`needs: verify` + `permissions: contents: write`, single step running
`gh release create "$GITHUB_REF_NAME" --verify-tag`
(`-F docs/release-notes/<tag>.md` when the notes file exists, else
`--generate-notes`; `gh release view` guard makes re-runs no-ops).
Execution order within this task (D15 — deterministic artifact lifecycle; ONE
artifact covers BOTH files):
```bash
# 1. author state/approvals/protected_path_edit-hook-manifest-ci-<YYYYMMDD>.json
#    (R3 fields; paths: BOTH workflow files)
# 2. edit fusebase-flow-verify.yml + create fusebase-flow-release.yml; validate:
python3 - <<'PY'
import yaml
for f in (".github/workflows/fusebase-flow-verify.yml",
          ".github/workflows/fusebase-flow-release.yml"):
    yaml.safe_load(open(f))
print("YAML OK")
PY
# 3. commit (pre-commit consumes the artifact)
# 4. IMMEDIATELY delete the artifact:
rm state/approvals/protected_path_edit-hook-manifest-ci-<YYYYMMDD>.json
# 5. prove fixture 07 is green again (R6 baseline):
find state/approvals -maxdepth 1 -name 'protected_path_edit-*.json' -print   # prints nothing
FF_ONLY=fixtures bash hooks/tests/run-tests.sh                                # fixture 07 PASS
```
Verify additionally: verify.yml step ORDER: tests < parity < manifest-freshness <
working-tree-clean; verify.yml `on:` contains `workflow_call:` and does NOT
contain `release:` or `tags:`; release.yml: `on.push.tags == ["v*"]`,
`jobs.publish.needs == verify`, `jobs.verify.uses` points at the local verify
workflow; `grep -rn "gh release create" .github/` → exactly ONE hit (release.yml
publish step). Full proof lands with the PR CI run (G3) + G13 structural checks
(the release workflow itself only fires on a real `v*` tag — structure is the
pre-tag evidence, per D10.6).
Commit: `ci(release): T6 gate GitHub Release publication on the full verify suite`.

## T7 — Health-check rewrite (D4, D5, D13)

Files: NEW `hooks/local/lib/hook-integrity-check.sh` (sourced lib:
`ffhc_hook_manifest_verify` + `ffhc_hook_tests_deep_run` per D13; the deep-run
function is the engine's :393–458 classification relocated verbatim with the D5
outcome mapping — timeout/skip ⇒ note line, FAIL/crash ⇒ LOCAL_BROKEN, pass ⇒
LOCAL_OK; the deep run invokes the FULL `bash hooks/tests/run-tests.sh`, D5/D7).
EDIT `hooks/local/fusebase-flow-health-check.sh`:
- Header: CRITICAL list "hook tests (run-tests)" → "hook layer integrity (manifest
  verify)"; exit-code table comment unchanged VALUES (0/1/2/3/4; 3 stays
  EXCEPTION_IN_EFFECT), updated wording.
- Flags: add `--run-hook-tests` (sets OPT_RUN_HOOK_TESTS=1); `--fast|--skip-hook-tests`
  unchanged (skips the hook-integrity critical ⇒ UNVERIFIED ⇒ exit 4). --help: new
  flag line, reworded --fast line, add `FFHC_MANIFEST_TIMEOUT` to env-knob line.
- Timeouts: `FFHC_MANIFEST_TIMEOUT="${FFHC_MANIFEST_TIMEOUT:-$(ffhc_default_timeout preflight)}"`;
  `FFHC_TESTS_TIMEOUT` default UNCHANGED (`ffhc_default_timeout tests`).
- Replace :387–458 with: source lib (missing lib ⇒ LOCAL_UNVERIFIED + upgrade hint,
  D13) + `ffhc_hook_manifest_verify` (respecting OPT_FAST; maps verifier rc 4 ⇒
  LOCAL_UNVERIFIED "manifest absent", rc 2 ⇒ LOCAL_BROKEN, rc 1 ⇒ record_drift,
  rc 0 ⇒ LOCAL_OK, other ⇒ LOCAL_BROKEN — D4 table) + conditional
  `ffhc_hook_tests_deep_run`.
- Line budget: engine total ≤ 803 lines (`wc -l`).
Verify (MSYS box; R6 guard first):
```bash
find state/approvals -maxdepth 1 -name 'protected_path_edit-*.json' -print         # nothing (R6)
time bash hooks/local/fusebase-flow-health-check.sh --no-upstream; echo "rc=$?"    # < 60 s; HEALTHY rc=0
printf '\n' >> hooks/shared/git_utils.py
bash hooks/local/fusebase-flow-health-check.sh --no-upstream; echo "rc=$?"         # rc=1 FLOW_LAYER_DRIFT; names hooks/shared/git_utils.py
git checkout -- hooks/shared/git_utils.py
bash hooks/local/fusebase-flow-health-check.sh --fast; echo "rc=$?"                # rc=4 PARTIAL_UNVERIFIED (unchanged contract)
bash hooks/local/fusebase-flow-health-check.sh --help                              # new flags + FFHC_MANIFEST_TIMEOUT listed
bash hooks/local/fusebase-flow-health-check.sh --bogus; echo "rc=$?"               # rc=2 usage (unchanged)
mv audit/hook-layer-manifest.json "${TMPDIR:-/tmp}/m.json"
bash hooks/local/fusebase-flow-health-check.sh --no-upstream; echo "rc=$?"         # rc=4; "manifest absent" UNVERIFIED item
mv "${TMPDIR:-/tmp}/m.json" audit/hook-layer-manifest.json
wc -l hooks/local/fusebase-flow-health-check.sh                                    # ≤ 803
# Deep run (full suite) — timing is PROVISIONAL here; T9/D14 owns the <120 s proof:
time bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests; echo "rc=$?"  # HEALTHY rc=0
```
Commit: `feat(health): T7 manifest-verify critical + --run-hook-tests deep diagnostic` (+R1 restamp).

## T8 — Update engine scenario tests

Files: `hooks/tests/test-health-check-timeout.sh` — retarget scenarios to the new
critical: (a) verify-timeout ⇒ UNVERIFIED/exit 4; (b) absent manifest ⇒ engine
exit 4 (standalone verifier rc 4 — SF8); (c) corrupt self-hash ⇒ exit 2 BROKEN;
(d) covered-file tamper ⇒ exit 1 FLOW_LAYER_DRIFT; (e) `--fast` ⇒ exit 4 with the
fast-mode banner; (f) `--run-hook-tests` forced-timeout (`FFHC_TESTS_TIMEOUT=1`) ⇒
verdict UNAFFECTED (still 0/HEALTHY) + note visible; (g) `--run-hook-tests` with an
injected failing suite stub ⇒ exit 2 BROKEN. Keep the existing PASS/FAIL line +
crash-guard contract. Scenarios drive the engine with `--no-upstream` + tight FFHC_*
knobs (D14.4 — this phase must stay cheap).
Verify: R6 guard, then `bash hooks/tests/test-health-check-timeout.sh; echo rc=$?`
(all PASS) and `FF_ONLY=health-check-timeout bash hooks/tests/run-tests.sh`.
Commit: `test(health): T8 scenario suite covers manifest-verify verdict contract` (+R1 restamp).

## T9 — AC3 budget: MEASURE the full suite on MSYS, optimize if over (D14)

No speculative edits — measurement decides. On the Win11/Git-Bash box, R6 guard
first. Measurement protocol (R4/FR-27 — bounded AND backgrounded; a bare
foreground `bash hooks/tests/run-tests.sh` is forbidden here, v3/NEW-3):

**Step 1 — LAUNCH** via the Bash tool with `run_in_background: true` (the harness
detaches it and re-notifies on exit). The command self-records rc + wall time:
```bash
# (Bash tool call, run_in_background: true)
TMP="${TMPDIR:-/tmp}"; date +%s > "$TMP/ff-t9.start"
s=$(date +%s); bash hooks/tests/run-tests.sh > "$TMP/ff-t9.out" 2> "$TMP/ff-t9.err"; rc=$?
printf 'rc=%s wall=%ss\n' "$rc" "$(( $(date +%s) - s ))" > "$TMP/ff-t9.done"
```
Fallback shape (only if `run_in_background` is unavailable — explicit detach +
PID capture):
```bash
TMP="${TMPDIR:-/tmp}"; date +%s > "$TMP/ff-t9.start"
( s=$(date +%s); bash hooks/tests/run-tests.sh > "$TMP/ff-t9.out" 2> "$TMP/ff-t9.err"; \
  printf 'rc=%s wall=%ss\n' "$?" "$(( $(date +%s) - s ))" > "$TMP/ff-t9.done" ) &
echo $! > "$TMP/ff-t9.pid"
```

**Step 2 — POLL with short foreground commands** (each returns immediately; NO
foreground `sleep`/`wait`; repeat between other work). The wall-clock deadline is
enforced HERE — every poll compares now against the recorded start epoch;
deadline = **900 s** (generous vs the historical 7–8 min MSYS worst case, so the
watchdog fires only on a genuine hang):
```bash
TMP="${TMPDIR:-/tmp}"
if [ -f "$TMP/ff-t9.done" ]; then
  echo "DONE: $(cat "$TMP/ff-t9.done")"
elif [ $(( $(date +%s) - $(cat "$TMP/ff-t9.start") )) -ge 900 ]; then
  echo "DEADLINE EXCEEDED (900 s) — killing and recording INCONCLUSIVE"
  [ -f "$TMP/ff-t9.pid" ] && kill "$(cat "$TMP/ff-t9.pid")" 2>/dev/null
else
  echo "RUNNING $(( $(date +%s) - $(cat "$TMP/ff-t9.start") ))s; stderr $(wc -l < "$TMP/ff-t9.err") lines"
fi
```
On DEADLINE EXCEEDED: stop the background task (`kill` the PID in the fallback
shape; the harness's task-stop for `run_in_background`), record the measurement
**INCONCLUSIVE (hung past watchdog)** in the gate evidence, and treat the result
as ≥ 120 s ⇒ go to the D14.4 optimization pass with the PARTIAL per-phase table
already in `$TMP/ff-t9.err`. Honesty notes: MSYS `kill` may orphan grandchild
processes — if the tree survives, note the leaked PIDs in the report; never
re-launch bare; the 900 s deadline exists in this poll loop only (no flag on the
suite enforces it).

**Step 3 — READ results** (only after DONE):
```bash
TMP="${TMPDIR:-/tmp}"
cat "$TMP/ff-t9.done"                                        # rc=0 wall=<N>s  ← the AC3 total
grep -E '^\[run-tests\] .* took [0-9]+s' "$TMP/ff-t9.err"    # per-phase table (D14.1)
tail -3 "$TMP/ff-t9.out"                                     # strict N/N PASS
```

**Step 4 — the AC3 deep-run command, measured the SAME way** (launch per Step 1
with `ff-t9b.*` files, poll per Step 2 with the same 900 s watchdog):
```bash
# (Bash tool call, run_in_background: true)
TMP="${TMPDIR:-/tmp}"; date +%s > "$TMP/ff-t9b.start"
s=$(date +%s); bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests > "$TMP/ff-t9b.out" 2> "$TMP/ff-t9b.err"; rc=$?
printf 'rc=%s wall=%ss\n' "$rc" "$(( $(date +%s) - s ))" > "$TMP/ff-t9b.done"
```

Decision (per D14):
- **Total < 120 s AND deep run < 120 s** ⇒ record the per-phase table + both
  `wall=` values as G2/G8 evidence. NO commit (measurement only).
- **≥ 120 s (or INCONCLUSIVE-over-deadline)** ⇒ optimize offenders in
  measured-cost order per D14.4. Named (inventory regenerated against source,
  v3/NEW-2): test-cli-flow-recovery.sh — the 10 FULL `cp -R "$PROJECT"` copies at
  :256/:284/:323/:349/:380/:478/:513/:526/:884/:926 (shared copy +
  mutate→assert→restore), the 3 repeated PARTIAL fixture builds at :631/:633,
  :672/:674, :837/:838/:842 (one prebuilt partial base), and the moot
  `FFHC_TESTS_TIMEOUT=600` at :496/:508; then test-cli-0259-compat.sh,
  test-bootstrap-exception.sh, test-secret-scan-staged.sh,
  test-ws5-upgrade-bounded.sh, test-sync-allowlist.sh,
  test-bootstrap-baseline-hop.sh fixture consolidation. Each optimization:
  behavior-preserving (same scenario names + assertions), ONE commit
  (`perf(tests): T9 <script> single-pass fixtures (D14)` +R1 restamp), verified by
  the script standalone + re-measure via Steps 1–3.
- **Still ≥ 120 s after all named levers** ⇒ STOP (D14.6): per-phase table into the
  gate report, G8/AC3 = FAIL, report to PO. FORBIDDEN: FF_ONLY-scoping the proof,
  raising FFHC_TESTS_TIMEOUT to mask, letting a phase go INCONCLUSIVE, skipping a
  phase (D14.5).

## T10 — Upgrade propagation (D11, AC5)

Files: `hooks/local/upgrade.sh`:
`CONTENT_FILES=( "FLOW_RULES.md" "audit/hook-layer-manifest.json" )` (:233); in the
COPY loop (:332–337) add `mkdir -p "$(dirname "$f")"` before `cp` (plan loop :252–256
is read-only — no change).
Ordering: COMMIT FIRST, then run the sim as post-commit verification — the sim
`git clone`s this repo, so consumer + staging trees must carry the committed T10
upgrade.sh (a red sim ⇒ `fix(upgrade): T10b …` follow-up commit).
Verify (consumer simulation — SF9-safe): write the following to
`<scratchpad>/t10-consumer-sim.sh` and run `bash <scratchpad>/t10-consumer-sim.sh`
(the agent never types `rm -rf`; the script's only recursive removal is
path-guarded to its own mktemp root — test-ws5-upgrade-bounded.sh:86 precedent):
```bash
#!/usr/bin/env bash
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"
SIM="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-t10.XXXXXX")"
safe_rm_tmp() {  # FR-06 guard: refuse anything outside our own mktemp root
  case "$1" in "${TMPDIR:-/tmp}"/ffhc-t10.*) rm -rf -- "$1" ;;
    *) echo "REFUSE cleanup of non-temp path: $1" >&2; return 9 ;; esac
}
trap 'safe_rm_tmp "$SIM"' EXIT
git clone --quiet "$REPO" "$SIM/consumer"
cd "$SIM/consumer"
# simulate a pre-ticket install: drop the new artifacts (plain rm -f of named files;
# keep the T10 upgrade.sh — it is the script under test, D11)
rm -f audit/hook-layer-manifest.json hooks/local/verify-hook-manifest.sh \
      hooks/local/stamp-hook-manifest.sh hooks/local/lib/hook_manifest.py \
      hooks/local/lib/hook-integrity-check.sh hooks/tests/run_hook_tests.py \
      hooks/tests/test-git-hooks-smoke.sh hooks/tests/test-hook-manifest.sh
rmdir audit 2>/dev/null || true            # older installs may lack audit/ entirely
# staging source = git clone (supported per upgrade.sh:40; tracked files only —
# no nested .fusebase-flow-source, nothing to rm)
git clone --quiet "$REPO" .fusebase-flow-source
bash hooks/local/upgrade.sh --auto-yes
test -f audit/hook-layer-manifest.json
test -x hooks/local/verify-hook-manifest.sh
test -f hooks/tests/run_hook_tests.py
bash hooks/local/verify-hook-manifest.sh
echo "PROPAGATION OK"
```
Expected output ends `PROPAGATION OK`; the trap removes only `$SIM`.
Commit: `fix(upgrade): T10 carry hook-layer manifest in the upgrade copy-set`.

## T11 — Docs + CHANGELOG (no skill edits — descoped, D7)

Files:
- `docs/hook-coverage.md`: runner description (single-process fixtures, phase list,
  fixture count), NEW "§ Manifest verification & trust model" (condense spec § trust
  model; canonical consumer-facing WHY; include the Scan A/Scan B extra-file policy).
- `docs/compatibility.md`: Windows section — full HEALTHY now reachable;
  `--run-hook-tests` = full suite, measured budget.
- `PUBLISHING.md` (two edits, per D10.3–D10.4):
  (a) NEW "## Release prerequisites (enforced)" — the in-repo gate summary (the
  release workflow publishes the Release iff its verify job is green on the
  tagged sha), the `v*` TAG RULESET requirement with the exact
  `gh api repos/{owner}/{repo}/rulesets --method POST` apply command from D10.4
  (+ the note to confirm the `verify` check-context string against the repo's
  check runs), the `main` branch-protection `gh api` command + UI click-path
  (kept from v2), and the applies-to-both-publication-options note;
  (b) § After publication (:99–105): REPLACE the manual `gh release create`
  instruction (:103) with "push the `v<version>` tag —
  `fusebase-flow-release.yml` creates the GitHub Release only after the full
  verify suite passes on that sha; manual `gh release create` is FORBIDDEN (it
  bypasses the gate)".
- `CHANGELOG.md`: entry under Unreleased (no version bump — Deploy phase owns it).
- NOT touched: `flow-skills/**` (v1's validation-and-qa gate-rule edit is DESCOPED —
  no tier concept exists; the existing full-unscoped-gate rule is already correct).
  No mirror regeneration needed.
Verify: `bash hooks/local/preflight.sh` (0 errors incl. mirror parity — mirrors
untouched); `git diff --stat` shows ONLY the four docs files.
Commit: `docs(flow): T11 manifest-verify trust model + release prerequisites + changelog`.

## T12 — Gate run (no code changes; STOP after)

Execute docs/specs/hook-manifest-verify/verification-gate.md G1–G13 in order on this
Windows box + via the PR CI run (R6 guard before every command). Produce the gate
report (shape per the handoff) and STOP — no deploy, no version bump, no spec
DRAFT→DONE flip, no branch-protection changes (operator/PO own those).

## Empirical acceptance tests (bound into the gate)

| AC | Command | Expected |
|---|---|---|
| AC1 | `time bash hooks/local/fusebase-flow-health-check.sh --no-upstream` (Win11/Git-Bash) | HEALTHY, exit 0, < 60 s |
| AC2 | tamper/corrupt/absent sequence (T7 verify block) | exit 1 naming file / exit 2 / exit 4 (verifier standalone rc 4 for absent) |
| AC3 | `time bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests` (T9-measured) | FULL suite completes, HEALTHY, < 120 s on MSYS |
| AC4 | structural inspection (G13): release.yml `on.push.tags` / `jobs.publish.needs: verify` / `jobs.verify.uses`; verify.yml `workflow_call:` (no `release:`/`tags:`); `grep -rn "gh release create" .github/` (exactly 1 hit); PUBLISHING.md § Release prerequisites + manual-create-forbidden line; optional red-fixture scratch-fork spot-check | publish job structurally unreachable on red verify (`needs:` edge present); Release creation workflow-owned only; ruleset + branch-protection apply commands documented |
| AC5 | T10 simulation script | prints `PROPAGATION OK` |
| AC7 | `python3 hooks/tests/run_hook_tests.py --compare-subprocess` (MSYS + CI) | 21/21 identical (exit_code, decision, rule_id), rc 0 |
