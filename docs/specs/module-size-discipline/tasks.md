# Tasks — module-size-discipline (FR-25)

**Task range:** T1..T10
**Gate task:** T9 (preflight + run-tests + independent reviewer agent)
**Deploy task:** T10 (commit + tag v3.16.0 + push origin main --follow-tags)
**Linked spec:** `docs/specs/module-size-discipline/spec.md`
**Linked decisions:** `docs/specs/module-size-discipline/decisions.md`
**Commit strategy:** single release commit (decision M7); per-task SHAs N/A.

| T# | Scope | Files | Cites | AC |
|---|---|---|---|---|
| T1 | Policy + gate logic | `policies/module-size.yml` (new), `hooks/shared/module_size.py` (new), `hooks/local/check-module-size.sh` (new) | M1 M2 M3 M4 | AC2 |
| T2 | pre-commit wiring | `hooks/git/pre-commit` | M1 | AC3 |
| T3 | Tests | `hooks/tests/test-module-size.sh` (new), `hooks/tests/run-tests.sh` (phase 2) | M5 | AC3 AC7 |
| T4 | FR-25 rule | `FLOW_RULES.md` (row + implication + status v0.16 + amendment) | M6 | AC1 |
| T5 | Carrier skill | `flow-skills/module-size-discipline/SKILL.md` (new) | M6 | AC5 |
| T6 | Steering: digest row + review dimension + LL interplay + session_start | `flow-skills/role-discipline/SKILL.md`, `flow-skills/code-review/SKILL.md`, `flow-skills/lightweight-lane/SKILL.md`, `hooks/handlers/session_start.py` | M6 | AC5 |
| T7 | Plan-time: target-file rule | `flow-skills/implementation-planning/SKILL.md`, `templates/tasks.md` | M6 | AC4 |
| T8 | Counts + catalogs + release docs | `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/compatibility.md`, `audit/README.md`, `PUBLISHING.md`, `docs/source-map.md`, `docs/fusebase-cli-edition.md` (as counts apply), `.claude-plugin/plugin.json`, `CHANGELOG.md`, `docs/release-notes/v3.16.0.md`, `VERSION` → 3.16.0, run `sync-version-strings.sh` + re-mirror | M6 M7 | AC6 |
| T9 | Gate: preflight 0/0 + run-tests 22/22 + independent reviewer agent; fix findings | — | M7 | AC7 |
| T10 | Ship: single commit, tag v3.16.0, push origin main --follow-tags, watch CI | — | M7 | — |

## Worker-undisturbed

`policies/protected-paths.yml: worker_undisturbed` = none for this repo → N/A.
