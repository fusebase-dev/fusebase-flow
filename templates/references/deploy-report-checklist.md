# Deploy report fill-in checklist (lazy-load reference, v2.9.0+)

> **Load on demand** when the Deploy phase is filling out `templates/deploy-report.md`. NOT loaded by downstream consumers of the filled artifact. Pre-v2.9.0 these checklist items lived inside the template body and were paid in tokens by every consumer; v2.9.0+ pays the cost only at fill time.

## Checklist for Deploy phase using this template

Before pasting:

- [ ] DP.1 + DP.6 verification rows actually performed (not just claimed)
- [ ] Deploy hash captured from real command output
- [ ] Each probe result has concrete evidence (output excerpt, log line, screenshot path) — not just "PASS"
- [ ] FR-14 commit SHA is real
- [ ] **Section 7a per-phase timestamps recorded** — UTC `started_at` + `ended_at` for each deploy-phase activity (deploy command, probes, smoke, FR-14 commit) per IM.11 / v2.8.0+
- [ ] **Section 7b net active vs wait breakdown computed** — total elapsed, active work (sum of phase wall-clocks), wait time, deploy-command-only duration
- [ ] Section 6 operator-side pending actions: literal commands, not paraphrases
- [ ] Section 8 operator-relay block is filled with actual content (not template `<...>` placeholders) — INCLUDING the new time line (elapsed / active / wait)
- [ ] If any probe failed: section 3 replaced with failure version + relay block reflects failure

---
