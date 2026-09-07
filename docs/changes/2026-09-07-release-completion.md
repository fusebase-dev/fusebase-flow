# Release completion

**Outcome:** integrate the v4.15.0 release portability repair with the compact maintainer process, then publish the verified candidate as v4.15.1. **Source:** T65 `bbc1629`; T66 `98e414f0e207c10e96a06e402e9f8bd9b3451df3`; repair `7a3bd749dca75317546fa8c8726a6fb2901c4a83`. **Status:** T65/T66 committed; T67 fixture correction reviewed and ready for commit and exact-SHA CI.

| Task | Result |
|---|---|
| T65 | `bbc1629`; selective repair integration preserves T63's seven diagnostic exclusions and behavior-based validation/release tests; repairs CRLF exact matching, N/A fail-closed phase reporting, stale fixtures, Linux Bash resolution and disabled validator-reuse claims |
| T66 | `98e414f`; v4.15.1 carriers, release notes, derived version strings, generated mirrors and restamped manifests |
| T67 | Replace T14's MSYS-specific missing-Python PATH with the shared deterministic minimal-PATH fixture; production recovery behavior and its exit-2 plus zero-write contract are unchanged |

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

| T67 check | Result / evidence |
|---|---|
| Trigger | Maintainer run `34170069865`: Linux failed T14 because `/usr/bin/python3` remained visible; Windows passed; `state/audit/T67-maintainer-linux.log` |
| Focused T14 owner | 3/3 scoped predicates PASS, exit 0 in 188 seconds with an inherited interpreter override cleared; `state/audit/T67-t14.log` |
| Syntax and manifests | PASS; hook 212/212, managed 376/376; `state/audit/T67-manifests.log` |
| Independent review | REVIEW_CLEAR, zero blockers; `state/audit/T67-independent-review.md` |
| Superseded full candidate | Run `34170085387` on `98e414f`: Linux 1234/1234 hook predicates and remaining package checks passed; Windows was canceled, the both-platform verify gate failed, and the workflow was canceled; `state/audit/T67-candidate-state.json` |

**Limits:** exact-state validator receipt reuse remains unavailable; ordinary-consumer timing, five-provider telemetry, real-symlink cases and Windows authority/signing remain unverified. Roll back T65, T66 and T67 as separate exact commits; never move `v4.15.0`.

Comment-policy review: applied (FR-22).
