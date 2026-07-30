# Spec — upgrade-source-integrity-and-observability

**Status:** DRAFT
**Scope lock:** locked 2026-07-30 — decisions frozen; see `decisions.md`
**Created:** 2026-07-30
**Linked decisions:** M1..M8
**Promoted from:** consumer report `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md` (WorkHub Managed, Windows 11 / Git Bash, 4.5.0 → 4.7.0)
**Deploy hash:** <captured at DRAFT → DONE flip>
**Lane:** Full (FR-21) — upgrade-path integrity, multi-file, one slice is security-adjacent
**Doc tier:** 4 (FR-23)

## Problem

A consumer upgraded 4.5.0 → 4.7.0 on Windows and needed **seven manual interventions** to reach HEALTHY. An adversarial scope review confirmed four of the eight reported findings and corrected the root cause of the most important one.

The live defects, all pre-release (v4.7.0 was tagged but its GitHub Release **never published** — CI gated it):

1. **Upgrade copies stale worktree bytes, not canonical content.** `hooks/local/upgrade.sh:496` copies from the persistent source clone's **working tree**. A clone whose fixtures were checked out under `core.autocrlf=true` *before* the `*.jsonl` LF pin landed (`601574d`) still holds CRLF on disk; `git pull` does not rewrite unchanged files. Those CRLF bytes are copied into the consumer, whose byte-exact manifest (`hook_manifest.py:106-111`) then reports permanent `FLOW_LAYER_DRIFT`. Both remedies the checker suggests make it worse, and `diff` normalizes — so it reads as a false positive.
2. **The suite's own upgrade backups fail its own allowlist.** `hooks/tests/test-sync-allowlist.sh:100-109` discovers targets with a repo-wide `find` that does not prune `*.pre-upgrade-<timestamp>` families, so Flow's own backups become unreachable targets and fail the phase.
3. **The framework recommends a cleanup its own guard denies.** `upgrade.sh:743-749,776-781` advises `rm -rf .fusebase-flow-source`; `policies/command-policy.yml:47-50` hard-denies it. FR-06 is right; the guidance is wrong, and there is no sanctioned cleanup entry point.
4. **A 25-minute run emits nothing for ~13 minutes.** Not Python buffering — `run-with-timeout.sh:440-493` redirects the entire child stream into a tempfile and loads it only at `:534-539`, so even `run-tests.sh`'s existing immediate stderr markers (`:112-129`) are swallowed. This is the exact failure mode FR-27 exists to prevent, inside Flow's own tooling; the consumer twice concluded the suite was broken and had to retract that.
5. **Reusable path approvals never expire in practice and staleness is invisible.** `path_policy.py:291-294` keeps non-bootstrap `protected_path_edit` exceptions valid until expiry, and the health check lists approvals without flagging age (`active-approvals.sh:63-88`). The consumer found two forgotten approvals that left the FR-07 guard on their deploy config open for months.

## Why now

v4.7.0's release is held on this work. F1/F2-class breakage hits a consumer on first contact, and F2 in particular silently affects **every Windows consumer** while actively misleading whoever investigates it. Nothing has been published, so these can be folded in rather than shipped and hot-fixed.

## In scope

- **Canonical source materialization** — managed content is materialized from the selected git commit/object database, not from a clone's worktree. A non-git `--source` is byte-verified before copy and fails explicitly if non-canonical.
- **Allowlist discovery prunes Flow-owned backup families** — exact timestamp shape only, never a broad `.pre-*` wildcard.
- **A sanctioned backup-cleanup entry point** (`hooks/local/cleanup-flow-backups.sh`), validating repo root, approved backup prefixes and timestamp shape; upgrade guidance points at it instead of a raw recursive delete.
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

