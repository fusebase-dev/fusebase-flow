# Decisions — hook-manifest-verify (LOCKED, v4)

Status: LOCKED (v4 — AC3 resolution after the post-gate Codex adversarial review +
orchestrator ruling; everything else in v3 confirmed SOUND). Deviations require
re-opening the decision, not silent divergence.

## Revision log (v3→v4) — AC3 platform-adaptive resolution

| Finding | How closed | Decisions/tasks changed |
|---|---|---|
| **AC3 BLOCKED (T9/D14.6)** — on a real Win11/Git-Bash box the full `run-tests.sh` suite measures ~950–1085s (individual phases each exceed the 120s budget: `liveness` 133s, `secret-scan-staged` 124s, `bootstrap-exception` 280s, `codex-parity` 48s), so `--run-hook-tests = full suite everywhere` cannot meet AC3's `< 120s` on MSYS. The out-of-scope, non-D14.4-named phases alone (liveness + codex-parity + module-size = 197s) exceed 120s ⇒ no D14.4-named lever can close the gap. | `--run-hook-tests` is now **PLATFORM-ADAPTIVE** (satisfies AC3's literal wording *"on Linux runs the full suite as before; on MSYS < 120s via the single-process runner"*): POSIX/Linux/macOS runs the FULL `run-tests.sh` unchanged; **MSYS runs the FAST diagnostic** = `run_hook_tests.py` (single-process fixtures) + `test-git-hooks-smoke.sh` + `test-hook-manifest.sh`, targeting < 120s (measured **~52s** end-to-end incl. the base health check). Same asymmetric outcome mapping on both paths (FAIL/crash ⇒ BROKEN; timeout/skip ⇒ NOTE only). The FULL MSYS suite stays reachable via **`--run-hook-tests-full`** / **`FFHC_RUN_HOOK_TESTS_FULL=1`**. The base health verdict is NOT gated on the optional deep run (unchanged); the DEFAULT `run-tests.sh` + CI stay FULL and unchanged (CI Linux/G3 is the authoritative full-suite green). | D5 (platform-adaptive bullet), D14.8 (new); tasks T9 (v4 optimization commit — one focused feat commit); gate G8/AC3 (platform-adaptive expectation), G2 (MSYS wall is diagnostic; full-suite green = CI/G3). Implementation: `ffhc_hook_tests_deep_run` split into `_ffhc_deep_run_full` + `_ffhc_deep_run_fast` in `hooks/local/lib/hook-integrity-check.sh`; `--run-hook-tests-full` wired in the engine. |

## Revision log (v2→v3) — residual-finding closure map

| Finding | How closed | Decisions/tasks changed |
|---|---|---|
| **B4 (BLOCKER — still open after v2)** — v2's `push.tags: [v*]` + `release: {types:[published]}` triggers plus documented branch protection were DETECTION, not enforcement: `release: published` fires AFTER publication (too late to gate); a tag can be pushed before any CI is green; documented settings are process, not an in-repo gate | Publication is now GATED IN-REPO: NEW `.github/workflows/fusebase-flow-release.yml` (triggered by `v*` tag push) — its `publish` job is the ONLY thing that creates the GitHub Release and declares `needs: verify`, where the `verify` job runs the FULL verify workflow (full suite → runner parity → manifest freshness) via `workflow_call` (`uses: ./.github/workflows/fusebase-flow-verify.yml` — ONE job definition, no step drift). Red suite ⇒ `publish` never runs ⇒ no Release exists for that tag. PUBLISHING.md's manual `gh release create` step (:103) is REPLACED by the workflow; manual Release creation is forbidden. v2's `tags:`/`release:` triggers on verify.yml are SUPERSEDED by `workflow_call:` (they must NOT be added — double-run + false gating). Honest boundary (D10.4): the raw `v*` tag ref and an admin manual-create bypass can only be closed by repo-admin settings — documented `v*` tag ruleset + `main` branch protection requiring the `verify` check, with exact `gh api` apply commands in PUBLISHING.md; the in-repo workflow gate is the primary enforcement and stands even if the operator forgets the settings. Both protected workflow files land in the SAME T6 commit under ONE D15 approval artifact (`paths` lists both — no extra protected-path dance). | D10 (rewritten), D15 + R3 (artifact `paths` ×2); tasks T6 (rewritten), T11 (PUBLISHING.md content); spec Part 1.1 / trust model / AC4 / out-of-scope; gate G13 (rewritten) |
| **NEW-2 (SHOULD-FIX)** — D14's `test-cli-flow-recovery.sh` offender list was stale/incomplete: it listed :631/:672/:837 as full-project copies (they are PARTIAL flow-skills/agents/overlays builds) and MISSED the full copies at :884 and :926 | Inventory REGENERATED against source (2026-07-08; `grep -nE 'cp -R\|cp -r\|cp -a'` + per-hit inspection of the 954-line file): **10 FULL `cp -R "$PROJECT"` copies** — :256 (U10), :284 (U11), :323 (U12), :349 (U19), :380 (U13), :478 (F2), :513 (U17), :526 (U18), :884 (CLAUDE_ONLY), :926 (U20) — and the PARTIAL sites correctly classified (base-fixture setup :47/:48/:55–:57; :350 intra-U19 legacy copy; LEGACY :631/:633; U9P :672/:674; BAD_PROJECT :837/:838/:842; U20 staging :934). Levers re-grounded on the real shapes (shared copy + mutate→assert→restore for the small-mutation full-copy scenarios; one prebuilt partial base for the 3 repeated partial builds; drop the moot `FFHC_TESTS_TIMEOUT=600` at :496/:508). | D14.4 (corrected inventory + levers); task T9 (mirrored list) |
| **NEW-3 (SHOULD-FIX)** — T9's measurement command (`bash hooks/tests/run-tests.sh > out 2> err`) was a bare foreground run — not backgrounded/bounded as R4/FR-27 require | T9's command block REWRITTEN to the exact bounded/backgrounded protocol for this Win11/Git-Bash box: launch via the Bash tool's `run_in_background: true` (fallback: explicit `&` + PID file), the command self-records `rc=… wall=…s` to a done-file; completion is observed by a SHORT-command poll loop (no foreground sleep) that enforces a 900 s wall-clock watchdog by comparing now vs the recorded start epoch on every poll; on breach: kill the PID / stop the background task, record the measurement INCONCLUSIVE, and treat the result as ≥ 120 s ⇒ proceed to D14.4 with the partial stderr table. The AC3 deep-run measurement uses the same protocol. Honest limitation stated: MSYS `kill` may orphan grandchildren — note leaked PIDs, never re-launch bare. | D14.2 (delegates to T9's protocol); task T9 (rewritten command block); T5 full-run verify line + R4 cross-reference |

