# Workflow: violation-recovery

> **Style:** Mode-B-lite. Per-rule recovery procedures. Hooks reference this workflow via the `reason` field they emit on deny / warn. The role-discipline skill (`flow-skills/role-discipline/SKILL.md`) names the rule; this workflow handles the multi-step recovery.

## When to run

After any of:

- A `pre_tool_use` hook returned `deny` (the agent or operator asks "what now?")
- A `stop` hook blocked a "done" claim (missing required-artifact signal)
- A git pre-commit hook rejected a commit (lint/typecheck/secret/protected-path)
- The operator notices a rule was violated post-hoc (rule was tripped but enforcement wasn't active at the time, e.g., an IDE without hooks)

The agent loads this workflow when a refusal happens and needs to surface concrete recovery steps.

## Recovery procedures by FR rule

### FR-01 — Spec before code

**Symptom:** code was edited without an approved spec.

1. Stop further code edits.
2. File a spec retroactively at `docs/specs/<slug>/spec.md` (status: DRAFT). Include the changes already made in the "Implementation summary" section.
3. Run `requirements-specification` skill backwards: derive AC1..ACn from the change.
4. Run `implementation-planning` skill: produce decisions.md (with the change as recommendation, ALTERNATIVE = revert), tasks.md (T-numbered breakdown of what was done), verification-gate.md.
5. PO + operator review. Decide: keep retroactive change or revert.
6. If keep: continue normal flow (gate report → deploy approval).
7. Document in spec.md audit log: "Spec filed retroactively after code change on <date>; root cause: <why FR-01 was bypassed>."

### FR-02 — Plan before edit

**Symptom:** multi-file change made without a written task list.

1. Stop further edits.
2. Reverse-engineer tasks.md from the changed-file set. One T-number per coherent change unit.
3. Get operator agreement that the task breakdown matches intent.
4. Continue per FR-01 recovery if spec also missing.

### FR-03 — One task = one commit

**Symptom:** multiple T-tasks bundled in one commit, OR commit message missing T-number.

- **Bundled commit (already pushed):** Leave as-is. In the gate report's "deviations" field, note: "Commits SHA `<x>` and SHA `<y>` were bundled at T-{N} and T-{M}; one-task-one-commit discipline was bypassed. Going forward, splitting per FR-03." No history rewrite for shipped commits.
- **Bundled commit (not yet pushed):** `git reset --soft HEAD~1`; re-stage by task; commit each separately with proper T-numbered messages. Lint+typecheck after each.
- **Missing T-number:** if not yet pushed, `git commit --amend` with corrected message. If pushed, document in next gate report.

### FR-04 — Persist handoffs

**Symptom:** handoff content was shown in chat without being saved to disk.

1. Save the handoff to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-<stage>.md` immediately, retroactively.
2. Add a one-line audit note at the top: "Saved retroactively after chat-output on <timestamp>."
3. Verify the saved content matches what was shown in chat.
4. Going forward: save first, then output the path in chat.

### FR-05 — Stop at gate

**Symptom:** AI Developer proceeded past T<gate> without an explicit deploy handoff.

1. Stop further deploy-side work.
2. Verify worker-undisturbed paths are still empty-diff (per FR-07 procedure).
3. Produce the gate report retroactively per `policies/gate-contracts.yml: gate_report` shape.
4. PO reviews and either: (a) authors the deploy handoff post-hoc, OR (b) requires rollback if gate evidence reveals issues.
5. Document in spec.md: "Stop-at-gate discipline bypassed on <date>; gate report produced retroactively."

### FR-06 — Reversible by default (destructive ops)

**Symptom:** a destructive command was run (force-push, reset --hard, rm -rf, --no-verify, etc.) without explicit confirmation.

| Specific case | Recovery |
|---|---|
| `git push --force` to main | Coordinate with team immediately. Reconstruct lost commits from teammates' local clones. Document in `docs/problem-catalog/<date>-force-push-main/problem.md`. |
| `git reset --hard <sha>` | Lost uncommitted changes are irrecoverable (no reflog). Lost commits are in reflog: `git reflog` → `git checkout <sha>` to recover. |
| `git add -A` then committed (`.env` or secrets included) | `git reset --soft HEAD~1` to uncommit. If pushed: rotate the credential immediately. Document in `docs/problem-catalog/<date>-secret-leak/problem.md`. |
| `rm -rf` of code | Restore from git: `git checkout HEAD -- <path>`. If untracked: restore from backup or re-create. |
| `--no-verify` bypassed pre-commit hook | Run `bash hooks/local/preflight.sh` manually. Fix anything the hook would have caught. Document in next gate report. |

### FR-07 — Worker-undisturbed

**Symptom:** a path declared protected in `policies/protected-paths.yml` was modified without an exception artifact.

1. Verify the change was actually intended (not an accidental edit).
2. If accidental: `git checkout HEAD -- <path>` to revert that file.
3. If intended: file an exception artifact at `state/approvals/protected_path_edit-<slug>-<date>.json` with `paths` array listing the approved paths. Operator authors.
4. Re-run `git diff` against `protected-paths.yml`. With the artifact in place, the protected-path check passes.

### FR-08 / FR-09 — Mode A / Mode B

**Symptom:** ASCII visual ended up in a Mode-B file (spec.md, decisions.md, etc.), OR Mode-B file opens with multi-paragraph preamble.

1. Move the visual to chat next time the file is referenced.
2. Replace inline with tabular form (front-loaded, no preamble).
3. No retroactive rewrite needed; just don't repeat in the next file write.
4. If the violation is in a high-traffic file (multiple sessions load it), consider one cleanup commit `docs(mode-b): tighten <file> to Mode B per FR-09`.

### FR-10 — Reproducibility before fix

**Symptom:** a fix was drafted in response to a single observed failure without 3-attempt reproduction.

1. Stop draft work.
2. Run 3 reproduction attempts under the same conditions.
3. If 3/3 reproduce: continue draft (the failure is systemic).
4. If 1/3 or 2/3: close as model-variance no-op; document the variance; revert any draft changes.
5. If 0/3: close as no-op-needed.

### FR-11 — Stop and ask, don't improvise

**Symptom:** agent invented a resolution to ambiguity instead of asking.

1. Surface the inferred decision to the operator: "I assumed X; is that right?"
2. If the operator confirms: document in spec.md as an inferred decision.
3. If the operator redirects: revert the inferred work; redo with the correct interpretation.

### FR-12 — Approval-gated side effects

**Symptom:** an action requiring an approval artifact was performed without one.

| Action | Recovery |
|---|---|
| Production deploy without artifact | Verify deploy success / failure. Author the artifact retroactively (`bash hooks/local/approve-local.sh production_deploy <slug> "<reason>"`). Document the bypass in spec.md audit log. |
| Schema migration without artifact | Verify migration applied cleanly. Author artifact retroactively. Verify rollback procedure documented. |
| Secret-file write without artifact | If actual secret was written: rotate immediately. Reset commit if not pushed. |
| Customer-visible message sent without artifact | Cannot un-send. Document; if outbound was wrong, send a correction; file `docs/problem-catalog/<date>-unintended-outbound/problem.md`. |
| Session-key used without artifact | Session is potentially compromised. Operator signs out immediately to invalidate. Document in `docs/problem-catalog/<date>-session-key-bypass/problem.md`. |

### FR-13 — Lint+typecheck per commit

**Symptom:** committed broken state (lint or typecheck failed but commit was made anyway).

1. Identify the broken commit by SHA.
2. Fix-forward: next commit fixes the issue. Reference the broken SHA in the fix commit message: `fix(lint): resolve T<n>'s lint regression introduced by sha:<broken-sha>`.
3. Document in next gate report's "deviations" field.

### FR-14 — Single docs commit on deploy

**Symptom:** deploy docs (spec.md flip, tasks.md marks, backlog index, README header) were split across multiple commits.

1. Already-shipped commits: leave as-is. Note in next deploy: "Previous deploy split docs across N commits; single-commit discipline applied going forward."
2. Not yet pushed: `git reset --soft <baseline>`; re-stage all docs files; one commit `docs(post-deploy): T<deploy> <slug> DONE — <hash>`.

### FR-15 — Knowledge curation triggers

**Symptom:** a recurring problem was solved without filing a problem-catalog entry, OR a recurring pattern was applied without filing a skill.

1. File the artifact retroactively:
   - For one-off incident: `docs/problem-catalog/<slug>/problem.md` per `templates/problem-catalog-entry.md`.
   - For pattern across 3+ tickets: `docs/skills/<slug>/SKILL.md` per `templates/skill-template.md`.
2. Update the corresponding index (`docs/problem-catalog/README.md` or `docs/skills/README.md`).
3. Cross-reference from the affected tickets' `decisions.md`.

## Recovery procedures by hook event

### `pre_tool_use` returned deny

The hook's `reason` field names the rule and the matched pattern. Steps:

1. Read the `reason` carefully; it cites the FR-NN.
2. If the operator wants to proceed anyway: check whether `require_approval` applies. If so, author the artifact via `bash hooks/local/approve-local.sh`.
3. If `deny` was a deny-list match (no approval path): the action is forbidden. Use the alternative documented in the FR section above.

### `stop` hook blocked a "done" claim

The hook's `reason` field lists missing signals. Steps:

1. Identify which signals are missing (gate report present? lint clean? worker-undisturbed re-check? deploy hash? probes? smoke results? rollback note? docs commit?).
2. Produce the missing signal in chat (e.g., paste the gate report; run the worker-undisturbed re-check; etc.).
3. Re-emit the "done" claim. The hook re-evaluates.

### git `pre-commit` hook rejected the commit

The hook prints which check failed (secret-path / secret-content / protected-path / lint / typecheck). Steps:

1. **Secret-path or secret-content:** unstage with `git reset HEAD -- <file>`. If a real secret was added: rotate. Do NOT use `--no-verify` to bypass.
2. **Protected-path:** either revert the protected file (`git checkout HEAD -- <path>`) or author a `protected_path_edit` exception artifact and re-attempt commit.
3. **Lint or typecheck failure:** fix the underlying issue. Re-stage. Re-commit.

### git `commit-msg` hook rejected the commit

The hook prints whether T-number is missing or the message is too vague. Steps:

1. Re-write the commit message: include T<n> for implementation commits, OR use `docs(...)` / `chore(...)` prefix for non-implementation commits.
2. `git commit --amend -m "<corrected message>"`.

## Cross-references

- Rule statements: `FLOW_RULES.md`
- Role-specific don't-lists + refusal phrasing: `flow-skills/role-discipline/references/<role>.md` (shared protocols: `flow-skills/role-discipline/SKILL.md`)
- Hook decision logic: `hooks/handlers/*.py`
- Policies hooks consult: `policies/*.yml`
- Live-user verification recovery (FR-12 specific): `workflows/live-user-verification.md`

## Last amended

```
2026-05-08 — initial v0.1.1 draft; per-rule recovery procedures consolidated from
              prototype HARD-RAILS "Recovery if violated" sections.
```
