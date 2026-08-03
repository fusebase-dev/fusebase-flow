### Q1 — Item 1

The quoting is correct for the repository’s Bash contract.

- `printf '%q'` protects every non-NUL value Bash can carry: spaces, quotes, `$`, backticks, newlines, globs, UTF-8 bytes, and leading `-`. A leading `-` remains safe because `--source` consumes the following argument directly. [bootstrap-upgrade.sh:69](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:69>) [bootstrap-upgrade.sh:317](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:317>)
- It is not universally POSIX-`sh` portable: `%q` may emit Bash `$'…'` quoting, especially for newlines/control characters. That is non-blocking because this is explicitly a Bash script and the recovery command invokes Bash. [bootstrap-upgrade.sh:1](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:1>)
- The unquoted repair path is safe: it comes only from fixed `FF_REPAIR_LAYERS` records, not operator input. [bootstrap-upgrade.sh:232](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:232>) [bootstrap-upgrade.sh:342](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:342>)
- The test genuinely discriminates the space-path defect. `eval "set -- …"` exposes the old split as distinct argv, and the exact `--source` value is asserted. The remediation exit status is captured immediately from the intended one-command fixture. [test-upgrade-repair-managed.sh:716](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:716>) [test-upgrade-repair-managed.sh:734](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:734>) [test-upgrade-repair-managed.sh:741](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:741>)

Item 1 passes.

### Q2 — Item 2

The implementation satisfies the narrowed invariant: no pre-existing regular file is modified by script-owned filesystem operations before binding.

- Installed-materializer routes create a fresh `ff-source-*` directory, then use `git archive` or `cp -R`. [materialize-managed-source.sh:193](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:193>)
- The embedded route likewise creates and populates only a fresh temporary tree. [bootstrap-upgrade.sh:381](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:381>)
- Cleanup removes only the owned `ff-source-*` tree. [bootstrap-upgrade.sh:126](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:126>) [materialize-managed-source.sh:34](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:34>)
- Binding occurs at line 480; `.git/info/exclude`, repair staging, backup twins, swaps, and rollback operations are later. [bootstrap-upgrade.sh:480](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:480>) [bootstrap-upgrade.sh:493](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:493>) [materialize-managed-source.sh:406](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:406>)

However, item 2 is not completely corrected:

1. The round-7-touched prose still literally says “before any content write” while the same lines acknowledge earlier writes. That is internally contradictory, especially in the consumer-facing release note. [decisions.md:256](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:256>) [decisions.md:300](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:300>) [v4.7.0.md:105](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:105>) [bootstrap-upgrade.sh:464](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:464>)

2. Test 3h-10 is still not co-extensive with its title/result. It snapshots only regular files in the consumer root, excludes `.git` and staging, and filters out the repaired target and backup. It therefore proves only “no other measured consumer file’s final bytes changed,” not “no pre-existing file changed.” Its explicit `NOT write order` qualification and COVERAGE label are honest, but the success claim is not. [test-upgrade-repair-managed.sh:754](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:754>) [test-upgrade-repair-managed.sh:767](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:767>) [test-upgrade-repair-managed.sh:785](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:785>) [test-upgrade-repair-managed.sh:791](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:791>)

These are finite item-2 defects.

### Q3 — Item 3

The M16 qualification is materially accurate: it identifies a private, writable `cp -R` copy, states that symlinks remain symlinks, and expressly denies tamper-proof or immutable-snapshot semantics. [decisions.md:308](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:308>) [materialize-managed-source.sh:83](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:83>)

Outside the deliberately scoped M16 edit, misleading “immutable” wording survives:

- M10 still calls the plain-source copy an immutable snapshot. [decisions.md:200](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:200>)
- The materializer comment does likewise. [materialize-managed-source.sh:85](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:85>)
- More importantly, the embedded route prints “immutable snapshot” directly to consumers. [bootstrap-upgrade.sh:419](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:419>)
- The release note also says every boundary-aware engine receives an immutable tree from git objects, which is not true for a plain source. [v4.7.0.md:122](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:122>)

