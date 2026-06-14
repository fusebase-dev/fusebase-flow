# Backlog ticket — health-check-fast-timeout

**Status:** promoted → `docs/specs/health-check-fast-timeout/spec.md` (2026-06-14)
**Source friction:** real consumer install on a Windows/schannel-impaired box — `fusebase-flow-health-check.sh` did not return within 2 minutes during install, reading as a hang. Reproduced in the framework maintenance session (engine backgrounded, >2 min, eventually HEALTHY).

## Pain
The health-check engine can exceed two minutes and **appear to hang**, indistinguishable from a real failure, because two operations are unbounded:
1. `git fetch origin --tags` in the upstream-comparison section (runs whenever `.fusebase-flow-source/.git` exists — i.e. right after an install) — hangs on a network-impaired host.
2. The engine runs `preflight.sh` + the `run-tests.sh` hook suite as sub-invocations (slow regardless of network).

## Rough acceptance
- The engine **always returns within a bounded time** with a partial verdict; a slow/unreachable step is reported as "unavailable (timed out)", never a silent hang.
- A `--fast` / local-only mode for a sub-5s verdict.
- No change to drift-detection semantics; no regression when the network is reachable.

Full plan, decisions, ACs, tasks: `docs/specs/health-check-fast-timeout/spec.md`.
