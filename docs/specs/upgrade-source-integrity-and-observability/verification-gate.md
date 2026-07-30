# Verification gate — upgrade-source-integrity-and-observability

**Linked spec:** `docs/specs/upgrade-source-integrity-and-observability/spec.md`
**Linked tasks:** `docs/specs/upgrade-source-integrity-and-observability/tasks.md`
**Gate task:** T7 · **Release task:** T8
**Pass threshold for smoke:** 4/4 PASS
**Discriminator baseline:** `85b97dd`

## Acceptance-criterion → task mapping

| AC | Implemented in | Test coverage |
|---|---|---|
| AC1 canonical materialization | T1 | `test-upgrade-conflict-classification.sh` — CRLF-worktree source → LF destination + manifest MATCH |
| AC2 non-git source verified | T1 | same — non-canonical `--source` aborts, writes nothing, names the path |
| AC3 truthful drift recovery text | T1 | grep: `git checkout -- <file>` no longer offered for the byte-mismatch class it cannot repair |
| AC4 sanctioned cleanup | T3 | `test-msys-tree-cleanup.sh` — valid family removed; lookalike / outside-root / unapproved-prefix / symlink all refused |
| AC5 heartbeat on captured runs | T4 | `test-health-check-timeout.sh` — stderr non-empty before child exit; captured payload byte-identical |
| AC6 exact-shape backup prune | T2 | `test-sync-allowlist.sh` — valid family passes; malformed lookalike + genuine unreachable target still fail |
| AC7 stale-approval warning | T5 | `test-approval-writer.sh` + health run — warning names path/age/expiry; exit status unchanged; array contract intact |
| AC8 full gate green | T7 | CI sequence below |
| AC9 anti-tautology | T1..T5 | § Regression discriminators |

## Lint / typecheck / test commands

| Layer | Command |
|---|---|
| Preflight | `bash hooks/local/preflight.sh` |
| Full suite (UNSCOPED — no `FF_ONLY`) | `bash hooks/tests/run-tests.sh` |
| Fixture parity | `python3 hooks/tests/run_hook_tests.py --compare-subprocess` |
| Hook manifest | `bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh` |
| Managed-content manifest | `bash hooks/local/stamp-managed-content-manifest.sh && git diff --exit-code audit/managed-content-manifest.json && bash hooks/local/verify-managed-content-manifest.sh` |
| Mirror drift | `bash hooks/local/mirror-skills.sh && bash hooks/local/mirror-agents.sh && git diff --exit-code` |
| Module size | `bash hooks/local/check-module-size.sh --all` |
| Linux parity | Ubuntu container run of the full suite — **required this ticket**, see below |

**Linux parity is mandatory before T8.** The previous release tagged on a green MSYS suite and went red on Linux CI. Container recipe is in `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md`; it costs ~50s of setup against an auth-gated CI round trip. A green MSYS run alone does **not** satisfy this gate.

## Regression discriminators (anti-tautology contract)

Each **defect** discriminator must be observed RED at `85b97dd` before its fix. Negative controls are green by construction and are labelled, never counted as proof.

| Defect | Assertion that FAILS at `85b97dd` | Negative control (green before and after) |
|---|---|---|
| F2 stale-worktree copy (T1) | CRLF-worktree source → destination LF + `verify-hook-manifest.sh` MATCH | canonical LF source upgrades identically |
| non-git source unverified (T1) | non-canonical `--source` aborts writing nothing | canonical non-git source still upgrades |
| allowlist counts Flow backups (T2) | `agents.pre-upgrade-20260730T120000Z/…` present → phase passes | `agents.pre-upgrade-notatimestamp/…` and a real unreachable target both still FAIL |
| no sanctioned cleanup (T3) | cleanup script exists and removes a valid family; upgrade guidance carries no raw recursive delete | lookalike / outside-root / unapproved-prefix / symlink all refuse, exit non-zero, delete nothing |
| captured runs silent (T4) | stderr non-empty **before** child exit | final captured payload byte-identical to pre-change |
| stale approvals invisible (T5) | aged active `protected_path_edit` → warning with path + age + expiry | fresh approval → no warning; health exit status unchanged; `EXCEPTION_IN_EFFECT` still classifies |

