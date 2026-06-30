# Backlog ticket — healthcheck-diff-source-hardening

**Status:** parked (filed 2026-06-29 as the MED follow-up from the FuseBase adversarial impl review of `cli-0.25.9-vendor-refresh`, shipped v3.30.0). Severity: MED, non-blocking.
**Predecessor:** `docs/specs/cli-0.25.9-vendor-refresh/spec.md` (v3.30.0). That release made `check-cli-flow-conflicts.sh` diff-frame `SHARED_MERGE_DRIFT` — flag only a CLI Stop command that Flow's merge actually DROPPED vs the pre-merge `.claude/settings.json` Stop chain.

## Pain

The diff-framed reporter's evidence source — `.claude/settings.json.pre-flow-merge` (the pre-merge backup `post-fusebase-update` writes) — is **ephemeral**. When that backup is absent (e.g. a project that never ran the Flow-aware update path, or a manually-edited tree), the reporter has no pre-merge baseline to diff against, so a genuinely-dropped CLI Stop hook is **not flagged**.

This is a deliberate no-false-positive trade-off, not a regression: Flow's merge is **preserve-only** (it appends `stop.py` and never removes an existing Stop hook), so in normal operation Flow never drops a CLI hook — there is nothing to flag. The gap is only theoretical (a hook dropped by some non-Flow actor, with no `.pre-flow-merge` evidence to prove it was ever wired).

## Why it was deferred (not folded into v3.30.0)

The real fix is **backup-persistence**: make the pre-merge baseline durable (or reconstruct it from a provenance record) so the diff has a stable source even when the ephemeral `.pre-flow-merge` is gone.

The fix that must NOT be taken: an "on-disk-but-unwired" fallback — i.e. flagging a CLI hook that exists in `.claude/hooks/` but isn't wired in `settings.json`. That fallback would **re-introduce the exact `run-typecheck-apps.js` false positive** this release removed (0.25.9 ships `run-typecheck-apps.js` on disk but wires it 0 times). Classifying on-disk-but-unwired as drift is precisely the stale model v3.30.0 retired.

So the hardening needs a backup-persistence design of its own (where the durable baseline lives, how it interacts with `stamp-cli-provenance.sh`, how absence degrades to a clear PARTIAL signal rather than silent non-detection).

## Acceptance (when picked up)

- A durable pre-merge baseline (or provenance-derived equivalent) so the diff source survives a missing `.claude/settings.json.pre-flow-merge`.
- A genuinely-dropped CLI Stop hook is flagged even without the ephemeral backup.
- No re-introduction of the on-disk-but-unwired false positive (the 0.25.9 `run-typecheck-apps.js` case stays benign).
- Absence of any baseline degrades to an explicit PARTIAL/advisory signal, never silent.
