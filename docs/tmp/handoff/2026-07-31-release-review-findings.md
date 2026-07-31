## Verdict table

| Area | Verdict | Evidence |
|---|---|---|
| Fail-open closure | **BLOCKER — not fully closed** | The ordinary case is fixed: clean committed objects plus a tampered managed payload aborts before base synthesis or engine execution, naming `audit/managed-content-manifest.json` and the offending path. However, `ff_boot_verify "$SOURCE_CLONE"` executes the verifier from the mutable worktree itself at [bootstrap-upgrade.sh](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:158>). A tampered `managed_content_manifest.py` can print a literal `MATCH`, exit 0, and approve both itself and other tampered worktree bytes. |
| Downgrade guard | **Code is correct; test missing** | Canonical `VERIFIED` plus worktree manifest absence becomes `UNVERIFIED_LEGACY_SOURCE`, then aborts at [bootstrap-upgrade.sh](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:347>). This closes the hide-manifest evasion in the written control flow. No test exercises this branch. |
| Shell trust | **PASS, literally** | No shell from either source tree is sourced to obtain the Step 2c verdict. But mutable-tree Python is executed, which creates the blocker above. |
| Rejected option 1 | **Rejection correct** | Demotion would install the same tampered bytes and contradict M10/M11: `UNVERIFIED_LEGACY_SOURCE` is reachable only when the manifest is absent. |
| Rejected option 2 | **Rejection correct** | Repointing `.fusebase-flow-source` would mutate the operator’s staging area before classification unless implemented through a separate disposable execution workspace. |
| Legitimate consumers | **PASS** | Verification covers only managed paths. Harmless local edits outside the managed set do not cause an abort. Managed staging edits now abort intentionally. |
| TOCTOU | **Residual risk** | There is a window after worktree verification and before/during legacy-engine reads, widened by possible K13 base synthesis or tag fetching. A concurrent local mutation can still change consumed bytes. This is acceptable only if concurrent staging-tree mutation is explicitly outside the threat model. |
| Performance/behavior | **Acceptable** | Pre-boundary sources incur a second managed-tree hash pass. Modern boundary-aware engines are unchanged. |
| Temp-tree cleanup | **PASS** | The transferred tree is released only on engine exit or signal. It remains available throughout engine execution; the basename guard limits deletion to `ff-source-*` trees. |
| Matrix | **12 RUN / 0 WAIVE genuinely represented** | The promoted B/H+ drift and C/H+ completion cells execute distinct H+ routes. No promoted cell is merely a renamed waiver. |
| Matrix completeness assertion | **PASS with limitation** | A cell remaining `RUN` but no longer calling `mx_ran` fails. Reclassifying it to `WAIVE` would still pass because zero waivers is not explicitly asserted. |
| Baseline discrimination | **Mixed by design** | Git B/H± drift cases fail at `5155a95` and discriminate the fix. Plain B/H+ and C/H+ additions would pass there because they are coverage promotions. The temp-leak assertion discriminates `f8fa613`. There is no assertion for manifest hiding or a lying mutable verifier. |
| Portable placement | **PASS** | The matrix and byte-exact group remain above the final `finish`; no portable group was moved below an unconditional exit. |

## Regressions

| Prior item | Status |
|---|---|
| B1 | No shell-helper self-approval regression. The analogous mutable Python-verifier hole is new. |
| B2 | **Closed:** manifest-absent legacy sources complete for plain/git and H±, with the named unverified state. |
| B3 | **Closed:** clean verifier-only sources remain `VERIFIED` and upgrade. |
| R1, R2, R4, R5 | No regression in this delta. Manifest-present failures remain fail-closed; the unsafe fallback was not widened. |
| K10 | **Closed:** a boundary-aware new engine is executed from the verified materialized tree. Only genuine pre-boundary engines use the separately checked worktree route. |
| Cleanup | No use-after-release found. |

The two manifests verify locally as MATCH: 139/139 hook assets and 285 managed assets. HEAD and branch match the request. I did not rerun the reported full suites; this checkout also contains unrelated untracked handoff files, so its current local `git status` is not literally clean.

## Ship verdict

**NO-SHIP for v4.7.0. One production-path fail-open remains.**

Minimal must-fix:

1. For Step 2c, verify `$SOURCE_CLONE` using trusted code from the already-verified canonical tree—or a fully embedded verifier—not `managed_content_manifest.py` from the mutable tree being judged.
2. Add a Git B/H± discriminator that tampers both a managed payload and the worktree verifier to fake `MATCH`; assert abort, exact manifest/path diagnostics, no engine marker, and no managed write.
3. Add the manifest-hide downgrade test. It should assert the engine never runs and the diagnostic names `audit/managed-content-manifest.json`.

The concurrent-mutation TOCTOU should then be explicitly accepted as a local threat-model limitation or removed with an immutable consumed snapshot.

---
🔎 Phase: Verify  
🎫 Ticket: msys-v3307-hardening  
➡️ Next: implement the trusted-verifier fix and the two missing negative controls.