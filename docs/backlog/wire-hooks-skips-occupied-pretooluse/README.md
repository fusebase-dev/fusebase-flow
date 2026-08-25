# wire-hooks-skips-occupied-pretooluse

**Status:** open — MEASURED defect, filed NOT fixed (that session was documentation-only)
**Filed:** 2026-08-25
**Found:** while filing consumer proposal E5. **Not reported by the consumer** — their mint-then-trim procedure keeps upstream's PreToolUse object, which happens to route around it.
**Severity:** high — silent loss of tool-time FR-06/07/12 enforcement, with a health-check recovery that cannot converge
**One-liner:** `--wire-hooks` never adds Flow's PreToolUse handler to a `.claude/settings.json` whose `PreToolUse` array is already non-empty, exits 0 anyway, and the wiring-intent marker is recorded on that rc 0 — so the tree records INTENT while Flow enforcement is absent, and the health check's own recovery command is the one that just produced the state.

## Reproduction — OBSERVED, deterministic (probe at `/c/tmp/e5-probe`)

Input: a consumer that wired its own veto BEFORE adopting Flow's hooks.

```json
{ "hooks": { "PreToolUse": [ { "matcher": "Bash|Edit|Write",
  "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/hooks/local/consumer-veto.local.sh", "timeout": 20 } ] } ] } }
```

`python3 hooks/local/fusebase-flow-overlays/settings-json-merge.py <settings.json>` →

```
[settings-merge] applied 7 change(s):
  - added MCP server fusebase-dashboards / fusebase-gate
  - added SessionStart event
  - added UserPromptSubmit event
  - added PostToolUse event
  - added PreCompact event
  - added Stop event with Fusebase Flow stop.py
merge rc=0
```

`grep -c 'hooks/handlers/pre_tool_use.py'` on the merged file: **0**.

Five lifecycle events wired. The one carrying FR-06 denies, FR-12 approvals and the FR-07 path policy: not wired, not mentioned, rc 0.

## Bounded by control cases (same probe)

| `PreToolUse` in the input | Flow handler after merge |
|---|---|
| key absent | wired (1) |
| `[]` empty array | wired (1) |
| `[consumer block, flow block]` | present (1); matcher union applies |
| **`[consumer block]` only** | **NOT wired (0)** |

## Mechanism

`merge_settings` in `hooks/local/fusebase-flow-overlays/settings-json-merge.py`: the add branch is `if event not in hooks or not hooks[event]` — a WHOLESALE REPLACE, correctly guarded to fire only when there is nothing to preserve. With a non-empty array the loop falls through to `_migrate_blocks` (no-op — no legacy Flow command) and `_widen_matchers` (correctly skips a block whose hook chain names no `hooks/handlers/` command). Nothing adds Flow's block. **There is no add-beside-preserving branch for PreToolUse** — only Stop has one, and it appends `stop.py` to an existing chain.

So the preserve property E5 ask 2 asks for is already there; what is missing is its other half — ADD while preserving.

## Why it is worse than a missing feature

`hooks/local/post-fusebase-update.sh:377-385` records the wiring-intent marker on `MERGE_EXIT`, and `hooks/local/lib/hook-wiring-intent.sh:76-83` writes `enabled: true` iff that rc is 0. This run therefore RECORDS INTENT while leaving enforcement absent. The health arm then does exactly what it was built for: `ffhc_hwi_wired` (`:150-156`) greps for the handler substring, does not find it, and `record_drift`s *"Flow PreToolUse ENFORCEMENT STRIPPED"* — printing the recovery `bash hooks/local/post-fusebase-update.sh --wire-hooks`, **the command that just produced this state**. The loop cannot converge.

This is the `live-enforcement-inertness` class: wired-looking, content-healthy, not running.

## Fix sketch — NOT built; a decision is needed first

- **(A) Add-beside-preserve for PreToolUse**, mirroring Stop: if no block in the array names `hooks/handlers/pre_tool_use.py`, APPEND Flow's block and never touch the consumer's. Needs no new flag, and it is the natural completion of the preserve-only posture.
- **(B) Refuse to record intent that was not achieved:** `ffhc_hwi_record_wiring` takes the merge rc AND a post-merge `ffhc_hwi_wired` result; a merge that left the handler absent records no intent, or records it with a loud warning.

These are not alternatives. (B) is the fail-closed backstop for whatever (A) misses, and (B) is the SAME predicate as E5 ask 1 (`--record-wiring-intent`, record-only, iff the canonical handler is present) — which is why the two tickets should be resolved together.

Open questions the spec must answer: where in the array Flow's block is appended (order is not a control — `hooks/README.md` § Consumer-authored hooks — but it is visible); whether an appended block gets the full E6 matcher; and whether a tree already in the bad state is repaired on the next `--wire-hooks` or needs an explicit path.

## Acceptance sketch

1. AC1 — merging into a settings.json whose `PreToolUse` holds only a consumer block leaves the consumer block byte-identical AND adds Flow's handler.
2. AC2 — the consumer block is never dropped, never reordered relative to other consumer blocks, and its matcher is never rewritten.
3. AC3 — a merge that ends with no Flow PreToolUse handler present never records an ENABLED wiring intent.
4. AC4 — the four control cases above are a test matrix, not prose.

## Related

- `docs/backlog/enforcement-only-hook-wiring/README.md` — E5 asks 1 + 4; same predicate, resolve together
- `docs/problem-catalog/live-enforcement-inertness/problem.md` — the class
- `docs/problem-catalog/flow-pretooluse-unwired-after-fusebase-update` (consumer-side) — the symptom they already catalogue
- `hooks/local/fusebase-flow-overlays/settings-json-merge.py` `merge_settings` · `hooks/local/post-fusebase-update.sh:377-385` · `hooks/local/lib/hook-wiring-intent.sh:76-83,150-156`
