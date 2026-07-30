# Tasks — upgrade-source-integrity-and-observability

**T-counter going in:** T0 (next task is T1)
**Task range:** T1..T9
**Gate task:** T7
**Review task:** T8
**Release task:** T9
**Linked spec:** `docs/specs/upgrade-source-integrity-and-observability/spec.md`
**Linked decisions:** `docs/specs/upgrade-source-integrity-and-observability/decisions.md` (M1..M10)
**Baseline for every discriminator:** `85b97dd` — each fix's assertion must be observed **RED** there first.

## Task chain

| T# | Track | Scope | Cites | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | hooks | Canonical source boundary, compatibility contract, already-corrupted repair | M1, M2, M10 | — | — | pending |
| T2 | hooks | Prune exact Flow backup families from sync-allowlist discovery | M4 | — | — | pending |
| T3 | hooks | Exact-authority `cleanup-flow-backups.sh`; retire raw `rm -rf` guidance | M5 | T1 | — | pending |
| T4 | hooks | Parent-owned heartbeat on captured long runs | M3 | T1 | — | pending |
| T5 | hooks | `created_at` + verdict-neutral stale-approval warnings | M9 | — | — | pending |
| T6 | docs | Bootstrap prominence, corrections, F7 deferral, release carriers | M6, M7, M8 | T1..T5 | — | pending |
| T7 | — | verification gate (no commit) | — | T1..T6 | — | pending |
| T8 | review | `code-review` + `security-permissions-review` (no commit) | M5, M6, M9 | T7 | — | pending |
| T9 | — | release: restamp, re-point `v4.7.0`, publish | M6 | T8 | — | pending |

Execution order: T1/T2/T5 may begin independently. T3 serializes after T1 because both edit `upgrade.sh`; T4 serializes after T1 because both edit `hook-integrity-check.sh`. All commits serialize because T1..T6 share manifest restamps. No “different files/no shared edits” parallel-safety claim applies.

## Per-task detail

### T1. Materialize managed source from canonical git objects

**Track:** hooks
**Scope:** Establish the source boundary before target-engine use. For a git source, `bootstrap-upgrade.sh` resolves the selected ref with `git rev-parse --verify <ref>^{commit}`, converts `SOURCE_REPO` to an absolute path, creates an absolute temporary `SOURCE_TREE`, and materializes incoming `U` with `git -c core.autocrlf=false archive <resolved-commit>` on every OS. Verify `SOURCE_TREE`, then invoke its engine with internal absolute `--source-tree`, absolute `--source-repo`, and full-OID `--source-commit`. A plain source hands off the two absolute paths without `--source-commit` and follows M10. `SOURCE_REPO` is metadata/ref resolution only; `SOURCE_TREE` is every incoming content read.

New `hooks/local/lib/materialize-managed-source.sh` owns snapshot/materialization and verification. Install its cleanup trap immediately after temp-tree creation, before verification or any read/source operation on source-derived content; cover classification abort, dry-run, attended abort, `INT`/`TERM`/`ERR`, and success. Compose it with the later write-phase recovery trap (currently armed only at `upgrade.sh:401-403`).

**Byte model (non-interchangeable):** `U` = forced-LF verified selected commit; `L` = consumer bytes as found; `B` = K13 historical base synthesized with the consumer's EOL setting only (`bootstrap-upgrade.sh:198-209`) because it must match the consumer tree. Never inherit consumer/global EOL for `U`; never force LF for `B`.

**Source-content read conversion (`SOURCE_CLONE` → `SOURCE_TREE`):** incoming merge lib `upgrade.sh:161-167`; clone/plain-dir detection, HEAD/VERSION `:189-217` (metadata remains `SOURCE_REPO`, VERSION content comes from `SOURCE_TREE`); incoming manifest module/list `:240-257`; directory diff and K9 upstream root `:289,313`; framework-doc planning/copy `:353-361,578-586`; legacy-skills decision `:367`; classified/legacy copy paths `:463-519`; incoming baseline/lib `:534-540`. No source-derived file may be read or sourced from `SOURCE_REPO` after the boundary.

**Non-git contract (M10):** snapshot to `SOURCE_TREE` first. `managed_content_manifest.py verify --root <SOURCE_TREE>` `MATCH` proceeds; manifest-bearing `BROKEN`/`DRIFT` aborts before writes and names reason/paths. `ABSENT` proceeds only with a logged `UNVERIFIED_LEGACY_SOURCE` marker; preserve the pre-classifier contract at `test-upgrade-conflict-classification.sh:310-319`. The non-git fixture includes a valid recorded base and a copy-eligible destination so a write/no-write assertion cannot pass via `unknown-base` preservation.

