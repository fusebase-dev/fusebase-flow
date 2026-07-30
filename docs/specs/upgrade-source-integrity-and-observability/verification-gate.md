# Verification gate — upgrade-source-integrity-and-observability

**Linked spec:** `docs/specs/upgrade-source-integrity-and-observability/spec.md`
**Linked tasks:** `docs/specs/upgrade-source-integrity-and-observability/tasks.md`
**Gate task:** T7 · **Review task:** T8 · **Release task:** T9
**Pass threshold for smoke:** 4/4 PASS
**Discriminator baseline:** `85b97dd`

## Acceptance-criterion → task mapping

| AC | Implemented in | Test coverage |
|---|---|---|
| AC1 three-way byte model | T1 | synthetic two-commit upstream: forced-LF verified `U`; as-found `L`; consumer-EOL K13 `B` |
| AC2 source boundary + compatibility | T1 | absolute internal source handoff; manifest `DRIFT/BROKEN` abort; `ABSENT` logs `UNVERIFIED_LEGACY_SOURCE` and preserves pre-classifier compatibility |
| AC3 truthful repair | T1 | ordinary `consumer-only` preservation + repeatable `bootstrap-upgrade.sh --repair-managed <path>` → manifest MATCH; recovery text names it |
| AC4 sanctioned cleanup | T3 | `test-msys-tree-cleanup.sh` — `--all`/exact target; exact stem set; traversal/glob/symlink/outside-root/string-prefix controls |
| AC5 heartbeat on captured runs | T4 | `test-health-check-timeout.sh` — stderr non-empty before child exit; captured payload byte-identical |
| AC6 exact-shape backup prune | T2 | `test-sync-allowlist.sh` — valid family passes; malformed lookalike + genuine unreachable target still fail |
| AC7 stale-approval warning | T5 | `test-approval-writer.sh`, `test-bootstrap-exception.sh`, `test-health-check-timeout.sh` — separate warning array; tighten-only policy; exit unchanged |
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

## Review gate

T8 runs after T7 and before release. Required on the same release candidate:

| Review | Trigger | Pass condition |
|---|---|---|
| `code-review` | Full T1..T6 diff vs spec/decisions | `SHIP`; no unresolved BLOCKER/MAJOR |
| `security-permissions-review` | T3 destructive cleanup tool + T6 `command-policy.yml` change | no unresolved sensitive-surface, permission, path-authority, or rollback finding |

Any review-driven code/policy/doc change invalidates T7 and both review results. T9 depends on both reviews passing after the last change.

## Regression discriminators (anti-tautology contract)

Each **defect** discriminator must be observed RED at `85b97dd` before its fix. Negative controls are green by construction and are labelled, never counted as proof.

| Defect | Assertion that FAILS at `85b97dd` | Negative control (green before and after) |
|---|---|---|
| F2 stale-worktree copy (T1) | synthetic two-commit upstream; pre-existing autocrlf=true worktree is CRLF; selected commit materializes/installs LF + manifest MATCH | canonical LF `U` unchanged; K13 `B` remains consumer-EOL |
| non-git source unverified (T1) | manifest `DRIFT/BROKEN` aborts before writes; pre-manifest source logs `UNVERIFIED_LEGACY_SOURCE` and still upgrades | manifest `MATCH` source upgrades; fixture has valid base + copy-eligible destination |
| already-corrupted consumer (T1) | `B=U(LF), L=CRLF`: ordinary upgrade preserves; approved exact-path repair produces manifest MATCH | unreported/unmanaged path or missing exact approval refuses |
| allowlist counts Flow backups (T2) | timestamped backup contains `Operating as AI Developer under Fusebase Flow v4.7.0` (`LIVE_RE`) → phase passes | malformed backup and real unreachable target contain same token and still FAIL |
| no sanctioned cleanup (T3) | `--all` and exact-target modes remove eligible members; raw delete absent at `upgrade.sh:776-781` | malformed/absolute/`..`/glob/symlink/outside-root/non-member/string-prefix/mixed-batch all refuse atomically |
| captured runs silent (T4) | stderr non-empty **before** child exit | final captured payload byte-identical to pre-change |
| stale approvals invisible (T5) | health golden fixture includes approval libs/policy before stamp; aged active `protected_path_edit` → separate warning with path + age + expiry | fresh/expired/deferral controls; unknown age warns; exit/counts/authorization unchanged; higher/invalid local threshold rejected |

**No discriminator is claimed for T6** (docs) or for F1/F3/F4 — the latter three are already-fixed or refuted, and authoring a test that passes at HEAD would be the exact tautology this contract forbids.

