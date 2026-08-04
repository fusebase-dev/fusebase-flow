# Spec — upgrade-source-integrity-and-observability

**Status:** DONE (shipped 2026-08-04, framework v4.7.0, tag `v4.7.0`)
**Scope lock:** re-locked 2026-07-30 after adversarial plan review; see `decisions.md`
**Created:** 2026-07-30
**Linked decisions:** M1..M17
**Promoted from:** consumer report `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md` (WorkHub Managed, Windows 11 / Git Bash, 4.5.0 → 4.7.0)
**Deploy hash:** `bad4d92` — pushed to `origin/main` (`85b97dd..bad4d92`, 77 commits); tag `v4.7.0` re-pointed `b11c60d` → `bad4d92` (decision M6); GitHub Release published 2026-08-04T00:57:45Z — <https://github.com/fusebase-dev/fusebase-flow/releases/tag/v4.7.0>
**Deployed:** 2026-08-04 · CI `fusebase-flow-release` run `30867061611`: verify **success** (all 14 steps) → publish **success**; separate `fusebase-flow-verify` run `30867017382` on `main` **success** · local gate: Windows unscoped **742/743 PASS, 0 FAIL** (the one non-PASS is `cli-flow-recovery` INCONCLUSIVE — it crosses its 900s liveness bound on this host; run directly it is **rc 0, 31/31 PASS, 0 FAIL**), Linux `ubuntu:24.04` **740/740 PASS, 0 FAIL**, every CI-mirrored step rc 0 · 8 adversarial review rounds, final round 0 class-(b)
**Lane:** Full (FR-21) — upgrade-path integrity, multi-file, one slice is security-adjacent
**Doc tier:** 4 (FR-23)

## Problem

A consumer upgraded 4.5.0 → 4.7.0 on Windows and needed **seven manual interventions** to reach HEALTHY. An adversarial scope review confirmed four of the eight reported findings and corrected the root cause of the most important one.

The live defects, all pre-release (v4.7.0 was tagged but its GitHub Release **never published** — CI gated it):

1. **Upgrade copies stale worktree bytes, not canonical content.** `hooks/local/upgrade.sh:496` copies from the persistent source clone's **working tree**. A source worktree populated with `core.autocrlf=true` before the `*.jsonl` LF pin landed (`601574d`), then advanced without rewriting unchanged files, can retain CRLF on disk. Consumers upgrading through that affected worktree receive those CRLF bytes; the byte-exact manifest (`hook_manifest.py:106-111`) then reports permanent `FLOW_LAYER_DRIFT`. Both current remedies preserve or recreate the mismatch, and `diff` normalizes — so the true-positive byte drift reads as a false positive.
2. **The suite's own upgrade backups fail its own allowlist.** `hooks/tests/test-sync-allowlist.sh:100-109` discovers targets with a repo-wide `find` that does not prune `*.pre-upgrade-<timestamp>` families, so Flow's own backups become unreachable targets and fail the phase.
3. **The framework recommends a cleanup its own guard denies.** `upgrade.sh:743-749` gives generic “remove once validated” guidance; `upgrade.sh:776-781` prints raw `rm -rf .fusebase-flow-source`, which `policies/command-policy.yml:47-50` hard-denies. FR-06 is right; the raw guidance is wrong, and there is no sanctioned cleanup entry point.
4. **A 25-minute run emits nothing for ~13 minutes.** Not Python buffering — `run-with-timeout.sh:440-493` redirects the entire child stream into a tempfile and loads it only at `:534-539`, so even `run-tests.sh`'s existing immediate stderr markers (`:112-129`) are swallowed. This is the exact failure mode FR-27 exists to prevent, inside Flow's own tooling; the consumer twice concluded the suite was broken and had to retract that.
5. **Reusable path approvals never expire in practice and staleness is invisible.** `path_policy.py:291-294` keeps non-bootstrap `protected_path_edit` exceptions valid until expiry, and the health check lists approvals without flagging age (`active-approvals.sh:63-88`). The consumer found two forgotten approvals that left the FR-07 guard on their deploy config open for months.

## Why now

v4.7.0's GitHub Release is held on this work. F1/F2-class breakage hits a consumer on first contact, and F2 silently affects consumers upgrading through an affected pre-`601574d`, `core.autocrlf=true` persistent source worktree while actively misleading whoever investigates it. No GitHub Release exists, but the remote `v4.7.0` tag was visible and at least one prerelease tester fetched it; any re-point requires a moved-tag notice and explicit authorization.

## In scope

