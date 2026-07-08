# Spec — cli-0.25.16-vendor-refresh

**Status:** DRAFT
**Created:** 2026-07-07
**Baseline:** FuseBase Flow v3.31.0 (branch `fix/msys-v3307-hardening`) · vendored CLI snapshot 0.25.9 · target CLI **0.25.16**
**Target release:** v3.32.0 (MINOR — precedent: 0.25.9 re-vendor shipped as MINOR v3.30.0)
**Source:** Adversarial compatibility review 2026-07-07 (Opus per-dimension report + Fable conclusion, Codex/Fable-vetted): **0 BREAK / 6 FRESHNESS / 5 COSMETIC**. Operator authorized executing ALL corrections + version bump. Review artifacts: scratchpad `compat-review-conclusion.md`, `opus-review-report.md`, `compat-evidence.md`.
**Re-vendor source tree:** `C:\Users\Pavel\AppData\Local\Temp\claude\c--Users-Pavel-projects-fusebase-flow-publish-fusebase-flow-FuseBase-CLI-edition\87747019-2423-46c8-8a22-83ca9dccd322\scratchpad\cli-latest\apps-cli-main` (`package.json` version 0.25.16; provider assets under `project-template/.claude/skills/`).

## Problem (proven)

Flow v3.31.0 is compatible with CLI 0.25.16 as-is (health check proven HEALTHY/exit 0 on real-shape 0.25.16 fixtures; every injected break still caught). But the vendored provider snapshot lags 0.25.9→0.25.16: **7 of 20 provider skills drifted (18 files)**, CLI retired 2 `fusebase-gate` runbooks and added 1 troubleshooting ref, and 5 live doc strings + 3 doc claims are stale. 0.25.16 ships genuine guidance changes agents should see: magic-link activation moved **server-side** (`/_auth/magiclink/{key}`, HttpOnly cookies; SPA never calls `activateAppMagicLink`), `apps[].id` became declarative-optional (CLI write-back on deploy; never set manually), gate SDK managed spec `^v2.3.28-sdk.1`, gate-runbook retraction. Drift never reaches live consumer files today (`flow_write_mode: never`) — all corrections are FRESHNESS.

Drift map re-verified 2026-07-07 against both trees with `diff -rq --strip-trailing-cr` (matches review exactly; both mirrors frozen at identical 0.25.9 content):

| Skill | Drifted files |
|---|---|
| app-backend | SKILL.md |
| app-secrets | SKILL.md |
| app-sidecar | SKILL.md |
| fusebase-cli | SKILL.md, references/fusebase-json-schema.md |
| fusebase-gate | SKILL.md + references/{app-magic-links, fusebase-auth, isolated-sql-migration-discipline, isolated-sql, isolated, membership, notes, portal-embed-context, tooling, users}.md (11 files) |
| fusebase-portal-specific-apps | SKILL.md |
| mcp-gate-debug | SKILL.md |
| **DELETE** (CLI retired) | fusebase-gate/references/isolated-sql-stores.md, isolated-sql-rls-plan.md |
| **ADD** (CLI new) | fusebase-gate/references/isolated-sql-integrator-troubleshooting.md |

Inbound-reference check (re-verified): the ONLY repo references to the 2 retired runbooks are inside vendored `mcp-gate-debug/SKILL.md` (both mirrors) — and the 0.25.16 `mcp-gate-debug` drops them and cites the new troubleshooting ref instead. The re-vendor self-heals the reference web; zero Flow-authored inbound refs.

## In scope (slices)

