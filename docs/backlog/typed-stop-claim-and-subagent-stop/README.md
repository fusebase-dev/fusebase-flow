# typed-stop-claim-and-subagent-stop

**Status:** closed — 6.0.0 has no Stop gate (`stop-gate-retirement`); the typed return is a file the DONE check reads (`done-check`). **Filed:** 2026-10-15 (consumer handoff 2026-10-14 §5 B4; `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** medium (gate-stage done claims unverified in Workflow runs). **Surface:** `hooks/handlers/stop.py` (FR-07), `hooks/local/fusebase-flow-overlays/settings-json-merge.py`, health-check engines, `hooks/local/lib/hook-wiring-intent.sh`, `hooks/flow_hook_event.schema.json`, `.claude/settings.json.example`.

## Observed

`stop.py` is not wired on `SubagentStop`. v5.11 O17 narrows completion evidence to agent-authored text and adds the `stop_hook_active` repeat guard. Claude Code docs: `SubagentStop` matches on agent type and carries `stop_hook_active`; `onFailure: "block"` has NO effect on `Stop`/`SubagentStop` (so it cannot make a sub-agent gate fail closed); whether hooks fire for Workflow agents is undocumented.

## Shape

Typed done claim (Workflow `schema` status); Stop enforces only "no untyped done claim"; a tally check applies to gate-stage agent types only, never build agents; only `stop.py` on `SubagentStop`, never the CLI lint/typecheck Stop hooks; wiring stays opt-in (F3); health reports "unenforced" as non-drift.

## Gate

T1 (does `SubagentStop` fire for a Workflow agent; which `agent_type`; payload keys; `stop_hook_active` on re-fire) as native-shape fixtures; the tally exists; O17 shipped.

## Acceptance

Bootstrap-only transcripts never satisfy the gate; a gate-stage untyped claim is denied; a build agent is never denied; repeat denial follows the O17 guard with an audit row; fixtures 09/13/16/18/20 unchanged. Contract-changing → premise review.
