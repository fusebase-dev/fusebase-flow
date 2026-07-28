# Verification gate — approval-binding-and-upgrade-classification

**Linked spec:** `docs/specs/approval-binding-and-upgrade-classification/spec.md`
**Linked tasks:** `docs/specs/approval-binding-and-upgrade-classification/tasks.md`
**Gate task:** T15
**Pass threshold for smoke:** 6/6 PASS (S4 split into S4a/S4b — see § Smoke prompts)

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
| AC3 *(revised — corrections round)* incl. extreme-offset totality | T17 | `test-approval-binding.sh` — `9999-12-31T23:59:59-14:00` / `+14:00` lower bound → `MALFORMED`, no exception; both handlers |
| AC9 *(revised — K6 rev)* strip-only digest, one-command binding | T18, T22 | `test-approval-binding.sh` — quoted-interior-whitespace pair hashes DIFFERENTLY; strip-only equivalence retained |
| AC11 *(tightened)* compat acceptance audited; strict honored by every carrier | T23 | `test-bootstrap-exception.sh` + `test-approval-binding.sh` — compat audit-log entry; strict deferral excluded from `ACTIVE_ARTIFACTS` |
| AC20 per-rule requirements, no display-name dedup | T19 | `test-command-policy.sh` — `fusebase deploy && git push origin main` + `lightweight_deploy` only → deny |
| AC21 denial names ALL required actions | T20 | `test-command-policy.sh` — deploy+migration with deploy artifact: both actions in one message; `all_required_actions`=2, `unsatisfied_actions`=1 |
| AC22 `--command` mandatory for command-gated actions; bound resolving invocation | T22 | `test-approval-binding.sh` — no `--command` → exit 2, no file; emitted invocation round-trips to allow |
| AC23 classifier-unavailable fails closed | T25 | `test-upgrade-conflict-classification.sh` — classifier-less run aborts; tree-wide no-write; `--unsafe-legacy-copy` is the only legacy route |
| AC24 no self-restamp of a diverged base | T26 | same — restamp advice absent from preflight/help text; tag-synthesized base preserves the local edit |
| AC25 bootstrap writes nothing before classification authorizes | T27 | same — aborted hop leaves consumer tree byte-identical (modulo base manifest + log) |
| AC26 `rm` gap closed; regex evasion documented | T28 | `test-command-policy.sh` — `rm build.log` denies; limitation cases linked to backlog; header/docs grep |
| AC27 inventory never `ACCEPT`s a gate-rejected artifact | T24 | `test-approval-binding.sh` — foreign `repo_id` → `REJECT (BINDING_MISMATCH)`; command-bound → `UNCHECKED` |
| AC6/AC16 *(coverage repair)* discriminating fixtures | T29 | fixtures 22/23 satisfied-first-action; AC16 incident file genuinely `changed-by-both`; `core.autocrlf=true` fixture |

## New acceptance criteria (corrections round — canonical text lives here; spec.md AC1..AC19 unchanged)