**No discriminator is claimed for T6** (docs) or for F1/F3/F4 — the latter three are already-fixed or refuted, and authoring a test that passes at HEAD would be the exact tautology this contract forbids.

## Worker-undisturbed paths

`fusebase_flow_internals` — edited by design, FR-07 bootstrap approval per commit, never `--no-verify`: `hooks/local/**`, `hooks/shared/**`, `policies/**`, `audit/**`.

Verified **not** protected: `hooks/tests/**` (so T2 needs no approval for its test edit; the manifest restamp still does).

Empty diff required: `templates/**`, `.claude/settings.json.example`, `.gitattributes` (M1 — the pins are already correct; touching them would signal a fix that isn't one), and the integrity hashers `hook_manifest.py` / `managed_content_manifest.py` hashing functions (M2 — no normalization).

## Smoke prompts (post-release)

Run against a **fresh consumer-shaped fixture**, not the dev tree — F2 only manifests on a real upgrade path. Evidence: `docs/tmp/handoff/2026-07-30-upgrade-source-integrity-smoke/`.

| ID | Scenario | Operator-visible success | Ground truth | Adversarial control |
|---|---|---|---|---|
| S1 | Windows consumer upgrade leaves no drift | `fusebase-flow-health-check.sh` reports HEALTHY on a consumer upgraded from a CRLF-worktree source | `verify-hook-manifest.sh` MATCH + `git ls-files --eol` shows `w/lf` on the four `.jsonl` fixtures | Same fixture through the **pre-T1** engine → `FLOW_LAYER_DRIFT` on exactly those four files |
| S2 | Suite is observably alive | Running the deep health check prints progress within a bounded interval, not silence | timestamps on successive stderr lines | Pre-T4 run → zero bytes for minutes |
| S3 | Backups are cleanable through a sanctioned path | `cleanup-flow-backups.sh` removes the upgrade's own backups; suite passes afterwards | `ls` before/after + allowlist phase green | A lookalike directory survives the run untouched |
| S4 | A forgotten approval is visible | Health check names an aged `protected_path_edit` with age + expiry | health output + the artifact on disk | A fresh approval produces no warning; exit status unchanged either way |

## Probes (post-release)

| ID | Probe | Pass criterion |
|---|---|---|
| G-M | Version parity | all four carriers `4.7.0`; `sync-version-strings.sh` empty diff |
| G-N | Fresh-clone preflight | exit 0 |
| G-O | Full suite at released commit, **and** in the Linux container | `N/N PASS` both |
| G-P | Both manifests verify | MATCH |
| G-Q | Tag + release | `v4.7.0` → release commit; CI verify green; GitHub Release exists (not 404) |
| G-R | Spec flip | DRAFT → DONE + tasks SHAs + backlog index in one commit |

## Rollback

Surface: **code-only**. No migration, no secrets. `created_at` is additive and no approval is invalidated, so a downgrade finds consumer artifacts as it left them. Manifests regenerate from source.

If a probe or smoke fails: stop, do not re-point the tag, leave the spec DRAFT, report per FR-10.

**Release-note hazards to carry forward:** (1) `v4.7.0` **moved** — pre-release testers who fetched the old tag must delete and re-fetch; (2) F7 remains open — prose quoting a destructive pattern is denied through Bash, and `git commit -F <file>` is the sanctioned path until the parser ticket lands.

## Cross-artifact consistency check (before release)

```
☐ Every AC1..AC9 exercised by ≥1 task
☐ Every decision M1..M8 cited by ≥1 task
☐ Every T1..T5 discriminator observed RED at 85b97dd; every negative control green
☐ Clarify Q-A..Q-D resolved in spec.md
☐ T1..T6 SHAs recorded
☐ No TODO/FIXME/WIP in diff
☐ .gitattributes and both hashing functions show EMPTY diff (M1/M2)
☐ Linux container run green (mandatory — the last release's exact miss)
☐ Spec still DRAFT (flips in T8)
☐ check-module-size.sh --all clean; upgrade.sh did not grow past ceiling
☐ Zero mirror drift
```

Any item fails → redirect. Do not bypass.
