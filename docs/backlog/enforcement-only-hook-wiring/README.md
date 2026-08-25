# enforcement-only-hook-wiring

**Status:** filed, NOT built — E5 ask 2 was ALREADY SHIPPED in v4.14.0; asks 1 + 4 are the remainder
**Filed:** 2026-08-25
**Source:** paperclip+hermes-v1 escalation E5 (`2026-08-20-E5-wiring-intent-api.md`), asks 1 + 4
**One-liner:** a record-only wiring-intent flag for a consumer that wires ONLY enforcement, plus an optional consumer-declared "also expected in the chain" list so a stripped consumer entry counts as drift too.

## Ask 2 was already shipped — one day after they filed

**E5 ask 2:** *"`settings-json-merge.py`: preserve-only for PreToolUse too — never drop or reorder a matcher object whose command is not Flow's."*

**Satisfied at v4.14.0, and stronger than asked.** `_widen_matchers` states the rule in its own docstring: *"Union, never overwrite — a consumer who added their own tools keeps them. Only OUR block is touched (its hook chain must name a `hooks/handlers/` command); somebody else's PreToolUse block is left alone."* Verified against the whole merge path, not just that function: the only three mutations `merge_settings` can make to a `PreToolUse` array are

| # | Mutation | Can it touch a consumer block? |
|---|---|---|
| i | wholesale replace when the event key is absent or the array is empty | No — there is nothing to preserve in that state |
| ii | `_migrate_blocks` rewrite of a legacy Flow command | No — `_is_legacy_flow_command` requires an EXACT match of two literal canonical strings, and its own comment refuses `startswith`/substring precisely to avoid clobbering customizations |
| iii | `_widen_matchers` matcher union | No — the ownership filter (`"hooks/handlers/" in command`) `continue`s past every non-Flow block before any mutation; a Flow block carrying a hand-written regex is WARNED about, never rewritten |

**No drop, no reorder, in any path.** A non-Flow PreToolUse block is not merely preserved — it is never read for any purpose except the ownership test. (By contrast `Stop` *does* have a reorder path, `stop_hooks.insert(0, …)`, though `CLI_STOP_HOOKS` is empty so it is inert.)

**Boundary of the guarantee, stated honestly:** ownership is the substring `hooks/handlers/` in the command. A consumer hook that itself lives under a path containing `hooks/handlers/` would be read as Flow's block and get its matcher unioned. Narrow, but it is where the guarantee ends.

## The remaining asks

### Ask 1 — record-only wiring intent

`post-fusebase-update.sh --record-wiring-intent` (or `--wire-hooks=pretooluse`): record intent for the CURRENT settings file **iff** the canonical handler is present in the PreToolUse chain. No merge.

Their evidence, re-confirmed at v4.14.0:

- The marker has exactly ONE creation path — `ffhc_hwi_record_wiring` (`hooks/local/lib/hook-wiring-intent.sh:76-83`, documented in the source as "the ONLY creation path"), called from `post-fusebase-update.sh:384-385` with the merge rc.
- `--wire-hooks` merges the FULL lifecycle set (`merge_settings` loops over every event in `FLOW_HOOKS`), so a consumer who wants only enforcement must take, then trim, five unrelated events. Their §1 documents exactly that mint-then-trim procedure — *"a procedure, not an API; every consumer doing enforcement-only wiring will repeat it."*

### Ask 4 — consumer-declared chain expectations

Let the health arm accept a consumer-declared "also expected in the chain" substring list (a small JSON beside the marker) so a STRIPPED CONSUMER entry is drift too. Their evidence holds: the arm's detection contract is a single canonical substring — `FFHC_HWI_HANDLER="hooks/handlers/pre_tool_use.py"` (`:34`), asserted as a TRIPWIRE at `:19-24`, greped at `:150-156`. A CLI regeneration that strips Flow's hook AND the consumer's is reported for one of them only.

## Why they are NOT being built now

1. **A defect in the same code path outranks the feature.** `wire-hooks-skips-occupied-pretooluse` (MEASURED this session, not reported by any consumer): `--wire-hooks` never adds Flow's PreToolUse handler when the array is already non-empty, exits rc 0, and the marker is recorded on that rc 0. Ask 1's predicate — *record intent iff the canonical handler is present* — is the SAME predicate that defect needs as its fail-closed backstop. Building the flag before fixing the merge would ship a record-only mode into a path that can already record an intent it did not achieve. **Resolve together, defect first.**
2. **Ask 4 raises the false-drift budget the arm was built to protect.** `hook-wiring-intent.sh:26-31` is explicit: *"a false alarm here is WORSE than the silence it replaces — it trains operators to ignore the one check that reports missing FR-06/07/12 enforcement,"* and only two states may reach `record_drift`. A consumer-supplied substring list is consumer-authored input feeding a drift verdict — it needs its own validate-and-reject design (see `self-granting-health-deferral` for what a newline in a consumer-supplied health field already does).
3. **Not urgent.** Their mint-then-trim procedure works, is disclosed, and is re-run after every CLI strip.

## Recorded because it is useful and nobody should re-derive it

E5 finding 5, **OBSERVED** on their host (T2707, 2026-08-21T00:55Z, Claude Code on Windows): a mid-session edit of `.claude/settings.json` took effect on the very next tool call — a freshly added matcher group fired and denied. No restart needed. Not measured here; it bears directly on how a recovery for either ask is expected to land.

## Acceptance sketch (to be refined at spec)

1. AC1 — `--record-wiring-intent` records an ENABLED marker only when `ffhc_hwi_wired` would return 0 for the current settings file, and never modifies the file.
2. AC2 — with the handler absent it records nothing, says why, and exits non-zero.
3. AC3 — a consumer-declared expectations list is validated by full-match against a fixed charset and REJECTED on anything else, never repaired.
4. AC4 — a missing consumer-declared entry reports through the same deferrable `record_drift` path as the Flow entry, with its own message.
5. AC5 — a malformed or foreign expectations file reports UNVERIFIED, never drift (the `hook-wiring-intent.sh:26-31` budget).

## Out of scope

- Any change to what `--wire-hooks` merges by default.
- Making the marker infer intent from file presence (`hook-wiring-intent.sh:10-17` rejected that reuse explicitly).

## Risks / unknowns

- Consumer-authored input feeding a health verdict is a new trust edge; `self-granting-health-deferral` is the live example of what that costs.
- Ordinary-consumer demand **UNVERIFIED** (`docs/north-star.md`) — enforcement-only wiring is a deep-adopter shape.

## Related

- `docs/backlog/wire-hooks-skips-occupied-pretooluse/README.md` — the measured defect; **fix first, resolve together**
- `docs/backlog/self-granting-health-deferral/README.md` — validate-and-reject precedent for consumer-supplied health input
- `hooks/local/lib/hook-wiring-intent.sh:19-24,26-31,34,76-83,150-156` · `hooks/local/post-fusebase-update.sh:377-385` · `hooks/local/fusebase-flow-overlays/settings-json-merge.py` `_widen_matchers` / `merge_settings`
- `hooks/README.md` § Consumer-authored hooks — E5 ask 3, SHIPPED
