# Implement handoff — provider-skill-drift-guards

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v3.1. Self-attest per `FLOW_RULES.md` § Self-attestation (FR-01..FR-19), naming AI Developer and the IM.1..IM.17 role-discipline section.

Load-bearing FRs this ticket: FR-03 (one task = one commit), FR-05 (stop at gate), FR-09 (Mode B), FR-13 (lint/typecheck — here: preflight + tests — clean per commit), FR-18 (supersede, don't accumulate).

Refusal phrasing for any rule-violating request:
> "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md`
2. `AGENTS.md` (esp. CLI-edition layering + installation safety rule)
3. `docs/specs/provider-skill-drift-guards/spec.md`
4. `docs/specs/provider-skill-drift-guards/decisions.md` (B1..B8 all LOCKED)
5. `docs/specs/provider-skill-drift-guards/tasks.md` (T10..T17)
6. `docs/specs/provider-skill-drift-guards/verification-gate.md`
7. `skills/role-discipline/SKILL.md` (IM.1..IM.17)
8. `hooks/local/check-cli-flow-conflicts.sh`, `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json`, `hooks/local/mirror-skills.sh`, `hooks/tests/test-cli-flow-recovery.sh`, `.claude/settings.json.example`, `.claude/hooks/*` — the surfaces you will edit

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `provider-skill-drift-guards` |
| **Status** | ready for AI Developer |
| **Source spec** | `docs/specs/provider-skill-drift-guards/spec.md` |
| **Decisions locked** | `B1..B8` |
| **Task range (this handoff)** | `T10..T17` (stop at gate T17) |
| **Decision letter prefix** | `B` |
| **T-counter going in** | `T9`; first task is `T10` |
| **Last shipped slice** | `cli-first-flow-second-recovery` (T9 `2f1ac96`, 2026-05-29) |

## Pre-cached identifiers

| Identifier | Value | Why |
|---|---|---|
| CLI provider skills (19) | api-exploration, app-backend, app-business-docs, app-dev-practices, app-routing, app-secrets, app-sidecar, app-ui-design, dev-debug-logs, file-upload, fusebase-cli, fusebase-dashboards, fusebase-gate, fusebase-portal-specific-apps, git-workflow, handling-authentication-errors, managed-integrations, mcp-gate-debug, remote-logs | drive provenance + drift lists; sourced from `agent-surface-ownership.json` `known_names` |
| CLI app-agents (2) | app-architect, app-create-checker | the `known_names` to pin in B4 |
| CLI quality hooks (4) | `.claude/hooks/quality-check-apps.js`, `run-lint-on-stop.sh`, `run-typecheck-apps.js`, `run-typecheck-on-stop.sh` | hook consolidation (B5) + provenance (B2) |
| CVE patch location | `run-typecheck-apps.js:104-105` (`shell: process.platform==="win32"`) | the node hook to KEEP/wire (B5) |
| Canonical Flow skills (14) | unchanged set — do NOT add CLI skills here | baseline non-regression |
| `repo-polish` skill | LOCAL-ONLY, gitignored (`.git/info/exclude`) — NOT a CLI skill | exclude from provenance manifest |

## Production state going in

- HEAD `3c9c00a` (VERSION 3.1). Working tree clean except this ticket's planning docs (committed by PO before you start).
- Baseline verified HEALTHY: `preflight` 0/0, `run-tests` 14/14, `test-cli-flow-recovery` PASS, `check-cli-flow-conflicts` + `health-check` HEALTHY.

## Frontend / UI implementation brief

N/A — no UI surface.

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| Zero diff expected | downstream worker paths — none in this template repo |
| Must NOT regress (verified baseline) | `mirror-skills.sh` canonical-only scope; `flow_write_mode:"never"` for 19 CLI skills; `post-fusebase-update.sh` CLI-exclusion; `skill-mirror-manifest.txt` = 28 lines |

## Execution notes (PO-authored)

- **Canonical-first, then mirror.** T14 edits the health-check skill text in canonical `skills/fusebase-flow-health-check/SKILL.md`, then runs `bash hooks/local/mirror-skills.sh` to refresh `.claude`/`.agents`/overlay copies. Never hand-edit a mirror (preflight fails on drift).
- **`agent-surface-ownership.json` lives at** `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json` (verify there are no other tracked copies; if a mirrored copy exists, update both and keep them identical).
- **`CLI_SNAPSHOT_STALE` is advisory/non-failing** — must NOT flip the reporter's exit code to drift/broken; missing→`CLI_LAYER_DRIFT` semantics stay unchanged (don't break `test-cli-flow-recovery.sh`'s existing assertions; extend, don't rewrite).
- **Provenance `source_cli_version`** is UNVERIFIABLE locally → write the literal `"unknown"` sentinel + `generated_at` date + per-file sha256. Freshness is advisory only.
- **Provenance manifest path** `audit/cli-vendor-manifest.json` is COMMITTED (it's a document of record, like `skill-mirror-manifest.txt`) — not gitignored.
- **B5 delete-vs-deprecate:** inspect `quality-check-apps.js` first. Only hard-delete the two `.sh` hooks if node fully covers lint+typecheck; otherwise add a deprecation header + leave unwired. State which you chose in the gate report.
- **T10/A4:** only fix TRACKED files. `docs/fusebase-health/**` is gitignored (local-only) — leave it. `CHANGELOG.md` historical entries: correct the filename only where it states a current-shipped fact; do not rewrite dated history narratives if ambiguous — note any skipped in the gate report.
- **One task = one commit**, conventional subject citing `T<n>` (e.g. `feat(flow): T13 add CLI vendor provenance manifest + generator`). Run preflight (and the relevant test) before each commit.

## Stop at gate

Per FR-05, stop at **T17**. Do NOT deploy (no deploy applies). Produce the gate report per `verification-gate.md` and halt. The PO will run code-review + security-permissions-review, then flip spec DRAFT→DONE in a single docs commit.

## Per-output state announcement (every chat reply)

```
---
📍 Phase: Implement
🎯 Ticket: provider-skill-drift-guards
✅ Completed: T10..T<n-1> (<SHAs>)
📍 Current: T<n> (<task name>)
⏭️ Next: <next task OR "stopping at gate; reporting">
```

## Per-commit pre-attestation

```
T<n> pre-commit check:
☐ preflight clean (0/0)  ☐ relevant test PASS  ☐ baseline protections unchanged
☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ commit cites T<n>
→ Committing T<n>: <scope>
```

## Gate report contract (when you reach T17)

Mode B report: per-task SHAs (T10..T16), test counts before/after, preflight + mirror-drift status, `check-cli-flow-conflicts` + `health-check` verdicts, provenance manifest parse, baseline-protection non-regression confirmation, deviations (incl. B5 delete-vs-deprecate choice and any A4 CHANGELOG lines skipped). Then halt.
