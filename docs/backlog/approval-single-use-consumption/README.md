# approval-single-use-consumption

**Status:** parked
**Filed:** 2026-07-28 (decision K11 of `approval-binding-and-upgrade-classification`)
**Why deferred, not rejected:** the design is right; the host lifecycle contract it needs does not exist yet.

## Goal

Make an FR-12 approval artifact genuinely **one-shot**: reserved at evaluation, consumed on the
approved command's success, released on its failure — so a valid artifact cannot authorize a second
command even within its TTL.

## Why it is not in `approval-binding-and-upgrade-classification`

`hooks/handlers/permission_request.py` and `hooks/handlers/pre_tool_use.py` both evaluate the SAME
command for one operator action. A claim taken at the first evaluation is already burned by the
second — the approval would fail on its very first correct use. Consuming before the command
succeeds also burns an approval on a transient deploy failure, which collides head-on with DP.6's
low-friction retry flow.

Binding (decision K2) removes most of the replay value without any of that machinery: an artifact
carrying `command_digest` + `repo_id` only ever authorizes one command in one repository.

## Prerequisites (all required before this is implementable)

| # | Prerequisite | Why |
|---|---|---|
| 1 | A **stable host call ID** shared by `permission_request.py` and `pre_tool_use.py` for one operator action | Without it, double evaluation burns the claim before first use. No shipped host currently guarantees one. |
| 2 | **Consume-on-success / release-on-failure** finalization | Needs a post-execution signal that reliably fires, including on crash and on host restart. `PostToolUse` fires only on success paths today. |
| 3 | **Orphan-reservation TTL + recovery** | A reservation whose finalizer never runs must expire, or one crashed deploy locks the action out. |
| 4 | **Atomicity on Windows and network filesystems** | `O_EXCL` claim semantics are the mechanism; both are untested surfaces for Flow, and both are common in the consumer base. |

## Shape once the prerequisites exist

Consume in `PostToolUse` on success only (the reserve→execute→finalize triple), keyed by the stable
call ID from prerequisite 1. Do **not** ship the `O_EXCL`-claim-at-evaluation design: it is the
version that burns the artifact before first use.

## Acceptance sketch

- One artifact authorizes exactly one successful command; a second identical command is denied.
- A failed command RELEASES the artifact — the operator retries without re-approving.
- A crash between reserve and finalize leaves the artifact usable after the orphan TTL, never
  permanently locked.
- Proven on Windows and on a network filesystem, not only on local POSIX.

## Related

- `docs/specs/approval-binding-and-upgrade-classification/decisions.md` — K11 (defer), K2 (binding as
  the interim risk reduction), K7 (strict cutover)
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md`
- `docs/backlog/host-call-identity-feature-request/README.md` — the UPSTREAM request for prerequisite 1 (the host already mints a per-invocation `tool_use_id` in the transcript; the ask is to surface it in the hook payload) + the consumer's withdrawn `O_EXCL` claim-at-evaluation NEGATIVE RESULT, which passed its own tests for three weeks and still produced both a wrong denial and a wrong allow
