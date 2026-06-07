# Verification gate — <slug>

**Linked spec:** `docs/specs/<slug>/spec.md`
**Linked tasks:** `docs/specs/<slug>/tasks.md`
**Gate task:** T<gate>
**Pass threshold for smoke:** <n>/<n> PASS (e.g., 4/4 PASS)

## Acceptance-criterion → task mapping

| AC | Implemented in | Test coverage |
|---|---|---|
| AC1 | T<n> | <test names or commands> |
| AC2 | T<m> | <test names> |
| AC3 | T<m+1>, T<m+2> | <test names> |

## Required gate-report fields (per `policies/gate-contracts.yml`)

| Field | Format |
|---|---|
| Implementation summary | 1–3 sentences |
| Per-task SHAs | `T<n>: <sha> <subject>` for every task in range |
| Test counts | `before: <n>, after: <m>, delta: +<k>` per layer |
| Lint status | `clean` / `<n> warnings` / `<n> errors` |
| Typecheck status | `clean` / `<n> errors` |
| Worker-undisturbed git diff | `<file>: empty diff ✓` per protected path |
| Manifest version | `<old> → <new>` or `N/A` |
| Architect/PO deviations | listed with reasoning, or `none` |
| Self-attestation | "Operating as AI Developer..." phrase |

## Lint / typecheck / test commands

| Layer | Command |
|---|---|
| Lint | `<command from AGENTS.md, e.g., npm run lint>` |
| Typecheck | `<command, e.g., npm run typecheck>` |
| Unit tests | `<command>` |
| Integration tests | `<command, if applicable>` |
| E2E tests | `<command, if applicable>` |

## Worker-undisturbed paths (this ticket)

Subset of `policies/protected-paths.yml` relevant to this ticket. Empty diff required unless an exception is declared.

- `<path-1>`
- `<path-2>`
- `<path-3>` — bounded-additive allowed for this ticket; functions added: `<list>`. Empty diff required on functions: `<list>`.

## Smoke prompts (post-deploy)

Define with `flow-skills/smoke-testing/SKILL.md`. Smoke PASS requires operator-visible outcome evidence plus ground-truth diagnostic inspection; supporting checks alone are incomplete. For interactive UI changes, at least one smoke prompt must exercise the real primary interaction; screenshot-only evidence is not sufficient. Name stable selectors or accessible locators for interactive controls and meaningful dynamic output. Browser smoke must include route/navigation, viewport, auth/session plan, unique test data, cleanup responsibility, and any backend/log/API diagnostic surface.

| ID | Scenario | Route / surface | Operator-visible success criterion | Ground-truth diagnostic | Stable selectors / locators | Auth / test data plan | Adversarial check | Evidence required |
|---|---|---|---|---|---|---|---|---|
| S1 | <one-liner> | <URL / page / command / N/A> | <specific user/operator-observable outcome> | <request dump / error log / rendered DOM / DB row / job trace> | `<selector or N/A>` | <no-auth / synthetic / live-user; unique data + cleanup> | <what would falsify the fix> | screenshot / response excerpt / diagnostic excerpt |
| S2 | <one-liner> | <surface> | <specific condition> | <diagnostic surface> | `<selector or N/A>` | <auth/data plan> | <falsification signal> | screenshot |
| S3 | <one-liner> | <surface> | <specific condition> | <diagnostic surface> | `<selector or N/A>` | <auth/data plan> | <falsification signal> | response excerpt |

Detailed steps for each smoke prompt below.

### S1: <scenario>

Steps:
1. <action>
2. <action>

Expected: <observation>
Pass criterion: <specific condition>
Route / surface: <URL / page / command / N/A>
Ground-truth diagnostic: <log/dump/DOM/DB/job artifact to inspect after the action>
Stable selectors / locators: <purpose/state selector or accessible locator; N/A for non-UI>
Auth / test data plan: <auth mode; unique values to create; cleanup expectation; no exact shared-state counts unless prepared>
Adversarial check: <signal that would prove the fix is still broken>
Evidence dir: `docs/tmp/handoff/<date>-<slug>-smoke/S1-*.{png,md,log}`

### S2: ...

...

## Probes (post-deploy)

| ID | Probe | Pass criterion | Evidence |
|---|---|---|---|
| G-M | deploy command exit 0 + version captured | exit code 0; deploy hash visible in output | command transcript |
| G-N | health endpoint | HTTP 200 + body contains `<expected>` | curl response |
| G-O | feature surface mounted | route resolves; HTTP 200 | curl / browser |
| G-P | feature behavior | <specific behavior under known input> | response body excerpt |
| G-Q | spec flip + backlog index update | both updated in single docs commit | `git log` |

## Manifest version bump (if applicable)

Old: `<version>`
New: `<version>`
Reason: <one-liner>

## Rollback procedure

If any probe fails:
1. `git revert <deploy hash>`
2. Redeploy: `<deploy command>`
3. File follow-up backlog ticket
4. Spec stays DRAFT until follow-up resolves

## Cross-artifact consistency check (mandatory before approving deploy)

```
Constitution invariants verified:
☐ Worker-undisturbed list — touched files: <list, or "none">
☐ Mixed-fleet considerations — <addressed in spec, or "N/A">
☐ Migration approach — <no migration | migration with documented blocker workaround>
☐ Auth model — <endpoint auth gates correct>
☐ Quality bar — <tests added, type safety preserved>

Cross-artifact:
☐ Every AC<n> exercised in at least one task
☐ Every locked decision <Letter><n> cited in at least one task
☐ All clarify Q-A's resolved (none remain in spec.md)
☐ All T-numbered tasks have SHAs filled in
☐ No TODO/FIXME/WIP markers in diff
☐ Spec status still DRAFT (will flip to DONE in deploy)
```

If ANY item fails, redirect AI Developer. Do NOT bypass.
