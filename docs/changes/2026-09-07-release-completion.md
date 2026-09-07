# Release completion

**Outcome:** integrate the v4.15.0 release portability repair with the compact maintainer process, then publish the verified candidate as v4.15.1. **Source:** main `cd4f34a`; repair `7a3bd749dca75317546fa8c8726a6fb2901c4a83`. **Status:** T65 reviewed and ready for commit.

| Task | Result |
|---|---|
| T65 | Selective repair integration: preserve T63's seven diagnostic exclusions and behavior-based validation/release tests; repair CRLF exact matching, N/A fail-closed phase reporting, stale fixtures, Linux Bash resolution and disabled validator-reuse claims; regenerate manifests from the integrated tree |
| T66 | Pending: prepare v4.15.1 carriers and release notes after T65 review/commit |

Historical T61 evidence remains attributed to `7a3bd74`: Linux affected-owner batch 203/204 followed by corrected validation-instructions 15/15; strict Python PY5 13/13; MSYS hook-wiring 41/41. The broader MSYS batch ended incomplete and is not a PASS. Current focused results will be recorded here; full release evidence requires both jobs and the aggregate gate from `.github/workflows/fusebase-flow-verify.yml` on the exact candidate SHA.

| T65 check | Result / evidence |
|---|---|
| Shell/Python syntax; regenerated manifests | PASS; hook 212/212, managed 376/376; `state/audit/T65-syntax-manifests.log` |
| Merged phase reporting | 8/8 PASS, including unauthorized N/A and MSYS signal-N/A rejection; `state/audit/T65-phase-reporting.log` |
| CRLF/recovery wiring owner | 41/41 PASS under the existing 600-second watchdog; `state/audit/T65-hook-wiring.log` |
| Selection attempt | INCOMPLETE: outer wrapper exit 1 after its 180-second window, no final summary; `state/audit/T65-selection.log`. T63's unchanged selection block retains its prior 27/27 proof; candidate CI must run the complete owner. |
| Independent review | REVIEW_CLEAR, zero blockers; `state/audit/T65-independent-review.md` |

**Limits:** exact-state validator receipt reuse remains unavailable; ordinary-consumer timing, five-provider telemetry, real-symlink cases and Windows authority/signing remain unverified. Rollback T65 and T66 by their exact commits; never move `v4.15.0`.

Comment-policy review: applied (FR-22).
