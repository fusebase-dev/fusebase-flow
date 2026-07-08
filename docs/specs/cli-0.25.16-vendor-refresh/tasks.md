# Tasks — cli-0.25.16-vendor-refresh

One task = one commit (FR-03). Order is mandatory: T1 → T2 → T3 → T4 → T5. Hard dependencies: T3 and T4 (CO-1/CO-2) MUST follow T1; T2/T5 are order-flexible but keep the chain linear. T-DEPLOY is operator-executed after the gate + adversarial review — NOT part of the implement handoff.

Shell variables used throughout (Git Bash; quote everything — the repo path contains spaces):

```bash
FLOW="/c/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition"
SRC="/c/Users/Pavel/AppData/Local/Temp/claude/c--Users-Pavel-projects-fusebase-flow-publish-fusebase-flow-FuseBase-CLI-edition/87747019-2423-46c8-8a22-83ca9dccd322/scratchpad/cli-latest/apps-cli-main/project-template/.claude/skills"
```

## T1 — FR-A: atomic 0.25.16 re-vendor (ONE commit)

**Step 0 — source provenance (STOP if it fails; report BLOCKED-AT, do not guess):**

```bash
[ -d "$SRC" ] || { echo "BLOCKED: CLI source tree missing"; exit 1; }
grep -q '"version": "0.25.16"' "$SRC/../../../package.json" || { echo "BLOCKED: CLI source is not 0.25.16"; exit 1; }
[ -f "$SRC/fusebase-gate/references/isolated-sql-integrator-troubleshooting.md" ] || { echo "BLOCKED: troubleshooting ref missing from source"; exit 1; }
```

**Step 1 — surgical copy of the EXACT 18 changed files into BOTH mirrors (no `rm -rf`, no dir-level `cp -R`):**

```bash
FILES="
app-backend/SKILL.md
app-secrets/SKILL.md
app-sidecar/SKILL.md
fusebase-cli/SKILL.md
fusebase-cli/references/fusebase-json-schema.md
fusebase-gate/SKILL.md
fusebase-gate/references/app-magic-links.md
fusebase-gate/references/fusebase-auth.md
fusebase-gate/references/isolated-sql-migration-discipline.md
fusebase-gate/references/isolated-sql.md
fusebase-gate/references/isolated.md
fusebase-gate/references/membership.md
fusebase-gate/references/notes.md
fusebase-gate/references/portal-embed-context.md
fusebase-gate/references/tooling.md
fusebase-gate/references/users.md
fusebase-portal-specific-apps/SKILL.md
mcp-gate-debug/SKILL.md
"
for m in .claude .agents; do
  for f in $FILES; do cp "$SRC/$f" "$FLOW/$m/skills/$f" || exit 1; done
done
```

**Step 2 — delete the 2 retired runbooks from BOTH mirrors (single files, `rm -f`):**

```bash
for m in .claude .agents; do
  rm -f "$FLOW/$m/skills/fusebase-gate/references/isolated-sql-stores.md" \
        "$FLOW/$m/skills/fusebase-gate/references/isolated-sql-rls-plan.md"
done
```

**Step 3 — add the new troubleshooting ref to BOTH mirrors:**

```bash
for m in .claude .agents; do
  cp "$SRC/fusebase-gate/references/isolated-sql-integrator-troubleshooting.md" \
     "$FLOW/$m/skills/fusebase-gate/references/isolated-sql-integrator-troubleshooting.md" || exit 1
done
```

**Step 4 — re-stamp the vendor manifest (from `$FLOW`):**

```bash
cd "$FLOW" && bash hooks/local/stamp-cli-provenance.sh
```

**T1 verification (all must pass BEFORE committing):**

