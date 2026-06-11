# Tasks — <slug>

**T-counter going in:** T<first - 1> (next task is T<first>)
**Task range:** T<first>..T<deploy>
**Gate task:** T<gate>
**Deploy task:** T<deploy>
**Linked spec:** `docs/specs/<slug>/spec.md`
**Linked decisions:** `docs/specs/<slug>/decisions.md`

## Task chain

| T# | Track | Scope | Cites decision | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T<first> | backend | <one-liner> | <Letter>1 | — | <sha> | done / pending |
| T<first+1> | spa | <one-liner> | <Letter>2 | T<first> | <sha> | pending |
| T<first+2> | extension | <one-liner> | <Letter>3 | T<first> | <sha> | pending |
| T<gate> | — | verification gate (no commit; gate report only) | — | T<first..gate-1> | — | pending |
| T<deploy> | — | deploy + post-deploy probes + single docs commit | — | T<gate> | <sha> | pending |

## Per-task detail

### T<first>. <task name>

**Track:** backend / spa / extension / docs / etc.
**Scope:** <what this task does, file by file>
**Files:** `<path>`, `<path>`
**Module-size (FR-25):** <"all targets under ceiling" | "extracts <concern> into `<new module>`" | "exemption: <one-line reason> (operator-approved)">
**Cites:** decision <Letter><n>
**Depends on:** <T-numbers, or "—">
**Acceptance:** AC<n> from spec
**Tests:** new unit / integration / e2e tests covering this scope
**Worker-undisturbed:** <empty diff expected on: paths>
**SHA:** <captured on commit>

---

### T<first+1>. <task name>

...

---

### T<gate>. Verification gate

No code change. AI Developer produces the gate report from `templates/gate-report.md`; required fields per `policies/gate-contracts.yml: gate_report`.

After gate report, AI Developer waits for an explicit deploy handoff. Do NOT proceed to T<deploy> on initiative.

---

### T<deploy>. Deploy + probes + single docs commit

**Procedure:** per `workflows/greenlight-deploy.md`.

1. Final pre-deploy worker-undisturbed re-check
2. Run deploy command (from `AGENTS.md` project-specific section)
3. Capture deploy hash
4. Run probes G-M..G-Q (see `verification-gate.md`)
5. Run smoke prompts S1..Sn (if applicable)
6. Single docs commit (FR-14): spec.md DRAFT → DONE with hash + tasks.md verification + backlog index update + README header
7. Output deploy report

**Approval artifact required:** `state/approvals/production_deploy-<slug>-<YYYYMMDD>.json` per `policies/approval-policy.yml`.

## Parallelism diagram (when applicable)

```
T<first> ─┬─ T<first+1>
          ├─ T<first+2>
          └─ T<first+3>
                         └─→ T<gate> ─→ T<deploy>
```

## Task chain audit

| Constitution invariant | Affirmed in tasks |
|---|---|
| Worker-undisturbed | T<n>, T<n+1> declare empty diff |
| Mixed-fleet | T<n> covers backwards-compat path; T<m> covers manifest version bump |
| Migration approach | T<n> uses no-migration design (or documents blocker workaround) |
