# host-call-identity-feature-request

**Status:** filed, NOT built — nothing here IS buildable by Flow; E3 ask 2 shipped separately
**Filed:** 2026-08-25
**Source:** paperclip+hermes-v1 escalation E3 (`2026-08-20-E3-host-call-identity-single-use.md`), asks 1 + 3
**Scope note:** this ticket is the UPSTREAM REQUEST plus the preserved negative result. The consumption design and its prerequisites 1-4 stay in `approval-single-use-consumption` and are **not restated here**.

## What already shipped

**E3 ask 2 — SHIPPED.** `policies/approval-policy.yml` § TRUST MODEL now states that a VALID artifact authorizes its action REPEATEDLY until `expires_at`, that the TTLs are a lifetime and never a use count, that nothing consumes an artifact on use, and that binding narrows WHICH action an artifact covers without SPENDING it — with the one real narrowing recorded (a digest-bound `protected_path_edit` artifact is single-CHANGESET, not single-USE). That was their one-sentence ask, and it closes the misreading that made the gate look stronger than it is.

## Ask 1 — the upstream request, with a stronger framing than the filing had

Their ask: push a Claude Code hooks feature request for a per-invocation `tool_use_id` (or equivalent) in the **PreToolUse AND PostToolUse** payloads, and link it from the backlog so consumers can track it.

Upstream's position that this is prerequisite #1 is right. **Found while filing, and it makes the request far easier to grant:** the host ALREADY mints exactly this identifier and already persists it.

| Fact | Evidence |
|---|---|
| Claude Code mints a per-invocation `tool_use_id` and writes it to the session transcript, correlating a `tool_result` back to its `tool_use` | `hooks/tests/fixtures/token-waste-*.jsonl` — `/message/content[*]/tool_use_id` |
| Flow ALREADY reads it, for exactly that correlation | `hooks/local/token-waste-audit.py:251,333` |
| It is absent from the hook event contract | `hooks/flow_hook_event.schema.json` properties: `session_id` is required; there is no per-invocation id |

So the request is not *"please invent an identity."* It is **"surface, in the hook payload you already send, the id you already mint."** That is the framing to file upstream.

Their supporting measurement, **OBSERVED** on their tree and not re-derived here: 286 audit rows on 2026-08-20, every one `session_id: null`, `host_tool` null.

## Ask 3 — the design it unblocks

Consume in PostToolUse on success, release on failure, orphan TTL. That is the sketch `approval-single-use-consumption` already carries and it is not repeated here. They offer a consumer arm to test Windows + a network filesystem — prerequisite 4, the hard part, and the one Flow cannot exercise alone.

## The negative result — preserved so nobody re-ships it

**Do not ship `O_EXCL` claim-at-evaluation.** The consumer ran it for three weeks on their 4.6.1 overlay with a `call_id` readmission. **It passed its own tests.** Their adversarial review (2026-08-20) failed it on two structural points and they WITHDREW the implementation (their ticket `flow-overlay-port-v4120`, decision NN3 rev 2):

| # | Defect | Mechanism |
|---|---|---|
| a | **Wrong denials** — a claim consumed on a command that is then DENIED | `_approval_state` is called per matched rule, before the whole-line decision is known; a later unsatisfied rule denies the line after the claim is already burned |
| b | **A wrong ALLOW** — the same `call_id` readmits indefinitely | Equality with a **caller-supplied** id is not freshness. Without a host-issued, unforgeable per-call identity there is no "same call" — only "same string the agent supplied" |

Defect (b) is precisely why ask 1 is a prerequisite and not decoration: any consume design keyed on an agent-suppliable value is a readmission oracle. Flow's backlog reached the same conclusion independently (`approval-single-use-consumption` § Shape once the prerequisites exist: *"Do not ship the `O_EXCL`-claim-at-evaluation design"*). What this entry adds is the field evidence — a consumer BUILT it, tested it green for three weeks, and it still produced both a wrong denial and a wrong allow. Green tests did not find it; an adversarial review did.

## Why nothing is built here

There is nothing buildable. Ask 1 is a request against a host Flow does not control, and ask 3 is gated on it. What this repo can do meanwhile is what it has done: keep binding + strict expiry, and stop the documentation from implying more than the gate delivers (ask 2, shipped).

## Acceptance sketch

1. AC1 — the upstream feature request exists, names BOTH PreToolUse and PostToolUse, and is linked from here and from `approval-single-use-consumption`.
2. AC2 — the request cites the transcript `tool_use_id` as an EXISTING host artifact, not a new one.
3. AC3 — no consume-on-evaluation design is implemented in ANY carrier before AC1 lands.

## Out of scope

- The consumption design itself — `approval-single-use-consumption` owns it.
- Any interim single-use SIMULATION. The consumer's own conclusion after their review, and ours.

## Related

- `docs/backlog/approval-single-use-consumption/README.md` — **the design + prerequisites 1-4; deliberately not duplicated here**
- `policies/approval-policy.yml` § TRUST MODEL — E3 ask 2, SHIPPED
- `docs/backlog/carrier-aware-approval-binding/README.md` — binding is replay reduction, never authorship (K3)
- `docs/problem-catalog/adversarial-review-convergence/problem.md` — the pattern this negative result is another instance of
- `hooks/flow_hook_event.schema.json` · `hooks/local/token-waste-audit.py:251,333`