## Revision log (v1→v2) — review-finding closure map

| Finding | How closed | Decisions/tasks changed |
|---|---|---|
| **B1+B2** — v1 made default `run-tests.sh` a "core tier" (≈20 existing phases moved behind `--full`) and made `--run-hook-tests` core-only; the default is the FULL local gate and must not lose coverage; AC3 requires the deep run = full suite | Tier model **REMOVED entirely**. Default `run-tests.sh` (no flags) keeps EVERY phase that runs today — the fixture fork-loop is REPLACED by the single-process runner (same 21 fixtures, same assertions), and 2 phases are ADDED (git-smoke, hook-manifest): a strict coverage SUPERSET. No `--full`/`--core`/`FF_FULL`/`Tier:` line. Fast iteration = the EXISTING `FF_ONLY` opt-in (fail-closed, scoped results file, loud banner — already not-a-full-gate by construction). `--run-hook-tests` runs the FULL suite on all platforms. | D5, D7 (rewritten), D8, D9; spec Part 2 + AC3/AC6; tasks T3/T5/T6/T7; gate G2/G8. The v1 `flow-skills/validation-and-qa/SKILL.md` edit is **DESCOPED** (no tier ⇒ the existing full-unscoped-gate rule is already correct). |
| **B1 (AC3 empirics)** — "<120 s on MSYS" must be a concrete measure-then-optimize instruction, not hand-waved | NEW **D14**: per-phase wall-time instrumentation; MEASURE the full suite on the real Win11/Git-Bash box; if ≥120 s, optimize the NAMED offenders (cli-flow-recovery, cli-0259, secret-scan-staged, bootstrap-exception, ws5-upgrade, sync-allowlist, bootstrap-baseline-hop) with named levers; if still ≥120 s after all levers, STOP and report per-phase timings (AC3/G8 FAIL, PO reopens D14). Masking (FF_ONLY, timeout-raising, letting a phase go INCONCLUSIVE) is forbidden. | NEW D14; NEW task T9; gate G2/G8 |
| **B3** — `generated_at` breaks the CI freshness gate (`stamp && git diff --exit-code` red every day after the commit date) | `generated_at` **REMOVED from the schema**. Exact idempotence contract in D1: stamp output is a pure function of (covered bytes, VERSION); same tree ⇒ byte-identical file; freshness gate is deterministic. Stamp date = git history. Deliberate, documented divergence from the stamp-cli-provenance precedent (that manifest is advisory-only, never freshness-gated — stamp-cli-provenance.sh:27). | D1; tasks T2; gate G9 (byte-idempotence, no "modulo generated_at") |
| **B4** — workflow triggers only on main push/PR/dispatch; a tag/release could publish despite red tests; AC4 was a recommendation | **[SUPERSEDED in v3 — see v2→v3 row B4; this v2 closure was found insufficient.]** D10: `on:` gains `push.tags: ["v*"]` + `release: {types: [published]}` — the SAME verify job runs on tag pushes and published releases. PUBLISHING.md gains a mandatory **"Release prerequisites (enforced)"** section: branch protection marks the `verify` job a required status check (exact `gh api` command documented), and release ordering = push main → verify green → tag the same sha. AC4 evidence is gated (new G13). | D10; tasks T6 (workflow `on:`), T11 (PUBLISHING.md); NEW gate G13 |
| **B5** — parity compared only (decision, rule_id); handlers return meaningful exit codes via `raise SystemExit(main())` | D6: `--compare-subprocess` compares the TRIPLE **(exit_code, decision, rule_id)** per fixture; in-process rc captured from SystemExit with CPython normalization (None→0, int→value, other→1); subprocess rc = returncode. All 7 handlers verified to end `raise SystemExit(main())` (pre_tool_use.py:177, user_prompt_submit.py:176, permission_request.py:72, stop.py:339, pre_compact.py:135, session_start.py:163, post_tool_use.py:82). | D6; spec AC7; tasks T3; gate G4 |
| **B6** — extra-file scan covered only `hooks/handlers/*.py` + `hooks/shared/*.py`; protected-paths.yml names recursive sitecustomize/usercustomize patterns | D3: TWO precisely-defined DRIFT scans — Scan A (import-adjacent extras under handlers/shared) + Scan B (recursive `hooks/**` walk flagging ANY file with basename `sitecustomize.py`/`usercustomize.py` not in the manifest, NO exclusions), mirroring policies/protected-paths.yml:93–100. Expected-set/extra definitions locked. | D3; tasks T2/T5 (test scenario); spec trust model |
| **B7** — T6's `protected_path_edit-*.json` approval artifact makes fixture 07 (expects deny) fail later test runs | NEW **D15**: T6 DELETES the artifact immediately after the protected commit and proves fixture 07 green in the same task; NEW standing rule **R6**: zero `state/approvals/protected_path_edit-*.json` asserted before EVERY test/health-check/gate run from T6 on. Deterministic — never "time it carefully". | NEW D15; tasks R3 (revised), R6 (new), T6; gate preamble |
| **SF8** — standalone verifier rc 3 = "absent" collides with the framework's public exit 3 = EXCEPTION_IN_EFFECT | D3: standalone verifier ABSENT = **exit 4**; exit 3 RESERVED/never emitted (engine exit-code table :34 and :798 keep 3 = EXCEPTION_IN_EFFECT). D4 maps verifier-4 → LOCAL_UNVERIFIED → PARTIAL_UNVERIFIED / engine exit 4 (aligned by design). | D3, D4; tasks T2/T5/T8; gate G6 |
| **SF9** — T9's `rm -rf "$SIM"` / nested `.fusebase-flow-source` rm not executable under FR-06 (command-policy.yml:14 hard-denies typed `rm -rf`) | Consumer sim is now a SCRATCHPAD SCRIPT: mktemp-rooted fixture, staging via `git clone` (kills the nested-dir rm entirely; upgrade.sh:40 documents clone as a supported source form), and a path-guarded `safe_rm_tmp` that refuses any path outside `${TMPDIR:-/tmp}/ffhc-t10.*`. The agent types only `bash <script>` — same precedent as test-ws5-upgrade-bounded.sh:86 (script-internal mktemp cleanup). | D11 (verification note); task T10 |