| Slice | What | Files | Class |
|---|---|---|---|
| **FR-A** (ATOMIC, all-or-none) | Re-vendor the 7 drifted skills into BOTH mirrors (`.claude/skills/` + `.agents/skills/`); delete 2 retired runbooks ×2; add 1 troubleshooting ref ×2; re-stamp `audit/cli-vendor-manifest.json` (asset_count 132→130) | **42 vendored path changes** (36 modified = 18 files ×2 mirrors, + 4 deleted = 2 runbooks ×2, + 2 added = 1 ref ×2) + `audit/cli-vendor-manifest.json` (1 modified) | FRESHNESS — BREAK-if-partial |
| **FR-B** | Two-writer table: `fusebase update` does NOT write `.agents/skills/` or `.codex/agents/` (0.25.16 `copyAgentsAndSkills` writes only AGENTS.md + `.claude/{skills,agents,hooks,settings.json}`; `ide-setup` writes only `.codex/config.toml`); move those 2 paths to the Flow-snapshot writer row | `docs/fusebase-cli-edition.md:34` | FRESHNESS |
| **FR-C1** | Stale "template ships no CUSTOM:SKILL markers": 0.25.16 template `AGENTS.md:40-42` ships a marker pair inside a **fenced usage example**; the fence-agnostic `CUSTOM_BLOCK_REGEX` captures/restores it. Phrase as usage example, NOT a semantic extension point. Optional same-line-region refresh: ":114 Roughly 200 lines" → measured 0.25.16 template length | `docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md:126-131` (+:114) | FRESHNESS |
| **FR-C2** (ATOMIC doc-pair) | Managed-app caveat in BOTH docs: `fusebase init --managed` appends an **unmarked** `AGENTS.managed.md` block that `fusebase update`/`product update` DESTROYS (AGENTS.md overwritten; block not CUSTOM-captured; re-appended only by `init --managed`). Recovery is CLI-side. Note the `.pre-refresh-<ts>` backup written by `post-fusebase-update.sh --refresh-overlays` | `docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md` (near :77-:91) AND `docs/fusebase-cli-edition.md` (Two-writer section, near :44-46) — both or neither | FRESHNESS |
| **FR-D** | Root `package.json` wrongly listed "Notably NOT touched": `syncManagedDependencies` mode `root` rewrites its 2 managed SDK fields on `update`/`product update` unless `--skip-deps` (only `@fusebase/dashboard-service-sdk` + `@fusebase/fusebase-gate-sdk`, re-synced to template spec `^v2.3.28-sdk.1`) | `docs/fusebase-health/CLI-CONFLICT-ANALYSIS.md:105` | FRESHNESS |
| **FR-E** (TAIL of FR-A — apply only AFTER FR-A lands) | 5 live strings 0.25.9→0.25.16: `README.md:533`, `README.md:544`, `docs/compatibility.md:24`, `docs/fusebase-cli-edition.md:122`, `audit/README.md:11`. At `docs/compatibility.md:51`: KEEP the dated 0.25.9 line, ADD a new dated 0.25.16 re-vendor line | 5 files | FRESHNESS (conditional on FR-A) |
| **CO-1..CO-5** | Cosmetics: stamp header, test labels (filenames KEPT — see decisions D6), ARCHITECTURE.md stale skill/agent names, flag-gate documentation, `.gitattributes` `*.js text eol=lf` | see tasks.md T4 | COSMETIC |
| **T5** | `docs/changes/` tracking note for the 0.25.16 guidance shift (auth-flow + SDK) — see evaluation 2 | `docs/changes/2026-07-07-cli-0.25.16-guidance-shift.md` | docs |
| **DEPLOY (operator-executed, NOT in implement handoff)** | VERSION 3.31.0→3.32.0 + `bash hooks/local/sync-version-strings.sh` + `.claude-plugin/{plugin,marketplace}.json` bumps. Touches FLOW_RULES.md live banner (FR-07 protected) → requires write-bootstrap-approval flow + DP.6 magic phrase + DP.1 approval artifact | VERSION, FLOW_RULES.md:57, AGENTS.md:160, CLAUDE.md:3, plugin.json, marketplace.json | release |

## Mandatory evaluation 1 — UX/UI + internal-vs-client

**Finding: NO app UI is authored by this ticket.** Every slice is framework-docs / vendored-asset / config maintenance; there is no application surface, no client- or internal-facing UI functionality created or updated. However, two vendored provider skills carry CLIENT-facing UX guidance:

