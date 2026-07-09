# Verification gate — hook-manifest-verify (v3)

All gates must pass before the ticket may be reported complete. Evidence = command +
observed output (rc, timing, key lines) captured in the gate report. Host: this
Windows 11 + Git-Bash box unless a gate says CI.

**Preamble (R6/D15, applies before EVERY gate command):**
`find state/approvals -maxdepth 1 -name 'protected_path_edit-*.json' -print` must
print nothing; if it prints, delete the leftover artifact first (fixture 07 fails
deterministically while one is active).

| G | Gate | Command / evidence | Pass condition |
|---|---|---|---|
| G1 | Preflight clean | `bash hooks/local/preflight.sh` | 0 errors / 0 warnings |
| G2 | FULL default suite green (CI-authoritative) + superset invariant (D7 + D14 v4) | backgrounded `bash hooks/tests/run-tests.sh` (per T9); `FF_LIST=1 bash hooks/tests/run-tests.sh`; CI (G3) | strict `[run-tests] N/N PASS`, rc 0 — the authoritative full-suite green is **CI Linux (G3)**; on MSYS the default suite stays FULL and its wall is DIAGNOSTIC, not a `< 120 s` gate (the `< 120 s` budget attaches to the adaptive deep run, G8/v4); `FF_LIST=1` shows **24 tags all RUN** (22 pre-ticket + git-smoke + hook-manifest — superset invariant); per-phase `took Ns` stderr table captured |
| G3 | Full suite green in CI | PR CI run of `fusebase-flow-verify` | ALL steps green in order: preflight → hook tests → runner parity → manifest freshness → module-size → mirror drift → public-surface → working-tree clean |
| G4 | In-process ≡ subprocess parity (D6 gate, B5) | `python3 hooks/tests/run_hook_tests.py --compare-subprocess` on MSYS AND in CI | 21/21 fixtures identical **(exit_code, decision, rule_id)**, rc 0 on both |
| G5 | AC1 — full HEALTHY on Windows | `time bash hooks/local/fusebase-flow-health-check.sh --no-upstream` | verdict HEALTHY, exit 0, < 60 s |
| G6 | AC2 — tamper/corrupt/absent triad | T7 verify block (append byte to `hooks/shared/git_utils.py` → revert; corrupt `manifest_self_sha256` → restore; `mv` manifest away → restore) | exit 1 FLOW_LAYER_DRIFT naming the exact file; exit 2 BROKEN; exit 4 PARTIAL_UNVERIFIED "manifest absent" (standalone verifier rc 4, never 3 — SF8); no crashes |
| G7 | Backwards compat | `--fast` ⇒ exit 4 + fast-mode banner; `--skip-hook-tests` alias identical; `--help` lists `--run-hook-tests` + `FFHC_MANIFEST_TIMEOUT`; unknown arg ⇒ exit 2; verdict names unchanged (HEALTHY / *_DRIFT / SHARED_MERGE_DRIFT / EXCEPTION_IN_EFFECT / BROKEN / PARTIAL_UNVERIFIED / PARTIAL_UPGRADE); engine exit map 0/1/2/3/4 unchanged (3 = EXCEPTION_IN_EFFECT untouched) | all observed |
| G8 | AC3 — deep run bounded budget, PLATFORM-ADAPTIVE (D14 v4) | `time bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests` (+ `--run-hook-tests-full` on MSYS) | **MSYS:** the FAST diagnostic (single-process fixtures + git-smoke + hook-manifest) COMPLETES, HEALTHY/0, **< 120 s** (measured ~52 s end-to-end). **POSIX/CI:** the FULL `run-tests.sh`, HEALTHY/0. `--run-hook-tests-full` / `FFHC_RUN_HOOK_TESTS_FULL=1` forces the full suite on MSYS too (bounded; a `FFHC_TESTS_TIMEOUT=1` timeout ⇒ NOTE, verdict STILL HEALTHY/0 — an optional check never forces exit 4). A forced-FAIL deep run ⇒ BROKEN/exit 2 on whichever path the platform takes. The base verdict is never gated on the deep run |
| G9 | Manifest BYTE idempotence + freshness (B3) | `bash hooks/local/stamp-hook-manifest.sh; cp audit/hook-layer-manifest.json "${TMPDIR:-/tmp}/m1.json"; bash hooks/local/stamp-hook-manifest.sh; cmp audit/hook-layer-manifest.json "${TMPDIR:-/tmp}/m1.json"`; `git diff --exit-code -- audit/hook-layer-manifest.json`; `grep -c generated_at audit/hook-layer-manifest.json` | cmp identical (byte-stable — NO "modulo generated_at" allowance); committed manifest current; grep count 0 (no timestamp fields); verify MATCH rc 0 |
| G10 | No FR-07 protected-logic diff | `git diff <base>...HEAD --stat -- hooks/handlers hooks/shared hooks/git policies FLOW_RULES.md` | EMPTY (zero lines) |
| G11 | AC5 — upgrade propagation | T10 consumer-sim script (path-guarded, SF9) | prints `PROPAGATION OK`; cleanup removed only the mktemp root |
| G12 | FR-25 discipline | `wc -l hooks/local/fusebase-flow-health-check.sh` ≤ 803; `bash hooks/local/check-module-size.sh --all`; new files < 800 lines | all pass |
| G13 | AC4 — release publication gated IN-REPO (B4, v3) | Inspect `.github/workflows/fusebase-flow-release.yml` + `.github/workflows/fusebase-flow-verify.yml`; `grep -rn "gh release create" .github/`; `grep -n "Release prerequisites" PUBLISHING.md` + read § After publication; optional scratch-fork spot-check (fork + deliberately red test + push `v0.0.0-test` tag ⇒ verify fails ⇒ publish job SKIPPED ⇒ no Release object) | release.yml structure: `on.push.tags == ["v*"]`; `jobs.verify.uses: ./.github/workflows/fusebase-flow-verify.yml`; `jobs.publish.needs: verify` (the gate edge — publish structurally unreachable while verify is red); grep shows EXACTLY ONE `gh release create` under `.github/` (the publish step). verify.yml `on:` contains `workflow_call:` and contains NEITHER `release:` NOR `tags:` (v2 triggers superseded — they gate nothing and would double-run); step order tests → parity → manifest-freshness → tree-clean. PUBLISHING.md: § Release prerequisites (enforced) present with BOTH repo-admin apply commands (`v*` tag ruleset requiring the `verify` check — D10.4 `gh api` JSON — and `main` branch protection) + the confirm-check-context note + the honest files-cannot-close-these boundary (raw tag ref; manual-create bypass); § After publication instructs tag-push-only and marks manual `gh release create` FORBIDDEN |

Gate-report requirements: G-table with per-gate verdict + evidence; timings for
G2/G5/G8 plus the D14 per-phase timing table; the parity output tail for G4 (showing
the triple); the CI run link for G3; G13's quoted gate lines (release.yml
`on.push.tags` / `needs: verify` / `uses:`, verify.yml `on:` block, the two
PUBLISHING.md headings); the R6 preamble check noted once. STOP at the gate —
deploy, version bump, tag push, ruleset/branch-protection setup, and spec
DRAFT→DONE are operator/Deploy-phase actions.
