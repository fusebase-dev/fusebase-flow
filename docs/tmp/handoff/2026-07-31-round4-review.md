1. CLOSURE 1

**Not closed.**

- Trusted-verifier provenance is correct: `$SOURCE_TREE` is materialized and verified before repair, remains alive, and repair requires `FF_SOURCE_STATE=VERIFIED`. Both modules come from `$SOURCE_TREE`, never the repaired consumer root ([bootstrap-upgrade.sh](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:346>), [repair gate](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:379>)).
- Missing module/Python, empty or malformed output, `ABSENT`, `DRIFT`, `BROKEN`, and non-exact `MATCH` all fail closed.
- **Blocker 1 — verifier rc is ignored.** `ff_boot_repair_verify` captures output but not `$?`; it accepts parsed `MATCH` regardless of verifier rc ([lines 262–266](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:262>)). Because the function is invoked as the left side of `||` at line 388, Bash disables `errexit` within that function call. `MATCH` plus rc 1/2/4/signal therefore returns 0. This directly violates the required “verifier rc != 0 fails” closure.
- `audit/hook-layer-manifest.json` really is in `MANAGED_FILES` ([managed_content_manifest.py:42](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/managed_content_manifest.py:42>)). Thus deleting only the hook manifest is caught by the managed-content verifier.
- **Blocker 2 — the skip is nevertheless an escape hatch.** `audit/managed-content-manifest.json` has no independent anchor. Concrete deterministic case:

  1. Delete the managed-content manifest.
  2. Leave the hook manifest present, with one hook path drifted; also leave unrelated workflow drift.
  3. The hook verifier authorizes repairing the hook path.
  4. Post-repair hook verification returns `MATCH`.
  5. Managed-content verification is skipped because its manifest is absent ([line 247](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:247>)).
  6. The unrelated workflow drift is invisible and the repair exits 0.

  This differs from the old wrapper-presence loop, which would run the installed managed verifier and receive rc 4. If both manifests are absent before authorization, repair normally refuses because no verifier reports a path. If they disappear after authorization, both post-checks skip and exit 0—a second TOCTOU form.
- Remaining Python invocations:

  - The hop’s verdict-bearing calls are isolated through `ff_boot_py`; no bare call remains there.
  - Both verify wrappers use `-I -S`.
  - `hook-integrity-check.sh` still uses bare Python for summary/path formatting—diagnostic, not rc classification—and for the optional deep fixture runner, whose rc is verdict-bearing.
  - `preflight.sh` retains several bare verdict-bearing Python checks.
  - CI’s runner-parity command is bare and verdict-bearing.
  - Both stamp wrappers remain bare; `stamp-hook-manifest.sh` remains `$PYTHON`-selectable. These are tooling generators followed by diff plus isolated verification, not integrity verdicts themselves.
- No repository caller sets `PYTHON=` for either verifier except the adversarial test. Removing it does not break an internal caller. On a `python`-only host, hook verification falls back successfully; managed-content verification still requires `python3`, exactly as before. Therefore the claim that **both** wrappers fall back `python3 → python` is false, though not a T8 regression.

2. CLOSURE 2

The three T9 corrections themselves match the code:

1. Hostile-interpreter hardening is scoped to the source-verdict boundary, not every later interpreter.
2. The legacy engine’s classifier remains exposed to ambient `PYTHONPATH`/`sitecustomize`.
3. Ahead/behind worktrees abort only when divergence touches managed content, `VERSION`, or top-level `docs/*.md`.

The disclosure is still incomplete:

- [Line 139](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:139>) says the post-repair re-check is hardened, but its verdict logic has the rc and manifest-skip fail-opens above.
- [Line 127](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/release-notes/v4.7.0.md:127>) says a re-stamped manifest aborts for a manifest-bearing source without qualifying transport. That is true for the git canonical-tree/worktree comparison, but false for a plain `--source` directory: the snapshot, payload, verifier, and re-stamped manifest share one authority and can verify self-consistently. Plain-source authenticity therefore depends on trusting the supplied directory; this is not disclosed.

