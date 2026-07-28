# Verification gate — approval-binding-and-upgrade-classification

**Linked spec:** `docs/specs/approval-binding-and-upgrade-classification/spec.md`
**Linked tasks:** `docs/specs/approval-binding-and-upgrade-classification/tasks.md`
**Gate task:** T15
**Pass threshold for smoke:** 5/5 PASS

## Acceptance-criterion → task mapping

| AC | Implemented in | Test coverage |
|---|---|---|
| AC1 body/filename action agreement | T3 | `test-approval-binding.sh` — action-mismatch case |
| AC2 parsed, mandatory expiry | T2, T9 | `test-approval-binding.sh` — expiry verdict table (missing/empty/null/int/malformed/past/future) |
| AC3 type-safe malformed handling | T2, T3 | `test-approval-binding.sh` — array/string/number/non-dict top level; assert no exception escapes |
| AC4 root-anchored policy resolution | T3 | `test-command-policy.sh` — foreign-CWD parity |
| AC5 fail-closed regex + empty policy | T4 | `test-command-policy.sh` — broken pattern in each of deny/require_approval/allow; empty policy |
| AC6 all-matching actions, one denial | T4, T6 | `test-command-policy.sh` — `fusebase deploy && npx prisma migrate deploy` |
| AC7 SQL case-insensitive + ALTER TABLE | T7 | `test-command-policy.sh` — lower/upper DROP, ALTER TABLE |
| AC8 Lightweight gate parity, both handlers | T7 | `test-command-policy.sh` + handler fixtures via `run_hook_tests.py` |
| AC9 binding enforced when present | T5 | `test-approval-binding.sh` — digest match/mismatch, repo mismatch, absent-field legacy |
| AC10 safe writer | T8 | `test-approval-binding.sh` — adversarial slug/reason, unknown action, traversal slug |
| AC11 cross-carrier expiry | T10 | `test-bootstrap-exception.sh` (green, unweakened) + new no-expiry path-artifact case |
| AC12 inventory | T9 | `test-approval-binding.sh` — four-verdict fixture dir + strict reject count |
| AC13 base manifest + 10-state classification | T11, T12 | `test-upgrade-conflict-classification.sh` — byte-stable stamp, verify, full K9 matrix |
| AC13b base synthesis + post-apply refresh | T12, T13 | same — two consecutive upgrades; untouched file refreshes on first run |
| AC13c per-file apply | T12 | same — mixed-class directory case |
| AC14 denial message (UX) | T6 | handler fixtures — per-verdict distinct reason, ≤8 lines, stale ≠ absent |
| AC15 conflict report (UX) | T12 | `test-upgrade-conflict-classification.sh` — every `consumer-only` path literally present; safe groups collapsed |
| AC16 4.6.1 patched-validator preserved + reported | T13 | `test-upgrade-conflict-classification.sh` — end-to-end fixture; expects `changed-by-both` |
| AC17 full gate green | T15 | CI sequence below |
| AC18 zero mirror drift | T14 | `mirror-skills.sh && mirror-agents.sh && git diff --exit-code` |
| AC19 truthful trust model | T1 | grep assertion — no authorship-enforcement claim in the three canonical files |

## Required gate-report fields

Per `policies/gate-contracts.yml: gate_report`; the AI Developer produces the report from `templates/gate-report.md`. Do not restate the field list here.

## Lint / typecheck / test commands

| Layer | Command |
|---|---|
| Preflight | `bash hooks/local/preflight.sh` |
| Full hook + shell suite (UNSCOPED — no `FF_ONLY`) | `bash hooks/tests/run-tests.sh` |
| Python fixture parity | `python3 hooks/tests/run_hook_tests.py --compare-subprocess` |
| Hook manifest freshness | `bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json` |
| Hook manifest verify | `bash hooks/local/verify-hook-manifest.sh` |
| Managed-content manifest | `bash hooks/local/stamp-managed-content-manifest.sh && git diff --exit-code audit/managed-content-manifest.json && bash hooks/local/verify-managed-content-manifest.sh` |
| Mirror drift | `bash hooks/local/mirror-skills.sh && bash hooks/local/mirror-agents.sh && git diff --exit-code` |
| Rule inventory | `bash hooks/local/rule-inventory.sh` |
| Module size (FR-25) | `bash hooks/local/check-module-size.sh --all` |

