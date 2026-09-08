# Handoff - v4.15.3 release preparation

**Base/tag:** `ecabe95c4767b287c106c1feaae346d3c77b791e` / `v4.15.2`. **Status:** [tagged run `34176386683`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34176386683) passed Linux, failed Windows at 633/634 essential predicates and skipped publication. v4.15.0, v4.15.1 and v4.15.2 remain immutable unpublished tags; T71 prepares v4.15.3.

Read `docs/changes/2026-09-07-release-completion.md` for the current outcome, focused proof, attribution and limits. The original ticket artifacts under `docs/specs/flow-performance-and-recovery-hardening/` remain historical detail and point back to that note.

Preserve the recorded limits: validator reuse remains disabled; ordinary-consumer timing, five-provider delivered-context telemetry, real-symlink cases and Windows authority isolation/successful signing remain unverified. Preserve unrelated untracked smoke/archive/wasted-code and repair-backup paths. Next action: commit the reviewed T71 correction and 4.15.3 package, then tag that exact source and rely on its single two-platform publication gate.