- **Canonical source materialization** — incoming `U` is materialized on every OS with `git -c core.autocrlf=false archive <resolved-commit>` and verified before any source-derived content is read. Existing local `L` remains byte-for-byte as found. K13 historical base `B` synthesis alone uses the consumer's EOL setting because `B` must model the consumer tree.
- **Source handoff boundary** — for git sources, `bootstrap-upgrade.sh` resolves `<ref>^{commit}`, materializes an absolute temporary `SOURCE_TREE`, then hands internal absolute `--source-tree`, absolute `--source-repo`, and full-OID `--source-commit` values to `upgrade.sh`. Plain sources hand off the two absolute paths without `--source-commit` and follow M10. `SOURCE_REPO` is metadata-only; every incoming content read uses `SOURCE_TREE`.
- **Non-git compatibility contract** — manifest-bearing sources must verify; `BROKEN`/`DRIFT` abort before writes. Pre-manifest sources proceed only through the logged `UNVERIFIED_LEGACY_SOURCE` fallback (M10).
- **Already-corrupted consumer repair** — ordinary upgrade preserves `B=U(LF), L=CRLF` as `consumer-only`. An explicit exact-path repair operation materializes and verifies the target, replaces only operator-approved drift paths, then re-runs manifest verification.
- **Allowlist discovery prunes Flow-owned backup families** — exact timestamp shape only, never a broad `.pre-*` wildcard.
- **A sanctioned backup-cleanup entry point** (`hooks/local/cleanup-flow-backups.sh`), validating repo root, exact stem membership and timestamp shape; upgrade guidance points at it instead of a raw recursive delete.
- **Parent-owned heartbeat for captured long runs** — the tempfile-capture wrapper gains progress output; `run-tests.sh` and the health deep-run opt in. Tempfile capture is **retained** (it is what prevents inherited-pipe hangs from MSYS native grandchildren).
- **Stale-approval visibility** — `created_at` on newly minted artifacts; health-check warning naming artifact path, age and expiry for long-lived active `protected_path_edit` exceptions.
- Release closure: restamp both manifests, CHANGELOG, `docs/release-notes/v4.7.0.md`.

## Out of scope

- **F1 and F3 — no code change.** Both were the last run of the **4.5** wholesale-copy engine, not 4.7.0 behaviour. `upgrade.sh:237-249` already drives the managed set through `managed_content_manifest.py list-managed` (decision K14), whose canonical list at `:34-49` **includes** `FLOW_RULES_HISTORY.md`; the 4.7 per-file classifier at `managed_content_manifest.py:220-294` already preserves-and-reports consumer-modified policy files. Neither can produce a discriminator that fails at HEAD. Documentation reinforcement of the bootstrap requirement is the only honest response, and it already landed in the v4.7.0 release notes.
- **F4 — refuted.** `merge-module-size-baseline.sh:95-103` deduplicates by path; the reported mechanism cannot produce the duplicate. No fix without a current-HEAD reproducer.
- **F7 / T6 — structured shell parsing.** Real and confirmed, but it needs a genuine execution-structure parser, not a narrowing patch. Deferred to its own ticket (see M8). A naive fix is actively dangerous: `git commit -m "$(rm -rf /)"` executes the substitution before git runs, and argv-splitting *worsens* the K21 quote-fragmentation evasion this release already documented.
- Broad `.pre-*` or `.pre-upgrade-*` exclusion from the **secret scan**. The reporter's premise is false — `test-secret-scan-staged.sh:158-177` enumerates via `git ls-files`, so untracked backups never enter it, and a blanket bypass would create a real hole.
- Line-ending normalization inside the integrity hasher. It would conceal transport corruption, which is the one thing a byte-exact manifest exists to detect.
- True single-use consumption for path approvals — remains `docs/backlog/approval-single-use-consumption/`.

## Audience classification

Internal / developer-facing only. `docs/audience.md` absent → `client-vs-internal` is a silent no-op. No client UI. Three operator-visible **CLI text** surfaces are treated as UX deliverables with acceptance criteria: the upgrade's drift/cleanup guidance (AC3, AC4), the long-run heartbeat (AC5), and the health-check staleness warning (AC7).

## Acceptance criteria