- `fusebase-portal-specific-apps` (client portal UI guidance) — **in the drifted 7, being re-vendored.** Correct handling for client-facing vendored guidance is a FAITHFUL byte-copy of the CLI's 0.25.16 version. The CLI owns vendored provider content; Flow must NOT inject Flow UX opinions into it. The implementer preserves the CLI's client-UX guidance **verbatim** (enforced by the byte-identity gate: `diff -rq --strip-trailing-cr` vs CLI source = empty).
- `app-ui-design` (client app UI guidance) — **NOT in the drifted 7** (verified in the SAME-13 list; byte-identical to 0.25.16 already). **Untouched by this ticket.**

`client-vs-internal` steering does not activate (no `docs/audience.md` in this framework repo; no app surface in scope).

## Mandatory evaluation 2 — business-logic changes

The 0.25.16 vendored content changes business-behavior **guidance**: (a) magic-link activation is now SERVER-SIDE platform-handled at `/_auth/magiclink/{key}` (HttpOnly `eversessionid`/`fbsfeaturetoken`/`fbsdashboardtoken` cookies + redirect; SPA never calls `activateAppMagicLink`, never writes session cookies via JS; backend resolves the recipient from request cookies); (b) `apps[].id` is declarative-optional (CLI write-back on `fusebase deploy`; never set manually); (c) gate SDK managed spec `^v2.3.28-sdk.1`. These live in VENDORED CLI-owned content, not Flow-authored business logic; the review proved **zero Flow-authored reliance** (reliance grep empty on Flow-authored surfaces). No Flow business logic changes; `business-logic-guardian` does not apply (no consumer business-logic doc governs vendored provider guidance).

**Decision: a `docs/changes/` tracking note IS warranted (T5).** The guidance shift touches the auth/sign-in domain — the highest-blast-radius domain a consumer app team works in — and a dated Flow-side record of WHEN Flow's vendored guidance switched models (0.25.9 client-side → 0.25.16 server-side) is cheap (one small file) and directly useful when debugging older apps built against the 0.25.9 guidance. File + outline specified in tasks.md T5. Not added to the `docs/changes/index.md` ledger (that ledger is Lightweight-lane-only; this is a Full-lane ticket).

## Mandatory evaluation 3 — problem catalog

**Decision: NO problem-catalog entry; the T5 changes note is the right vehicle.** Justification: `docs/problem-catalog/` entries record platform/tooling problems Flow ENCOUNTERED and SOLVED (each existing entry is a named failure + diagnosis + fix). Here we did not fix a platform bug and did not solve a platform problem — the platform evolved its magic-link flow upstream and we are faithfully refreshing vendored guidance to match. A "we-fixed-X" catalog entry would misrecord provenance (the fix is CLI/platform-side) and pollute the catalog's retrieval value. The T5 note captures the same knowledge (what changed, when, why old guidance looks different) in the correct dated-changes home.

## Out of scope

- Any change to CLI behavior or CLI-owned content beyond faithful byte-copy (clean-room boundary: re-vendored assets stay CLI-owned; Flow attestation is NOT asserted over them — `docs/clean-room.md` / `docs/source-map.md` boundary unchanged).
- `post-fusebase-update.sh --refresh-overlays` order-B truncation hardening (splice only the marker-delimited region) — separate hardening ticket per review conclusion §6.3.
- Health-check engine changes (proven version-agnostic; verdict/exit contract, `ffhc_*` API, read-only/no-`fusebase`-calls guarantee all untouched).
- Test filename renames (D6: filenames kept; labels only).
- `hooks/tests/test-cli-flow-recovery.sh:66/:74` `0.25.5` sentinels (intentional older-CLI simulation fixtures — not stale strings).
- The 13 unchanged provider skills, CLI Stop hooks (4/4 identical), app-agents (2/2 identical), `.claude/settings.json.example` (wired set unchanged 0.25.9→0.25.16).

