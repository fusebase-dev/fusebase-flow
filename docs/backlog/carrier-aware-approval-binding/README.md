# carrier-aware-approval-binding

**Status:** OPEN — replaces consumer proposal E1, which is **DECLINED as proposed**
**Opened:** 2026-08-21
**Source:** paperclip+hermes-v1 escalation E1 (`2026-08-20-E1-require-binding-knob.md`)
**Premise review:** Codex 5.6 Sol xHigh, verdict **WRONG-LAYER / NO-BUILD as proposed** (`/c/tmp/e1-review-out.md`)

## The exposure is real — the proposed fix is not

**Confirmed at the source.** `hooks/shared/approval_artifact.py:151-161`, `_binding_ok`, states it in its
own docstring: *"Absent/empty recorded value => not bound => ok."* Binding is enforced only when the
artifact's author chose to record it, so an artifact with no `command_digest` and no `repo_id`
authorizes its action in any checkout, indefinitely.

Their measurement, OBSERVED on their tree: **42 unexpired `production_deploy` artifacts, 42/42
unbound**, 10 without `action`, 0 at `schema_version: 2` — every one eligible, and observed `VALID`
under `strict_approvals: true`.

Their framing is exact and worth preserving: **present is decided by whoever wrote the artifact.**

## Why `require_binding` as a global knob is the wrong control

### 1. It is invalid for three of the carriers (BLOCKER)

The carriers structurally cannot supply the same facts:

| Carrier | Supplies | Source |
|---|---|---|
| command policy | `command_digest` + `repo_id` | `command_policy.py:122-131` |
| path policy | `repo_id` only — **no command digest** | `path_policy.py:284-294` |
| active-approval reporting | neither | `active-approvals.sh:118-129` |

`write-bootstrap-approval.sh:120-134` mints a **tree-digest**-bound protected-path artifact. A global
"command digest AND repo id required" predicate **rejects that legitimate artifact** — breaking the
FR-07 staged-approval flow that is the sanctioned way to commit a protected path.

### 2. The proposed fail-safe can brick its own recovery (HIGH)

"Absent or unparsable ⇒ treat as true" is circular:

- Malformed YAML raises during load (`policy_loader.py:44-50,65-84`).
- `path_policy` reads approval-policy strictness **before** examining artifacts (`:267-272`), so an unloadable policy denies even when a valid recovery artifact exists.
- `approve-local.sh` loads approval-policy **before** writing an artifact (`:127-138`), so it cannot repair the state it is locked out by.
- `--wire-hooks` rewires hooks; it is not a damaged-policy repair (`post-fusebase-update.sh:24`).

### 3. `is_acceptable` cannot express the question (HIGH)

`is_acceptable(verdict, strict)` receives only those two values, and `VALID` carries no information
distinguishing bound from unbound (`approval_artifact.py:237-257`). Centralising correctly needs a
mode-independent `UNBOUND` / `MISSING_BINDING` state or a structured acceptance context — not a check
bolted onto one caller. A knob honoured in one carrier while others bypass it is the same shape as the
PowerShell gate bypass fixed in v4.14.0.

### 4. K2 already answered this, and the flip would change it (HIGH)

K2 locked *enforce bindings when present; otherwise retain action scope*
(`approval-binding-and-upgrade-classification/decisions.md:48-52`) and **specifically rejected
immediate mandatory binding because it would invalidate every legacy approval without warning**
(`:54-57`).

Default `false` **extends** K2. Flipping globally **changes K2's locked fallback**, and flipping
without migration repeats the outage K2 rejected, one release later. K7 (`:136-147`) establishes that
a later cutover can be legitimate — but only with warning, inventory, and scheduled reissue.

Sibling K19 (`:355-366`) already rejected optional binding for command-gated writers and requires
`--command`, so **new** command-gated artifacts are already bound by construction.

### 5. It would claim more authority than binding provides (HIGH)

Binding reduces **replay**. It does not prove authorship. K3 (`:63-74`) records that the agent and
operator share an OS principal and locally stored claims are forgeable — a same-principal process can
hand-write a *correctly bound* artifact, because both hashes are computable
(`approval_artifact.py:129-162`). Any doc for this must say replay reduction, not authenticated
approval.

## What the population actually proves

42/42 unbound proves **both** the exposure and that an unqualified flip is unsafe. Expiry-less
artifacts never leave the population naturally (`compat-approval-surfacing/README.md:34-38`), so the
unbound set does not shrink on its own — and binding cannot be synthesised, because Flow does not know
which future command received the original authorisation. K7 rejected the equivalent synthetic
migration for expiry (`decisions.md:138-140`).

## Replacement design — the slice order to build if commissioned

1. Revise K2 and lock the threat model: **replay reduction, not authorship**.
2. Define the **carrier/action binding table** — command-gated high-blast actions require `command_digest` + `repo_id`; ordinary protected-path artifacts require repo/path scope; bootstrap artifacts require exact staged-tree binding; reporting evaluates with its own carrier's inputs.
3. Add a mode-independent missing-binding state and centralise audited acceptance.
4. Verify every writer against its carrier-specific invariant.
5. Carrier-aware inventory, health surfacing, and exact re-mint guidance.
6. Enable enforcement first for **named high-blast command actions** only.
7. Consider a scoped default flip only after migration and recovery are proven.

Note the carrier-table requirement is already recorded independently
(`compat-approval-surfacing/README.md:48-58`) — this ticket and that one should be resolved together.

## Standing wasted-work risk

Judged harmful in three months if a global flip breaks legacy and protected-path recovery while adding
little protection for new artifacts — which K19 already binds — and none against a same-principal
process able to write matching fields.

## Ordinary-consumer impact

**UNVERIFIED.** The North Star records that no ordinary consumer has been measured
(`docs/north-star.md:43-45`). Both consumers driving this chain are atypical — deep adopters running
their own overlays. Keep enforcement scoped and opt-in until an ordinary consumer is measured.

## What the reporting consumer should do meanwhile

Their consumer-owned PreToolUse veto is the correct interim enforcement layer and should stay. Their
own filing says so; this ticket does not ask them to remove it. It is the wrong *long-term* home for
the reason they give — every consumer relying on binding would have to reinvent the predicate, and the
health check cannot see a consumer-added hook — and that argument survives this review intact.