1. **AC1** — The byte models are distinct and tested: incoming `U` is the selected `<commit>^{commit}` materialized with `git -c core.autocrlf=false archive <commit>` on **every OS**, then verified against its shipped manifest; local `L` is read as found; K13 base `B` synthesis **alone** uses `git -c core.autocrlf=<consumer-setting> archive <prior-tag>` so `B` matches the consumer's existing tree. A synthetic two-commit upstream (commit A: LF blob without pin; commit B: adds the LF pin without changing the blob) leaves a pre-existing `core.autocrlf=true` worktree CRLF, but upgrade installs LF and `verify-hook-manifest.sh` reports MATCH. The paired K13 fixture proves `B` remains consumer-EOL and an untouched CRLF local file is not misclassified.
2. **AC2** — For a git source, `bootstrap-upgrade.sh` resolves `<ref>^{commit}`, creates an absolute temporary `SOURCE_TREE`, and invokes `upgrade.sh` with internal absolute `--source-tree`, absolute `--source-repo`, and full-OID `--source-commit`. A plain source omits `--source-commit`. Materialization and its early cleanup trap occur before any source-derived file is sourced or read. For non-git sources, verify the materialized snapshot with `managed_content_manifest.py verify --root <SOURCE_TREE>`: manifest-bearing `BROKEN` or `DRIFT` aborts before writes with offending paths; `ABSENT` proceeds only through a named, logged `UNVERIFIED_LEGACY_SOURCE` compatibility fallback.
3. **AC3** — *(UX)* Ordinary upgrade explicitly preserves an already-corrupted `B=U(LF), L=CRLF` path as `consumer-only`; it is not presented as repaired. The integrity checker names the deliberate repair command: `bash hooks/local/bootstrap-upgrade.sh --repair-managed <repo-relative-path>` (repeat the flag per verifier-reported managed path). That mode materializes and verifies the target commit, requires operator approval for the exact path list, replaces only those paths from verified `U`, then re-runs hook/managed manifest verification. Ordinary `--auto-yes` does not authorize repair; `git checkout -- <file>` is not offered for this byte-mismatch class.
4. **AC4** — *(UX)* `upgrade.sh` guidance contains **no** raw `rm -rf`. `cleanup-flow-backups.sh` accepts exactly one mode: `--all`, or one or more exact repo-relative backup targets. Eligible stems are the exact managed dirs/files returned by `managed_content_manifest.py list-managed`, plus `VERSION`, legacy `skills`, `policies/module-size-baseline.txt`, and exact `docs/_fusebase-flow/<source-top-level-doc-basename>.md` entries when framework docs were installed; exact `.fusebase-flow-source/` is a special target. Backup targets require `.pre-upgrade-<YYYYMMDDTHHMMSSZ>`. Reject absolute paths, `..`, glob metacharacters, symlinks, non-members, and any resolved target outside the repo root; exit non-zero and delete nothing. Authorization is exact stem membership, never string-prefix matching.
5. **AC5** — *(UX)* A captured long-running child emits parent-owned progress to stderr **before** it exits, at a bounded interval, while the final captured output remains byte-exact. Test: start a slow child under the wrapper and assert stderr is non-empty before child exit. Fails at HEAD (zero intermediate bytes). Tempfile capture is retained.
6. **AC6** — `hooks/tests/test-sync-allowlist.sh` prunes exact Flow backup families (`<name>.pre-upgrade-<timestamp>`) from discovery. A genuine unreachable target, and a lookalike name that is *not* a Flow backup, both still fail. Each fixture file contains `Operating as AI Developer under Fusebase Flow v4.7.0` so it matches `LIVE_RE` (`test-sync-allowlist.sh:33-35`): timestamped backup passes; malformed lookalike and genuine unreachable target remain reported.
7. **AC7** — *(UX)* `approve-local.sh` records additive `created_at` on new artifacts. Health reports only active `protected_path_edit` artifacts older than the policy threshold; absent `created_at` means `age=unknown` and warns. A separate `APPROVAL_WARNINGS[]` array is printed outside verdict counts and is excluded from `LOCAL_DRIFT`, `LOCAL_BROKEN`, and `LOCAL_UNVERIFIED`; authorization and health exit status are unchanged. Lower threshold days are tighter: local override may lower/equal the shipped value and must reject higher, non-integer, boolean, or non-positive values. Test: aged and unknown-age active artifacts warn with path/age/expiry; a fresh artifact does not; verdict/exit stay identical.
8. **AC8** — Full unscoped gate green at the release commit: `bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && python3 hooks/tests/run_hook_tests.py --compare-subprocess && bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh`, plus `stamp/verify-managed-content-manifest.sh` clean, zero mirror drift, and README version badge equal to `VERSION`.
9. **AC9** — Every slice T1..T5 has a discriminator observed **RED at `85b97dd`** before its fix. Coverage repairs and negative controls are labelled as such, never counted as proof (the anti-tautology contract carried forward from `approval-binding-and-upgrade-classification`).

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed (`policies/protected-paths.yml:84-93`) | Protected edits: T5 `hooks/shared/policy_loader.py` + `policies/approval-policy.yml`; T6 `policies/command-policy.yml`. Not protected: `hooks/local/**`, `hooks/tests/**`, `audit/**`; manifest restamps need no FR-07 approval. `hooks/handlers/**` and `hooks/git/**` remain protected but are not edited. Never `--no-verify` |
| Mixed-fleet | Consumers on ≤4.6.1 must use `bootstrap-upgrade.sh`; F1/F3 recur only via the stale engine. Release notes already state this; M7 strengthens it |
| Migration approach | No data migration. `created_at` is additive; artifacts lacking it are treated as unknown-age and warned, never rejected |
| Auth model | Unchanged. M9 adds **visibility**, not enforcement — no approval is invalidated by this work |
| Quality bar | T1..T5 each have RED-at-baseline discriminator coverage + negative controls; no new FF_TAGS phase required (existing phases extend) |