## Constraints (FR-07 / clean-room)

- Implement phase (T1–T5): NO diff to FLOW_RULES.md, VERSION, `.claude-plugin/*`, deploy-policy semantics, ratchet-governance.yml. The version bump is DEPLOY-phase, operator-executed, via the write-bootstrap-approval flow.
- FR-A is all-or-none within ONE commit: partial application (files without re-stamp, one mirror without the other, deletes without adds) is the single way this ticket can CREATE a break (manifest/tree/mirror inconsistency → false CLI_SNAPSHOT_STALE or stale certification).
- Surgical file operations only: `cp` of the 18 named files + `rm -f` of 2 named runbooks per mirror + `cp` of 1 named add per mirror. **No `rm -rf` of any skill directory** (destructive-op policy; protected-path git hooks also apply).
- Health check stays read-only; never calls `fusebase`.

## Acceptance criteria

- **AC1 (FR-A)** Each of the 7 re-vendored skill dirs is byte-identical to the CLI 0.25.16 source (`diff -rq --strip-trailing-cr` empty) in BOTH mirrors; the 2 runbooks are absent from both mirrors; the troubleshooting ref present in both; `audit/cli-vendor-manifest.json` re-stamped with `asset_count: 130`; health-check self-run (`bash hooks/local/check-cli-flow-conflicts.sh --json .`) → verdict HEALTHY + 0 `CLI_SNAPSHOT_STALE` (baseline today: HEALTHY + 0 stale; the criterion proves the re-stamped manifest self-matches the new tree — a missed re-stamp yields ~18 stale and fails this AC). All in ONE commit.
- **AC2 (FR-B/C/D)** `docs/fusebase-cli-edition.md:34` no longer attributes `.agents/skills/`/`.codex/agents/` to `fusebase update`; CLI-CONFLICT-ANALYSIS CUSTOM:SKILL claim corrected as fenced-usage-example; managed-app caveat present in BOTH docs (C2 pair complete); CCA:105 root-package.json corrected to the managed-deps caveat.
- **AC3 (FR-E)** All 5 live strings read 0.25.16; `docs/compatibility.md` has BOTH dated lines (0.25.9 kept + 0.25.16 added). Applied strictly after AC1.
- **AC4 (CO)** CO-1..CO-5 applied per decisions (filenames unchanged; run-tests wiring untouched at `run-tests.sh:383`; `.gitattributes` gains `*.js text eol=lf`).
- **AC5 (T5)** `docs/changes/2026-07-07-cli-0.25.16-guidance-shift.md` exists per outline; NOT in index.md ledger; no problem-catalog entry created.
- **AC6 (gate)** Full verification-gate.md passes: preflight errors:0 warnings:0 · run-tests all-green (N/N, 0 FAIL; bounded per FR-27) · sync-allowlist 5/5 · mirror parity for the 7 skills · manifest 130 · health self-run HEALTHY/0-stale.
- **AC7 (no-regression)** No diff outside the enumerated files; FLOW_RULES/VERSION/plugin files untouched at implement time; the 13 unchanged skills + hooks + agents byte-unchanged.

## Risks

| Risk | Mitigation |
|---|---|
| Partial FR-A (the review's only real hazard, F-6) | One atomic commit; ordering files→mirror→re-stamp; AC1 self-match gate catches a missed re-stamp; per-skill byte-identity catches a missed file/mirror |
| CLI source tree missing/stale at implement time (session scratchpad) | T1 step 0 verifies the tree exists AND `package.json` version == 0.25.16; BLOCKED-AT stop if not |
| `rm -rf` misuse on skill dirs | Explicit surgical `rm -f` of 2 named files per mirror; tasks give exact commands |
| FR-E landing before FR-A (falsely claims 0.25.16 over a 0.25.9 snapshot) | Task order T1→T3 hard dependency; gate re-checks manifest freshness before accepting T3 |
| Test relabels breaking run-tests parsing | D6 keeps filenames + wiring; labels/comments only; run-tests green in gate |