---

## D1 — Manifest format, location, generation, self-hash, BYTE-STABLE stamping

- File: `audit/hook-layer-manifest.json`, **committed** (document-of-record precedent:
  `audit/cli-vendor-manifest.json`).
- Schema: `{schema_version:1, flow_version:<VERSION>, description:<FIXED string>,
  asset_count, assets:[{path,"sha256"}], manifest_self_sha256}` — **no `generated_at`,
  no timestamps of any kind** (v2/B3). Assets sorted by repo-relative POSIX path
  (backslashes normalized), sha256 over raw file bytes (64 KiB chunks; same
  `sha256_of` shape as stamp-cli-provenance.sh:96–99).
- **Idempotence contract (exact, LOCKED):** the stamped file is a pure function of
  (covered file bytes, `VERSION`). Fixed serialization: `json.dumps(doc, indent=2)`
  with a fixed key construction order + one trailing `"\n"`, written with
  `open(..., "w", newline="\n")` (LF even on Windows). Therefore:
  (a) `stamp; stamp` ⇒ byte-identical file (`cmp` clean);
  (b) CI `stamp && git diff --exit-code -- audit/hook-layer-manifest.json` fails
  **iff** a covered asset or VERSION changed since the committed stamp — never
  because of the date. "When was it stamped" = git history; the `description`
  string says so.
- Self-hash: `manifest_self_sha256 = sha256(utf8(json.dumps({"schema_version":…,
  "flow_version":…, "assets":…}, sort_keys=True, separators=(",",":"))))` — covers
  version + asset list; excludes `description`/`asset_count`/itself. Honest scope:
  detects corruption/hand-edits, not a recomputing attacker (trust model in spec).
- Deliberate divergence from the stamp-cli-provenance precedent: that manifest keeps
  `generated_at` because it is **advisory-only and never freshness-gated**
  (stamp-cli-provenance.sh:27–28); this manifest IS CI-freshness-gated, so
  byte-stability outranks precedent symmetry.
- Generation: `hooks/local/stamp-hook-manifest.sh` (thin bash wrapper →
  `hooks/local/lib/hook_manifest.py stamp`). The lib CLI accepts `--root <dir>`
  (default `git rev-parse --show-toplevel`) so tests can operate on temp copies.
  Never hand-maintained; CI enforces freshness (D10). *Rejected:* embedding globs as
  data in the manifest and having verify trust them — the resolver must be ONE piece
  of code shared by stamp and verify (a tampered manifest could otherwise shrink its
  own coverage).

## D2 — Covered file set (exact resolution)

Spec table is authoritative; resolver lives ONLY in `hook_manifest.py::collect_assets(root)`:
- `hooks/handlers/*.py`, `hooks/shared/*.py` (skip `__pycache__`, `*.pyc`)
- `hooks/git/*` (plain files)
- `hooks/tests/*.sh` + `hooks/tests/run_hook_tests.py` + `hooks/tests/fixtures/*` (ALL
  files — fixtures include `*.jsonl` transcripts referenced by stop fixtures 18–21)
- `hooks/local/*.sh` EXCLUDING `*.local.*` (upgrade.sh preserves operator
  `hooks/local/*.local.*`; including them ⇒ guaranteed consumer false drift)
- `hooks/local/lib/*` files (`*.sh` + `hook_manifest.py` — the verifier covers itself)
*Rejected:* `policies/*.yml` (FR-07-protected but consumer-variant: module-size-baseline
merge rows, `*.local.yml` layering) — false-drift generator; revisit as v2 if wanted.
*Rejected:* overlays/`fusebase-flow-overlays/**` — recovery-template ownership, separate
mechanism, high churn.

## D3 — Verify semantics (`hooks/local/verify-hook-manifest.sh`)

- Wrapper → `hook_manifest.py verify [--json] [--root <dir>]`. Single python pass; no
  new deps (hashlib/json/stdlib only).
- Exit codes: `0` MATCH · `1` DRIFT (modified/missing/flagged-extra) · `2` BROKEN
  (unparseable manifest OR self-hash mismatch) · **`4` ABSENT** (no manifest file).
  **`3` is RESERVED and never emitted** (v2/SF8): the health-check's public exit 3 =
  EXCEPTION_IN_EFFECT (engine header :34, dispatch :798) — a standalone rc 3 would
  collide with that meaning in scripts and operator muscle memory.
- JSON: `{verdict, flow_version, counts:{listed,matched,modified,missing,extra},
  files:[{path,status∈{modified,missing,extra},reason?}]}`.
- **Extra-file policy (precise, v2/B6).** Expected set `E` = exactly the manifest's
  `assets[].path` set (produced by `collect_assets` at stamp time). Two DRIFT scans:
  - **Scan A — import-adjacent extras:** any on-disk file matching
    `hooks/handlers/*.py` or `hooks/shared/*.py` with path ∉ E ⇒ `status: extra`,
    DRIFT (rc 1). `__pycache__/` dirs and `*.pyc` excluded.
  - **Scan B — python startup tripwire:** recursive walk of `hooks/**`; ANY file
    whose **basename** is `sitecustomize.py` or `usercustomize.py` with path ∉ E ⇒
    `status: extra`, `reason: python-startup-file`, DRIFT (rc 1). **NO exclusions**
    apply to Scan B — not `*.local.*`, not `__pycache__`, any depth. This mirrors
    policies/protected-paths.yml:93–100 (`hooks/sitecustomize.py`,
    `hooks/usercustomize.py`, `**/sitecustomize.py`, `**/usercustomize.py`) for the
    layer the manifest owns; repo-wide `**` enforcement stays with the
    pre-commit/pre_tool_use hooks + the `python3 -S` runtime close (the T29 tripwire
    comment at protected-paths.yml:93–96).
  - Extras anywhere else under covered dirs (tests/local/git) are informational only
    (consumers legitimately add local scripts); `*.local.*` is never flagged by
    Scan A — but a `sitecustomize.py` at ANY depth under `hooks/` IS flagged by
    Scan B (basename rule, no exclusions).
  *Rejected:* strict extras everywhere (false drift on consumer additions);
  *rejected:* no extra scan (leaves the cheapest injection vector dark);
  *rejected:* Scan B limited to `hooks/` top level (the protected patterns are
  recursive; the scan must be too).
- Windows determinism: raw-byte hashing REQUIRES LF-stable checkouts ⇒ D12.

