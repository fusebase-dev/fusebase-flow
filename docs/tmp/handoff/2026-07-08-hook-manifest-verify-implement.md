# Implement handoff — hook-manifest-verify (AI Developer) — v3

Date: 2026-07-08 · Ticket: hook-manifest-verify · Lane: Full · Phase: Implement
(v3: design revised after the Codex re-check of v2 — closure maps in decisions.md
§ Revision log, v1→v2 AND v2→v3; do not consult v1/v2 snapshots of these docs.)

## Role bootstrap (do this first, in order)

1. Read `AGENTS.md` + `CLAUDE.md`; read `FLOW_RULES.md` STOPPING at `## Amendment log`.
2. Read `flow-skills/role-discipline/SKILL.md` + `references/ai-developer.md`; emit the
   AI Developer self-attestation.
3. Mandatory ticket reads (in order):
   - `docs/specs/hook-manifest-verify/spec.md` (DRAFT v3 — the contract)
   - `docs/specs/hook-manifest-verify/decisions.md` (LOCKED D1–D15 v3 — do not re-decide)
   - `docs/specs/hook-manifest-verify/tasks.md` (the T-chain you execute, T1–T12)
   - `docs/specs/hook-manifest-verify/verification-gate.md` (G1–G13 — where you STOP)
4. Ground-truth files before editing (verify cited line ranges still hold):
   `hooks/tests/run-tests.sh` (fixture phase :143–289; FF_TAGS :44–47; run_shell_phase
   list :373–390; run_exitcode_phase :400–428; summary contract :451–463),
   `hooks/local/fusebase-flow-health-check.sh` (exit table :34; hook-test critical
   :387–458; exit dispatch :796–803), `hooks/local/lib/run-with-timeout.sh`
   (`ffhc_default_timeout` :83–89 — preflight 60/30, tests 120/60 MSYS/POSIX),
   `hooks/local/stamp-cli-provenance.sh` (wrapper pattern; NOTE: its `generated_at`
   is NOT copied — D1 is byte-stable by design), `hooks/local/upgrade.sh`
   (CONTENT_FILES :233; copy loop :332–337; `.fusebase-flow-source` contract :40,
   :170), `.github/workflows/fusebase-flow-verify.yml` (`on:` = push main /
   pull_request / workflow_dispatch — NO tag or release triggers today; job name
   `verify` — the check context the documented ruleset references; step list),
   `policies/protected-paths.yml` (:93–100 startup-file patterns; § exception_artifact),
   `policies/command-policy.yml` (:14 — typed `rm -rf` is a hard deny; shapes how you
   run the T10 sim), two fixtures (01, 07, 18) + `hooks/handlers/pre_tool_use.py`
   (:177 `raise SystemExit(main())` — the exit-code path the parity gate compares),
   `hooks/shared/policy_loader.py` (reset_cache), `PUBLISHING.md` (T11 target —
   § After publication :99–105; the manual `gh release create` at :103 is what T11
   REPLACES; the allowlists show `.github` ships with the published tree, so the
   gate travels), `docs/release-notes/` (naming convention `v<version>.md`, files
   exist through v3.9.0 — drives release.yml's `-F`-vs-`--generate-notes` fallback).

## Scope rules (hard)

- **FR-07 — NEVER modify:** `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`,
  `policies/*.yml`, `FLOW_RULES.md`, any `sitecustomize.py`. The runner DRIVES the
  handlers in-process; the smoke test EXECUTES the git wrappers; neither edits them.
  Tamper tests (T2/T7/G6) use uncommitted edits reverted immediately via
  `git checkout -- <file>` — never staged, never committed.
- **Protected-path commit (T6 only)** — deterministic artifact lifecycle (D15):
  author `state/approvals/protected_path_edit-hook-manifest-ci-<YYYYMMDD>.json`
  (fields per protected-paths.yml § exception_artifact; cite this handoff in
  `approved_by`; `paths` lists BOTH workflow files —
  `[".github/workflows/fusebase-flow-verify.yml",
  ".github/workflows/fusebase-flow-release.yml"]` — ONE artifact for the ONE T6
  commit, no second protected-path dance) → commit → **immediately `rm` the
  artifact** → prove fixture 07 PASS
  (`FF_ONLY=fixtures bash hooks/tests/run-tests.sh`). Then R6 (below) forever after.
  Do not disable or bypass hooks; NEVER `--no-verify`.
- **R6 (zero-artifact pre-test guard):** from T6 on, before EVERY run-tests /
  health-check / gate command:
  `find state/approvals -maxdepth 1 -name 'protected_path_edit-*.json' -print`
  must print nothing (an active artifact deterministically fails fixture 07, which
  expects deny/FR-07).
- **No version bump, no release, no tag push, no deploy, no repo-settings changes**
  — Deploy phase / operator own them. NEVER run `gh release create` yourself: from
  T6 on, Release creation belongs EXCLUSIVELY to fusebase-flow-release.yml's gated
  `publish` job (a manual create bypasses the AC4 `needs: verify` gate). T11 only
  DOCUMENTS the repo-admin backstops (`v*` tag ruleset + `main` branch protection,
  each with its `gh api` apply command) in PUBLISHING.md § Release prerequisites;
  applying them is operator-owned.
- **NO framework-skill edits.** v1's `flow-skills/validation-and-qa/SKILL.md` edit is
  DESCOPED (no tier concept exists since v2 — D7). `flow-skills/**`, `.claude/skills/**`,
  `.agents/**` stay untouched; no mirror regeneration.
- **Coverage superset invariant (D7/AC6):** the default `run-tests.sh` must keep
  EVERY existing phase. You may not add `--full`/`--core`/`FF_FULL` flags or a
  `Tier:` line. `FF_LIST=1` must show 24 tags, all RUN.
- Backwards-compat invariants (any violation = stop and report): `--fast` ⇒ exit 4;
  engine exit map 0/1/2/3/4 + verdict names unchanged (3 = EXCEPTION_IN_EFFECT);
  strict `[run-tests] N/N PASS` + `exit $fail` unchanged; scoped FF_ONLY runs stay
  fail-closed non-strict; the standalone verifier uses exit **4** (never 3) for
  "manifest absent".

## Execution — ordered task chain

Execute `docs/specs/hook-manifest-verify/tasks.md` T1→T11 exactly; T-numbers, exact
file ops, and per-task verification commands are specified there. One task = one
commit (T9: zero commits if the measured budget already passes; else one commit per
optimized script). Standing rules R1–R6 apply to every task — especially **R1: every
commit touching a covered path re-runs `bash hooks/local/stamp-hook-manifest.sh` and
stages `audit/hook-layer-manifest.json` in the same commit** (otherwise CI's
freshness gate and your own T7 HEALTHY check fail).

Summary of the chain (authority = tasks.md):

| T | Commit delivers |
|---|---|
| T1 | `.gitattributes` `*.jsonl` LF pin (+ renormalize check) |
| T2 | `hooks/local/lib/hook_manifest.py` (byte-stable stamp, NO generated_at; verify rc 0/1/2/4; extra-file Scans A+B) + `stamp-hook-manifest.sh` + `verify-hook-manifest.sh` + committed `audit/hook-layer-manifest.json` |
| T3 | `hooks/tests/run_hook_tests.py` (single-process runner; `--compare-subprocess` asserting the TRIPLE exit_code/decision/rule_id) + run-tests.sh fixture phase rewired (ALL other phases untouched) |
| T4 | `hooks/tests/test-git-hooks-smoke.sh` (5 scenarios, tag `git-smoke`) |
| T5 | run-tests.sh: +2 run_shell_phase entries + FF_TAGS (24 tags) + per-phase `took Ns` STDERR timing lines; `hooks/tests/test-hook-manifest.sh` (6 scenarios incl. Scan B startup-file + rc 4 absent + byte-idempotence) |
| T6 | Release gate, PROTECTED ×2 files under ONE D15 artifact: verify.yml `on:` gains `workflow_call:` ONLY (NO `tags:`/`release:` — v2 approach superseded, v3/B4) + runner-parity step + manifest-freshness step (ORDER: tests → parity → freshness → … → tree-clean); NEW fusebase-flow-release.yml — `v*` tag push → `verify` job (`uses: ./.github/workflows/fusebase-flow-verify.yml`) → `publish` job with `needs: verify`, the sole `gh release create` under `.github/`; D15 artifact lifecycle (author with BOTH paths → commit → rm → fixture-07 proof) |
| T7 | `hooks/local/lib/hook-integrity-check.sh` + engine rewrite (manifest critical with D4 mapping incl. verifier-4 ⇒ UNVERIFIED; `--run-hook-tests` = FULL suite; engine ≤ 803 lines) |
| T8 | `test-health-check-timeout.sh` retargeted (absent ⇒ 4; self-hash ⇒ 2; tamper ⇒ 1; deep-run timeout ⇒ note-only; failing-suite stub ⇒ 2) |
| T9 | D14 MEASURE on this box — bounded/backgrounded per T9 Steps 1–3 verbatim (`run_in_background: true` launch, start/done files, short-command poll loop enforcing the 900 s watchdog; a bare foreground run is FORBIDDEN, v3/NEW-3); per-phase timing table; optimization commits ONLY if ≥ 120 s (corrected offender inventory + levers in D14.4, v3/NEW-2); STOP-and-report if still over |
| T10 | upgrade.sh CONTENT_FILES + mkdir guard in the copy loop; path-guarded consumer-sim script proof (`PROPAGATION OK`) |
| T11 | docs/hook-coverage.md trust-model §, compatibility.md, PUBLISHING.md — NEW § Release prerequisites (enforced: `v*` tag-ruleset + branch-protection `gh api` apply commands, confirm-check-context note, honest boundary) AND § After publication :103 REPLACED (push the tag — the gated workflow publishes; manual `gh release create` FORBIDDEN), CHANGELOG (Unreleased). NO skill/mirror edits |

Liveness (FR-27): never launch a potentially-long run bare. Full-suite runs on this
MSYS box run backgrounded with output to files, polled (T9 Steps 1–3 are the exact
protocol — done-file completion signal, 900 s watchdog enforced by the poll loop);
bound heavy phases via `FF_PHASE_TIMEOUT` / `FF_CLI_RECOVERY_TIMEOUT`;
`FF_SKIP_CLI_RECOVERY=1` is acceptable for iteration but NEVER for the G2/G8/T9
measurements (D14.5) — the CI PR run is the Linux full proof (G3).

## Gate + STOP

After T11, execute `verification-gate.md` G1–G13 in order (T12), with the R6
preamble before every command. Then STOP: post the gate report and WAIT for the
operator. Do not deploy, tag, bump VERSION, change repo settings, or flip the spec
status.

## Gate-report shape (Mode B)

```
# Gate report — hook-manifest-verify — <UTC timestamp>
Branch/HEAD: <branch> @ <short-sha>   Commits: T1..T11 (list sha + subject; T9 may be absent/multiple)
| G | Verdict | Evidence |
|---|---------|----------|
| G1..G13 | PASS/FAIL | command → rc, timing, key output lines (G2/G5/G8 include wall time + the D14 per-phase table; G4 includes the 21/21 triple-parity tail; G3 links the green CI run; G13 quotes release.yml's `on.push.tags` / `needs: verify` / `uses:` lines, verify.yml's `on:` block, and the two PUBLISHING.md headings) |
Deviations from decisions.md: <none | list with justification — a deviation without a reopened decision is a FAIL>
Residual risks / notes: <...>
STOPPED AT GATE — awaiting operator (deploy + version bump are Deploy-phase).
```

## Known hazards (verified during design — do not rediscover the hard way)

- Engine is AT the FR-25 803-line ceiling — all new logic goes into
  `hooks/local/lib/hook-integrity-check.sh` (sourced, shared scope like
  `active-approvals.sh`); the engine may only shrink (G12).
- `.jsonl` fixtures are covered assets; without T1's LF pin, Windows
  `core.autocrlf=true` checkouts hash-drift them (false FLOW_LAYER_DRIFT). T1 must
  land BEFORE the first manifest stamp (T2).
- **Byte-stable stamp is load-bearing (B3):** no `generated_at`, fixed key order,
  `indent=2`, trailing `\n`, `newline="\n"` on write. If you copy the
  stamp-cli-provenance.sh date field out of habit, CI's freshness gate goes red the
  day after every merge. G9 `cmp`-checks this.
- `hooks/local/*.local.*` are operator overrides preserved by upgrade.sh — they must
  be EXCLUDED from the manifest (D2) or every customized consumer reads drifted.
  BUT Scan B (startup-file tripwire) has NO exclusions — a `sitecustomize.py`
  anywhere under `hooks/` is DRIFT even if named `*.local.*`-adjacent (D3).
- Handlers bind `from shared.audit_logger import emit` at import — do NOT try to
  monkeypatch audit logging (D6 keeps it unpatched; state/audit.log.jsonl is
  gitignored and today's subprocess runs already append to it).
- **Exit-code parity (B5):** handlers exit via `raise SystemExit(main())`
  (pre_tool_use.py:177 et al.) — capture `e.code` with CPython normalization
  (None→0, int→value, other→1). The parity triple is (exit_code, decision, rule_id);
  comparing stdout alone is a v1 defect, do not regress to it.
- The python runner must keep the synthetic `_parse-invariant` row (D6) and keep
  assertion semantics exact (decision exact, rule_id exact, rule_id-contains
  substring, each only when non-empty). Fixtures carry no `_expected_exit_code` —
  normal mode asserts decision/rule_id; parity mode asserts the triple.
- **Fixture 07 vs approval artifacts (B7):** fixture 07 expects deny/FR-07 and FAILS
  while ANY active `state/approvals/protected_path_edit-*.json` exists. This is
  solved DETERMINISTICALLY: T6 deletes its artifact immediately after the commit,
  and R6 asserts zero artifacts before every subsequent test/gate run. Never rely on
  timing; never "fix" the fixture.
- **Verifier exit codes (SF8):** standalone verify = 0/1/2/4; exit 3 is RESERVED
  (the engine's public exit 3 = EXCEPTION_IN_EFFECT, engine :34/:798). If you find
  yourself writing `exit 3` in hook_manifest.py, stop.
- **Typed `rm -rf` is hook-denied (SF9):** command-policy.yml:14 hard-denies it in
  agent-typed commands. The T10 consumer sim runs as a SCRIPT whose only recursive
  removal is the path-guarded `safe_rm_tmp` on its own `${TMPDIR:-/tmp}/ffhc-t10.*`
  mktemp root (precedent: test-ws5-upgrade-bounded.sh:86). Type only
  `bash <scratchpad>/t10-consumer-sim.sh`; run it AFTER the T10 commit (the sim
  clones the repo, so both consumer and staging must carry the committed T10
  upgrade.sh).
- `run_with_timeout` cannot wrap bash FUNCTIONS (upgrade.sh precedent) — the verify
  call in the engine wraps the SCRIPT via `ffhc_run_bounded_stdout`.
- D14 measurement discipline: the two structural speedups (single-process fixtures;
  engine-driving phases inheriting the fast manifest critical — incl.
  test-cli-flow-recovery.sh's engine drives at :496/:508) land BEFORE T9. Measure
  first; optimize only what the per-phase table indicts; each perf commit is
  behavior-preserving (same scenario names + assertions). The offender inventory in
  D14.4 was REGENERATED against source in v3 (NEW-2): 10 FULL `cp -R "$PROJECT"`
  copies (:256/:284/:323/:349/:380/:478/:513/:526/:884/:926) vs the PARTIAL builds
  (:47–:57 base, :350, :631/:633, :672/:674, :837/:838/:842, :934) — do not work
  from the stale v2 list.
- **T9 measurement liveness (v3/NEW-3):** the full-suite measurement is NEVER a bare
  foreground `bash hooks/tests/run-tests.sh`. Use T9 Steps 1–3 verbatim: launch via
  the Bash tool's `run_in_background: true` writing start/done files (fallback:
  explicit `&` + PID file), poll with short foreground commands only (no `sleep`, no
  `wait`), and enforce the 900 s watchdog IN THE POLL LOOP (now vs recorded start
  epoch — nothing on the suite side enforces it). On breach: kill/stop, record
  INCONCLUSIVE, treat as ≥ 120 s. MSYS `kill` may orphan grandchildren — note leaked
  PIDs in the report; never re-launch bare.
- **Do NOT add `tags:` or `release:` triggers to verify.yml (v3/B4):** the v2 design
  did, and it gates nothing — `release: published` fires AFTER publication, and a
  bare tag-triggered verify only marks a red tag without stopping the Release. The
  release workflow reaches verify via `workflow_call:`; re-adding tag triggers would
  also double-run the suite on every tag. T6's verify step checks the `on:` block
  contains NEITHER.
- **Release creation is workflow-owned from T6 on:** the `needs: verify` edge in
  fusebase-flow-release.yml IS the AC4 enforcement — typing `gh release create`
  manually bypasses it (forbidden; PUBLISHING.md says so post-T11). Transient red on
  a tag ⇒ fix on main, re-run the release workflow from the Actions UI on the same
  tag (idempotent: `gh release view` guard + `--verify-tag`). The `v*` tag ruleset +
  branch protection are documented operator actions (D10.4) — you never apply repo
  settings.