## Worker-undisturbed paths

Relevant protected map (`policies/protected-paths.yml:84-93`): `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`. T5 requires FR-07 approval for `hooks/shared/policy_loader.py` + `policies/approval-policy.yml`; T6 requires it for `policies/command-policy.yml`. No other planned task edits a protected path.

Verified **not** protected: `hooks/local/**`, `hooks/tests/**`, `audit/**`. Hook-local edits, test edits, and both manifest restamps require no FR-07 approval. Never `--no-verify`.

Empty diff required: `templates/**`, `.claude/settings.json.example`, `.gitattributes` (M1 — the pins are already correct; touching them would signal a fix that isn't one), and the integrity hashers `hook_manifest.py` / `managed_content_manifest.py` hashing functions (M2 — no normalization).

## Smoke prompts (post-release)

Run against a **fresh consumer-shaped fixture**, not the dev tree — F2 only manifests on a real upgrade path. Evidence: `docs/tmp/handoff/2026-07-30-upgrade-source-integrity-smoke/`.

| ID | Scenario | Operator-visible success | Ground truth | Adversarial control |
|---|---|---|---|---|
| S1 | Affected Windows route + existing victim repair | New upgrade from synthetic CRLF worktree installs LF; existing `B=U(LF), L=CRLF` victim is preserved by ordinary upgrade then repaired only by approved exact-path mode | both manifests MATCH; `git ls-files --eol` shows `w/lf` on repaired fixtures | pre-T1 engine drifts; ordinary fixed upgrade alone preserves victim bytes and does not falsely claim repair |
| S2 | Suite is observably alive | Running the deep health check prints progress within a bounded interval, not silence | timestamps on successive stderr lines | Pre-T4 run → zero bytes for minutes |
| S3 | Backups are cleanable through a sanctioned path | `cleanup-flow-backups.sh` removes the upgrade's own backups; suite passes afterwards | `ls` before/after + allowlist phase green | A lookalike directory survives the run untouched |
| S4 | A forgotten approval is visible | Health check names an aged `protected_path_edit` with protected path(s) + age + expiry | health output + the artifact on disk | A fresh approval produces no warning; exit status unchanged either way |

## Probes (post-release)

| ID | Probe | Pass criterion |
|---|---|---|
| G-M | Version parity | all four carriers equal `VERSION`; README version badge equals `VERSION`; `sync-version-strings.sh` empty diff |
| G-N | Fresh-clone preflight | exit 0 |
| G-O | Full suite at released commit, **and** in the Linux container | `N/N PASS` both |
| G-P | Both manifests verify | MATCH |
| G-Q | Tag + release | `v4.7.0` → release commit; CI verify green; GitHub Release exists (not 404) |
| G-R | Spec flip | DRAFT → DONE + tasks SHAs + backlog index in one commit |

## Rollback

Surface: **code + policy + docs + release ref; no migration or secret-state change**. `created_at` is additive and no approval is invalidated, so a downgrade finds consumer artifacts as it left them. Manifests regenerate from source; tag rollback requires the same explicit published-ref authorization.

If a pre-ref probe fails: stop, do not re-point the tag, leave the spec DRAFT, report per FR-10. If a post-ref smoke fails: halt publication/closure and present explicit-authorized release-ref rollback vs fix-forward; never pretend the tag was not already moved.

**Release-note hazards to carry forward:** (1) `v4.7.0` **moved** — pre-release testers who fetched the old tag must delete and re-fetch; (2) F7 remains open — prose quoting a destructive pattern is denied through Bash, and `git commit -F <file>` is the sanctioned path until the parser ticket lands.

## Cross-artifact consistency check (before release)

```
☐ Every AC1..AC9 exercised by ≥1 task
☐ Every decision M1..M10 cited by ≥1 task
☐ Every T1..T5 discriminator observed RED at 85b97dd; every negative control green
☐ Clarify Q-A..Q-D resolved in spec.md
☐ T1..T6 SHAs recorded; T8 code-review + security-permissions-review both pass on that candidate
☐ No TODO/FIXME/WIP in diff
☐ .gitattributes and both hashing functions show EMPTY diff (M1/M2)
☐ Linux container run green (mandatory — the last release's exact miss)
☐ README version badge equals VERSION
☐ Spec still DRAFT (flips in T9)
☐ check-module-size.sh --all clean; upgrade.sh did not grow past ceiling
☐ Zero mirror drift
```

Any item fails → redirect. Do not bypass.
