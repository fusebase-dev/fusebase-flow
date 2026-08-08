# Implement handoff — steps 5, 6, 7 (finish the gate architecture)

Attest as **AI Developer** under Fusebase Flow v4.7.1. Read
`flow-skills/role-discipline/references/ai-developer.md` + `flow-skills/communication/SKILL.md`.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `0f72369`. **Only session on this branch** —
verify HEAD + clean tree (untracked `docs/wasted-code/` excepted) first; STOP if either differs.

**Contract:** `docs/specs/backlog-triage-execution/architecture-review.md`, steps 5–7.

## Write-time discipline (inlined — not inherited)

| Rule | At write time |
|---|---|
| FR-22 | Tripwire + ≤1-line WHY pointer; emit `comment-policy review: applied (FR-22)` per diff |
| FR-25 | Never grow a baselined file; extract instead |
| FR-09/18 | Mode B; replace stale content, never stack old+new |
| FR-03 | **One step = one commit.** Subject prefix `docs\|chore\|build\|ci\|style\|revert\|merge\|flow` or a T-number |
| FR-13 | `bash -n` all touched; pre-commit must pass; never `--no-verify` |

Restamp **both** manifests in the same commit as any manifest-collected change.

---

## Step 5 — move `signal-reap` to Windows CI. Commit `A5`.

`signal-reap` measured **1075s** and is fault-injection, not ordinary regression coverage.

- Move it out of the local default into the CI/`FF_FULL` tier (step 3 established those tiers).
- Keep the **field discriminator** (killed harness ⇒ zero surviving descendants) and the essential
  collateral controls (same-executable sibling survives; identity mismatch kills nothing; normal
  exit kills nothing). Collapse repeated scenarios that prove the same property.
- The orphan sentinel must run **only** around the Windows/MSYS deep runner, not on every local
  check — per the architecture review.

**Discriminator:** the local default still completes ~5m30s at 111/111 with no skips-as-passes;
`signal-reap` still runs and passes when explicitly selected; the pre-fix orphan case is still red
against pre-fix code.

---

## Step 6 — required Linux **and** Windows exact-SHA jobs. Commit `A6`. **FR-07 protected.**

**This is the step that makes two-platform gating real.** It is currently *required in prose and
unenforced in machinery* — the enforced job is Ubuntu-only.

`.github/workflows/**` is an FR-07 protected path. The operator has authorized this work in chat.
**You** mint the single-use, digest-bound FR-07 approval (`hooks/local/write-bootstrap-approval.sh`
or `approve-local.sh` as appropriate), commit, then **consume it**. Do not hand the operator a
command; do not proceed without minting one.

- Add a required **Windows/MSYS** job alongside the existing Ubuntu job, both pinned to the exact
  tagged SHA.
- `publish` must be **unreachable** if either job is red, times out, or is skipped.
- Both jobs must run with **committed defaults** — no `FF_SKIP_*`, no timeout overrides. If the
  Windows job does not fit its runner budget after step 4's 18m27s, report the number; do not add
  an override to make it fit.

**Discriminator:** a red or timed-out job on either platform makes `publish` unreachable — prove
it by inspecting the job graph/needs, and state exactly which condition gates publication.

Then update `PUBLISHING.md` + `docs/maintainer-execution.md` to drop the `NOT YET ENFORCED`
qualifier — **only if** the machinery genuinely enforces it now.

---

## Step 7 — delete what is now dead. Commit `A7`.

- Delete `hooks/tests/lib/cli-flow-recovery-profile.sh` + `test-cli-flow-recovery-profile.sh`
  (step 2 made the phase opt-in; step 4 is done, so the diagnostic has served its purpose).
- Remove the `FF_CLI_RECOVERY_TIMEOUT` / override guidance wherever it is documented as the way to
  make the gate pass — that path no longer exists.
- Remove any remaining text describing a local run as release evidence.
- Expose per-scenario rows for the decomposed recovery modules if `run_exitcode_phase`'s
  single-row treatment now hides results (the review lists this; step 4 deliberately deferred it).
  This ripples into `docs/hook-coverage.md`, `docs/fusebase-health/*` and
  `hooks/local/lib/hook-integrity-check.sh` — check each.

**Discriminator:** no required path invokes the deleted files; no shipped document cites the
override or a local run as release evidence; `release-authority` and `ff-only` phases stay green.

---

## Release readiness (after A7)

State plainly in your report whether the repo is releasable, using only what the machinery
enforces:
- both platform jobs required and green on one exact SHA;
- committed defaults, no overrides, no skips-as-passes;
- manifests fresh, mirrors clean, module ratchet clean;
- no shipped document making a claim the code does not hold.

**Do NOT** bump VERSION, tag, push, or publish. That is the operator's call and a separate ticket.

## Verify before stopping

```
bash -n <each shell touched>
bash hooks/tests/run-tests.sh                      # fast default: ~5m30s, 111/111
FF_ONLY=signal-reap bash hooks/tests/run-tests.sh  # still passes on demand
FF_ONLY=release-authority,ff-only bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --all
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

## Report

Per step: commit SHA, files, discriminator red-before/green-after, and for step 6 the exact
publication-gating condition. Then the release-readiness verdict. If a step needs a decision, STOP
and report. A transient provider error is a dispatch failure, not a task verdict — retry it.