```bash
# (a) 7 skills byte-identical to CLI source, BOTH mirrors — expect NO output
for m in .claude .agents; do
  for s in app-backend app-secrets app-sidecar fusebase-cli fusebase-gate fusebase-portal-specific-apps mcp-gate-debug; do
    diff -rq --strip-trailing-cr "$FLOW/$m/skills/$s" "$SRC/$s"
  done
done
# (b) mirror parity — expect NO output
for s in app-backend app-secrets app-sidecar fusebase-cli fusebase-gate fusebase-portal-specific-apps mcp-gate-debug; do
  diff -rq --strip-trailing-cr "$FLOW/.claude/skills/$s" "$FLOW/.agents/skills/$s"
done
# (c) manifest self-match: asset_count 130
python3 -c "import json;d=json.load(open('audit/cli-vendor-manifest.json'));assert d['asset_count']==130,d['asset_count'];print('asset_count OK 130')"
# (d) health-check self-run: assert exit code + verdict + stale count (a missed re-stamp shows ~18 stale here)
bash hooks/local/check-cli-flow-conflicts.sh --json . > /tmp/hc-t1.json; rc=$?
[ "$rc" -eq 0 ] && grep -q '"verdict": *"HEALTHY"' /tmp/hc-t1.json \
  && [ "$(grep -c CLI_SNAPSHOT_STALE /tmp/hc-t1.json)" -eq 0 ] \
  && echo "HC OK" || echo "HC FAIL (rc=$rc)"
# (e) scope check: EXACTLY the 42 vendored path changes (36 modified + 4 deleted + 2 added) + audit/cli-vendor-manifest.json (1 modified)
#     Porcelain over the vendored areas + manifest = 43 lines (36 M + 4 D + 2 ?? + 1 M);
#     repo-wide tracked changes = 41 lines (excludes the 2 untracked adds; pre-existing ?? session artifacts don't count)
git -C "$FLOW" status --porcelain -- .claude/skills .agents/skills audit/cli-vendor-manifest.json
[ "$(git -C "$FLOW" status --porcelain -- .claude/skills .agents/skills audit/cli-vendor-manifest.json | wc -l)" -eq 43 ] \
  && [ "$(git -C "$FLOW" status --porcelain | grep -v '^??' | wc -l)" -eq 41 ] \
  && echo "SCOPE OK (42 vendored path changes + manifest)" || echo "SCOPE FAIL"
```

Commit: `feat(vendor): T1 atomic re-vendor 7 provider skills to CLI 0.25.16 (-2 gate runbooks, +1 troubleshooting ref, manifest 132->130)`

## T2 — FR-B + FR-C1 + FR-C2 + FR-D: doc corrections (ONE commit)