## D4 — Health-check integration + verdict mapping

Replace the run-tests CRITICAL (engine :387–458) with the manifest-verify CRITICAL
("hook layer integrity"). Bounded via `ffhc_run_bounded_stdout` at
`FFHC_MANIFEST_TIMEOUT` (default `ffhc_default_timeout preflight` = 30 s POSIX /
60 s MSYS; run-with-timeout.sh:83–89). Mapping:

| verify result | engine classification | verdict / exit |
|---|---|---|
| MATCH (0) | `LOCAL_OK` "hook layer integrity: N files match release <flow_version>" | contributes to HEALTHY / 0 |
| DRIFT (1) | `record_drift "hook_layer_manifest"` — first 5 paths + "+N more" | FLOW_LAYER_DRIFT / 1 (deferrable) |
| BROKEN (2) | `LOCAL_BROKEN` (manifest corrupt / self-hash fail) | BROKEN / 2 |
| ABSENT (4) | `LOCAL_UNVERIFIED` "manifest absent (pre-upgrade install; run upgrade.sh)" | PARTIAL_UNVERIFIED / 4 |
| timeout/skip | `LOCAL_UNVERIFIED` (existing pattern) | PARTIAL_UNVERIFIED / 4 |
| any other rc | `LOCAL_BROKEN` (unexpected verifier failure — fail closed) | BROKEN / 2 |

Verifier exit 3 never occurs (D3); the engine's own exit 3 = EXCEPTION_IN_EFFECT is
untouched (:798). WHY drift = exit 1 (not BROKEN/2): a hash mismatch proves
*divergence from release X*, not *breakage* — the drift class already means "concrete
finding with a recovery path" (`upgrade.sh` / `git checkout --`), it keeps BROKEN
reserved for harness-crash/corrupt integrity anchors, and `record_drift` keeps legit
mid-ticket hook-layer work deferrable via the existing `health_check_deferral`
artifact instead of an undeferrable exit 2. Manifest self-hash failure IS exit 2: the
integrity anchor itself is untrustworthy — nothing can be asserted, and there is no
benign cause (absence is the benign case and has its own class). `--fast`: unchanged
— skips the hook-integrity critical ⇒ UNVERIFIED-by-design ⇒ exit 4, never 0 (LOCKED
contract + existing scenario tests assert it).

## D5 — `--run-hook-tests` (optional deep diagnostic = the FULL suite)

- Runs `bash hooks/tests/run-tests.sh` — the FULL unscoped suite (D7: there is no
  tier concept; v2/B1). Bounded at `FFHC_TESTS_TIMEOUT` (defaults unchanged:
  `ffhc_default_timeout tests` = 120 s MSYS / 60 s POSIX, run-with-timeout.sh:83–89),
  classified by the RELOCATED existing logic (strict pass-line select, INCONCLUSIVE,
  crash guard, artifact attribution — moved verbatim into the lib, D13).