A scoped run (`FF_ONLY=...`) is **not** acceptable as the gate. The gate report may cite only `state/audit/hook-test-results.md`, never `hook-test-results-scoped.md`.

## Worker-undisturbed paths (this ticket)

Every path below is `fusebase_flow_internals` in `policies/protected-paths.yml`. This ticket edits them **by design**, so each commit is authorized through the FR-07 bootstrap approval (`bash hooks/local/write-bootstrap-approval.sh` → commit → `--consume`), never `--no-verify`. Empty diff is therefore **not** expected on these; what is required is that every commit carries a digest-bound approval.

- `hooks/shared/**`
- `hooks/handlers/**`
- `hooks/local/**`
- `policies/**`
- `audit/**`
- `flow-skills/**` and their `.claude/skills/**` / `.agents/skills/**` mirrors

Empty diff **is** required on: `hooks/git/**` (git fallback hooks — untouched by this ticket), `templates/**`, `.claude/settings.json.example` (no PostToolUse added; K11 defers consumption).

## Smoke prompts (post-deploy)
<!-- prevents: false-green-deploy — taxonomy: policies/ratchet-governance.yml (A3). Outcome + ground-truth columns are the safety-bearing part. -->

Smoke runs against a **fresh clone of the released tag in a scratch directory with hooks wired** — not the development tree — because the defect being fixed is precisely one that only appears on a consumer install. Evidence dir: `docs/tmp/handoff/2026-07-28-approval-binding-and-upgrade-classification-smoke/`.

| ID | Scenario | Route / surface | Operator-visible success criterion | Ground-truth diagnostic | Stable selectors | Auth / test data plan | Adversarial check | Evidence required |
|---|---|---|---|---|---|---|---|---|
| S1 | Replayed unrelated approval no longer authorizes a deploy | `bash hooks/local/run-handler.sh pre_tool_use` with a `fusebase deploy` command | Hook **denies**; message names `production_deploy` and states the artifact's action did not match | `state/audit/*.log` hook decision entry showing verdict `ACTION_MISMATCH` | N/A | Scratch clone; hand-written artifact `production_deploy-other-20260728.json` with body `{"action":"database_migration"}` | Same run on 4.6.1 must **allow** — proves the fix, not the fixture | command transcript + audit-log excerpt |
| S2 | Expiry-less legacy artifact is visible and rejected under strict | `bash hooks/local/approve-local.sh --inventory`, then strict run | Inventory row shows `legacy-no-expiry` and `verdict(strict)=REJECT`; with `strict_approvals: true` the deploy is denied | Inventory stdout + hook decision entry | N/A | Scratch clone; artifact with `expires_at` key absent | With strict OFF the same artifact is **allowed and logged** — proves K7 compat, not silent acceptance | inventory stdout + both decision entries |
| S3 | Documented Lightweight deploy actually passes the gate | `pre_tool_use` and `permission_request` with `fusebase deploy` | Both handlers **allow** with only a `lightweight_deploy` artifact present | Decision entries from both handlers | N/A | `bash hooks/local/approve-local.sh lightweight_deploy smoke-ll 'ship it'` | Removing the artifact denies through both handlers; a `production_deploy` artifact also allows | two decision entries per case |
| S4 | Consumer's patched validator survives an upgrade, and the upgrade still delivers content | `bash hooks/local/bootstrap-upgrade.sh` on a 4.6.1 fixture carrying a locally edited `hooks/shared/command_policy.py` | Report lists that exact path under **`changed-by-both`**; the local edit is **still present**; AND a file the fixture never touched **was** refreshed to 4.7.0 | `git diff` of the fixture tree + `grep` for the sentinel + `sha256sum` of an untouched control file | N/A | Scratch 4.6.1 clone; sentinel comment inserted into the validator; a control file recorded before the run | Same fixture through the **old** `upgrade.sh` loses the edit — proves the classifier preserved it. The control file proves base synthesis worked and the run was not a silent no-op | report stdout + pre/post `sha256sum` of both files |
| S5 | Compound command cannot smuggle an ungated migration | `pre_tool_use` with `fusebase deploy && npx prisma migrate deploy` | Denied; the single message names **both** `production_deploy` and `database_migration` | Decision entry listing `required_actions` with two entries | N/A | Valid `production_deploy` artifact present, no migration artifact | Same command on 4.6.1 is **allowed** by the deploy artifact alone | command transcript + decision entry |