## Wire format

Approval artifact gains one additive, authorization-neutral field (M9):

```jsonc
{ "created_at": "2026-07-30T12:00:00Z" }   // additive; absent = unknown age → warn, never reject
```

`policies/approval-policy.yml` gains a visibility-only staleness threshold:

```yaml
stale_approval_warn_after_days: 7   # health-check warning only; never changes exit status
```

## Backend changes

- `hooks/local/bootstrap-upgrade.sh` — resolve `<ref>^{commit}`, materialize before target-engine use, pass internal source boundary, own early cleanup trap, expose repeatable `--repair-managed <path>`.
- `hooks/local/upgrade.sh` — consume `SOURCE_TREE` for all incoming content; retain `SOURCE_REPO` for metadata only; guidance text; cleanup pointer.
- `hooks/local/lib/materialize-managed-source.sh` *(new)* — `git archive`/worktree materialization + non-git source verification.
- `hooks/local/cleanup-flow-backups.sh` *(new)* — validated cleanup.
- `hooks/local/lib/run-with-timeout.sh` — parent-owned heartbeat; capture retained.
- `hooks/tests/run-tests.sh`, `hooks/local/lib/hook-integrity-check.sh` — opt into heartbeat; integrity checker also carries AC3 exact-path repair guidance (`hook-integrity-check.sh:84-86`).
- `hooks/tests/test-sync-allowlist.sh` — prune exact backup families.
- `hooks/local/approve-local.sh`, `hooks/local/lib/approval_inventory.py`, `hooks/local/lib/active-approvals.sh`, `hooks/local/fusebase-flow-health-check.sh`, `hooks/shared/policy_loader.py`, `policies/approval-policy.yml` — `created_at`, tighten-only threshold, separate staleness warnings.

**FR-25 watch:** `upgrade.sh` is at **790/800**. T1 must put materialization logic in the new lib file, not the shell.

## Client / extension / SPA changes

None — internal developer tooling only.

## Risks

- **Materialization changes what gets installed.** Mitigation: AC1 separately proves forced-LF verified `U`, as-found `L`, and consumer-EOL `B`; the existing ten-state classifier and per-file apply remain authoritative outside the explicit repair path.
- **Heartbeat could corrupt captured output.** Mitigation: heartbeat goes to **stderr from the parent**; AC5 asserts the captured payload stays byte-exact. Tempfile capture is retained precisely because it prevents the MSYS inherited-pipe hang already catalogued.
- **A cleanup script is a destructive tool.** Mitigation: AC4 authorizes exact stem-set membership only and rejects path traversal, glob syntax, symlinks, and outside-root resolution. It never accepts a caller-supplied glob or string-prefix authority.
- **A staleness warning could become noise or a false gate.** Mitigation: `APPROVAL_WARNINGS[]` is separate from verdict arrays; lower-only local threshold overrides; exit status and authorization unchanged (M9/AC7).
- **FR-25 ceiling on `upgrade.sh`.** Mitigation: extraction into the new lib is in-scope, not scope creep.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | Does F7 block the v4.7.0 release? | No — pre-existing, documented under K21, needs a real parser; own ticket (M8) | 2026-07-30 |
| Q-B | Fix F1/F3/F4? | No — already-fixed / refuted; no discriminator exists at HEAD | 2026-07-30 |
| Q-C | Normalize line endings in the hasher? | No — it would hide transport corruption (M2) | 2026-07-30 |
| Q-D | Re-point `v4.7.0` or cut `v4.7.1`? | Re-point only after explicit authorization + moved-tag notice: no GitHub Release exists, but the remote tag was visible and fetched by a prerelease tester (M6) | 2026-07-30 |

Operator authorized end-to-end autonomous execution; decisions are PO recommendations locked under that authorization and flagged **ASSUMPTION** where a different call changes the work.

## Related

- `decisions.md` · `tasks.md` · `verification-gate.md`
- Consumer report: `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md`
- Prior art: `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` (CRLF-vs-manifest, same family as F2)
- Deferred: `docs/backlog/command-gate-shell-evasion/` (F7's home), `docs/backlog/approval-single-use-consumption/` (S1's architectural half)