**Already-corrupted repair (AC3):** ordinary K9 remains unchanged and preserves `B=U(LF), L=CRLF` as `consumer-only`. Add repeatable external `bootstrap-upgrade.sh --repair-managed <repo-relative-path>` and an internal exact-path handoff to the verified engine: materialize + verify the target, require operator authorization for the exact verifier-reported managed path list (ordinary `--auto-yes` is insufficient), replace only those paths from `U`, then run hook/managed manifest verification. Update `hook-integrity-check.sh:84-86` to print that command and remove `git checkout -- <file>` for the byte-mismatch class.

**Do not** touch `.gitattributes` (the pins already exist and are correct) and **do not** normalize in the hasher (M2 — it would hide transport corruption).

K13 base synthesis retains its existing consumer-EOL archive at `bootstrap-upgrade.sh:198-209`; that citation does **not** authorize consumer EOL for incoming `U`. Reference `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` pitfall 5.
**Files:** `hooks/local/bootstrap-upgrade.sh`, `hooks/local/upgrade.sh`, `hooks/local/lib/materialize-managed-source.sh` (new), `hooks/local/lib/hook-integrity-check.sh`, `hooks/tests/test-upgrade-conflict-classification.sh`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json`
**Module-size (FR-25):** `upgrade.sh` is at **790/800** — logic goes in the new lib, shell stays orchestration. Extraction here is in-scope.
**Cites:** M1, M2, M10
**Acceptance:** AC1, AC2, AC3
**Discriminators (must be RED at `85b97dd`):** (1) create a local synthetic two-commit upstream — A contains an LF `.jsonl` blob without an EOL pin; populate a separate `core.autocrlf=true` worktree at A (assert CRLF); B adds `*.jsonl text eol=lf` without changing the blob; advance without rewriting; upgrade from B must install LF + manifest MATCH. No dependency on repository history before `601574d`. (2) Corrupt a manifest-bearing non-git snapshot: abort before writes and name the path; a pre-manifest snapshot must proceed only with `UNVERIFIED_LEGACY_SOURCE`. (3) Seed `B=U(LF), L=CRLF`: ordinary upgrade preserves; explicit approved repair replaces the named path and manifest verification becomes MATCH.
**Negative controls:** canonical LF `U` upgrades identically; K13 `B` remains consumer-EOL and does not misclassify untouched CRLF `L`; repair refuses an unreported/unmanaged path and any run without exact operator authorization.
**Worker-undisturbed:** `hooks/local/**`, `hooks/tests/**`, and `audit/**` are not protected; no FR-07 approval. Never `--no-verify`.

---

### T2. Prune exact Flow backup families from allowlist discovery

**Track:** hooks
**Scope:** `hooks/tests/test-sync-allowlist.sh:100-109` builds `TRUE_TARGET` with a repo-wide `find` that prunes some generated paths but not `<name>.pre-upgrade-<UTC-timestamp>` families, so Flow's own upgrade backups become unreachable targets and fail at `:82-87,112-118`. Prune **exact shape only** per M4 — a known managed name, `.pre-upgrade-`, then a UTC timestamp. No `.pre-*` wildcard.
**Files:** `hooks/tests/test-sync-allowlist.sh`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json`
**Module-size:** under ceiling
**Cites:** M4
**Acceptance:** AC6
**Discriminator (RED at `85b97dd`):** create `agents.pre-upgrade-20260730T120000Z/ai-developer/AGENT.md` containing `Operating as AI Developer under Fusebase Flow v4.7.0` (matches `LIVE_RE` at `test-sync-allowlist.sh:33-35`) → phase currently FAILS as an unreachable target; after the fix it passes.
**Negative control:** `agents.pre-upgrade-notatimestamp/ai-developer/AGENT.md` and a genuinely unreachable non-backup target contain the same `LIVE_RE` token and both **still fail**. A prune that swallows these is over-broad and must be rejected.
**Explicitly NOT in scope:** any secret-scan exclusion. `test-secret-scan-staged.sh:158-177` enumerates via `git ls-files`, so untracked backups never enter it; the reporter's premise is false and a bypass would create a hole (M4).
**Worker-undisturbed:** `hooks/tests/**` and `audit/**` are not protected; no FR-07 approval, including manifest restamps.

---

### T3. Sanctioned backup cleanup

**Track:** hooks
**Scope:** `upgrade.sh:743-749` gives generic “remove once validated” guidance; the raw `rm -rf` is at `:776-781` and `policies/command-policy.yml:47-50` hard-denies it. Add `hooks/local/cleanup-flow-backups.sh` with exact grammar: either `--all`, or one or more exact repo-relative targets; modes cannot be combined.

Build an exact repo-relative authorized stem set: `flow-skills`, `agents`, `workflows`, `policies`, `templates`, `hooks`, `.claude-plugin`, `.codex-plugin`, `FLOW_RULES.md`, `FLOW_RULES_HISTORY.md`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json` (the managed dirs/files at `managed_content_manifest.py:34-49`), plus `VERSION`, legacy `skills`, `policies/module-size-baseline.txt`, and each exact `docs/_fusebase-flow/<basename>.md` derived from an installed source top-level framework doc. Exact `.fusebase-flow-source/` is a separate allowed target. Backup targets require an exact `.pre-upgrade-<YYYYMMDDTHHMMSSZ>` suffix.

Reject absolute paths, `..` segments, glob metacharacters, symlinks, non-members, malformed timestamps, and any resolved target outside the resolved repo root. Authorization is set membership after parsing, never `startsWith`/shell string-prefix matching. `--all` enumerates only the same validated set. Any invalid explicit batch exits non-zero before deleting any target. Replace raw-delete guidance with the sanctioned command.

**Do not** add an exception to the FR-06 deny (M5) — narrowing the destructive surface by validation is the point.
**Files:** `hooks/local/cleanup-flow-backups.sh` (new), `hooks/local/upgrade.sh`, `hooks/tests/test-msys-tree-cleanup.sh`, `README.md`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json`
**Module-size:** under ceiling
**Cites:** M5
**Acceptance:** AC4
**Discriminator (RED at `85b97dd`):** grep `upgrade.sh:776-781` for a raw recursive delete → currently present; after the fix, absent. The cleanup entry point is absent at baseline; after implementation, both `--all` and exact-target modes delete valid fixtures.
**Negative controls (all refuse, exit non-zero, delete nothing):** malformed timestamp, lookalike/unmanaged stem, absolute path, `..`, each glob metacharacter class, symlink (inside or outside), resolved outside-root path, string-prefix lookalike, and a mixed valid+invalid explicit batch.
**Worker-undisturbed:** `hooks/local/**`, `hooks/tests/**`, and `audit/**` are not protected; no FR-07 approval.

---

### T4. Parent-owned heartbeat on captured long runs

**Track:** hooks
**Scope:** `run-with-timeout.sh:440-457` designs tempfile capture, `:462-493` redirects the child's whole stream into it, and `:534-539` reads it only after completion — so `run-tests.sh`'s already-immediate stderr markers (`:112-129`) are swallowed, producing ~13 minutes of silence in a 25-minute run. The health deep-run wraps the whole suite this way (`hook-integrity-check.sh:117-125`).

Add an **optional parent-owned heartbeat**: while the child runs, the parent prints a bounded-interval progress line to **stderr**. `run-tests.sh` and the health deep-run opt in. `bounded-run.sh:26-97` already implements this pattern in this codebase — mirror it rather than inventing one.

Serialize after T1: both tasks edit `hooks/local/lib/hook-integrity-check.sh`; T1 lands AC3 recovery text first, T4 then adds the deep-run heartbeat opt-in without reverting that text.

**Keep tempfile capture** (M3). Do **not** switch to `tee` or a pipe: the tempfile design is documented protection against MSYS native grandchildren holding an inherited pipe open past the deadline and freezing the harness. Do **not** add `stdbuf`/`PYTHONUNBUFFERED` — child-side flushing cannot escape a parent redirect, so it would ship as a fix and change nothing.
**Files:** `hooks/local/lib/run-with-timeout.sh`, `hooks/tests/run-tests.sh`, `hooks/local/lib/hook-integrity-check.sh`, `hooks/tests/test-health-check-timeout.sh`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json`
**Module-size:** under ceiling
**Cites:** M3
**Acceptance:** AC5
**Discriminator (RED at `85b97dd`):** run a slow child under the wrapper and read stderr **before** the child exits → currently zero intermediate bytes; after the fix, ≥1 heartbeat line.
**Negative control:** the final captured payload is asserted **byte-identical** to the pre-change behaviour. A heartbeat that contaminates captured output is a regression, not a fix.
**Worker-undisturbed:** `hooks/local/**`, `hooks/tests/**`, and `audit/**` are not protected; no FR-07 approval.

---

### T5. `created_at` + stale-approval visibility

**Track:** hooks
**Scope:** Implement M9's visibility-only seam. Add additive `created_at` to newly minted artifacts (`approve-local.sh:165-180`). Add shipped `stale_approval_warn_after_days: 7`. In `policy_loader.py:79-82,130-150`, define lower days as tighter: local override may lower/equal; reject higher, non-integer, boolean, zero, or negative values with an explicit policy error. Do not silently drop or accept a relaxing value.

`active-approvals.sh` populates new `APPROVAL_WARNINGS[]` only for still-active `protected_path_edit` artifacts. A missing `created_at` yields `age=unknown`; an aged artifact names artifact/path(s), age, and expiry. Update the documented array contract at `active-approvals.sh:11-16` and the health declarations/contract at `fusebase-flow-health-check.sh:128-131,155-157`. Do not overload `ARTIFACT_NOTES[]`.

`fusebase-flow-health-check.sh` prints `APPROVAL_WARNINGS[]` beside active artifacts but outside all verdict counts. Warnings are excluded from `LOCAL_DRIFT`, `LOCAL_BROKEN`, `LOCAL_UNVERIFIED`, and counts at `:560-590`; approval evaluation, `ACTIVE_ARTIFACTS[]`, `DEFERRED_CHECKS[]`, `EXCEPTION_IN_EFFECT`, verdict, and exit code are unchanged.

Note the upstream default TTL for `protected_path_edit` is 60 minutes (`approval-policy.yml:107-110`); the reporter's three-month artifacts came from consumer-local config. Do not change the default.
**Files:** `hooks/local/approve-local.sh`, `hooks/local/lib/approval_inventory.py`, `hooks/local/lib/active-approvals.sh`, `hooks/local/fusebase-flow-health-check.sh`, `hooks/shared/policy_loader.py`, `policies/approval-policy.yml`, `hooks/tests/test-approval-writer.sh`, `hooks/tests/test-bootstrap-exception.sh`, `hooks/tests/test-health-check-timeout.sh`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json`
**Module-size:** under ceiling
**Cites:** M9
**Acceptance:** AC7
**Discriminator (RED at `85b97dd`):** extend `test-health-check-timeout.sh`'s golden fixture **before its one-time stamp** with `active-approvals.sh`, `approval_artifact.py`, `audit_logger.py`, `policy_loader.py`, `hooks/shared/__init__.py`, and `policies/approval-policy.yml`; install an aged active `protected_path_edit`, run health → currently only listed; after fix, `APPROVAL_WARNINGS[]` prints path + age + expiry while exit/verdict remain byte-for-byte equivalent. `test-approval-writer.sh` alone is insufficient proof of the health exit contract.
**Negative controls:** fresh approval → no warning; missing `created_at` → `age=unknown` warning; expired or `health_check_deferral` artifact → no staleness warning; aged warning does not enter any verdict array/count; `EXCEPTION_IN_EFFECT` still classifies. `policy_loader` tests accept lower/equal thresholds and reject higher/invalid values.
**Worker-undisturbed:** FR-07 approval required for `hooks/shared/policy_loader.py` and `policies/approval-policy.yml`. `hooks/local/**`, `hooks/tests/**`, and `audit/**` are not protected. Never `--no-verify`.

---

### T6. Docs: corrections, bootstrap prominence, F7 deferral

**Track:** docs
**Scope:**
1. **Record the corrections** (M7): F1/F3 were stale-4.5-engine behavior, not 4.7.0 defects (`upgrade.sh:237-249`; `managed_content_manifest.py:34-49`); F4 is refuted (`merge-module-size-baseline.sh:85-103`). Add the release-note correction and cross-link both directions with the source report `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md`.
2. **Raise bootstrap-route prominence** — upgrading from ≤4.6.1 with the stale local engine is unsupported and produced F1/F3. Update `README.md`, `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`, root `AGENTS.md`, and canonical `hooks/local/fusebase-flow-overlays/agents-md-overlay.md`. Root-only edits are forbidden: `post-fusebase-update.sh:248-279` restores from the canonical overlay. Extend `hooks/tests/test-cli-flow-recovery.sh` to prove refresh/recovery preserves the corrected text.
3. **F7 deferral** (M8): promote `docs/backlog/command-gate-shell-evasion/README.md` with the semantic corpus and an explicit **"must not be attempted"** list (anchor-to-start, strip `-m`/`-F`, ignore heredoc bodies, argv-split). Add a one-line note in `policies/command-policy.yml`'s header that prose quoting a destructive pattern will be denied and `git commit -F <file>` is the sanctioned path.
4. **Release carriers:** CHANGELOG + `docs/release-notes/v4.7.0.md` cover T1..T5, the M6 moved-tag notice/explicit authorization requirement, and F7. Set the README badge at `README.md:9` equal to `VERSION` (currently 4.6.1 vs 4.7.0).
5. **Integrity carriers:** `policies/command-policy.yml` changes always restamp `audit/managed-content-manifest.json`; hook/test/overlay changes restamp both manifests. Verify both after stamping.
**Files:** `README.md`, `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`, `AGENTS.md`, `hooks/local/fusebase-flow-overlays/agents-md-overlay.md`, `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md`, `docs/backlog/command-gate-shell-evasion/README.md`, `policies/command-policy.yml`, `CHANGELOG.md`, `docs/release-notes/v4.7.0.md`, `hooks/tests/test-cli-flow-recovery.sh`, `audit/hook-layer-manifest.json`, `audit/managed-content-manifest.json`
**Cites:** M6, M7, M8
**Acceptance:** AC8 — zero mirror drift; canonical overlay recovery test green; README badge equals `VERSION`; both manifests clean
**Worker-undisturbed:** FR-07 approval required only for `policies/command-policy.yml`. `hooks/local/**`, `hooks/tests/**`, `audit/**`, root/docs carriers are not protected. Never `--no-verify`.

---

### T7. Verification gate

No commit. Produce the gate report from `templates/gate-report.md`; fields per `policies/gate-contracts.yml: gate_report`. **Unscoped** run only — no `FF_ONLY`; cite only `state/audit/hook-test-results.md`.

Additionally required this ticket: confirm each T1..T5 discriminator was observed RED at `85b97dd`, and that every negative control passes. Then halt and wait for the release handoff.

**Worker-undisturbed:** no edits; FR-07 N/A.

---

### T8. Review

No commit. Run `code-review` against spec/decisions/tasks and the complete T1..T6 diff; require a `SHIP` verdict with no unresolved BLOCKER/MAJOR. Run `security-permissions-review` because T3 adds a destructive cleanup tool and T6 changes `policies/command-policy.yml`; require its sensitive-surface findings resolved and permission posture accepted. Record both reports with exact reviewed commit/diff range. Any fix returns to the owning implementation task and requires T7 rerun before both reviews rerun.

**Acceptance:** both reviews PASS/SHIP on the same release candidate; no unresolved security/permission/destructive-path finding.
**Worker-undisturbed:** review-only; no edits; FR-07 N/A.

---

### T9. Release

1. Restamp `audit/hook-layer-manifest.json` + `audit/managed-content-manifest.json`; confirm `sync-version-strings.sh` leaves an empty diff, all four version carriers equal `VERSION`, and the README version badge equals `VERSION`.
2. Full unscoped gate green **at the release commit**.
3. After both T8 reviews pass, present old/new tag commits + moved-tag notice and obtain explicit operator authorization. Only then recreate `v4.7.0`; delete the remote tag and re-push (M6). Not a force-push.
4. Release workflow publishes only if verify is green (`needs: verify`).
5. Probes + smoke per `verification-gate.md`.
6. Single docs commit (FR-14): spec DRAFT → DONE with hash, tasks SHAs, review evidence, backlog index.
7. Deploy report.

**Requires** an explicit operator DP.6 authorization for the tag re-point — a published-ref mutation is not covered by a prior approval for a different action (DP.1).

**Worker-undisturbed:** final docs/manifest restamps are not protected; release-ref mutation is governed by explicit DP.6 authorization, not FR-07. Never `--no-verify`.

## Task chain audit

| Invariant | Affirmed in |
|---|---|
| Worker-undisturbed | T1-T4: local/tests/audit unprotected. T5: FR-07 only for `hooks/shared/policy_loader.py` + `policies/approval-policy.yml`. T6: FR-07 only for `policies/command-policy.yml`. T7-T9: no protected edit planned. Manifest restamps are unprotected |
| Mixed-fleet | T1 (canonical materialization helps every consumer), T6 (bootstrap-route prominence) |
| Migration | None. `created_at` additive; absent = unknown-age → warn, never reject |
| Anti-tautology | Every T1..T5 names a RED-at-`85b97dd` discriminator **and** negative controls; T6 is docs-only and claims no discriminator |
| FR-25 | T1 names the extraction seam (`upgrade.sh` at 790/800) |
| FR-22 | Tripwires required at: materialization (why not the worktree), heartbeat (why not `tee`), cleanup (why validation not an FR-06 exception) |
| Review before release | T8 runs `code-review` + `security-permissions-review`; T9 depends on both passing |
