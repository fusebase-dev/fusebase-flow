# Handoff - v4.15.2 release preparation

**Base/tag:** `1e5f44ee80a5ccd2479f8b317142511cbcab5bdb` / `v4.15.1`. **Status:** [tagged run `34174615178`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34174615178) passed Linux, failed Windows at 627/628 essential predicates and skipped publication. v4.15.1 remains immutable and unpublished; T70 prepares v4.15.2.

Read `docs/changes/2026-09-07-release-completion.md` for the current outcome, focused proof, attribution and limits. The original ticket artifacts under `docs/specs/flow-performance-and-recovery-hardening/` remain historical detail and point back to that note.

Preserve the recorded limits: validator reuse remains disabled; ordinary-consumer timing, five-provider delivered-context telemetry, real-symlink cases and Windows authority isolation/successful signing remain unverified. Preserve unrelated untracked smoke/archive/wasted-code and repair-backup paths. Next action: commit the reviewed T70 repair and release preparation, then tag that exact source as v4.15.2 and rely on its single two-platform publication gate.
