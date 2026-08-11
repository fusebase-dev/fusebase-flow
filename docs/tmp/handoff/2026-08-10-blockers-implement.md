# Implement handoff — B2, B4, B3, the MAJORs, and the B1 measurement job

Attest as **AI Developer** under Fusebase Flow v4.7.1. Read
`flow-skills/role-discipline/references/ai-developer.md` + `flow-skills/communication/SKILL.md`.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `6e428d0`. **Only session on this branch** —
verify HEAD + clean tree (untracked `docs/wasted-code/` excepted); STOP if either differs.

**Contract:** `docs/specs/backlog-triage-execution/blocker-fix-plan.md` (note its header: B1 as
written is **superseded** — do not implement the per-platform tier) and
`plan-review-2.md` for the corrected order.

## Write-time discipline (inlined — not inherited)

| Rule | At write time |
|---|---|
| FR-22 | Tripwire + ≤1-line WHY pointer; emit `comment-policy review: applied (FR-22)` per diff |
| FR-25 | Never grow a baselined file; extract instead |
| FR-09/18 | Mode B; replace stale content, never stack old+new |
| FR-03 | One item = one commit. Subject prefix `docs\|chore\|build\|ci\|style\|revert\|merge\|flow` or a T-number |
| FR-13 | `bash -n` all touched; pre-commit must pass; never `--no-verify` |

Restamp **both** manifests in the same commit as any manifest-collected change.
`.github/workflows/**` is FR-07 protected — the operator authorised this in chat, so **you** mint
the single-use digest-bound approval, commit, then consume it.

---

## C1 — B2: a force-moved tag must not publish unverified code. **Highest value.**

`gh release create --verify-tag` matches on tag **name** only; the tag target is never compared to
the SHA that passed `verify`.

Resolve the tag's target SHA at publish time and compare it to the SHA `verify` ran on. Mismatch ⇒
refuse and fail loudly.

**Also enumerate and report the other paths to publication** the review named — manual Release
creation, `workflow_dispatch`, re-running an old workflow. Close what the workflow can close; for
anything that requires a repo setting (tag protection, branch protection, restricting who can
publish), **report it as an operator action** rather than pretending code closed it.

**Discriminator:** simulate a tag whose target ≠ the verified SHA ⇒ publish must refuse. Prove the
matching case still publishes.

---

## C2 — B4: a skipped discriminator is a non-pass

`hooks/tests/test-run-tests-signal-reap.sh` — three of four discriminators can `skip()`, and
`finish()` excludes skips from the exit status. A loaded Windows run can lose most coverage and
still exit 0.

- A skipped **DISCRIMINATOR** must make the phase non-zero. **CONTROLS** may still skip.
- Keep skips reported separately and never counted as passes.
- **Do not** convert a genuine "cannot run on this platform" into a permanent red: if a
  discriminator is structurally inapplicable, it must be *excluded by construction* (not present
  on that platform) rather than present-and-skipping. State which case each row is.

**Discriminator:** force each discriminator's skip branch ⇒ phase exits non-zero; force a control's
skip ⇒ phase still passes.

---

## C3 — B3: predicate 32 must exercise production recovery/write

`hooks/tests/cli-flow-recovery-direct.sh` — it compares an already-mirrored tree; it never runs
production **recovery/write** mode over the full corpus, so the 4-skill fixture can hide a
production-only regression.

**Discriminator:** break a production-only path in `mirror-skills.sh` write mode ⇒ predicate 32
goes red. It must not be satisfiable by parity alone.

---

## C4 — the MAJORs. One commit, or one each if they fight.

| # | Fix |
|---|---|
| 7 | rc 124/137 must not land in the generic crash branch — restore the load-vs-defect distinction **without** restoring an escape hatch (a bound hit is still a FAIL, just a *labelled* one) |
| 12 | `hooks/git/pre-commit` fails open when `python3` is absent. Make it **fail closed** — this was step 3's stated safety justification and it is currently false |
| 9 | dual-platform `verify` runs on ordinary pushes/PRs ⇒ template consumers inherit maintainer-grade runner cost with no opt-in. Scope triggers to release/maintainer paths (North Star hit) |
| 8 | recovery bound headroom 1.64x vs documented 2–3x — either raise the ceiling with recorded justification or record why 1.64x is accepted |
| 10 | `release-authority` anchors still comment-blind in places — anchor to structure, not prose |
| 11 | no shipped writer can mint the Step-6 FR-07 approval as documented (`approve-local.sh` emits no `paths`, records an unverifiable `repo_id`). **Fix it or file it** — do not leave the documented path broken and silent |

---

## C5 — B1: the measurement job only. **Do NOT choose the architecture.**

Add a **non-publishing, exact-SHA Windows measurement job** whose only purpose is to produce the
number: a full `run-tests.sh` on `windows-latest` with a wall large enough to finish (the estimate
is ~88m; give it real headroom, e.g. 180 min) and **per-phase timings emitted**.

- It must be **manually triggered** (`workflow_dispatch`) and must **not** gate publication.
- It must run **committed defaults** — no `FF_SKIP_*`, no overrides.
- Its output must be retrievable: per-phase wall times, total, and the SHA.

**Do NOT** implement a per-platform tier, sharding, or a ceiling change. The review's order is
measure → then choose, and choosing before measuring is what it rejected.

---

## Verify before stopping

```
bash -n <each shell touched>
bash hooks/tests/run-tests.sh                       # fast default ~5m30s, no regression
FF_ONLY=signal-reap,release-authority,ff-only bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --all
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

## Report

Per item: commit SHA, files, discriminator red-before/green-after. For C1, the full list of
publication paths and which remain open as operator actions. For C5, confirm the job is
non-publishing and manually triggered. Anything you could not do — say so; do not improvise a
decision the review reserved for measurement. A transient provider error is a dispatch failure,
not a task verdict: retry it.
