# Evidence

<!--
One file per phase: docs/flow/evidence/P<n>.md. One row per criterion (the item id).
Status is PASS, FAIL: <why> or BLOCKED-AT-<gate>, as the builder's claim (row_status in policies/evidence-classes.yml).
A BLOCKED-AT row that cites an owner answer A<n> of backlog.md, in its Status or Note, passes the gate listed as blocked, never as PASS; without one it fails.
Capture: where the test tool wrote it, with its sha256 and size in bytes; for a test-id row, <file>::<test name> with - in sha256 and Bytes.
Log: the run log (the run directory's README.md, or a TAP log for a test-id row). Example rows:

| B1 | PASS | runs/run-a3f9c1/S1/expired-link.json | 0f4c...64 hex | 1834 | runs/run-a3f9c1/README.md | - |
| B2 | PASS | packages/core/test/auth.test.ts::magic link expires | - | - | test-results/run-7be210/unit.tap | - |
-->

| Criterion | Status | Capture | sha256 | Bytes | Log | Note |
|---|---|---|---|---|---|---|
