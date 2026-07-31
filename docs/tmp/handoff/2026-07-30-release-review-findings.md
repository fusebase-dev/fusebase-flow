| Blocker | Verdict | HEAD proof |
|---|---|---|
| **B1 — old install trusts source helper** | **CLOSED** | Without an installed materializer, bootstrap uses its embedded snapshot/verdict path at [bootstrap-upgrade.sh:187](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:187>). Plain bytes are snapshotted at lines 220–225 and judged by embedded `ff_boot_verify` at lines 141–184/230–236. Source shell is sourced only after `VERIFIED` at lines 240–247. Therefore a tampered helper overriding `ff_source_verify_tree` is reported as manifest DRIFT and never sourced. `backup-hygiene.sh` follows the rule: installed copy is default; the source copy is selected only when `FF_SOURCE_STATE=VERIFIED` at lines 273–279. The source’s Python verifier is executed under M11’s existing trust model, but no source-derived shell runs before the verdict. |
| **B2 — genuine pre-manifest/no-helper source cannot complete** | **CLOSED** | Manifest absence becomes `UNVERIFIED_LEGACY_SOURCE` at [bootstrap-upgrade.sh:145](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:145>). If the engine lacks `--source-tree`, bootstrap first rebinds `ENGINE_SRC` to the persistent source tree at lines 417–428, then releases the temporary tree at lines 432–433, and finally executes the persistent engine at line 437. Internal flags are constructed only in the opposite branch at lines 409–414. The plain+git fixtures inspect argv and delivery at [test-upgrade-source-boundary.sh:374](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-source-boundary.sh:374>). |
| **B3 — verifier-only v4.7.0 source stranded** | **PARTIALLY CLOSED** | A clean manifest+`managed_content_manifest.py` source no longer needs a materializer: embedded verification accepts literal `MATCH` at [bootstrap-upgrade.sh:141](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:141>), and both clean plain/git historical-shape fixtures upgrade at [test-upgrade-source-boundary.sh:410](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-source-boundary.sh:410>). However, M11 is weakened on the git legacy-engine route: bootstrap verifies the git-object snapshot, deletes it, then executes an engine that consumes the mutable worktree. A dirty worktree can therefore install tampered bytes after a `VERIFIED` verdict. |

## New-regression findings

### BLOCKER — verified-tree/consumed-tree split reopens M11 and R1

Concrete failing shape:

1. The verifier-only git source has a clean committed manifest and payload, but its worktree payload or `upgrade.sh` is tampered.
2. Bootstrap archives committed objects into the temporary tree at [bootstrap-upgrade.sh:200](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:200>) and verifies that clean tree at lines 230–237.
3. Because the historical engine is pre-boundary, bootstrap switches to `$SOURCE_CLONE/hooks/local/upgrade.sh` at lines 417–431 and deletes the verified tree.
4. It executes that mutable worktree engine at line 437. The fixture’s legacy engine explicitly copies from `.fusebase-flow-source`, not the verified snapshot, at [upgrade-fixtures.sh:53](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/lib/upgrade-fixtures.sh:53>).

Result: `VERIFIED` followed by installation of unverified bytes. This is a new fail-open introduced while unstranding B3.

The current negative control is plain-only at [test-upgrade-source-boundary.sh:444](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-source-boundary.sh:444>). Its claim that transport cannot change the result is false because git verification reads objects while the legacy engine reads the worktree.

Other regression posture:

- K10 still executes the new engine from the verified temporary tree: [bootstrap-upgrade.sh:320](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:320>) and lines 409–416.
- R2’s symlink/atomic-repair implementation is unchanged; its five assertions were preserved by the extraction.
- R4 and R5 implementation files have empty diffs.
- Supported new-engine routes transfer ownership at bootstrap lines 411–416 and the engine arms cleanup at [upgrade.sh:218](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/upgrade.sh:218>).
- A self-consistent hybrid source with a boundary-aware engine but no materializer leaks its transferred temporary tree: `upgrade.sh` takes the warning-only path at lines 229–231 without arming cleanup. This is not the published historical tag shape, but it should be handled or explicitly rejected.

## Source-shape matrix

Mechanically, the closing assertion works:

- It generates all 12 keys and detects a missing/renamed row at [test-upgrade-source-boundary.sh:503](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-source-boundary.sh:503>).
- A RUN without `mx_ran` fails at lines 510–515.
- A WAIVE without a disposition/reason fails at lines 516–519.
- Current count is 8 RUN / 4 WAIVE. No RUN cell is vacuous: each has behavioral rc/content/log/argv checks.

But the B/H+ waiver premise is insufficient. The installed helper does make source-materializer presence irrelevant to the **verdict**, but shapes B/C do not collapse onto A for the complete route:

- A uses a boundary-aware engine consuming the verified tree.
- Historical B uses a legacy engine consuming the mutable source tree.
- C receives a different `UNVERIFIED_LEGACY_SOURCE` verdict.

Accordingly, the B/H+ waivers at lines 42 and 48 do not justify omitting the git dirty-worktree case. The git/B/H− RUN is a meaningful clean-success test, but lacks the required drift control.

## Test reality

- Seven semantic assertion outcomes were added: B2 plain+git, B3 clean plain+git, B3 drift, B1 self-approval, and matrix completeness.
- Transplanted onto `c54f9d9`, the first six fail. Only `source-shape-matrix-is-complete` passes because it is coverage bookkeeping, not a production discriminator.
- The five `upgrade-repair` outcomes already existed at `c54f9d9`; they pass there by design and are non-vacuous regression carriers.
- FR-25 extraction preserved all 15 prior runtime assertions. Current total is 22: 17 boundary + 5 repair, exactly prior 15 + seven additions. No case was silently dropped.
- Neither test has a portable group below an unconditional exit. Boundary’s portable M2 assertion reaches the final `finish` at lines 529–557; repair’s final carrier reaches `finish` at lines 222–240.
- `git diff --check` passed, and both manifests independently report `MATCH`. Local Git Bash could not launch inside the read-only Windows sandbox (`CreateFileMapping`, error 5), so I make no additional local-suite claim beyond the reported Linux/Windows evidence.

## Ship verdict

**NO-SHIP for v4.7.0.**

Minimal must-fix:

1. On the manifest-bearing legacy-engine route, make the engine consume the verified immutable snapshot—or otherwise fail closed. It must never verify git objects and then execute/read the mutable worktree.
2. Add a git verifier-only fixture with a clean committed manifest and tampered worktree. Require DRIFT/abort before engine execution or consumer writes, for H− and the currently waived H+ route.
3. Keep temporary-tree ownership deterministic for any parser-aware/helper-less source, or explicitly reject that unsupported hybrid before ownership transfer.

Comment-policy review: N/A (FR-22; no code diff).

---
🧭 Phase: Verify  
🎫 Ticket: msys-v3307-hardening-final-release-review  
➡️ Next: fix the legacy-engine verified-tree split, add the missing git drift controls, then rerun both platform gates and final review.