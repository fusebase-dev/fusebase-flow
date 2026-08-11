# Implement handoff — step 4: decompose `cli-flow-recovery`

Attest as **AI Developer** under Fusebase Flow v4.7.1. Read
`flow-skills/role-discipline/references/ai-developer.md` + `flow-skills/communication/SKILL.md` —
a delegated session inherits no auto-load.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `896cbf7`. **Only session on this branch** —
verify HEAD + clean tree (untracked `docs/wasted-code/` excepted) first; STOP if either differs.

**Contract:** `docs/specs/backlog-triage-execution/architecture-review.md`, step 4. Do not
re-derive it.

## Write-time discipline (inlined — not inherited)

| Rule | At write time |
|---|---|
| FR-22 | Tripwire + ≤1-line WHY pointer; emit `comment-policy review: applied (FR-22)` |
| FR-25 | Never grow a baselined file; extract instead. `test-cli-flow-recovery.sh` is at **953** |
| FR-09/18 | Mode B; replace stale content, never stack old+new |
| FR-03 | One commit. Subject: `docs\|chore\|build\|ci\|style\|revert\|merge\|flow` prefix or a T-number |
| FR-13 | `bash -n` all touched; pre-commit must pass; never `--no-verify` |

Restamp **both** manifests in the same commit.

## The target

`hooks/tests/test-cli-flow-recovery.sh` — 953 lines, **31 assertion groups**, **10 full
`cp -R "$PROJECT"` clones**, ~26 recursive copies, ~26 minutes. Measured cost is NOT the copies
(0.43s each); it is **~9 direct `post-fusebase-update.sh` invocations at ~78s** plus health-engine
drives. Reducing clones is for isolation and clarity; reducing *invocations* and *fixture size* is
what buys time.

## Required outcome (the review's own discriminator)

1. **All 31 predicates preserved.** Produce an explicit mapping — old assertion → new test/row.
   A predicate that has no home is coverage loss, not a decomposition; if one cannot be carried,
   STOP and report rather than dropping it.
2. **Full `$PROJECT` clones: 10 → 1.**
3. Both CI paths still green (`GITHUB_ACTIONS`/`CI` takes the full path automatically).

## How, and the constraints on how

- **Cheaper fixture, not less coverage.** The test references only **2** skills by name
  (`communication`, `role-discipline`) out of 34, and has **no hard-coded skill counts** — verified.
  A reduced fixture is therefore possible without weakening any named assertion. But an earlier
  review warned: do **not** pick fixture members from what current assertions happen to mention —
  that is circular. Use **synthetic representative** skills covering more than one layout
  (`SKILL.md`-only, and nested `references/`/assets), assert every fixture member in **both**
  provider mirrors, and keep a separate full-production `mirror-skills.sh --check` so production
  breadth is not lost.
- **No shared mutable fixture across scenarios.** One clone means one *base*; scenarios must not
  mutate a shared tree in sequence and depend on order. Restore or re-derive per scenario.
- Reduce `post-fusebase-update.sh` invocations only where a scenario genuinely does not need its
  own run. Say which you merged and why.
- `hooks/tests/lib/cli-flow-recovery-profile.sh` still exists — use it to record before/after
  timings. It is deleted at step 7, not now.

## Verify before stopping

```
bash -n <each shell touched>
FF_ONLY=cli-flow-recovery bash hooks/tests/run-tests.sh      # time it, before and after
bash hooks/tests/run-tests.sh                                 # fast default still ~5m30s, 111/111
bash hooks/local/check-module-size.sh --staged
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

Do **not** run the full attesting gate. Scoped runs are not release evidence — CI on the tagged
SHA is (`9e9904e`).

## Report

Commit SHA; the **31 → new** predicate mapping in full; clone count before/after; phase wall time
before/after; fast-default timing unchanged; module-size result; and anything you could not carry.
If a predicate cannot be preserved, STOP and report — do not drop it. A transient provider error
is a dispatch failure, not a task verdict: retry it.