3. REGRESSIONS FROM T8/T9

- Happy path remains intact: with both manifests present, both canonical modules return rc 0 plus parsed `MATCH`, so repair exits 0. The existing AC3 case tests this end-to-end.
- Wrapper behavior is otherwise preserved: same module arguments and exit contracts; `-I -S` is compatible because both modules are stdlib-only. Health timeout handling and rc mapping are unchanged. Managed-content’s lack of `python` fallback is pre-existing.
- B1–B7, R1/R2/R4/R5, K10, M10, and M11 remain intact. **B8 is only partially closed:** hostile startup and `$PYTHON` selection are closed; exact fail-closed post-repair verification is not.
- Both B8 tests are genuine discriminators at `490e569`:

  - The post-repair case leaves two real drifts and repairs only one; the old bare interpreter forges success.
  - The wrapper fixture now copies the wrapper and module, stamps a real manifest, proves clean rc 0, creates real handler drift, proves ordinary nonzero, then attempts `$PYTHON` and `PYTHONPATH` forgeries. It is no longer the prior bash-127 tautology.
  - The clean control works under both baselines; the induced handler drift is real.
  - Missing cases: `MATCH` plus nonzero rc, absent managed manifest plus cross-layer drift, and manifests disappearing after authorization.
- T8/T9 audit changes are restamps only; every changed hash matches the corresponding file, and both modules currently report `MATCH`—140 hook assets and 286 managed assets.
- No gated source exceeds 800 lines: bootstrap 658, upgrade 737, materializer 441, tests ≤596. The JSON manifests are 569/1153 lines but are generated data, outside the source-module ceiling.
- Both ranges pass `git diff --check`; protected-path diff across `dea4445..d44618f` is empty.
- I could not independently rerun Bash tests in this read-only Windows sandbox because Git Bash aborts with `CreateFileMapping ... Win32 error 5`. The reported Windows/Linux gates are consistent with the static trace but do not exercise the two missing failure cases.

4. WHOLE-TICKET VIEW

The pre-boundary route is structurally coherent, not a pile of point patches:

- one canonical materialization boundary;
- verifier code selected from the proven tree;
- isolated interpreter helpers;
- exact duplicate-rejecting verdict parsers;
- an explicit legacy capability branch;
- a binary-safe CRLF-only comparator for enumerated unmanaged inputs.

The defects are localized inconsistencies:

- `ff_boot_verify` and `_ff_mms_verify` require both rc 0 and exact `MATCH`; `ff_boot_repair_verify` requires only the latter.
- Hook-manifest absence is anchored by the managed manifest; managed-manifest absence has no reciprocal anchor.
- The two verdict parsers agree; the disagreement is in caller logic, not parsing.

Accepted residuals already documented:

- mutable staging-directory TOCTOU and its single-principal assumption;
- `UNVERIFIED_LEGACY_SOURCE` compatibility without integrity;
- ambient Python execution in a pre-boundary engine after handoff;
- the enumerated unmanaged-input list must grow if future legacy engines read new paths;
- conservative aborts for consumed-path worktree divergence and untracked top-level docs.

Missing disclosure: manifest-bearing plain directories provide self-consistency, not independent upstream authenticity.

5. SHIP OR NO-SHIP

**NO-SHIP — finite defects, not a structural rejection.**

Remaining ship blockers:

1. Post-repair verifier rc is not required to be zero.
2. Manifest-absence skipping can suppress a required layer check and return success with remaining drift; both checks can also disappear after authorization.
3. Release notes overclaim plain-source re-stamp detection and currently overstate the post-repair guarantee.

Do not re-point or publish `v4.7.0`. Hand the ticket back as a design decision: define which manifests a repair must require, bind that set before authorization, require `rc == 0 && parsed verdict == MATCH`, and either disclose plain-source trust explicitly or introduce an independent trust anchor.

State: Architect | Phase: Verify | Ticket: msys-v3307-hardening | Next: keep v4.7.0 unpublished and return the repair-verification contract for design disposition.

VERDICT: NO-SHIP