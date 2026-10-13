# sentinel-reap-probes-before-term

**Status:** open — not scheduled. **Filed:** 2026-10-12 (T134 audit F5). **Severity:** low-medium (cleanup latency under load). **Surface:** `hooks/tests/lib/orphan-reap.sh:282-314` (`ffor_reap`).

## Observed

`ffor_reap` takes a `ps` snapshot and runs identity checks BEFORE sending TERM, despite its "SIGNAL FIRST" comment. On a load-contended MSYS host the pre-TERM snapshot cost 2.4–6.6 s (T134 audit, 7 instrumented runs), which is most of the kill→cleanup time; the post-KILL sweep added 2.6–4.5 s. Correctness is unaffected (identity checks guard against pid reuse); latency is.

## Ask

Decide whether TERM can go out to the verified group before the full snapshot (identity of the GROUP is already pinned by the in-flight record + start token) while the snapshot-based sweep stays for KILL. Process-lifecycle contract change → premise review first; `signal-reap` (release-gated) must stay green, including the T134 heartbeat-anchored detection gate and causal completion gate.
