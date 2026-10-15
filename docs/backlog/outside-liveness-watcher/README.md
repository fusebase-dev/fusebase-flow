# outside-liveness-watcher

**Status:** parked — gated on v5.11 O4/O5, consumer T1 and phase-7 silence records. **Filed:** 2026-10-15 (consumer handoff 2026-10-14 §5 B1; `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** medium (silent hangs: one consumer, 4 silences 185–519 min, 11.7 h on an awake host). **Surface:** new stdlib script under `hooks/local/`, `flow-skills/liveness-discipline`, `hooks/local/lib/backup-hygiene.sh`.

## Observed

The bounded-watcher pattern exists only as prose (`liveness-discipline/SKILL.md` § Wake interval). Nothing shipped observes a delegator whose own call hangs, a turn-ended session, or a bounded call stuck after reap (`bounded-run-waits-unbounded-after-reap`). v5.11 O5 adds `bounded_run` heartbeat files that record their deadline; nothing reads them yet.

## Shape

Per-run, opt-in, bounded shell/stdlib watcher launched by the delegator under `bounded_run` — not a daemon (CONTRIBUTING:13, SECURITY:5, constitution:23). Reads activity only: last commit time, `index.lock` age, run-folder mtimes, `state/audit/liveness/*.hb` with their deadlines. Exits on progress, completion or stall; the exit wakes the delegator (Claude Code: background task notification or `asyncRewake` exit 2). No kill, no re-dispatch, no network, no memory alert, no telemetry.

## Gate (all before build)

- v5.11 O4/O5 shipped; consumer phase-7 alert/response records show a silence the O4 pattern missed.
- Consumer transcript gap histogram including the 20–30 min band, to set the stall bound.
- T1 result for any hook-based adapter arm.

## Acceptance

Replaying the consumer's two awake-host hangs exits the watcher within two sweep intervals; a call with an advancing heartbeat and no terminal record is never reported before deadline+5; a heartbeat stale past deadline+5 with no terminal record reports "bounded call did not return"; 0 processes killed; new state paths covered by the `.git/info/exclude` writer. Contract-changing (stall interpretation) → premise review before code.