- On Linux this is the same suite the engine runs today (AC3's "as before"). On MSYS
  it fits the bound via D6 (single-process fixtures) + D14 (measured budget with
  named optimization levers).
- Asymmetric outcome mapping (fail-honest, unchanged from v1): pass ⇒ `LOCAL_OK`
  extra line; **observed FAIL/crash ⇒ `LOCAL_BROKEN`**; timeout/skip ⇒ NOTE only,
  NOT `LOCAL_UNVERIFIED` (an optional check must never force exit 4). "Never
  required for the verdict" = its absence never blocks HEALTHY; it does not mean
  observed failures are ignored.
- **Platform-adaptive (v4, supersedes v1–v3's "uniform FULL suite everywhere").**
  `--run-hook-tests` runs the FULL `run-tests.sh` on POSIX/Linux/macOS and the FAST
  diagnostic (single-process fixtures + git-smoke + hook-manifest self-test) on MSYS
  (< 120 s), because the MSYS full-suite wall (~950–1085 s, T9) cannot meet AC3.
  `--run-hook-tests-full` / `FFHC_RUN_HOOK_TESTS_FULL=1` forces the full suite on MSYS
  too. Same outcome mapping on both paths (FAIL/crash ⇒ LOCAL_BROKEN; timeout/skip ⇒
  NOTE only). The base verdict is never gated on the deep run; the DEFAULT
  `run-tests.sh` + CI stay FULL. See the v3→v4 revision-log row.
- `--fast --run-hook-tests` combination: legal, flags independent (--fast governs the
  manifest critical; the deep run still executes). Documented in --help.

## D6 — Single-process runner (`hooks/tests/run_hook_tests.py`) + isolation + parity proof

- NEW file under `hooks/tests/` (NOT FR-07-protected; handlers/shared untouched).
- Per handler: import ONCE via `importlib.util.spec_from_file_location` (unique module
  name `ff_handler_<stem>`), with `hooks/` on `sys.path` (handlers also self-insert).
  Per fixture (sorted `fixtures/*.json`, same order as bash):
  1. `shared.policy_loader.reset_cache()` — parity with each subprocess's cold cache.
  2. `sys.stdin = io.TextIOWrapper(io.BytesIO(raw_fixture_bytes), encoding="utf-8")`
     (raw bytes as the subprocess pipe delivered; deterministic UTF-8 decode).
  3. Capture stdout via `contextlib.redirect_stdout(io.StringIO())`; stderr redirected
     and DISCARDED (parity with the loop's `2>/dev/null`).
  4. **Exit-code capture (v2/B5):** `rc = module.main()` wrapped:
     `except SystemExit as e: rc = _norm(e.code)` where `_norm` = CPython semantics —
     `None → 0`, `int → value`, anything else `→ 1`. All 7 handlers end
     `raise SystemExit(main())` (pre_tool_use.py:177, user_prompt_submit.py:176,
     permission_request.py:72, stop.py:339, pre_compact.py:135, session_start.py:163,
     post_tool_use.py:82), so the SystemExit path is the production exit path.
     `except BaseException: FAIL(detail=traceback head)` (subprocess parity: a crash =
     empty/invalid stdout = FAIL).
  5. Parse decision/rule_id from captured stdout exactly as today
     (`json.loads(out) if out.strip().startswith("{") else {}`;
     `decision=get("decision","")`, `rule_id=get("rule_id","") or ""`).
  6. Assertions byte-identical to run-tests.sh:240–255: `_expected_decision` exact,
     `_expected_rule_id` exact, `_expected_rule_id_contains` substring — each applied
     only when the field is non-empty. (Fixtures carry no `_expected_exit_code`;
     normal-mode assertions stay decision/rule_id — the exit code is asserted by the
     parity gate below, for every fixture.)
- Side effects: `audit_logger.emit` is NOT patched — today's subprocess runs already
  append to `state/audit.log.jsonl` (gitignored); leaving it identical is the
  parity-first choice. *Rejected:* monkeypatching emit (each handler binds
  `from shared.audit_logger import emit`, so patching the module misses the bound
  names — fragile, and it would diverge from the production path). cwd = git root
  (`os.chdir`) so relative `transcript_path` fixtures resolve as today.
- Parse-invariant continuity: the runner reads metadata from JSON dicts (no TSV), so
  the empty-middle-field hazard is structurally gone; a synthetic `_parse-invariant`
  row is retained (metadata `{"_expected_rule_id":"", "_expected_rule_id_contains":"FR-12"}`
  must select the SUBSTRING assertion path) to keep the guarantee explicit + the count
  contract stable.
- Output protocol: identical per-test lines (`PASS: <fixture>  (<test>) -> decision=…` /
  `FAIL: … ->…detail`) on stdout; exit code = fail count. run-tests.sh runs it as ONE
  bounded phase and aggregates by counting `^PASS:`/`^FAIL:` lines (existing
  run_shell_phase parse contract).
- **Correctness gate (LOCKED, v2/B5):** `--compare-subprocess` mode runs every fixture
  BOTH ways (in-process + `python3 hooks/handlers/<h> < fixture` via subprocess) and
  diffs the TRIPLE **(exit_code, decision, rule_id)** per fixture — in-process
  exit_code from step 4's SystemExit capture, subprocess exit_code from
  `proc.returncode`. ANY component divergence ⇒ the fixture is named with both
  triples and the mode exits nonzero. Required green 21/21 on MSYS (implementer) AND
  as a permanent CI step (ubuntu). ~21 spawns — cheap everywhere, priceless as a
  regression tripwire.

## D7 — run-tests.sh composition: the default stays the FULL unscoped gate (no tiers)

**v2/B1+B2 — rewritten.** `bash hooks/tests/run-tests.sh` (no flags) remains the full
local gate; no phase moves behind any flag.

- Every phase in today's run order STAYS in the default run: module-size,
  health-check-timeout, the 18 `run_shell_phase` entries (run-tests.sh:373–390), and
  the `run_exitcode_phase` cli-flow-recovery (:428, incl. FF_SKIP_CLI_RECOVERY +
  240 s bound + INCONCLUSIVE contract).
- Exactly two composition changes, both coverage-neutral-or-additive:
  1. The fixture fork-loop (:143–289) is REPLACED by ONE bounded phase invoking
     `run_hook_tests.py` — same 21 fixtures, same assertion semantics, same
     `PASS:`/`FAIL:` shapes, `_parse-invariant` retained (D6).
  2. Two NEW phases join via the existing `run_shell_phase` machinery:
     `test-git-hooks-smoke.sh` (tag `git-smoke`, D9) and `test-hook-manifest.sh`
     (tag `hook-manifest`, T5), inserted before `test-newline-preserve.sh` (:373);
     both tags added to `FF_TAGS` (:44–47) in run order (after
     `health-check-timeout`).
- **Coverage invariant (AC6):** the default run's phase set is a strict SUPERSET of
  today's 22 tags (⇒ 24 tags). `FF_LIST=1` proves it mechanically.
- **NO tier flags.** `--full` / `--core` / `FF_FULL` / `Tier:` results-file line —
  all REJECTED (the v1 design error: making the default a subset silently destroyed
  the documented full local gate). Fast iteration = the EXISTING `FF_ONLY` scoping:
  explicit opt-in, loud SCOPED banner (:132–141), deliberately non-strict summary
  (:456–458), separate `hook-test-results-scoped.md` — already fail-closed and
  labeled not-a-full-gate by construction (:5–15).
- Gate rule: UNCHANGED — final pre-commit/pre-deploy gate = full unscoped run;
  FF_ONLY is implement-loop only. The v1 plan to edit
  `flow-skills/validation-and-qa/SKILL.md` is DESCOPED; the run-tests.sh header rule
  (:5–15) stands as written.
- Contracts unchanged: strict `[run-tests] N/N PASS`, `exit $fail`, results-file
  Total/PASS/FAIL shape, FF_ONLY/FF_LIST semantics.
- Additive only: per-phase wall-time lines on STDERR (D14 step 1) — stderr keeps
  every stdout parse contract byte-clean (`progress()` precedent, :112).

## D8 — Phase inventory (all phases run in the default suite)

**v2: this is an inventory, not a tiering.** All 21 existing `test-*.sh` + the 2 new
tests run in the default (and only) suite:

| Test | Surface | v2 status |
|---|---|---|
| test-git-hooks-smoke.sh (NEW) | hooks/git wrappers (genuinely bash) | ADDED to default (D9) |
| test-hook-manifest.sh (NEW) | stamp/verify scripts | ADDED to default (T5) |
| test-module-size.sh, test-health-check-timeout.sh | shell scenario phases | unchanged (T8 retargets health-check-timeout content) |
| the 18 run_shell_phase scripts (:373–390) | upgrade tooling / installers / harness / pre-commit integration (genuinely bash) | unchanged position; D14 may apply behavior-preserving perf consolidation |
| test-cli-flow-recovery.sh | heavy recovery drive | unchanged position (exit-code phase, FF_SKIP_CLI_RECOVERY + 240 s bound); primary D14 optimization target |

Fold-into-python-runner candidates: NONE beyond the fixture phase itself — every
retained script tests a genuinely-bash integration surface (git hooks, installers,
upgrade engine, the harness), not handler logic; handler logic is already fixture-
covered. Honest classification over forced migration.

## D9 — Git-wrapper smoke set (new default-suite phase, single-pass WS5)

`hooks/tests/test-git-hooks-smoke.sh`, tag `git-smoke`, `PASS:/FAIL: git-smoke <name>`
contract; ONE temp repo built once (git init + config), scenarios sequential:
1. commit-msg blocks missing T-number (`feat: no ticket` ⇒ rc 1)
2. commit-msg allows docs prefix (`docs(flow): clarify X` ⇒ rc 0)
3. commit-msg allows T-numbered subject (`feat(x): T9 add y` ⇒ rc 0)
4. pre-commit §1 blocks staged `.env` (bash-only path ⇒ rc 1)
5. pre-commit passes a benign staged file end-to-end (rc 0; §2/§3 take the documented
   first-adoption fallback in a fresh temp repo — this exercises the full wrapper)
Budget: ≤ ~50 spawns, target ≤ ~30 s MSYS (measured in T9's per-phase table; it is a
D14 optimization subject like any other phase if it blows the budget). Deep §2/§3
trusted-HEAD coverage stays in test-secret-scan-staged.sh / test-trusted-enforcer.sh
— the smoke proves the wrappers run and gate, not every branch.

## D10 — CI + release gates (trust-model enforcement, AC4) — v3: in-repo publish gate

**Release mechanism ground truth (verified 2026-07-08).** PUBLISHING.md publishes a
public repo (Option 1 fresh-repo / Option 2 orphan-squash), pushes `main` + the
`v<version>` tag, then creates the GitHub Release from that tag — today via a MANUAL
`gh release create` (PUBLISHING.md:103, "Create the GitHub Release (mandatory…)").
Consumers obtain Flow via template-copy, `git clone` (optionally at the tag), or the
Release page; install.sh runs inside an already-obtained tree (no asset download).
So "publish a release" has two consumer-facing surfaces: **(1) the GitHub Release
object** — gateable entirely in-repo; **(2) the raw `v*` tag ref** — only gateable by
repo-admin settings (documented backstop, D10.4).

Both workflow files below are FR-07 ci_cd_config ⇒ ONE T6 commit under ONE D15
approval artifact whose `paths` lists both.

1. **Verify workflow becomes reusable:** `.github/workflows/fusebase-flow-verify.yml`
   `on:` = existing `push: {branches: [main]}` + `pull_request: {branches: [main]}` +
   `workflow_dispatch` + NEW **`workflow_call:`** (the release workflow calls this
   job — ONE definition of the full gate, zero step drift). v2's `push.tags: ["v*"]`
   and `release: {types: [published]}` triggers are **REJECTED/superseded** (v3/B4):
   `release: published` fires AFTER publication (gates nothing), and a bare
   tag-triggered verify run only *marks* a red tag — it cannot stop publication.
2. **Step order** (unchanged from v2 — sequential steps ⇒ a red step stops the job
   before the manifest is ever blessed): existing "Hook tests" step
   (`bash hooks/tests/run-tests.sh` — unchanged text; the default run IS the full
   suite per D7) → NEW "Runner parity"
   (`python3 hooks/tests/run_hook_tests.py --compare-subprocess`) → NEW "Hook-layer
   manifest freshness": `bash hooks/local/stamp-hook-manifest.sh` then
   `git diff --exit-code -- audit/hook-layer-manifest.json` (deterministic because D1
   stamping is byte-stable) then `bash hooks/local/verify-hook-manifest.sh` (stamp and
   verify must agree ⇒ exit 0) → existing working-tree-clean step remains the backstop.
3. **NEW release workflow — the in-repo publish gate:**
   `.github/workflows/fusebase-flow-release.yml` (exact content, LOCKED):
   ```yaml
   name: fusebase-flow-release
   on:
     push:
       tags: ["v*"]
   permissions:
     contents: read
   jobs:
     verify:
       uses: ./.github/workflows/fusebase-flow-verify.yml
     publish:
       needs: verify        # ← THE GATE: red verify ⇒ this job never runs
       runs-on: ubuntu-latest
       permissions:
         contents: write    # create the GitHub Release
       steps:
         - name: Checkout
           uses: actions/checkout@v6
         - name: Create GitHub Release (reachable only when verify passed)
           env:
             GH_TOKEN: ${{ github.token }}
           run: |
             tag="$GITHUB_REF_NAME"
             notes="docs/release-notes/${tag}.md"
             if gh release view "$tag" >/dev/null 2>&1; then
               echo "Release $tag already exists — nothing to publish."; exit 0
             fi
             if [ -f "$notes" ]; then
               gh release create "$tag" --verify-tag -t "$tag" -F "$notes"
             else
               gh release create "$tag" --verify-tag -t "$tag" --generate-notes
             fi
   ```
   Semantics: pushing `v*` runs the FULL verify suite on the tagged sha; `needs:
   verify` makes `publish` structurally unreachable when the suite is red ⇒ **no
   GitHub Release ever exists for a red sha**. Release creation is no longer manual:
   T11 REPLACES PUBLISHING.md:103's manual `gh release create` with "push the tag —
   the release workflow publishes the Release iff verify is green; manual
   `gh release create` is FORBIDDEN (it bypasses the gate)". Transient red ⇒ fix,
   then re-run the workflow from the Actions UI (same tagged sha); the
   `gh release view` guard + `--verify-tag` make re-runs idempotent.
   `docs/release-notes/v<version>.md` is the existing notes convention (files exist
   through v3.9.0); `--generate-notes` is the fallback when a notes file is absent.
4. **Honest enforcement boundary (what files can and cannot enforce).**
   IN-REPO (this ticket, primary): no GitHub Release — the consumer-facing
   publication object, Releases page entry, and notification surface — is ever
   published for a sha whose full hook-test suite is red. CANNOT be enforced by
   files: (a) the raw `v*` tag ref existing (git accepts tag pushes regardless of
   CI — a consumer doing `git clone --branch vX` before/without the Release gets
   unverified code); (b) a repo admin manually running `gh release create` in
   defiance of PUBLISHING.md. Both require repo-admin settings — documented as
   mandatory prerequisites in PUBLISHING.md § Release prerequisites (T11), each
   with its apply command:
   - `v*` **tag ruleset** requiring the `verify` status check on the tagged commit
     BEFORE the tag can be pushed (closes (a)):
     ```bash
     gh api repos/{owner}/{repo}/rulesets --method POST --input - <<'JSON'
     { "name": "v* tags require green verify", "target": "tag",
       "enforcement": "active",
       "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
       "rules": [ { "type": "required_status_checks", "parameters": {
             "strict_required_status_checks_policy": false,
             "required_status_checks": [ { "context": "verify" } ] } } ] }
     JSON
     ```
     (check context = the verify JOB name as Actions reports it — `verify`;
     PUBLISHING.md tells the operator to confirm the exact string against the
     repo's check runs before saving the ruleset);
   - **branch protection on `main`** requiring `verify` (kept from v2; `gh api`
     command + UI click-path stay in PUBLISHING.md).
   These are settings, not files — the release-workflow `needs:` gate is the
   PRIMARY enforcement and stands alone even if an operator forgets the settings.
5. Both PUBLISHING.md publication options inherit the gate automatically: `.github/`
   is on the public-surface allowlist, both workflows travel with the published
   tree, and the first `v<version>` tag push in the published repo triggers the
   gated release workflow there (`uses: ./…` resolves on the same ref, so verify +
   release always travel together).
6. AC4 evidence at the gate (G13): release-workflow structure (`on.push.tags:
   ["v*"]`; `jobs.verify.uses: ./.github/workflows/fusebase-flow-verify.yml`;
   `jobs.publish.needs: verify`; the publish step is the only `gh release create`
   under `.github/`), verify.yml `on:` contains `workflow_call:` and NOT `release:` /
   `tags:`, step order, and the PUBLISHING.md section — plus the optional
   red-fixture spot check on a scratch fork/tag.

## D11 — Upgrade propagation (AC5)

`upgrade.sh` CONTENT_DIRS already carries `hooks/` (⇒ runner, smoke, stamp/verify
scripts, lib, updated engine + run-tests). The manifest is NOT covered (`audit/` not
in the copy set; CONTENT_FILES today = `( "FLOW_RULES.md" )`, upgrade.sh:233) ⇒ add
`"audit/hook-layer-manifest.json"` to `CONTENT_FILES` and add
`mkdir -p "$(dirname "$f")"` before `cp` in the COPY loop (upgrade.sh:332–337; older
installs may lack `audit/`). The PLAN loop (:252–256) is read-only diffing — no mkdir
needed there (v2 precision fix; v1 said "both loops").
*Rejected:* adding all of `audit/` to CONTENT_DIRS — `skill-mirror-manifest.txt` etc.
are regenerated per-consumer by the mirror step; wholesale copy invites churn.
Verification is the T10 path-guarded consumer-sim script (v2/SF9) — staging source via
`git clone` (a supported source form per upgrade.sh:40); the sim runs POST-commit so
consumer + staging carry the T10 upgrade.sh.
**Known limitation (accepted, documented):** a real pre-v2 consumer runs its OLD
upgrade.sh once (CONTENT_FILES without the manifest): pass 1 refreshes `hooks/`
(incl. the new upgrade.sh + engine) but not the manifest ⇒ the engine reports
PARTIAL_UNVERIFIED "manifest absent (pre-upgrade install; run upgrade.sh)" (D4) —
the message IS the fix; pass 2 copies it. Pre-existing self-refresh pattern, not a
new defect; the absent class is exit 4 (never a crash, never false-HEALTHY).

## D12 — `.gitattributes`: pin `*.jsonl text eol=lf`

Prerequisite for raw-byte hashing: fixture transcripts (`fixtures/*_transcript.jsonl`)
are covered assets but `.jsonl` has no eol pin ⇒ `core.autocrlf=true` Windows clones
would check them out CRLF ⇒ deterministic false drift on every Windows install.
Pin + `git add --renormalize`. All other covered classes already pinned
(`*.py/*.sh/*.json` + explicit `hooks/git/pre-commit|commit-msg`).

## D13 — FR-25: engine at the 803-line ceiling ⇒ extract to a sourced lib

The engine may shrink, never grow. New `hooks/local/lib/hook-integrity-check.sh`
(sourced, shared-scope like active-approvals.sh) provides:
- `ffhc_hook_manifest_verify` — runs bounded verify, applies the D4 mapping into
  LOCAL_OK/LOCAL_BROKEN/LOCAL_UNVERIFIED/record_drift.
- `ffhc_hook_tests_deep_run` — the RELOCATED :393–458 classification (verbatim logic)
  with the D5 outcome mapping, gated by OPT_RUN_HOOK_TESTS.
Engine keeps ≤ ~15-line call sites; missing lib ⇒ the hook-integrity critical records
LOCAL_UNVERIFIED with a re-upgrade hint (degrade-sane, consistent with the absent-
manifest class; upgrade.sh copies hooks/ atomically so engine+lib travel together).
Net engine line count must be ≤ 803 (gate G12).

## D14 — AC3 budget: MEASURE → optimize named offenders → stop-and-report (never mask)

The deep run (`--run-hook-tests`) = full `run-tests.sh` (D5/D7); AC3 requires
**< 120 s wall on MSYS**. This is EMPIRICAL — the implementer measures on the real
Win11/Git-Bash box (task T9):

1. **Instrument (T5):** `run_bounded_phase` and `run_exitcode_phase` record
   `start=$SECONDS` and emit `[run-tests] <label> took <N>s` to **STDERR** after each
   phase (the `progress()` precedent, run-tests.sh:112 — stderr keeps every stdout
   parse contract byte-clean: strict summary, `^PASS:`/`^FAIL:` counting,
   `ffhc_select_pass_line`).
2. **Measure (T9):** bounded + backgrounded per R4/FR-27 — the exact
   launch/poll/deadline protocol is T9's command block (v3/NEW-3): Bash-tool
   `run_in_background: true` (fallback explicit `&` + PID file), self-recorded
   `rc=… wall=…s` done-file, short-command poll loop enforcing a 900 s wall
   watchdog, kill + INCONCLUSIVE(⇒ treat as ≥ 120 s ⇒ step 4) on breach. Never a
   bare foreground run.
3. **Feasibility facts (why <120 s is credible, not hoped):** two structural wins land
   BEFORE T9 — (a) the fixture fork-loop (21 fixtures × ≥3 MSYS spawns at ~0.8–1.4 s
   each) becomes one python process (seconds); (b) every phase that DRIVES the health
   engine inherits the fast manifest critical instead of a nested run-tests attempt:
   all of test-health-check-timeout.sh, and test-cli-flow-recovery.sh's two full
   engine drives at :496/:508 (today launched with `FFHC_TESTS_TIMEOUT=600`).
4. **If total ≥ 120 s — optimize offenders in measured-cost order.** Each
   optimization: behavior-preserving (same scenario names + assertions), its own
   commit, re-verified by running that script standalone then the full suite. Named
   candidates + levers (verified against source):
   - `test-cli-flow-recovery.sh` (954 lines) — inventory REGENERATED against source
     2026-07-08 (`grep -nE 'cp -R|cp -r|cp -a'` + per-hit inspection; v3/NEW-2 —
     v2's list wrongly counted :631/:672/:837 as full copies and missed :884/:926):
     - **10 FULL fixture-tree copies** `cp -R "$PROJECT" …` (the dominant cost;
       each duplicates the entire fixture): :256 (U10P flag-gated), :284 (U11P
       hooks-off), :323 (U12P skills-deleted), :349 (U19P legacy-leftover), :380
       (U13P agents-gap), :478 (F2P engine-hooks-off), :513 (U17P
       engine-flag-gated), :526 (U18P engine-agents-gap), :884 (CLAUDE_ONLY
       CLI-surface-absent), :926 (U20P skills→flow-skills migration).
     - **PARTIAL copies** (subset builds — smaller, second-order): :47/:48 +
       :55–:57 (one-time base `$PROJECT` setup: flow-skills, agents,
       hooks/local/lib, overlays, handlers); :350 (intra-U19P
       `flow-skills`→`skills` legacy copy); :631/:633 (LEGACY fixture build);
       :672/:674 (U9P fixture build); :837/:838/:842 (BAD_PROJECT fixture build);
       :934 (U20P `.fusebase-flow-source` staging).
     Levers, in measured-cost order: (1) every full-copy scenario applies only a
     SMALL mutation (rm/add of a few paths, or a settings.json write) then runs a
     read-only probe — replace N full copies with ONE shared copy + per-scenario
     mutate→assert→restore (restore = re-copy just the mutated paths from
     `$PROJECT`; same scenario names + assertions — behavior-preserving per this
     decision's rule); (2) the three repeated partial fixture builds
     (LEGACY/U9P/BAD_PROJECT each re-copy flow-skills+agents+overlays from repo
     root) collapse onto one prebuilt partial base; (3) drop the now-moot
     `FFHC_TESTS_TIMEOUT=600` inflation at :496/:508 (the manifest critical
     replaces the nested run-tests attempt); keep the `FF_CLI_RECOVERY_TIMEOUT`
     240 s bound + INCONCLUSIVE-on-timeout contract unchanged
     (run-tests.sh:400–427).
   - `test-cli-0259-compat.sh` (536 lines), `test-bootstrap-exception.sh` (615 lines),
     `test-secret-scan-staged.sh` (468 lines; 6 × `mktemp -d` fixture repos),
     `test-ws5-upgrade-bounded.sh` (358 lines; 3 × `mktemp -d`),
     `test-sync-allowlist.sh`, `test-bootstrap-baseline-hop.sh`: consolidate
     per-scenario temp repos into per-family shared fixtures (WS5 single-pass
     precedent); replace hot `$( … )` substitution chains with file redirects.
   - `test-health-check-timeout.sh` (post-T8): ensure every scenario drives the
     engine with `--no-upstream` + tight FFHC_* knobs.
5. **Forbidden AC3 "fixes":** scoping the deep run with FF_ONLY; letting any phase
   time out INCONCLUSIVE and calling the wall time met; raising `FFHC_TESTS_TIMEOUT`
   to hide the miss; deleting or skipping a phase. The suite must genuinely COMPLETE
   (strict `N/N PASS`, rc 0) under 120 s.
6. **Escalation:** if after optimizing every named offender the suite still measures
   ≥ 120 s, STOP — put the per-phase timing table in the gate report, mark G8/AC3
   FAIL; the PO reopens this decision. Do NOT reinterpret AC3.
7. Bound note: `FFHC_TESTS_TIMEOUT` defaults stay `ffhc_default_timeout tests`
   (120 s MSYS / 60 s POSIX — run-with-timeout.sh:83–89); the deep-run
   timeout⇒NOTE-only mapping (D5) is unchanged. A Linux deep run that exceeds 60 s
   behaves exactly as today (NOTE, verdict unaffected) — no regression; CI runs the
   suite directly, not through the engine.

**D14.8 — AC3 resolution (v4, supersedes the D14.6 BLOCKED escalation for MSYS).**
The T9 measurement confirmed the D14.6 escape: the full suite is ~950–1085 s on this
box, and phases *outside* this ticket's authorized levers (`liveness` 133 s,
`codex-parity` 48 s, `module-size` 16 s = 197 s) already exceed 120 s, so optimizing
every D14.4-named offender could never reach < 120 s. Rather than reinterpret AC3, the
orchestrator ruled `--run-hook-tests` **platform-adaptive** (D5/v3→v4 row): the MSYS
deep run is the FAST diagnostic (fixtures + git-smoke + hook-manifest, measured ~52 s
end-to-end incl. the base health check) — this satisfies AC3's literal wording
(*"on MSYS < 120 s via the single-process runner"*). The full MSYS suite is opt-in
(`--run-hook-tests-full` / `FFHC_RUN_HOOK_TESTS_FULL=1`); the DEFAULT `run-tests.sh`
stays FULL with CI Linux (G3) as the authoritative full-suite green. The D14.4 named
levers (cli-flow-recovery et al.) and the D14.6 escalation remain valid history but no
longer gate AC3 on MSYS.

## D15 — Protected-path approval-artifact lifecycle (deterministic; fixture 07 safety)

- Fixture `07_pre_tool_use_blocked_protected_path_edit.json` expects `deny`/FR-07.
  ANY active `state/approvals/protected_path_edit-*.json` legitimately flips
  pre_tool_use to allow ⇒ deterministic fixture-07 FAIL while the artifact exists.
- **T6 lifecycle (LOCKED):** author the artifact (v3: its `paths` lists BOTH
  workflow files — fusebase-flow-verify.yml AND fusebase-flow-release.yml; one
  artifact, one commit, no extra protected-path dance) → edit/create the two
  workflow files → commit (the
  pre-commit consumes the artifact) → **DELETE the artifact in the same task step**
  (`rm state/approvals/protected_path_edit-hook-manifest-ci-<YYYYMMDD>.json` — a
  single named file; not `rm -rf`) → prove
  `FF_ONLY=fixtures bash hooks/tests/run-tests.sh` shows fixture 07 PASS.
- **Standing rule R6 (tasks.md):** from T6 completion onward, EVERY
  run-tests / health-check / gate invocation is preceded by the zero-artifact guard:
  `find state/approvals -maxdepth 1 -name 'protected_path_edit-*.json' -print` must
  print nothing; if it prints, delete the leftover (this ticket authors exactly one)
  before running. Deterministic — never "time it carefully".
- Artifacts are disk-only (`.gitignore:5` = `state/approvals/*`) — no commit can
  carry one into CI. `health_check_deferral-*.json` is a different pattern and
  unaffected.
