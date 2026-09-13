# Active handoff

Mode: run-ledger
**Updated:** 2026-08-12T22:25:52Z
**Branch:** `main`
**Release baseline:** `main` at `096619d` before this corrective documentation commit
**Current HEAD:** the corrective commit containing this handoff

## Release state

| Version | State | Evidence |
|---|---|---|
| `v4.8.0` | PUBLISHED | Tag/release published from `20fd707`. |
| `v4.9.0` | TAGGED, RELEASE FAILED, UNPUBLISHED | Immutable tag targets `096619d`; release workflow failed and published nothing. |
| `v4.9.1` | NEXT | Corrective release; create a new tag after the authoritative-state corrections are committed and verified. |

Do not move or reuse `v4.9.0`. Release publication remains gated by the exact tagged SHA on Linux
and Windows/MSYS per `PUBLISHING.md`.

## Main changes since v4.8.0

| Surface | Commit(s) | Current state |
|---|---|---|
| S2d Python version symmetry | `d5abf3d` | Landed: a resolved `python3` must prove Python >=3.10. |
| S2b git fail-closed | `facae26` | Landed: broken git in repository context blocks; outside-repository behavior is preserved. |
| R1 denial diagnostic | `ac0879d` | Landed: denial names rule and pattern without claiming match location. |
| R2 deploy-approval receipt | `88b3ea6` | Landed: locked C3 receipt contract is implemented. |
| Release fingerprint table | `eb31188`, `98fbb37` | Landed: managed-content and hook-layer lookup; self-reference limit requires each tag's row in the next release. |
| Published-tag policy | `f08b5a8` | Landed as procedural policy; no repository ruleset mechanically enforces immutability. |
| `INSTALLED_FROM` | `9fdba11`, reverted by `519170d` | REVERTED — NOT SHIPPED. It described a future upgrade source and could not identify the tree already on disk; fingerprint lookup superseded it. |

T4-T8 in `docs/specs/consumer-escalation-v480/spec.md` were T1 fix-forward work and are moot after
`519170d`.

## Open

| Item | State | Next evidence/action |
|---|---|---|
| R1 root defect (K21/M8) | OPEN | Parser/matching behavior still treats honest quoted prose as executable text; S4b owns any semantic change. |
| Tag immutability | OPEN — procedural only | Apply repository-side enforcement; until then, operator confirmation is the control. |
| Windows job-probe flake | OPEN — cause unproven | Instrument rc, elapsed time, helper-path outcome, and output marker before choosing retry logic. See `docs/backlog/release-gate-flaky-job-probe/README.md`. |

## Next action

Prepare and verify the `v4.9.1` corrective release from a new commit on `main`; do not alter the
`v4.9.0` tag. After tagging `v4.9.1`, append the exact row emitted by
`bash hooks/local/print-release-fingerprints.sh v4.9.1` for delivery in the following release.
