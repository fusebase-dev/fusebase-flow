# Release completion

**Outcome:** integrate the v4.15.0 release portability repair with the compact maintainer process, then publish the verified candidate as v4.15.1. **Source:** T65 `bbc1629`; repair `7a3bd749dca75317546fa8c8726a6fb2901c4a83`. **Status:** T65 committed; T66 reviewed and ready for commit.

| Task | Result |
|---|---|
| T65 | `bbc1629`; selective repair integration preserves T63's seven diagnostic exclusions and behavior-based validation/release tests; repairs CRLF exact matching, N/A fail-closed phase reporting, stale fixtures, Linux Bash resolution and disabled validator-reuse claims |
| T66 | This commit: v4.15.1 carriers, release notes, derived version strings, generated mirrors and restamped manifests |

Historical T61 evidence remains attributed to `7a3bd74`: Linux affected-owner batch 203/204 followed by corrected validation-instructions 15/15; strict Python PY5 13/13; MSYS hook-wiring 41/41. The broader MSYS batch ended incomplete and is not a PASS. Current focused results are recorded below; full release evidence requires both jobs and the aggregate gate from `.github/workflows/fusebase-flow-verify.yml` on the exact candidate SHA.

| T65 check | Result / evidence |
|---|---|
| Shell/Python syntax; regenerated manifests | PASS; hook 212/212, managed 376/376; `state/audit/T65-syntax-manifests.log` |
| Merged phase reporting | 8/8 PASS, including unauthorized N/A and MSYS signal-N/A rejection; `state/audit/T65-phase-reporting.log` |
| CRLF/recovery wiring owner | 41/41 PASS under the existing 600-second watchdog; `state/audit/T65-hook-wiring.log` |
| Selection attempt | INCOMPLETE: outer wrapper exit 1 after its 180-second window, no final summary; `state/audit/T65-selection.log`. T63's unchanged selection block retains its prior 27/27 proof; candidate CI must run the complete owner. |
| Independent review | REVIEW_CLEAR, zero blockers; `state/audit/T65-independent-review.md` |

| T66 check | Result / evidence |
|---|---|
| Version sync and mirrors | PASS; ten derived surfaces updated; agent/skill mirrors regenerated with zero pre-existing drift; `state/audit/T66-sync.log`, `state/audit/T66-mirrors.log` |
| Preflight | PASS; 0 errors, 0 warnings; `state/audit/T66-preflight.log` |
| Package boundary | PASS; four carriers at 4.15.1, release note present, tracked public-surface allowlist valid; `state/audit/T66-package-integrity.log` |
| Independent review | REVIEW_CLEAR, zero blockers; `state/audit/T66-independent-review.md` |

**Limits:** exact-state validator receipt reuse remains unavailable; ordinary-consumer timing, five-provider telemetry, real-symlink cases and Windows authority/signing remain unverified. Rollback T65 and T66 by their exact commits; never move `v4.15.0`.

Comment-policy review: applied (FR-22).