1. **AC1** — Managed content is materialized from the selected git commit's object database. Test: a source clone whose fixture worktree carries CRLF (checked out pre-pin, then advanced without rewriting) yields **LF** at the destination, and `verify-hook-manifest.sh` reports MATCH. Fails at HEAD, which copies the CRLF.
2. **AC2** — A non-git `--source` directory is byte-verified against its shipped manifest before any copy; a non-canonical source **aborts** with a diagnostic naming the offending path, and writes nothing.
3. **AC3** — *(UX)* When the integrity checker reports drift, its recovery text does not suggest an operation that cannot fix it. `git checkout -- <file>` is not offered for a byte-mismatch class it cannot repair; the message names the actual remedy.
4. **AC4** — *(UX)* `upgrade.sh` guidance contains **no** raw `rm -rf`. `bash hooks/local/cleanup-flow-backups.sh` removes exact Flow-owned `<name>.pre-upgrade-<UTC-timestamp>` families and `.fusebase-flow-source/`; it **refuses** a lookalike path, a non-timestamped name, anything outside the repo root, and anything not matching an approved prefix — exit non-zero, nothing deleted.
5. **AC5** — *(UX)* A captured long-running child emits parent-owned progress to stderr **before** it exits, at a bounded interval, while the final captured output remains byte-exact. Test: start a slow child under the wrapper and assert stderr is non-empty before child exit. Fails at HEAD (zero intermediate bytes). Tempfile capture is retained.
6. **AC6** — `hooks/tests/test-sync-allowlist.sh` prunes exact Flow backup families (`<name>.pre-upgrade-<timestamp>`) from discovery. A genuine unreachable target, and a lookalike name that is *not* a Flow backup, both still fail. Test: create `agents.pre-upgrade-20260730T120000Z/ai-developer/AGENT.md` → phase passes; create `agents.pre-upgrade-notatimestamp/…` → still reported.
7. **AC7** — *(UX)* `approve-local.sh` records `created_at` on new artifacts. The health check emits an explicit warning per active `protected_path_edit` exception older than a policy-set threshold, naming path, age and expiry. The warning does **not** change the health exit status. Test: install an aged active artifact → warning present with all three fields.
8. **AC8** — Full unscoped gate green at the release commit: `bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && python3 hooks/tests/run_hook_tests.py --compare-subprocess && bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh`, plus `stamp/verify-managed-content-manifest.sh` clean and zero mirror drift.
9. **AC9** — Every slice T1..T5 has a discriminator observed **RED at `85b97dd`** before its fix. Coverage repairs and negative controls are labelled as such, never counted as proof (the anti-tautology contract carried forward from `approval-binding-and-upgrade-classification`).

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed (`policies/protected-paths.yml`) | `hooks/local/**`, `hooks/shared/**`, `policies/**`, `audit/**` are `fusebase_flow_internals` → FR-07 bootstrap approval per commit. `hooks/tests/**` is **not** protected (verified). Never `--no-verify` |
| Mixed-fleet | Consumers on ≤4.6.1 must use `bootstrap-upgrade.sh`; F1/F3 recur only via the stale engine. Release notes already state this; M7 strengthens it |
| Migration approach | No data migration. `created_at` is additive; artifacts lacking it are treated as unknown-age and warned, never rejected |
| Auth model | Unchanged. S1 adds **visibility**, not enforcement — no approval is invalidated by this work |
| Quality bar | 5 discriminators + negative controls; no new FF_TAGS phase required (existing phases extend) |

## Wire format

Approval artifact gains one additive field:

```jsonc
{ "created_at": "2026-07-30T12:00:00Z" }   // additive; absent = unknown age → warn, never reject
```

`policies/approval-policy.yml` gains a staleness threshold:

```yaml
stale_approval_warn_after_days: 7   # health-check warning only; never changes exit status
```

## Backend changes

- `hooks/local/upgrade.sh` — materialize from git objects; guidance text; cleanup pointer.
- `hooks/local/lib/materialize-managed-source.sh` *(new)* — `git archive`/worktree materialization + non-git source verification.
- `hooks/local/cleanup-flow-backups.sh` *(new)* — validated cleanup.
- `hooks/local/lib/run-with-timeout.sh` — parent-owned heartbeat; capture retained.
- `hooks/tests/run-tests.sh`, `hooks/local/lib/hook-integrity-check.sh` — opt into heartbeat.
- `hooks/tests/test-sync-allowlist.sh` — prune exact backup families.
- `hooks/local/approve-local.sh`, `hooks/local/lib/approval_inventory.py`, `hooks/local/lib/active-approvals.sh`, `hooks/local/fusebase-flow-health-check.sh`, `policies/approval-policy.yml` — `created_at` + staleness warning.
- Integrity-checker recovery text (AC3) — wherever `FLOW_LAYER_DRIFT` guidance is emitted.

**FR-25 watch:** `upgrade.sh` is at **790/800**. T1 must put materialization logic in the new lib file, not the shell.

## Client / extension / SPA changes

None — internal developer tooling only.

## Risks

- **Materialization changes what gets installed.** Mitigation: AC1's discriminator asserts destination bytes and manifest MATCH; the existing ten-state classifier and per-file apply are untouched.
- **Heartbeat could corrupt captured output.** Mitigation: heartbeat goes to **stderr from the parent**; AC5 asserts the captured payload stays byte-exact. Tempfile capture is retained precisely because it prevents the MSYS inherited-pipe hang already catalogued.
- **A cleanup script is a destructive tool.** Mitigation: AC4 requires refusal on lookalike/non-timestamped/outside-root paths, proven by negative tests. It never takes a caller-supplied glob.
- **A staleness warning could become noise or a false gate.** Mitigation: warning only, exit status unchanged (AC7), threshold policy-set.
- **FR-25 ceiling on `upgrade.sh`.** Mitigation: extraction into the new lib is in-scope, not scope creep.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | Does F7 block the v4.7.0 release? | No — pre-existing, documented under K21, needs a real parser; own ticket (M8) | 2026-07-30 |
| Q-B | Fix F1/F3/F4? | No — already-fixed / refuted; no discriminator exists at HEAD | 2026-07-30 |
| Q-C | Normalize line endings in the hasher? | No — it would hide transport corruption (M2) | 2026-07-30 |
| Q-D | Re-point `v4.7.0` or cut `v4.7.1`? | Re-point — no Release was ever published (M6) | 2026-07-30 |

Operator authorized end-to-end autonomous execution; decisions are PO recommendations locked under that authorization and flagged **ASSUMPTION** where a different call changes the work.

## Related

- `decisions.md` · `tasks.md` · `verification-gate.md`
- Consumer report: `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md`
- Prior art: `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` (CRLF-vs-manifest, same family as F2)
- Deferred: `docs/backlog/command-gate-shell-evasion/` (F7's home), `docs/backlog/approval-single-use-consumption/` (S1's architectural half)
