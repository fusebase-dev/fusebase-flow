# Verification gate — cli-0.25.16-vendor-refresh

The implementer MUST pass every row below after T5, produce the gate report, and HALT (FR-05 — stop at gate; no VERSION bump, no push, no deploy). Run from repo root: `FLOW="/c/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition"`; CLI source `$SRC` as defined in tasks.md.

| # | Check | Command | PASS criterion |
|---|---|---|---|
| G1 | Preflight | `bash hooks/local/preflight.sh` | Final line `preflight finished — errors: 0, warnings: 0`; exit 0 |
| G2 | Byte-identity vs CLI source (7 skills × 2 mirrors) | `for m in .claude .agents; do for s in app-backend app-secrets app-sidecar fusebase-cli fusebase-gate fusebase-portal-specific-apps mcp-gate-debug; do diff -rq --strip-trailing-cr "$FLOW/$m/skills/$s" "$SRC/$s"; done; done` | Zero output (no `differ`, no `Only in`) |
| G3 | Provider-mirror parity (7 skills) | `for s in app-backend app-secrets app-sidecar fusebase-cli fusebase-gate fusebase-portal-specific-apps mcp-gate-debug; do diff -rq --strip-trailing-cr "$FLOW/.claude/skills/$s" "$FLOW/.agents/skills/$s"; done` | Zero output |
| G4 | Retired runbooks gone / new ref present (both mirrors) | Run the fenced **G4 block** below (predicate-based, self-failing) | Prints `G4 .claude PASS` AND `G4 .agents PASS`; any `FAIL` line = gate failure |
| G5 | Manifest self-match | `python3 -c "import json;d=json.load(open('audit/cli-vendor-manifest.json'));assert d['asset_count']==130,d['asset_count'];print('OK 130')"` | `OK 130` (was 132) |
| G6 | Health-check self-run | Run the fenced **G6 block** below (captures rc; asserts rc==0 AND verdict AND stale count in one predicate) | Prints `G6 PASS` — asserts exit 0 + verdict `HEALTHY` + `CLI_SNAPSHOT_STALE` count **0** together (a missed re-stamp/partial FR-A shows ~18 stale → `G6 FAIL`) |
| G7 | Full hook-test suite (bounded — FR-27: never launch bare; ~7-8 min wall) | `cd "$FLOW" && bash hooks/tests/run-tests.sh > /tmp/run-tests-gate.log 2>&1` — run backgrounded/bounded, poll the log for liveness (new PASS lines), then inspect the tail | Final `[run-tests] N/N PASS` with `0 FAIL`, no `INCONCLUSIVE` (baseline N=409 at review time; N/N all-green is the criterion, not the fixed number) |
| G8 | Sync-allowlist guard | `bash hooks/tests/test-sync-allowlist.sh` (also runs inside G7) | `[test-sync-allowlist] 5/5 PASS` |
| G9 | Stale-string sweep | `grep -rn "0\.25\.9" README.md docs/compatibility.md docs/fusebase-cli-edition.md audit/README.md hooks/local/stamp-cli-provenance.sh` | Only the KEPT dated history line `docs/compatibility.md:51` (2026-06-29 entry) matches |
| G10 | FR-C2 doc-pair atomicity | `grep -l "AGENTS.managed" docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md docs/fusebase-cli-edition.md` | BOTH files listed (caveat present in both) |
| G11 | Scope containment | `git log --stat` for T1..T5 commits + `git status --porcelain` + the fenced **G11 block** below on the T1 commit | 5 commits, each citing its task; T1 commit touches EXACTLY the 42 vendored path changes (36 modified + 4 deleted + 2 added, across both mirrors) + `audit/cli-vendor-manifest.json` (1 modified) = 43 paths (name-status 37 M / 4 D / 2 A) — `G11 T1-scope PASS` printed, nothing else in the commit; NO diff to FLOW_RULES.md, VERSION, `.claude-plugin/*`, `hooks/local/check-cli-flow-conflicts.sh` engine logic, `run-tests.sh:383` wiring, the 13 unchanged skills, `.claude/hooks/*`, `.claude/agents/*`, `.codex/*`; working tree clean |
| G12 | Shell/Python syntax (T4-touched files) | `bash -n hooks/local/stamp-cli-provenance.sh hooks/tests/run-tests.sh hooks/tests/test-cli-flow-recovery.sh hooks/tests/test-cli-0259-compat.sh && python3 -m py_compile hooks/local/fusebase-flow-overlays/settings-json-merge.py` | Exit 0 |
| G13 | T5 artifact discipline | `ls docs/changes/2026-07-07-cli-0.25.16-guidance-shift.md; git diff HEAD~1 --stat -- docs/changes/index.md docs/problem-catalog/` | Note exists; index.md UNCHANGED across the chain; problem-catalog/ UNCHANGED |

**Fenced check blocks** (run from repo root; `$FLOW` as above; commands moved out of the table so `||`/`|` stay copy-paste-exact):

```bash
# G4 — retired runbooks gone / new ref present (predicate-based; any FAIL line = gate failure)
for m in .claude .agents; do
  [ ! -e "$FLOW/$m/skills/fusebase-gate/references/isolated-sql-stores.md" ] \
    && [ ! -e "$FLOW/$m/skills/fusebase-gate/references/isolated-sql-rls-plan.md" ] \
    && [ -f "$FLOW/$m/skills/fusebase-gate/references/isolated-sql-integrator-troubleshooting.md" ] \
    && echo "G4 $m PASS" || echo "G4 $m FAIL"
done

# G6 — health-check self-run (asserts exit code + verdict + stale count together)
bash hooks/local/check-cli-flow-conflicts.sh --json . > /tmp/hc-gate.json; rc=$?
[ "$rc" -eq 0 ] && grep -q '"verdict": *"HEALTHY"' /tmp/hc-gate.json \
  && [ "$(grep -c CLI_SNAPSHOT_STALE /tmp/hc-gate.json)" -eq 0 ] \
  && echo "G6 PASS" || echo "G6 FAIL (rc=$rc)"

# G11 — T1-commit scope: 42 vendored path changes + manifest = 43 paths (37 M / 4 D / 2 A)
T1=<T1_SHA>   # substitute the T1 commit SHA
[ "$(git show --name-status --format= "$T1" | wc -l)" -eq 43 ] \
  && [ "$(git show --name-status --format= "$T1" | grep -c '^M')" -eq 37 ] \
  && [ "$(git show --name-status --format= "$T1" | grep -c '^D')" -eq 4 ] \
  && [ "$(git show --name-status --format= "$T1" | grep -c '^A')" -eq 2 ] \
  && echo "G11 T1-scope PASS" || echo "G11 T1-scope FAIL"
```

**Gate report contract:** per-task SHAs (T1–T5), the G1–G13 table with observed values (verbatim key lines: preflight final line, run-tests final line, verdict + stale count, asset_count), FR-22 comment-policy marker, FR-07 confirmation (FLOW_RULES/VERSION/plugin untouched), clean-room note (re-vendored assets stay CLI-owned; Flow attestation NOT asserted over them). Then **HALT** — an adversarial (Codex) review runs post-gate; the VERSION bump is Deploy-phase, operator-executed (tasks.md T-DEPLOY).

**Known-benign observations (do not chase):** `generated_at` in the manifest bumps to the run date; `source_cli_version` stays the literal `unknown` sentinel (UNVERIFIABLE_LOCALLY by design); run-tests wall time ~7-8 min is normal on this host (health-check-timeout suites dominate).
