### Q1 — Accuracy under M17

Not fully accurate.

- M17 wording is now correct: the anchor is outside the repaired tree, not consumer control; downgrade cost and fail-closed semantics are accurately stated at [decisions.md:308](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:308>) and [decisions.md:318](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:318>).
- The release note’s “second authority” paragraph is properly qualified: Git objects defeat worktree restamping but are not upstream provenance when the staging repository is writable by the same principal. [v4.7.0.md:130](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:130>)
- New overclaim: “the only write that can precede the bind” is false; Q4 details the additional temporary-tree writes. This appears in [decisions.md:256](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:256>), [v4.7.0.md:105](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:105>), and [bootstrap-upgrade.sh:464](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:464>).
- New overclaim: “one runnable `RECOVER:` line” is not true for legitimate `--source` paths requiring shell quoting. [decisions.md:317](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:317>)
- Surviving overclaim in the M16 anchor table: a plain-source `cp -R` result is called an “immutable snapshot,” although it is writable and preserves symlinks. [decisions.md:308](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:308>) [materialize-managed-source.sh:83](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:83>)

No true guarantee was unnecessarily weakened: source-only membership, non-shrink after binding, and rc-0-plus-exact-`MATCH` remain intact.

### Q2 — Defect 2

Yes, the named symlink defect is fixed.

Every bound manifest, and every source-required wrapper, passes through `ff_boot_linked_seg` before presence or hashing. Leaf and parent components are checked. [bootstrap-upgrade.sh:292](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:292>) [bootstrap-upgrade.sh:330](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:330>) Every bound record reaches that check through the saved-set loop. [bootstrap-upgrade.sh:503](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:503>)

- Legitimate non-symlink consumers retain the same verdict behavior.
- `..`, empty paths, trailing slashes, and unusual caller input cannot reach this function: its paths are fixed records in `FF_REPAIR_LAYERS`. [bootstrap-upgrade.sh:232](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:232>)
- The segment walk is equivalent to `_ff_repair_dest_ok`’s symlink walk, but not its complete containment/non-regular-file validation. [materialize-managed-source.sh:303](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:303>)
- Hardlinks and bind mounts remain regular files/directories and pass. Junction rejection depends on whether the host exposes the reparse point through `test -L`. Those are not the specified symlink/R2 defect and do not exceed M17’s same-principal model.

### Q3 — Defect 3

Not completely fixed.

For safe, shell-simple source paths, both intended branches work:

- Reported wrapper → `--repair-managed <wrapper>`.
- Unreported manifest → ordinary upgrade under K13b.

The membership decision comes from the live drift output. [bootstrap-upgrade.sh:315](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:315>) Calling `ff_managed_drift_paths` is acceptable: it is explicitly part of the repair API, and its result selects advice only; the verdict still comes from isolated Python, rc 0, and exact `MATCH`. [materialize-managed-source.sh:14](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:14>) [bootstrap-upgrade.sh:367](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:367>)

Blocking defect: `$SRC_OVERRIDE` is interpolated without shell quoting. A path containing spaces, quotes, command substitutions, semicolons, or newlines yields a broken or injectable recovery command. [bootstrap-upgrade.sh:316](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:316>) [bootstrap-upgrade.sh:322](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:322>) Test 3h-9 uses only `.fusebase-flow-source` and executes the text through `eval`, so it does not cover this. [test-upgrade-repair-managed.sh:693](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:693>)

If `$SOURCE_TREE` disappears, drift discovery silently becomes empty and emits the ordinary-upgrade branch. That distinction remains advice-only and cannot forge the current verdict, but restoration is no longer guaranteed if the original `--source` also disappeared.

### Q4 — Defect 4

No. The narrowed claim remains false.

All installed-materializer routes—including `--source`, reused staging, and `--repo` after cloning—create and populate a temporary `ff-source-*` tree before the bind. [bootstrap-upgrade.sh:447](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:447>) [materialize-managed-source.sh:202](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:202>) [materialize-managed-source.sh:213](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:213>)

The embedded pre-4.7.0 route likewise creates and populates a temporary tree before binding. [bootstrap-upgrade.sh:384](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:384>) [bootstrap-upgrade.sh:407](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:407>)

The true invariant is narrower: no pre-existing consumer file is touched before binding; `.git/info/exclude` and managed-path writes occur afterwards. The absolute “only write” claim is NO-SHIP-class inaccurate.

### Q5 — Regressions

