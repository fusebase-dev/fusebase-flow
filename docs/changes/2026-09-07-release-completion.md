# Release completion

**Outcome:** integrate the v4.15.0 release portability repair with the compact maintainer process, then publish the verified successor as v4.15.2. **Source:** T65 `bbc1629`; T66 `98e414f0e207c10e96a06e402e9f8bd9b3451df3`; T67 `d7501fcb7b2ee442cdc94048accdb428c37c889b`; T69/v4.15.1 `1e5f44ee80a5ccd2479f8b317142511cbcab5bdb`; repair `7a3bd749dca75317546fa8c8726a6fb2901c4a83`. **Status:** v4.15.1 is immutable and unpublished: [tagged run `34174615178`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34174615178) passed Linux, failed Windows at 627/628 essential predicates and skipped publication. T70's two-caller repair and v4.15.2 package are reviewed, verified and ready for commit plus the single tagged two-platform gate.

| Task | Result |
|---|---|
| T65 | `bbc1629`; selective repair integration preserves T63's seven diagnostic exclusions and behavior-based validation/release tests; repairs CRLF exact matching, N/A fail-closed phase reporting, stale fixtures, Linux Bash resolution and disabled validator-reuse claims |
| T66 | `98e414f`; v4.15.1 carriers, release notes, derived version strings, generated mirrors and restamped manifests |
| T67 | Replace T14's MSYS-specific missing-Python PATH with the shared deterministic minimal-PATH fixture; production recovery behavior and its exit-2 plus zero-write contract are unchanged |
| T68 | Normalize Windows fixture path identities, write T13 recovery sources root-relative and find Bash beside Git's `mingw32`/`mingw64` layout; production recovery behavior is unchanged |
| T69 | Select 29 registered essential consumer phases explicitly, require the T33 runner-trust owner and package checks, keep full diagnostics callable, and make one exact-tag two-platform gate the publication authority |
| T70 | Send skill and agent mirror plan sources and authorized manifests root-relative so MSYS short paths and native Python long paths retain the same fail-closed ownership boundary; prepare v4.15.2 |

Historical T61 evidence remains attributed to `7a3bd74`: Linux affected-owner batch 203/204 followed by corrected validation-instructions 15/15; strict Python PY5 13/13; MSYS hook-wiring 41/41. The broader MSYS batch ended incomplete and is not a PASS. Current focused results are recorded below; release evidence requires both jobs and the aggregate gate from `.github/workflows/fusebase-flow-verify.yml` on the exact tagged SHA.

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

## T68/T69 release gate correction

Full candidate run `34170878444` at `d7501fc` passed Linux and ended Windows at 1218/1223 predicates; the verify gate failed. The Windows failures exposed three fixture portability defects and one abrupt-death meta-runner diagnostic. The essential profile keeps consumer behavior and runner trust fail-closed while leaving unrelated diagnostics available for change-scoped use.

| Check | Result / evidence |
|---|---|
| Trigger | Linux SUCCESS; Windows 1218/1223 and `verify-gate` FAILED; no tag/publication; `state/audit/T68-candidate-state.json`, `state/audit/T68-windows-failure.log` |
| Wasted-effort windowing | 9/9 PASS after canonicalizing the Windows temp-root spelling; `state/audit/T68-wasted-effort-windowing.log` |
| T34 recovery selector | 4/4 PASS, including the real group and scoped observability; `state/audit/T69-t34.log` |
| T13 recovery ownership | Existing composite matrix PASS, rc0 in 26 seconds; an earlier entrypoint attempt was INCOMPLETE/rc124 before T13, and a corrected launcher first failed pre-execution at rc2; `state/audit/T69-t13.log`, `state/audit/T69-t13-focused.log` |
| Signal-reap diagnostic | 7/8 PASS, rc1: the forced launch-window child/grandchild survived; identity and collateral controls passed. The unproven sentinel change is excluded from source and retained at `state/audit/T69-deferred-sentinel.patch`; the diagnostic remains callable and no cleanup-fix claim is made. |
| Release selection | New explicit-29 and mode-conflict predicates PASS; the broader local selection owner ended INCOMPLETE/rc124 with no final summary and was not rerun; `state/audit/T69-selection.log` |
| Runner trust | 8/8 PASS for failure, crash, timeout, missing phase, zero rows and unauthorized `N/A`; `state/audit/T69-t33.log` |
| Publication workflow | 56/56 PASS, including mutations removing the essential profile or T33 step; `state/audit/T69-release-authority.log` |
| Syntax, manifests and preflight | Shell 4/4 and Python AST 3/3 PASS; hook 212/212 and managed 376/376 PASS; preflight finished with 0 errors and 0 warnings; `state/audit/T69-shell-syntax.log`, `state/audit/T69-python-syntax.log`, `state/audit/T69-manifests.log`, `state/audit/T69-preflight.log` |
| Independent review | REVIEW_CLEAR, zero source blockers; `state/audit/T69-independent-review.md` |
| Tagged release gate | FAILED on Windows at 627/628 while Linux passed; mirror-skills full-corpus write exposed the short-path caller defect and publication was skipped; exact source/tag `1e5f44ee80a5ccd2479f8b317142511cbcab5bdb`; [run `34174615178`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34174615178) |

The tagged workflow will exercise the complete profile, its distinct report/summary and package checks on disposable Linux and Windows hosts. The existing phase and job bounds remain fail-closed. An essential consumer or runner-trust failure blocks publication; an unrelated diagnostic failure retains its evidence for a separate follow-up without automatically expanding this release.

## T70 portable mirror write and v4.15.2 preparation

| Check | Result / evidence |
|---|---|
| Trigger | v4.15.1 tagged run `34174615178`: Linux SUCCESS; Windows 627/628, `verify-gate` FAILED and publication SKIPPED; `state/audit/T69-tagged-windows.log` |
| Cause and correction | Both shipped mirror callers passed absolute MSYS manifest and canonical-source paths to native Python after it canonicalized the root's 8.3 spelling. Both now pass root-relative sources and their literal authorized relative manifest; writer containment, exact manifest authorization and symlink rejection are unchanged. |
| Short-path caller proof | PASS using distinct long and `GetShortPathNameW` spellings: both real callers completed initial writes, exact manifests, byte/mtime-stable no-ops and one-source repairs; `state/audit/T70-short-path-callers.log` |
| Version and package | Four carriers at 4.15.2; derived strings and mirrors synchronized; hook 212/212 and managed 376/376 manifests; preflight and package integrity PASS; `state/audit/T70-sync.log`, `state/audit/T70-manifests.log`, `state/audit/T70-preflight.log`, `state/audit/T70-package-integrity.log` |
| Independent review | REVIEW_CLEAR; caller symmetry and the unchanged writer safety boundary accepted; `state/audit/T70-independent-review.md` |

**Limits:** exact-state validator receipt reuse remains unavailable; ordinary-consumer timing, five-provider telemetry, real-symlink cases and Windows authority/signing remain unverified. Roll back T65, T66, T67, T69 and T70 separately; never move `v4.15.0` or `v4.15.1`.

Comment-policy review: applied (FR-22).
