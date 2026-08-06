# Implement handoff — T9 and T2

Attest as **AI Developer** under Fusebase Flow v4.7.1 (FR-01..FR-27 + IM.1..IM.18). Read
`flow-skills/role-discipline/references/ai-developer.md` and
`flow-skills/communication/SKILL.md` — a delegated session inherits no auto-load.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `8917bc2`. Synchronous. Stop at the gate.
Do **NOT** bump VERSION, tag, push, or deploy.

**Authoritative contract:** `docs/specs/backlog-triage-execution/execution-plan.md` — read §2
(evidence register), §3 (locked constraints P1–P10), §6 (task table), §7 (gates). Do not
re-derive anything it already states.

## Write-time discipline (inlined — you do NOT inherit it)

| Rule | At write time |
|---|---|
| FR-22 | Comments only: (1) a tripwire an editor could unknowingly break, (2) a ≤1-line pointer to the WHY-home. Delete WHAT-restating/changelog comments. After the diff, emit `comment-policy review: applied (FR-22)` |
| FR-25 | Module-size ratchet. `hooks/tests/test-cli-flow-recovery.sh` is AT its 954-line baseline — it may **shrink, never grow**. Extraction along a responsibility seam is in-scope, not scope creep |
| FR-09/18 | Artifacts are Mode B: dense, tabular, front-loaded. Replace stale content; never stack old+new |
| FR-03 | **One task = one commit.** T9 and T2 are separate commits. Commit subject prefix must be one of `docs|chore|build|ci|style|revert|merge|flow` or cite a T-number |
| FR-13 | `bash -n` every shell file you touch; pre-commit must pass. Never `--no-verify` |

## T9 — install-document ownership audit (do this first; smaller)

**Targets:** `docs/install-fusebase-cli-project.md`; new `hooks/tests/test-install-fusebase-cli-project-doc.sh`. **No installer automation.**

**Verified defect.** The PowerShell block copies `.fusebase-flow-source\skills`; the Bash block at
the same step correctly copies `flow-skills`. Root `skills/` **does not exist** (canonical moved
in v3.9.0). A Windows operator following the canonical procedure installs **zero** Flow skills.

I already enumerated every `.fusebase-flow-source/<path>` in the file and checked it against the
tree: **exactly one is broken — `skills`.** The other 15 resolve. Do not re-run that sweep as
discovery; re-run it as the test.

**Also in scope (P7 — the plan expands S1 rather than narrowing it):**
- `.codex-plugin/` and `.claude-plugin/` appear only in the *collision/preserve* lists, never in
  either copy block, so a fresh manual install never creates them. Decide and state whether they
  are install-required; if yes, add to both blocks symmetrically.
- The provider-copy path (`.agents/skills/`, `.claude/skills/` snapshots) has **no PowerShell
  equivalent** and sits next to a warning against restoring provider skills from a bundled copy.
  Resolve the contradiction in the document; do not invent new install behaviour.
- The document claims default post-update recovery restores lifecycle settings, but
  `hooks/local/post-fusebase-update.sh` requires `--wire-hooks` for that work. Correct the claim
  to match the code.

**Test (the discriminator).** `test-install-fusebase-cli-project-doc.sh` must:
1. Extract every `.fusebase-flow-source/<path>` from **both** blocks and assert each exists in
   the repo. Against the pre-fix document this **FAILS** on `skills` — prove that, then fix.
2. Assert Bash and PowerShell copy blocks are **symmetric** (same source set).
3. Emit `PASS: install-doc <name>` / `FAIL: install-doc <name>`; exit = fail count.
4. Register tag `install-doc` in `FF_TAGS` in `hooks/tests/run-tests.sh` and add a
   `run_shell_phase` line.

## T2 — instrumentation only (P1: no optimization)

**Targets:** `hooks/tests/test-cli-flow-recovery.sh`; new `hooks/tests/lib/cli-flow-recovery-profile.sh`; new `hooks/tests/test-cli-flow-recovery-profile.sh`.

**Forbidden by P1/P3:** any fixture reduction, invocation consolidation, timeout change, shared
mutable fixture, or optimization selection. This task only makes cost **visible**.

**Do.** Extract a timing helper to `hooks/tests/lib/cli-flow-recovery-profile.sh` (a new file —
this is how you respect FR-25 without growing the 954-line baseline). Emit one structured event
per scenario/substep to a trace file under `state/audit/cli-flow-recovery-profiles/<full-head>/`.
Keep stdout byte-clean: the harness parses `^PASS:`/`^FAIL:` and a strict summary — traces go to
the file and/or stderr, never stdout.

**Trace schema — record, per event:** event name, scenario id, monotonic start/end, duration,
plus the invoked script basename. **Provenance:** full HEAD SHA, platform, and any non-default
`FF_*` values. **Redaction:** allowlist `FF_*` names only; never dump the environment.

**Test.** `test-cli-flow-recovery-profile.sh` asserts the trace file is created, is parseable,
that durations are non-negative and monotonic, and that provenance fields are present. Register
tag `cli-flow-profile` in `FF_TAGS` + a `run_shell_phase` line.

**Module-size proof.** After T2, `hooks/tests/test-cli-flow-recovery.sh` must be **≤ 954 lines**.
Run `bash hooks/local/check-module-size.sh --staged` before committing.

## Verify before you stop

```
bash -n <each shell file touched>
bash hooks/tests/test-install-fusebase-cli-project-doc.sh      # T9
bash hooks/tests/test-cli-flow-recovery-profile.sh             # T2
FF_ONLY=install-doc,cli-flow-profile bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --staged
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

Restamp both manifests in the **same commit** as the code (a stale manifest reddens CI — this
repo has done it twice). Do **not** run the full `run-tests.sh`: `cli-flow-recovery` alone takes
~26 min and its bound is a known open defect.

## Report back

Per task: T-number, commit SHA, files, the discriminator result (red arm before / green after),
module-size result, and anything you could NOT do. If a target turns out to be wrong, **STOP and
report** — do not improvise a different fix. If you hit a transient provider error, retry; a
rate-limit is a dispatch failure, not a task verdict.