| Edit | File:line | Exact change |
|---|---|---|
| FR-B | `docs/fusebase-cli-edition.md:34-35` | Remove `.agents/skills/<cli-skill>/` and `.codex/agents/app-*.md` from the `fusebase update` writer row (0.25.16 `copyAgentsAndSkills` writes only `AGENTS.md` + `.claude/{skills,agents,hooks,settings.json}`; `ide-setup` writes only `.codex/config.toml`). Add them to the "Fusebase Flow snapshot" writer row (:35) — they are Flow-mirrored frozen copies |
| FR-C1 | `docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md:126-131` | The ":131 CUSTOM:SKILL extension points" bullet under "It does **not** include:" is stale. Rewrite: the 0.25.16 template DOES ship a `CUSTOM:SKILL:BEGIN/END` marker pair at template `AGENTS.md:40-42` — inside a **fenced usage example** (docs how-to, not a semantic extension point) — and the fence-agnostic `CUSTOM_BLOCK_REGEX` captures/restores it on update. Also refresh `:114` "Roughly 200 lines" to the measured 0.25.16 template length (`wc -l` the source template at edit time) |
| FR-C2a | `docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md` (insert near the update-effects table / "CLI behavior change" section, :77-:91) | Add managed-app caveat: `fusebase init --managed` appends an **unmarked** `AGENTS.managed.md` block to AGENTS.md; `fusebase update`/`product update` DESTROYS it (AGENTS.md overwritten; block carries no CUSTOM markers so it is not captured; only `init --managed` re-appends). Recovery is CLI-side (re-run `init --managed`). `post-fusebase-update.sh --refresh-overlays` writes a `.pre-refresh-<ts>` backup first |
| FR-C2b (atomic with C2a — both or neither) | `docs/fusebase-cli-edition.md` (Two-writer section, near :44-46) | Same caveat, condensed to the two-writer framing: the managed block is a third AGENTS.md writer surface with NO update-survival; unmarked → destroyed on update; recovery CLI-side; `.pre-refresh-<ts>` backup exists on `--refresh-overlays` |
| FR-D | `docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md:105` | Replace "`package.json` (root...) — NOT touched" with a managed-deps caveat: `fusebase update`/`product update` runs `syncManagedDependencies` mode `root`, rewriting ONLY the 2 managed SDK fields (`@fusebase/dashboard-service-sdk`, `@fusebase/fusebase-gate-sdk`) to the template spec (`^v2.3.28-sdk.1` at 0.25.16) unless `--skip-deps`; everything else in root package.json is preserved (resolves the internal inconsistency with the same doc's :81) |

Verification: `git diff --stat` touches exactly 2 files; C2 present in BOTH files; no other line regions changed.
Commit: `docs(freshness): T2 FR-B two-writer row, FR-C1 CUSTOM:SKILL example, FR-C2 managed-app caveat pair, FR-D root package.json managed-deps`

## T3 — FR-E: version strings (ONE commit; REQUIRES T1 landed)

Pre-check (refuse to start otherwise): `python3 -c "import json;assert json.load(open('audit/cli-vendor-manifest.json'))['asset_count']==130"`.

| File:line | Change |
|---|---|
| `README.md:533` | `FuseBase CLI 0.25.9` → `FuseBase CLI 0.25.16` (asset counts in the sentence stay: 20 provider skills, 2 app-agents, 4 quality hooks) |
| `README.md:544` | `the FuseBase CLI 0.25.9 wired set` → `the FuseBase CLI 0.25.16 wired set` (hook names unchanged) |
| `docs/compatibility.md:24` | `(FuseBase CLI 0.25.9)` → `(FuseBase CLI 0.25.16)` (count 40 = 20×2 unchanged) |
| `docs/compatibility.md:51` | KEEP the 2026-06-29 0.25.9 line verbatim; ADD below it: `2026-07-07 - FuseBase CLI 0.25.16 re-vendor; 7 provider skills refreshed (magic-link activation now platform-server-side, apps[].id declarative-optional, gate SDK ^v2.3.28-sdk.1); fusebase-gate drops isolated-sql-stores.md + isolated-sql-rls-plan.md, adds isolated-sql-integrator-troubleshooting.md; manifest 132->130 assets. Wired Stop set unchanged.` |
| `docs/fusebase-cli-edition.md:122` | `The FuseBase CLI 0.25.9 wired Stop set` → `The FuseBase CLI 0.25.16 wired Stop set` |
| `audit/README.md:11` | `(FuseBase CLI 0.25.9: 20 provider skills ...)` → `(FuseBase CLI 0.25.16: 20 provider skills ...)` |

Verification: `grep -rn "0\.25\.9" README.md docs/compatibility.md docs/fusebase-cli-edition.md audit/README.md` → ONLY the kept dated history line at `docs/compatibility.md:51`.
Commit: `docs(freshness): T3 FR-E bump 5 live CLI version strings 0.25.9->0.25.16 + dated re-vendor line`

## T4 — CO-1..CO-5 cosmetics (ONE commit; CO-1/CO-2 REQUIRE T1 landed)

| CO | File:line | Change |
|---|---|---|
| CO-1 | `hooks/local/stamp-cli-provenance.sh:5` | Header comment `(FuseBase CLI 0.25.9)` → `(FuseBase CLI 0.25.16)` (comment only; script output unaffected) |
| CO-2 | `hooks/tests/run-tests.sh:428` | Label `"cli-flow-recovery (0.25.9 model)"` → `"cli-flow-recovery (0.25.9-era wired-set model; unchanged through 0.25.16)"`. **Filename + `run-tests.sh:383` wiring UNCHANGED (D6)** |
| CO-2 | `hooks/tests/test-cli-flow-recovery.sh:79,218,223,226` | Comments/labels: annotate the 0.25.9 wired-set model as "unchanged through 0.25.16" (e.g. :79 `# FuseBase CLI 0.25.9 wired Stop set` → `# FuseBase CLI 0.25.9+ wired Stop set (unchanged through 0.25.16)`); assertion STRINGS may be relabeled but assertion LOGIC untouched. `:66/:74` `0.25.5` sentinels untouched (intentional fixtures) |
| CO-2 | `hooks/tests/test-cli-0259-compat.sh` (header comment block, ~:2-15) | Add one line: the 0.25.9-era model these tests encode (wired Stop set, flag-gates) is verified unchanged through CLI 0.25.16. **Filename KEPT (D6)** |
| CO-2 | `hooks/local/fusebase-flow-overlays/settings-json-merge.py:71` | Comment `CLI 0.25.9 wires its own Stop set` → `CLI 0.25.9+ (unchanged through 0.25.16) wires its own Stop set` |
| CO-3 | `docs/fusebase-health/ARCHITECTURE.md:21-22` | :21 — replace the stale `feature-*`/`fusebase-portal-specific-features` skill names with the current 0.25.16 set (`app-backend`, `app-dev-practices`, `app-routing`, `app-secrets`, `app-sidecar`, `fusebase-portal-specific-apps`, ...; count `~16` → `20`); :22 — `feature-architect.md`, `feature-create-checker.md` → `app-architect.md`, `app-create-checker.md` (D10) |
| CO-4 | `docs/fusebase-health/ARCHITECTURE.md` (short new paragraph near the ownership/engine discussion) | Document the CLI-side prune gates invisible to the present-file-only engine (D9 — docs, not JSON): `copy-template.ts` `FLAG_GATED_PATH_PREFIXES` = `managed-integrations/references/personal-auth-flow.md` ← flag `managed-integrations-personal-auth`, `examples/isolated-sql-rls` ← flag `postgres-rls`; plus the `audiences:` frontmatter prune gate (dashboards refs; currently inert — 0 vendored refs carry it). Note: absence of a path-gated ref is benign, never verdict-affecting |
| CO-5 | `.gitattributes` | Add `*.js        text eol=lf` (Config/data or script section) + 1-line tripwire comment: prevents 2 spurious advisory `CLI_SNAPSHOT_STALE` on Windows autocrlf clones (vendored `.claude/hooks/*.js` are LF; sha256-manifest-matched). No renormalize needed — repo files already LF in index |

Verification: `bash -n hooks/local/stamp-cli-provenance.sh hooks/tests/run-tests.sh hooks/tests/test-cli-flow-recovery.sh hooks/tests/test-cli-0259-compat.sh` all exit 0; `python3 -m py_compile hooks/local/fusebase-flow-overlays/settings-json-merge.py`; run-tests green at gate.
Commit: `chore(cosmetic): T4 CO-1..CO-5 relabels, ARCHITECTURE refresh, flag-gate docs, .js eol=lf`

## T5 — docs/changes tracking note (ONE commit; decided YES in D7)

Create `docs/changes/2026-07-07-cli-0.25.16-guidance-shift.md` (Mode B, ≤40 lines). Outline:

```
ticket: cli-0.25.16-vendor-refresh
class:  vendored-guidance shift record (CLI-owned content; no Flow behavior change)

What changed (0.25.9 -> 0.25.16 vendored provider guidance):
- AUTH/SIGN-IN: app magic-link activation moved SERVER-SIDE. Platform handles
  /_auth/magiclink/{key} (fusebase-gate activates on nimbus-ai, sets HttpOnly
  eversessionid/fbsfeaturetoken/fbsdashboardtoken cookies, 302s to stored
  redirectPath). SPA never calls activateAppMagicLink, never writes session
  cookies via JS; backend resolves the recipient from request cookies. Old
  0.25.9 guidance (SPA /link route calls activate, POSTs tokens in body) is
  RETIRED — apps built on it still work but follow the legacy /link forward.
- fusebase.json: apps[].id now declarative-OPTIONAL; the CLI writes it back on
  fusebase deploy. Never set manually / via an AI agent.
- Gate SDK managed spec: ^v2.3.28-sdk.1 (synced into root package.json by
  fusebase update / product update unless --skip-deps).
- fusebase-gate references: isolated-sql-stores.md + isolated-sql-rls-plan.md
  retired by the CLI; isolated-sql-integrator-troubleshooting.md added.

Why recorded: auth-domain guidance shift; this note is the dated Flow-side
marker for debugging apps built against the 0.25.9 model.
Provenance: CLI-owned vendored content, faithfully re-vendored (byte-copy).
No problem-catalog entry: platform evolution, not a Flow-solved problem (D8).
Spec: docs/specs/cli-0.25.16-vendor-refresh/
```

Do NOT append to `docs/changes/index.md` (Lightweight-lane ledger only). Do NOT create a problem-catalog entry (D8).
Verification: file exists, ≤40 lines body, index.md untouched, no `docs/problem-catalog/` diff.
Commit: `docs(changes): T5 record 0.25.16 vendored guidance shift (server-side magic-link, apps[].id, gate SDK)`

## T-DEPLOY — VERSION bump (OPERATOR-EXECUTED at Deploy phase; NOT in the implement handoff)

After the gate passes + adversarial review clears:

1. DP.1 approval artifact + DP.6 magic-phrase confirm per deploy policy.
2. FR-07 write-bootstrap-approval flow (`hooks/local/write-bootstrap-approval.sh` → `approve-local.sh`) — the bump rewrites FLOW_RULES.md's live banner string.
3. `echo 3.32.0 > VERSION` (LF, single line) → `bash hooks/local/sync-version-strings.sh` (rewrites the live attestation/banner strings in FLOW_RULES.md:57 / AGENTS.md:160 / CLAUDE.md:3 + allowlisted docs; re-mirrors).
4. Bump `.claude-plugin/plugin.json` `version` and `.claude-plugin/marketplace.json` `plugins[0].version` to `3.32.0` (preflight enforces ==VERSION parity).
5. `bash hooks/local/preflight.sh` → errors:0 warnings:0; commit (single FR-14 docs/release commit), tag `v3.32.0`, release per `release-deploy-reporting`.