| AC | Contract | Decision |
|---|---|---|
| AC20 | Every matching `require_approval` rule is evaluated independently; requirements are never de-duplicated by display action. `fusebase deploy && git push origin main` with only a `lightweight_deploy` artifact is **denied** naming `production_deploy`. | K18(a) |
| AC21 | A denial carries `all_required_actions` (every action any matched rule demands) distinct from `unsatisfied_actions`; the single message renders the full set with per-action status; both lists reach the audit log. | K18(b) |
| AC22 | `approve-local.sh` exits 2 and writes nothing when `--command` is absent for an action reachable from a `command-policy.yml` `require_approval` rule; non-command-gated actions are unaffected. The denial message's resolving invocation includes `--command '<safely quoted blocked command>'`, so the documented path always mints a bound artifact. | K19 |
| AC23 | When the target version ships the classifier and it cannot run (no python3 / module unavailable), `upgrade.sh` aborts non-zero writing nothing. Legacy whole-directory copy is reachable only via `--unsafe-legacy-copy`, which no diagnostic suggests. A genuinely pre-classifier source tree still upgrades. | K20(a) |
| AC24 | No Flow tooling advises restamping the base manifest from the consumer's current tree. Missing base → `bootstrap-upgrade.sh` (tag-sourced synthesis); drifted base → recovery only from the exact prior upstream tag/package, else paths stay `unknown-base` (preserved). | K20(b) |
| AC25 | `bootstrap-upgrade.sh` executes the fetched engine from the source clone/staging dir and writes NO managed consumer path before classification authorizes it; an aborted hop leaves the consumer tree byte-identical except `audit/managed-content-manifest.json` (the classifier's own input, documented) and logs. | K10, K20 |
| AC26 | The `rm` `require_approval` pattern gates flagless deletes (`rm build.log`). `policies/command-policy.yml` header and `docs/hook-coverage.md` state that matching is regex over the raw command string, defeatable by quote-fragmentation and dynamic construction; `docs/backlog/command-gate-shell-evasion/README.md` exists and is indexed. | K21 |
| AC27 | `--inventory` is truthful under K17: `repo_id` is validated against the inventory's own root (mismatch → `REJECT (BINDING_MISMATCH)`); an artifact whose only unverifiable element is `command_digest` reports `UNCHECKED (command-bound)`, never `ACCEPT`. | K7, K17 |

Revised existing ACs (supersede in place, FR-18): **AC3** additionally requires totality over extreme-but-valid ISO offsets (no `OverflowError` escape). **AC9** binds via `sha256(command.strip())` — strip-only, no interior whitespace collapse (K6 REVISED); interior-whitespace variants inside quoted arguments are DIFFERENT commands. **AC11** additionally requires every compat acceptance of a legacy artifact to be audit-logged and `strict_approvals` to be honored by `path_policy` AND `active-approvals.sh`.

## Regression discriminators (anti-tautology contract — corrections round)

Each corrected **defect** names the concrete assertion that FAILS against the pre-correction code. A corrections commit whose new test would also pass on the old code does not close its finding.

**Scope of the claim (corrected 2026-07-28 after re-review).** The contract binds **defect discriminators**, not every assertion added in the round. The honest split:

| Class | Status vs `808db35` | Examples |
|---|---|---|
| Defect discriminators (T17..T28) | **RED before, GREEN after** — verified | overflow escape · digest collision · display-dedup bypass (`allow`!) · unbound mint · `only_when` AttributeError · `match_order` fallthrough · inventory false ACCEPT · classifier fallback · restamp advice · bootstrap pre-writes · `rm build.log` |
| Coverage repairs | **GREEN before by design** — they close a *coverage* gap, not a behaviour gap | `core.autocrlf=true` fixture (the flag already worked — see the struck EOL row); command-policy compat-audit (that carrier already logged) |
| Negative / supporting controls | **GREEN before, intentionally** — they prove the fix did not over-reach | both-artifacts→allow · non-command-gated writer action · pre-classifier source still upgrades · `rm  build.log` (double space) |
| Known-weak, retained honestly | **GREEN before** — documented as not proving what a reader might assume | static handler fixtures 22/23 (carry no artifact, so first-match and all-match both deny; `run_hook_tests.py` runs fixtures from the repo root, so a fixture cannot carry its own `state/approvals/`) · `t29-compound-first-action-satisfied-still-denies` (`808db35` already handled distinct displays) |

The earlier blanket phrasing — "every corrections assertion is RED against `808db35`" — was **overstated** and is superseded. Every *defect* discriminator is red; controls and coverage repairs are green by construction and are labelled as such rather than counted as proof.

| Defect (review ref) | Discriminating assertion | Pre-correction result |
|---|---|---|
| `parse_expiry` OverflowError (BLOCKER, `approval_artifact.py:94`) | `evaluate_artifact({..., "expires_at": "9999-12-31T23:59:59-14:00"}, expected_action=a) is Verdict.MALFORMED` | raises `OverflowError` |
| K6 collapse collision (BLOCKER, `approval_artifact.py:110`) | `digest('fusebase deploy --app "safe  prod"') != digest('fusebase deploy --app "safe prod"')` | digests equal |
| Unbound default mint (BLOCKER, `approve-local.sh:139`) | `approve-local.sh production_deploy s1 r` without `--command` → exit 2, approvals dir unchanged | exit 0, unbound artifact written |
| Unbound resolving invocation (BLOCKER, `denial_message.py:63-66`) | rendered fix line contains `--command '` + the exact blocked command | line has no `--command` |
| Display-action dedup bypass (BLOCKER, `command_policy.py:198-200`) | `fusebase deploy && git push origin main` + only `lightweight_deploy` → `deny` | `allow` |
| Unsatisfied-only denial (MAJOR, `command_policy.py:239,245`; `test-command-policy.sh:123`) | deploy+migration with deploy artifact: message contains `production_deploy` AND `database_migration` | only `database_migration` |
| `only_when` non-mapping (MAJOR, `command_policy.py:185-186`) | rule with `only_when: "direct_to_main"` → deny `FLOW-POLICY-ERROR` | `AttributeError` escapes |
| Malformed `match_order` (MAJOR, `command_policy.py:284`) | `match_order: [deny, allow]` with live `require_approval` rules → deny `FLOW-POLICY-ERROR` | falls to `default: allow` |
| Compat accept unaudited (MAJOR, `path_policy.py:251-253`) | compat-accepting an expiry-less path artifact writes an audit-log entry naming it | no entry |
| Strict ignored by health lib (MAJOR, `active-approvals.sh:58`) | `strict_approvals: true` + expiry-less deferral → NOT in `ACTIVE_ARTIFACTS` | classified active |
| Inventory false ACCEPT (MAJOR, `approval_inventory.py:45-49`) | foreign-`repo_id` artifact row → `REJECT (BINDING_MISMATCH)`; command-bound row → `UNCHECKED` | both print `ACCEPT` |
| Destructive classifier fallback (BLOCKER, `upgrade.sh:249-256,491-502`) | classifier-expected-but-unavailable run: non-zero exit + consumer-edited managed file byte-identical | proceeds; file overwritten |
| Self-restamp advice (BLOCKER, `preflight.sh:293,298`) | preflight missing/stale-base output does NOT name `stamp-managed-content-manifest.sh` as the fix | names it on both paths |
| Bootstrap pre-classification writes (MAJOR, `bootstrap-upgrade.sh:128-167`) | aborted `changed-by-both` hop: tree-wide pre/post `sha256sum` identical (modulo base manifest + log), incl. a sentinel in consumer-customized `hooks/local/upgrade.sh` | engine + `hooks/local/lib/` already replaced |
| `rm` pattern gap (BLOCKER, `command-policy.yml:118`) | `decide("rm build.log")` → deny requiring `destructive_file_delete` | `default: allow` |
| Non-discriminating fixtures 22/23 (MAJOR) | fixture with the FIRST matched action satisfied by a valid artifact → deny on the second | old first-match code **allows** (new fixture); old fixtures passed on old code |
| AC16 fixture never `changed-by-both` (MAJOR, `test-upgrade-conflict-classification.sh:293`) | upstream 4.7.0 rewrites the validator; consumer-patched validator classifies `changed-by-both`; `--auto-yes` aborts; sentinel survives | fixture's upstream leaves the validator unchanged — abort path unexercised |
| EOL fixtures pinned (MAJOR, `:283,:302`) | `core.autocrlf=true` consumer fixture: untouched file classifies `current`/`upstream-only` | no such fixture; behavior unproven. **This row's coverage gap was real and is now closed; the accompanying claim that the `git archive` autocrlf flag "has no effect" was FALSE and is struck** — `git -c core.autocrlf=true archive` emits CRLF on Git for Windows (verified by the AI Developer and independently by the PO). The flag is load-bearing; the fixture is the standing proof. This discriminator is therefore GREEN against `808db35` by design, because the flag already worked. |

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

Empty diff **is** required on: `templates/**`, `.claude/settings.json.example` (no PostToolUse added; K11 defers consumption).

**Ratified deviations (PO, 2026-07-28) — both were unavoidable and are approved retroactively:**

| # | Path | Ruling |
|---|---|---|
| D1 | `hooks/git/pre-commit` (+8/-1, `4d23f30`) | **RATIFIED.** Originally listed zero-diff; that was a PO error. `FR07_SENTINELS` and the PREP extractor list are the **import closure** of `path_policy`, so T2's `approval_artifact.py` must appear in both or the trusted-HEAD enforcer dies `ImportError` and blocks every commit in the repo — which it did, for real, at T11. The change is two list entries plus a tripwire and it *strengthens* the boundary: the new module is now integrity-checked from HEAD. Any **further** `hooks/git/**` change remains out of scope and must be reported, not made. |
| D2 | `.github/workflows/fusebase-flow-verify.yml` (`ci_cd_config`) | **RATIFIED.** `tasks.md` T11 names the file explicitly and AC13 requires the managed-content manifest be CI-freshness-gated, so the edit was on the locked plan's authority; only the handoff's posture table failed to list the class. The narrow single-path 15-minute `protected_path_edit` artifact, committed then deleted, was the correct FR-07 instrument. |

## Smoke prompts (post-deploy)
<!-- prevents: false-green-deploy — taxonomy: policies/ratchet-governance.yml (A3). Outcome + ground-truth columns are the safety-bearing part. -->

Smoke runs against a **fresh clone of the released tag in a scratch directory with hooks wired** — not the development tree — because the defect being fixed is precisely one that only appears on a consumer install. Evidence dir: `docs/tmp/handoff/2026-07-28-approval-binding-and-upgrade-classification-smoke/`.

| ID | Scenario | Route / surface | Operator-visible success criterion | Ground-truth diagnostic | Stable selectors | Auth / test data plan | Adversarial check | Evidence required |
|---|---|---|---|---|---|---|---|---|
| S1 | Replayed unrelated approval no longer authorizes a deploy | `bash hooks/local/run-handler.sh pre_tool_use` with a `fusebase deploy` command | Hook **denies**; message names `production_deploy` and states the artifact's action did not match | `state/audit/*.log` hook decision entry showing verdict `ACTION_MISMATCH` | N/A | Scratch clone; hand-written artifact `production_deploy-other-20260728.json` with body `{"action":"database_migration"}` | Same run on 4.6.1 must **allow** — proves the fix, not the fixture | command transcript + audit-log excerpt |
| S2 | Expiry-less legacy artifact is visible and rejected under strict | `bash hooks/local/approve-local.sh --inventory`, then strict run | Inventory row shows `legacy-no-expiry` and `verdict(strict)=REJECT`; with `strict_approvals: true` the deploy is denied | Inventory stdout + hook decision entry | N/A | Scratch clone; artifact with `expires_at` key absent | With strict OFF the same artifact is **allowed and logged** — proves K7 compat, not silent acceptance | inventory stdout + both decision entries |
| S3 | Documented Lightweight deploy actually passes the gate | `pre_tool_use` and `permission_request` with `fusebase deploy` | Both handlers **allow** with only a `lightweight_deploy` artifact present | Decision entries from both handlers | N/A | `bash hooks/local/approve-local.sh lightweight_deploy smoke-ll 'ship it'` | Removing the artifact denies through both handlers; a `production_deploy` artifact also allows | two decision entries per case |
| S4a | Consumer's patched validator is preserved and reported | `bash hooks/local/bootstrap-upgrade.sh --auto-yes` on a 4.6.1 fixture carrying a locally edited `hooks/shared/command_policy.py` | Run **aborts**; report names that exact path under **`changed-by-both`**; the local edit is **still present**; nothing was written | `sha256sum` of the patched file pre/post + `grep` for the sentinel + report stdout | N/A | Scratch 4.6.1 clone; sentinel comment inserted into the validator | Same fixture through the **old** `upgrade.sh` loses the edit — proves the classifier preserved it | report stdout + pre/post `sha256sum` |
| S4b | Base synthesis makes the upgrade actually deliver content | Same command on a **clean** 4.6.1 fixture (no local edits) | Run **completes**; a file 4.7.0 changed **was** refreshed | `sha256sum` of a control file pre/post; report shows a non-zero `upstream-only` count | N/A | Scratch 4.6.1 clone, unmodified | If the control file is unchanged, base synthesis failed, everything fell to `unknown-base`, and the "successful" upgrade silently installed nothing | report stdout + pre/post `sha256sum` |
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

### S4a / S4b: preservation and delivery are two runs, not one

**PO correction (2026-07-28), raised by the AI Developer at the gate.** The original single S4 was self-contradictory: it demanded both an abort on `changed-by-both` **and** a refreshed control file in the same run. An abort writes nothing, so those cannot both hold. Split into two fixtures — S4a proves the patch survives (dirty tree, aborts), S4b proves the upgrade still delivers (clean tree, completes). Both behaviours are already proven at unit level by the `upgrade-classify` phase; these are the deployed-surface versions. Prior wording is in git history.

**Pass threshold is now 6/6** (S1, S2, S3, S4a, S4b, S5).

### S4a: Consumer's patched validator is preserved and reported

Steps:
1. Clone 4.6.1 to `/scratch/s4a`; insert a sentinel comment into `hooks/shared/command_policy.py`; `sha256sum` it
2. Run `bash hooks/local/bootstrap-upgrade.sh --auto-yes` targeting 4.7.0
3. Re-`sha256sum`; `grep` the sentinel; inspect the report

Expected: non-zero exit (abort); report lists `hooks/shared/command_policy.py` under **`changed-by-both`**; sentinel still present; hash unchanged.
Pass criterion: all four. Preserved-but-unreported is a **FAIL** (AC15 — the consumer's core complaint was not being told which files diverged). Silently proceeding is a FAIL (K9 row 4).
Ground-truth diagnostic: pre/post `sha256sum` plus report stdout.
Adversarial check: the same fixture through the old 4.6.1 `upgrade.sh` must lose the sentinel. If it survives there too, the test is not exercising the overwrite path.
Evidence dir: `.../S4a-*.{log,md}`

### S4b: Base synthesis makes the upgrade actually deliver content

Steps:
1. Clone 4.6.1 to `/scratch/s4b`, **unmodified**; `sha256sum` a control file that 4.7.0 changes (e.g. `hooks/local/upgrade.sh`)
2. Run `bash hooks/local/bootstrap-upgrade.sh --auto-yes` targeting 4.7.0
3. Re-`sha256sum` the control file; read the classification counts in the report

Expected: run completes; control file hash **changed** to 4.7.0 content; report shows a non-zero `upstream-only` count and a zero or near-zero `unknown-base` count.
Pass criterion: the control file changed. **A run that preserves everything is not a pass** — it means base synthesis failed, every path fell to `unknown-base`, and the upgrade reported success while installing nothing. This is the specific silent failure K13 exists to prevent.
Ground-truth diagnostic: pre/post `sha256sum` plus the report's per-classification counts.
Adversarial check: delete the synthesized base mid-run (or point `VERSION` at an unresolvable tag) — the counts must flip to `unknown-base` and the control file must stay unchanged, proving the control assertion is actually sensitive to synthesis.
Evidence dir: `.../S4b-*.{log,md}`

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
☐ Every AC1..AC27 (incl. AC13b, AC13c; AC20..AC27 defined in this file's corrections section) exercised in at least one task
☐ Every locked decision K1..K21 (K6 as REVISED) cited in at least one task
☐ Every corrections-round DEFECT discriminator verified RED against pre-correction code; coverage repairs and controls labelled, not counted as proof (§ Regression discriminators)
☐ K13 base lifecycle proven both ways: synthesis on first run, refresh after apply
☐ All clarify Q-A..Q-D resolved in spec.md
☐ All T1..T14 have SHAs filled in
☐ No TODO/FIXME/WIP markers in diff
☐ Spec status still DRAFT (flips to DONE in T16)
☐ FR-25: check-module-size.sh --all clean; command_policy.py and path_policy.py did not grow past their seams
☐ AC18: mirror-skills.sh + mirror-agents.sh produce empty diff
```

If ANY item fails, redirect the AI Developer. Do NOT bypass.
