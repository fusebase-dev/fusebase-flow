# Change-note template (Lightweight Lane — FR-21)

The **entire** planning + handoff + deploy artifact for a Lightweight-lane change. Use inline in the commit body for the smallest changes, or save to `docs/changes/<date>-<slug>.md`. Replaces spec + decisions + tasks + verification-gate + two handoff docs for LL-eligible work only. Keep each field short.

Eligibility: bounded read-only diagnosis complete · path router succeeded with no mechanical match · semantic assessor declared no objective Full trigger · ordinary/reversible/mechanically-verifiable outcome. Incomplete assessment stops at `BLOCKED-AT-lane-assessment`. See `flow-skills/lightweight-lane/SKILL.md`.

---

```
change_tier: lightweight
ticket: <slug>
Decision:     <the one product outcome to ship>
Problem:      <one line — what's wrong / what's needed and why now>
Diagnosis:    <bounded read-only evidence path(s) + conclusion>
Router:       <NO_MECHANICAL_MATCH + structured result location or inline result>
Semantic:     <complete · no triggers, with assessed behavior/diff paths>
Change:       <one line — exactly what was changed (file(s) / behavior)>
Verified:     <the live proof — probe/measurement, observed vs expected; 1–3 lines>
Rollback:     <one line — git revert <SHA>, or restore <path>>
Commit:       <SHA, filled after commit>
Deploy:       go-ahead "<operator phrase>" · deployed <SHA/hash> · FR-07 check: clean
```

## Field notes

- **change_tier** — `lightweight`. If an objective Full trigger appeared mid-flight, stop and promote (record `promoted: lightweight→full — <trigger-id> · <evidence-path> · <reason>` in the promoting commit body, or the project's ledger if it keeps one). File count or a deeper cause alone does not promote.
- **Decision / Diagnosis / Router / Semantic** — persist the one product outcome decision and the complete assessment. A router input error or `NO_MECHANICAL_MATCH` without semantic declarations is never a Lightweight result.
- **Verified** — the safety floor. Live proof the change works (run it on a real input, compare observed to expected, make it reproducible from this note). Never "looks right."
- **Rollback** — the safety floor. One concrete command.
- **Deploy** — record the explicit operator go-ahead, the deployed SHA/hash, and that the FR-07 protected-path re-check was clean. No DP.6 magic phrase / DP.1 JSON for LL; the plain go-ahead is the gate (hook-wired projects: `approve-local.sh lightweight_deploy <slug> 'ship it' --command '<exact deploy command>'`).

## Ledger (optional)

The durable record is the `change_tier` + `Commit` fields above (git carries them). A consolidated ledger is **opt-in and path-configurable** — only if your project keeps one. Default location `docs/changes/index.md`; a per-app docs layout may use `docs/<app>/changes.md` or skip the file entirely. Do not create a repo-root ledger just because of this change.

```
<YYYY-MM-DD> · <slug> · lightweight · <SHA>
```

(or, on promotion: `<YYYY-MM-DD> · <slug> · promoted lightweight→full · <reason>`)