Apart from the Q1/Q3/Q4 defects, B1–B8, R1–R5, K10, M13’s verdict semantics, and M16’s saved-set semantics remain intact.

- No source-supplied shell reaches a verdict; source shell is admitted only after verification for the repair API. [bootstrap-upgrade.sh:110](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:110>)
- Post-repair success still requires rc 0 and exact parsed `MATCH`. [bootstrap-upgrade.sh:367](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:367>)
- Membership binds once and the saved records are never re-derived. [bootstrap-upgrade.sh:251](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:251>) [bootstrap-upgrade.sh:480](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:480>)
- `ff_repair_managed` write atomicity is unchanged. [materialize-managed-source.sh:349](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:349>)
- FR-07 protected paths listed at [protected-paths.yml:89](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/protected-paths.yml:89>) have empty diff.
- M2 hashers, M3 `run-with-timeout.sh`, `.gitattributes`, and `templates/**` have empty diff.
- Both manifest verifiers return `MATCH`; recorded hashes agree in both manifests. [hook-layer-manifest.json:48](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/audit/hook-layer-manifest.json:48>) [managed-content-manifest.json:284](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/audit/managed-content-manifest.json:284>)
- `bootstrap-upgrade.sh` is exactly 799 lines against the 800-line ceiling. [module-size.yml:18](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/module-size.yml:18>) [bootstrap-upgrade.sh:799](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:799>)

### Q6 — Tests

- **3h-8:** sound RED discriminator. Fixture construction, both-verifiers-`MATCH` precondition, repair occurrence, symlink survival, correct diagnostic, and all-or-none platform coverage are independently asserted. The zero-fixture SKIP is honest. [test-upgrade-repair-managed.sh:621](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:621>) [test-upgrade-repair-managed.sh:658](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:658>)
- **3h-9:** sound for its two simple-path fixtures; `$?` is captured immediately and the grep cannot match test commentary. It misses quoting/injection cases, while `eval` can return the status of an injected final command rather than the intended recovery command. [test-upgrade-repair-managed.sh:688](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:688>) [test-upgrade-repair-managed.sh:693](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:693>)
- **3h-10:** honestly labeled COVERAGE rather than a RED discriminator, but it is false coverage for the stated temporal contract. It compares final file hashes only inside the consumer root, excludes `.git`, staging, the repaired path, backups, and every temporary `ff-source-*` tree; it cannot establish what was written before binding. [test-upgrade-repair-managed.sh:716](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:716>) [test-upgrade-repair-managed.sh:729](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-repair-managed.sh:729>)
- No pre-existing case was changed or weakened; 3h-8 through 3h-10 were appended.

Independent execution was unavailable because sandboxed Git Bash terminated with Windows `CreateFileMapping` error 5; the findings above are structural and do not depend on a test run.

### Q7 — FR-22

The trims did not delete a load-bearing constraint. The M16 block retains source-only membership, the M14 regression tripwire, M17’s threat boundary, and the downgrade-cost statement. [bootstrap-upgrade.sh:240](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:240>) Step 2c retains the two-read TOCTOU, same-principal assumption, “do not move after Step 2b” warning, unsafe-host examples, and retrieval pointer. [bootstrap-upgrade.sh:554](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:554>)

That is a legitimate FR-22 improvement, but compliance remains incomplete: `trust_critical_globs` is empty, while the M16, symlink, and remediation tripwires remain multi-line blocks. [comment-policy.yml:31](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/comment-policy.yml:31>) This is non-blocking under the review policy.

VERDICT: NO-SHIP

| Must-fix item | Class |
|---|---|
| Replace the false “only write before bind” language with the actual invariant, accounting for canonical temporary-tree materialization on every route; make 3h-10 test only what it can prove or add genuine ordering instrumentation. | **(a)** |
| Shell-quote the emitted `--source` value and add recovery tests for spaces/metacharacters without an `eval` status-masking escape. | **(a)** |
| Remove or precisely qualify “immutable snapshot” for plain sources, including preserved-symlink behavior. | **(a)** |

### NON-BLOCKING

- Hardlinks, bind mounts, and platform-specific junction handling remain outside the exact symlink/R2 control and M17’s hostile-co-tenant exclusion.
- FR-22 trimming preserved the constraints but did not reduce all changed tripwires to the configured one-line default.

---
Phase: Verify  
Ticket: upgrade-source-integrity-and-observability  
Next: Fix the three bounded class-(a) defects, then rerun the targeted tests and adversarial review.