### S1: Replayed unrelated approval no longer authorizes a deploy

Steps:
1. `git clone --branch v4.7.0 <repo> /scratch/s1 && cd /scratch/s1 && cp .claude/settings.json.example .claude/settings.json`
2. Hand-write `state/approvals/production_deploy-unrelated-20260728.json` with body `action: database_migration` and a far-future `expires_at`
3. Pipe a `fusebase deploy` tool-use payload into `bash hooks/local/run-handler.sh pre_tool_use`

Expected: exit/decision `deny`.
Pass criterion: stdout names `production_deploy` as required AND states the artifact's body action did not match its filename. A generic "no artifact found" is a **FAIL** — that is the AC14 regression.
Ground-truth diagnostic: the audit-log decision entry carrying verdict `ACTION_MISMATCH`, not just stdout.
Auth / test data plan: scratch clone only; no shared state; delete `/scratch/s1` after.
Adversarial check: run the identical payload and artifact against a 4.6.1 clone — it must **allow**. If 4.6.1 also denies, the fixture is wrong and S1 proves nothing.
Evidence dir: `docs/tmp/handoff/2026-07-28-approval-binding-and-upgrade-classification-smoke/S1-*.{log,md}`

### S2: Expiry-less legacy artifact visible and rejected under strict

Steps:
1. Scratch clone as S1; write an artifact with the `expires_at` key **absent**
2. `bash hooks/local/approve-local.sh --inventory`
3. Run the deploy payload with `strict_approvals: false`, then with `true`

Expected: inventory names the file with `legacy-no-expiry`; compat allows-with-log; strict denies.
Pass criterion: all three observations hold. Compat silently allowing with **no** log entry is a FAIL — K7 requires the acceptance be auditable.
Ground-truth diagnostic: inventory stdout plus both audit-log decision entries.
Adversarial check: the compat-mode allow must appear in the audit log; absence means the legacy path is silent, which is the pre-fix behaviour.
Evidence dir: `.../S2-*.{log,md}`

### S3: Documented Lightweight deploy passes the gate

Steps:
1. Scratch clone; `bash hooks/local/approve-local.sh lightweight_deploy smoke-ll 'ship it'`
2. Run a `fusebase deploy` payload through `pre_tool_use` **and** `permission_request`
3. Delete the artifact; repeat. Mint `production_deploy` instead; repeat.

Expected: allow / allow, then deny / deny, then allow / allow.
Pass criterion: all six observations. This is the direct regression for the contradiction where four shipped documents promised a gate the policy denied.
Ground-truth diagnostic: decision entries from both handlers — testing only `pre_tool_use` misses the `permission_request` path entirely.
Evidence dir: `.../S3-*.{log,md}`

### S4: Consumer's patched validator survives an upgrade that still delivers content

Steps:
1. Clone 4.6.1 to `/scratch/s4`; insert a sentinel comment into `hooks/shared/command_policy.py`; `sha256sum` it. Also `sha256sum` an untouched **control** file that 4.7.0 changes (e.g. `hooks/local/upgrade.sh`).
2. Run the documented adoption path (`bash hooks/local/bootstrap-upgrade.sh`) targeting 4.7.0
3. Re-`sha256sum` both; `grep` the sentinel

