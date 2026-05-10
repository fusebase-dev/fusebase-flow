# Gate report fill-in checklist (lazy-load reference, v2.9.0+)

> **Load on demand** when the AI Developer is filling out `templates/gate-report.md`. NOT loaded by downstream consumers of the filled artifact. Pre-v2.9.0 these checklist items lived inside the template body and were paid in tokens by every consumer; v2.9.0+ pays the cost only at fill time.

## Checklist for AI Developer using this template

Before pasting the filled report to operator, verify:

- [ ] Every task in T<first>..T<gate> has a row in the per-task commit table
- [ ] All commit SHAs are real (not placeholders)
- [ ] **Per-task `started_at`, `committed_at`, and wall-clock filled in (IM.11 / v2.8.0+)** — record the UTC timestamp when you pick up each task and when its commit lands
- [ ] **Section 1b time totals computed** — total elapsed (wall), total active development (sum of wall-clocks), wait time (elapsed − active), average task wall-clock
- [ ] Lint + typecheck output is pasted verbatim (not paraphrased)
- [ ] Worker-undisturbed re-check actually run; output pasted
- [ ] Test counts before / after / delta computed (operator should be able to verify)
- [ ] Deviations field is honest (don't hide split-tasks; surface them)
- [ ] Section 9 operator-relay block is filled in with actual content (not template `<...>` placeholders)
- [ ] State announcement footer included

If any checkbox is "no" — don't ship the report yet. The PO will catch it; better to fix now.

---