Per the operator’s explicit scope, these surviving instances are non-blocking observations, although the runtime message is misleading in practice.

### Q4 — Scope

No unauthorized fourth functional change exists.

The delta contains only:

- Item 1 implementation and its space-path test.
- Item 2 wording/test-label changes.
- Item 3 M16 qualification.
- Required manifest re-stamps.
- One comment-only compression of the round-6 symlink tripwire to retain the 799-line ceiling. It preserves byte-identical external-content risk, unrecoverability, the R2 distinction, and leaf/parent coverage. [bootstrap-upgrade.sh:287](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:287>)

No load-bearing constraint was removed.

### Q5 — Regressions

The behavioral invariants remain intact.

- No source-supplied shell carries a verdict; source shell is admitted only after verification. [bootstrap-upgrade.sh:110](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:110>) [bootstrap-upgrade.sh:425](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:425>)
- Post-repair success still requires rc 0 and exact parsed `MATCH`. [bootstrap-upgrade.sh:367](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:367>)
- Membership is bound once, and the saved records drive every later verification. [bootstrap-upgrade.sh:251](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:251>) [bootstrap-upgrade.sh:503](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:503>)
- Consumer manifest/wrapper symlink refusal remains before presence and hashing and is reached for every bound record. [bootstrap-upgrade.sh:291](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:291>) [bootstrap-upgrade.sh:330](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:330>)
- Repair batch atomicity remains unchanged. [materialize-managed-source.sh:349](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:349>)
- The FR-07 paths defined at [protected-paths.yml:84](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/protected-paths.yml:84>) have empty `c77b139..HEAD` diff.
- M2 hashers, M3 `run-with-timeout.sh`, `.gitattributes`, and `templates/**` are untouched.
- Direct isolated-Python verification returned `MATCH`: hook manifest 140/140 and managed manifest 286 listed, zero drift. Recorded hashes agree. [hook-layer-manifest.json:48](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/audit/hook-layer-manifest.json:48>) [managed-content-manifest.json:284](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/audit/managed-content-manifest.json:284>)
- Both source/test files are exactly 799 lines against the 800 ceiling. [module-size.yml:17](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/module-size.yml:17>)

I could not independently rerun the Bash suite because Git Bash terminates in this sandbox with Windows `CreateFileMapping` error 5. That does not contradict the recorded 743/743 Windows and 740/740 Linux gates.

### Q6 — Release readiness

Version carriers inspected are `4.7.0`; an independent read-only reproduction of the sync allowlist found zero stale live-version strings.

The consumer-facing repair bullet is nevertheless internally false as written: it first says binding happens “before it writes any content,” then immediately says writes precede binding. [v4.7.0.md:105](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:105>) That contradiction must not ship in final release notes.

The current checkout also has no tracked or staged diff, but it is not literally clean: `git status --short` reports 49 untracked historical handoff/wasted-code entries. This does not alter the reviewed HEAD and is non-blocking to the commit verdict, but publication should use HEAD or a clean clone.

VERDICT: NO-SHIP

| Must-fix item | Class |
|---|---|
| Replace the surviving literal “before any content write” wording in the round-7-touched M13/M16, release-note, and bind-tripwire text with the actual invariant: no pre-existing file is touched before binding. | **(a)** |
| Rename/rephrase 3h-10 to state exactly what it measures: no collateral final-byte changes among measured, non-target regular files in the consumer root, excluding `.git` and staging; it proves neither global coverage nor write order. | **(a)** |

Zero class-(b) findings.

### NON-BLOCKING

- `%q` recovery syntax is Bash-safe but not guaranteed portable to arbitrary POSIX `sh`.
- Out-of-scope “immutable snapshot/tree” wording remains consumer-visible at `bootstrap-upgrade.sh:419` and `v4.7.0.md:122`.
- The worktree has untracked files, though tracked and staged diffs are empty.

---
Phase: Verify  
Ticket: upgrade-source-integrity-and-observability  
Next: Correct the two bounded item-2 claims, rerun the targeted gate, then repeat this final review.