Expected: report lists `hooks/shared/command_policy.py` under **`changed-by-both`**; sentinel still present; its hash unchanged. Control file hash **changed** to the 4.7.0 content.
Pass criterion: all four observations. Two distinct failure modes are being excluded at once — (i) sentinel gone = the overwrite defect is unfixed; (ii) control file unchanged = base synthesis failed, every path fell to `unknown-base`, and the "successful" upgrade silently installed nothing. A run that preserves everything is **not** a pass.
Preserved-but-unreported is also a **FAIL** (AC15 — the consumer's core complaint was not being told which files diverged).
Ground-truth diagnostic: pre/post `sha256sum` of both files plus the report stdout.
Adversarial check: the same fixture through the old 4.6.1 `upgrade.sh` must lose the sentinel. If it survives there too, the test is not exercising the overwrite path.
Evidence dir: `.../S4-*.{log,md}`

### S5: Compound command cannot smuggle an ungated migration

Steps:
1. Scratch clone; mint a valid `production_deploy` artifact only
2. Run `fusebase deploy && npx prisma migrate deploy` through `pre_tool_use`

Expected: deny, one message naming both required actions.
Pass criterion: both action names in a **single** message. Two serial denials (deny, fix, deny again) is a FAIL per AC14.
Ground-truth diagnostic: decision entry with a two-element `required_actions`.
Adversarial check: identical run on 4.6.1 must allow.
Evidence dir: `.../S5-*.{log,md}`

## Probes (post-deploy)

| ID | Probe | Pass criterion | Evidence |
|---|---|---|---|
| G-M | Release tag + version sync | `VERSION` = 4.7.0; both plugin manifests match; `bash hooks/local/sync-version-strings.sh` leaves an empty diff | command transcript |
| G-N | Fresh-clone preflight | `bash hooks/local/preflight.sh` exits 0 on a clean clone of the tag | transcript |
| G-O | Full suite on the released tag | `bash hooks/tests/run-tests.sh` reports `[run-tests] N/N PASS` (unscoped) | `state/audit/hook-test-results.md` |
| G-P | Both manifests verify on the released tag | `verify-hook-manifest.sh` and `verify-managed-content-manifest.sh` exit 0 | transcript |
| G-Q | Spec flip + backlog index in one docs commit | `git log -1 --stat` shows spec DRAFT→DONE, tasks SHAs, backlog index together | `git log` |

## Manifest version bump

Old: `4.6.1`
New: `4.7.0`
Reason: behaviour-tightening security change to the FR-12 command gate plus a new upgrade-classification engine and a new committed manifest — minor bump, not patch. Not 5.0.0: strict schema stays OFF this release (K7), so no consumer's existing approvals break on upgrade.

## Rollback procedure
<!-- prevents: irreversible-loss (catastrophic-low-frequency) — taxonomy: policies/ratchet-governance.yml -->

**Rollback surface:** `code-only`. No migration, no secrets, no sidecar, no cross-app contract. `audit/managed-content-manifest.json` is generated, not state — it regenerates from source at any tag. Legacy approval artifacts are never mutated (K7), so a rollback finds consumer artifacts exactly as it left them.

If any probe fails:
1. `git revert <deploy hash>` → re-tag. Consumers who already adopted 4.7.0 stay safe: the classifier only ever *preserves* more than the old engine, so a partial fleet is not a hazard.
2. Re-verify with G-N and G-O on the reverted tag.
3. File a follow-up backlog ticket.
4. Spec stays DRAFT until the follow-up resolves.

**Specific rollback hazard:** a consumer who upgraded and *relied* on the new gate denying something would silently lose that denial on downgrade. Release notes must state that downgrading from 4.7.0 restores the replayable gate.

## Cross-artifact consistency check (mandatory before approving deploy)

```
Constitution invariants verified:
☐ Worker-undisturbed list — touched: hooks/**, policies/**, audit/**, flow-skills/** (by design; FR-07 bootstrap approval per commit)
☐ Mixed-fleet considerations — T9 compat mode, T12 unknown-base preserve, T13 ≤4.6.1 adoption hop
☐ Migration approach — no data migration; two-stage schema rollout (K7); legacy artifacts never auto-mutated
☐ Auth model — unchanged and now truthfully documented (K3): schema/expiry/action/binding enforced, operator identity NOT
☐ Quality bar — 3 new test files, all registered in FF_TAGS; run_hook_tests.py EXPECTED_HANDLER_FIXTURES updated

Cross-artifact:
☐ Every AC1..AC19 (incl. AC13b, AC13c) exercised in at least one task
☐ Every locked decision K1..K17 cited in at least one task
☐ K13 base lifecycle proven both ways: synthesis on first run, refresh after apply
☐ All clarify Q-A..Q-D resolved in spec.md
☐ All T1..T14 have SHAs filled in
☐ No TODO/FIXME/WIP markers in diff
☐ Spec status still DRAFT (flips to DONE in T16)
☐ FR-25: check-module-size.sh --all clean; command_policy.py and path_policy.py did not grow past their seams
☐ AC18: mirror-skills.sh + mirror-agents.sh produce empty diff
```

If ANY item fails, redirect the AI Developer. Do NOT bypass.
