# Implement handoff — gate architecture, steps 1–3

Attest as **AI Developer** under Fusebase Flow v4.7.1. Read
`flow-skills/role-discipline/references/ai-developer.md` + `flow-skills/communication/SKILL.md` —
a delegated session inherits no auto-load.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `9f09cfa`. **You are the only session on this
branch** — verify HEAD + clean tree (untracked `docs/wasted-code/` excepted) before starting; if
either differs, STOP and report. Two sessions collided earlier this week.

**Authoritative contract:** `docs/specs/backlog-triage-execution/architecture-review.md`
(verdict `DELETE-AND-MOVE`, seven-step sequence with per-step discriminators). Do not re-derive it.

## Write-time discipline (inlined — not inherited)

| Rule | At write time |
|---|---|
| FR-22 | Tripwire + ≤1-line WHY pointer only; emit `comment-policy review: applied (FR-22)` per diff |
| FR-25 | Never grow a baselined file; extract instead |
| FR-09/18 | Mode B; replace stale content, never stack old+new |
| FR-03 | One step = one commit. Subject: `docs\|chore\|build\|ci\|style\|revert\|merge\|flow` prefix or a T-number |
| FR-13 | `bash -n` everything touched; pre-commit must pass; never `--no-verify` |

Restamp **both** manifests in the same commit as any manifest-collected change.

## The finding this all rests on (verified, do not re-litigate)

The local full gate is **not mechanically required for publication**.
`.github/workflows/fusebase-flow-release.yml` publishes only after its reusable `verify` job
passes on the tagged SHA. The prose disagrees with the machinery: `PUBLISHING.md` requires a local
full run, `docs/maintainer-execution.md` requires two platforms, and the enforced CI job is
**Ubuntu-only**. That inconsistency is the defect.

---

## Step 1 — Lock CI as the sole release-evidence authority. Commit `A1`.

Reconcile the documents with what the machinery already does. **No test logic changes.**

- `PUBLISHING.md` — a release claim rests on the CI `verify` job for the tagged SHA, not a local
  run. Local runs are developer feedback.
- `docs/maintainer-execution.md` — same correction; keep the two-platform *requirement* but state
  plainly that it is **not yet enforced** (the required job is Ubuntu-only) and point at step 6.
- `hooks/tests/run-tests.sh` header + `flow-skills/validation-and-qa/SKILL.md` — stop describing
  the local full run as release proof.
- Health-check text that implies the same.

**Discriminator (must fail today):** a check asserting that no shipped document claims a *local*
run is release evidence, and that `PUBLISHING.md` names the CI job. Grep-based is acceptable here
because the claim is textual; state that limitation in the test header.

**Do not** weaken any safety statement — this narrows *where evidence comes from*, not what is
checked.

---

## Step 2 — Remove `cli-flow-profile` from required execution. Commit `A2`.

It was a temporary diagnostic, never release coverage — it proves trace schema/containment/
redaction, not recovery correctness.

- Remove the `cli-flow-profile` phase from the default/required set in `hooks/tests/run-tests.sh`.
- Keep the files; make the phase opt-in (an explicit `FF_ONLY=cli-flow-profile` still runs it).
- **Do not delete** `hooks/tests/lib/cli-flow-recovery-profile.sh` yet — step 4 needs it for the
  decomposition, and it is deleted at step 7.

**Discriminator:** an unscoped run no longer executes the phase; `FF_ONLY=cli-flow-profile` still
does; required assertion totals change only by that phase's own rows.

---

## Step 3 — Make the fast phase set the local default. Commit `A3`.

- Introduce an explicit fast default: the phases that are cheap and catch real regressions.
- The heavy phases (`cli-flow-recovery`, `signal-reap`, and anything else over ~60s) become
  opt-in locally via a named flag, and remain CI's job.
- The full unscoped run must stay reachable by one explicit invocation for maintainers.
- **Emit a visible banner** stating the local default is not release evidence and naming the CI
  job that is.

**Discriminator (the review's own):** three loaded-host MSYS runs of the local default complete
**within 10 minutes, with no overrides and no skips reported as passes**. Record all three
timings in the commit body.

**Trap:** a scoped/fast run must remain structurally incapable of writing
`state/audit/hook-test-results.md` or matching the strict full-gate summary shape. That guard
already exists — verify you have not weakened it.

---

## Verify before stopping

```
bash -n <each shell file touched>
bash hooks/tests/run-tests.sh                 # the NEW fast default — time it, 3x
FF_ONLY=cli-flow-profile bash hooks/tests/run-tests.sh   # still runs on demand
bash hooks/local/check-module-size.sh --staged
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

Do **not** run the old full monolith — that is the thing being retired.

## Report

Per step: commit SHA, files, the discriminator's red-before/green-after, and for step 3 the three
timings. If a step needs a decision rather than an implementation, STOP and report. A transient
provider error is a dispatch failure, not a task verdict — retry it.
