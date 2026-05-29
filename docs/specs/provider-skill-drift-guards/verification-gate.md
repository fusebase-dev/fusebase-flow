# Verification gate — provider-skill-drift-guards

**Linked spec:** `docs/specs/provider-skill-drift-guards/spec.md`
**Linked tasks:** `docs/specs/provider-skill-drift-guards/tasks.md`
**Gate task:** T17
**Pass threshold for smoke:** N/A — framework/template change, no deployed surface. Gate is source-level (preflight + tests + reporters).

## Acceptance-criterion → task mapping

| AC | Implemented in | Test coverage |
|---|---|---|
| AC1 | T13 | run `stamp-cli-provenance.sh`; JSON parse; sha cross-check vs `sha256sum` |
| AC2 | T14 | mutate fixture CLI skill → `CLI_SNAPSHOT_STALE` advisory in reporter output |
| AC3 | T14 | inject `CUSTOM:SKILL` block → reported "at-risk on next refresh" |
| AC4 | T11 | `check-cli-flow-conflicts.sh` healthy; synthetic `app-foo.md` Flow agent → flow-owned |
| AC5 | T12 | grep wired Stop hooks for `jq` → none; `node run-typecheck-apps.js` parses |
| AC6 | T15 | install docs: CLI-owned paths copy-if-absent/excluded; hazard documented |
| AC7 | T10 | `git grep run-typecheck-features.js` / `FR-01..FR-18` → none in tracked files |
| AC8 | T16 | `VERSION`=3.2.0; CHANGELOG + release notes present; README refreshed |
| AC9 | T11..T16 | full gate green + baseline-protection non-regression checks |

## Required gate-report fields (per `policies/gate-contracts.yml`)

| Field | Format |
|---|---|
| Implementation summary | 1–3 sentences |
| Per-task SHAs | `T<n>: <sha> <subject>` for T10..T16 |
| Test counts | `run-tests before/after`; `test-cli-flow-recovery before/after` |
| Lint status | N/A (no app lint); shell/JSON parse instead |
| Typecheck status | N/A (no app typecheck) |
| Worker-undisturbed git diff | `none` (no protected downstream paths) |
| Manifest version | `skill-mirror-manifest` 28 lines unchanged; new `cli-vendor-manifest.json` added |
| Architect/PO deviations | listed with reasoning, or `none` |
| Self-attestation | "Operating as AI Developer..." phrase |

## Lint / typecheck / test commands

| Layer | Command |
|---|---|
| Structure/frontmatter/mirror-drift | `bash hooks/local/preflight.sh` |
| Hook fixtures | `bash hooks/tests/run-tests.sh` |
| CLI/Flow recovery sim | `bash hooks/tests/test-cli-flow-recovery.sh` |
| Conflict reporter | `bash hooks/local/check-cli-flow-conflicts.sh` |
| Health check | `bash hooks/local/fusebase-flow-health-check.sh` |
| Provenance generator | `bash hooks/local/stamp-cli-provenance.sh` |

## Worker-undisturbed paths (this ticket)

None. Template repo; no downstream worker paths. All changes additive to framework tooling/docs.

## Baseline-protection non-regression (must re-confirm at gate)

These were verified CONFIRMED-holding pre-ticket and must NOT regress:

- `mirror-skills.sh` iterates canonical `skills/` only (14) — CLI skills never written by it.
- `agent-surface-ownership.json` keeps `flow_write_mode:"never"` for the 19 CLI provider skills.
- `post-fusebase-update.sh` restore set excludes `.claude/hooks/**`, CLI provider skills, MCP/`fusebase.json`/`skills-lock.json`, active `.codex/config.toml`.
- `audit/skill-mirror-manifest.txt` still 28 lines (14 Flow skills × 2 mirrors); CLI skills excluded.

## Smoke prompts (post-deploy)

N/A — no deployed surface. Source-level gate only.

## Probes (post-deploy)

N/A.

## Manifest version bump

`VERSION`: `3.1` → `3.2.0`. New file `audit/cli-vendor-manifest.json` (provenance). `skill-mirror-manifest.txt` unchanged (28 lines).

## Rollback procedure

If any gate check fails: fix forward within the failing task's commit, or `git revert <task sha>`; spec stays DRAFT until gate is green.

## Cross-artifact consistency check (mandatory before approving DRAFT→DONE)

```
Constitution invariants verified:
☐ Worker-undisturbed list — touched files: none downstream
☐ Mixed-fleet — N/A (edition template)
☐ Migration approach — no migration (additive)
☐ Auth model — N/A
☐ Quality bar — provenance generator + drift/CUSTOM tests added; preflight extended

Cross-artifact:
☐ Every AC1..AC9 exercised in at least one task
☐ Every locked decision B1..B8 cited in at least one task
☐ All clarify Q-A/B/C resolved (none remain in spec.md)
☐ All T10..T16 have SHAs filled in
☐ No TODO/FIXME/WIP markers in diff
☐ Baseline-protection non-regression confirmed
☐ Spec status still DRAFT (flips to DONE in the post-review docs commit)
```

If ANY item fails, redirect AI Developer. Do NOT bypass.
