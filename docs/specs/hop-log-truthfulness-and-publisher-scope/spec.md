# Hop-log truthfulness + publisher scope (E8/E9 consumer batch)

**Status:** SPECIFIED — premise review complete (verdict SOUND-WITH-FIXES, corrections applied); ready for planning. **Implementation review of `497edf1`/`ef93b0b`/`44d0fd2`/`24cbff3` returned DO-NOT-SHIP** — the remediation set is in `corrections.md`; S1–S4 decisions below are unchanged. **Round 2:** the remediation (`fb6dd44`…`13ebe20`, T76–T82) was re-reviewed on `13ebe20`: C1–C8 accepted, **DO-NOT-SHIP** again on one High (R1 — C3's suppression loses real preflight failures) and two Lows (R2, R3); build plan in `corrections.md` § Round 2. S1–S4 still unchanged.
**Opened:** 2026-09-09 · **Against:** v4.15.3
**Source:** paperclip+hermes-v1, cover note + E8 + E9, committed `287435ab`

## What the consumer got right, and what they retracted

The 4.14.1 → 4.15.3 hop **validated the design**: 3 `changed-by-both` files, none in enforcement code,
down from 15 on their previous major hop. Their security overlay, protected-paths, PreToolUse veto and
approval customization all classified `consumer-only` and survived. They also **retired one of their
own overlays**, taking v4.15.3's ownership-aware `mirror-skills.sh` verbatim because it supersedes the
patch they were carrying.

**They withdrew E8's original framing themselves.** Their first draft accused v4.15.3 of re-wiring the
full lifecycle set without consent — a claimed F3 regression. Their own adversarial review refuted it
before sending. Verified here: the behaviour is authorized, not rogue.

## Verified locally before this spec was written

1. **The log contradicts itself in one run.** `hooks/local/upgrade.sh:803-805` is an **unconditional**
   `echo` in the summary block asserting *".claude/settings.json (Claude Code lifecycle hooks) was NOT
   modified — to (re)wire those, run … `--wire-hooks`"*. It prints on every run, including runs where
   the nested `post-fusebase-update.sh` merged and reported *"merged Fusebase Flow lifecycle events"*
   (`post-fusebase-update.sh:559`). Two scripts, one hop, contradictory claims — and the false one is
   hardcoded.
2. **E8's authorization chain is exactly as they describe.**
   `hook-wiring-intent.sh:218-228` maps `schema_version == 1` to the whole `claude_settings` surface;
   `post-fusebase-update.sh:188-192` sets `WIRE_HOOKS=1; AUTO_RESTORE=1` when an ENABLED marker names
   that surface and `--wire-hooks` was not requested. Automatic wiring therefore proceeds from a
   legacy blanket marker with no new flag. Their code-did-what-the-marker-authorized reading is right.
3. **E9 is a missed generalization of our own fix.** `lib/plugin-parity.sh` (preflight) gates on **two**
   predicates — ownership by `name`, **and publisher context** (the release ledger exists).
   `lib/partial-upgrade-check.sh:50-64` (health) carries only the first. Its own tripwire says
   *"scoped to FLOW-OWNED manifests by `name`"* — predicate 2 is precisely the one added because name
   alone proved insufficient, and `plugin-parity.sh`'s comment describes **this consumer**: *"all three
   of their manifests carry `name: fusebase-flow` — because they were generated FROM Flow's."*

## Premise review — what it confirmed, what it corrected

Read-only adversarial review, 17 files in bounded ranges including historical versions. Both defects
above stand; neither requires undoing automatic recovery.

**Confirmed history of the trailer.** The settings claim **was true for v4.14.1**: `post-fusebase-update.sh`
initialized `WIRE_HOOKS=0`, enabled it only through `--wire-hooks`, and skipped settings otherwise
(`v4.14.1:hooks/local/post-fusebase-update.sh:80-85,355-359`); upgrade invoked only `--refresh-overlays`
(`v4.14.1:hooks/local/upgrade.sh:698`). Commit `0829d16` introduced automatic restoration from valid
intent. That made an old unconditional message stale — it does **not** establish that the restoration
was wrong. Schema-1 intent still authorizes the whole surface (`hook-wiring-intent.sh:223`).

**Feasibility resolved positively, design corrected.** `upgrade.sh:697-706` invokes recovery
synchronously and captures stdout/stderr in `RECOVERY_LOG`; on success it forwards only `*` action
lines, on failure it prints only the final 15 lines and then **deletes the log**. Recovery already
distinguishes changed-vs-already-wired settings but emits no event list in those summary entries
(`post-fusebase-update.sh:555-559`), and it can return nonzero **after changes occurred** (`:744-786`).
So upgrade *can* observe recovery; today it discards the useful distinctions. The correction is in S1.

**Same defect, same sentence.** `upgrade.sh:729-749,803-804` also unconditionally claims the Git
fallback pre-commit was reinstalled and *"the fixed pre-commit is live"*, even though the code directly
above it handles installer failure and custom-hook preservation. Fixing only the settings clause leaves
an identical defect adjacent to it. S1 widens to the whole trailer.

**Third instance — recorded as evidence, not folded into scope silently.**
`fusebase-flow-health-check.sh:243-269` asserts *"Existing CLI hooks preserved"* after inspecting only
event-key presence and a Flow stop-path string. That branch cannot establish before/after preservation.
Actual CLI-hook loss on that path is **UNVERIFIED**; the evidentiary gap is established. It is listed
here so the pattern is on record; S1's build scope is the `upgrade.sh` trailer. If the implementer
touches this branch, say so in the change note — it is a claim-vs-evidence fix of the same family, not
a new check.

**The missing check, named precisely:** *agreement between a component's observed outcome and every
caller's summary — including failure, preservation and no-op branches.* Encode it as a concrete
reporting test whose regression scenario is the consumer's withdrawn diagnosis (a run that merged
lifecycle events and then printed "was NOT modified"). **No repository-wide audit is required** to fix
these findings.

## Slices

### S1 — the hop log must report what actually happened — BUILD FIRST

The consumer's own ranking, and it is right: *"a one-line truthful report … is worth more than the
feature ask."* This is the finding that cost them a wrong diagnosis and nearly cost us a false
regression report.

`upgrade.sh` must not assert a static claim about a file another part of the same run may have
modified. The "run `--wire-hooks`" advice must not appear after a run that already wired, and must not
appear after a run that found settings already current.

**Outcome contract.** Recovery/merger owns the factual result; upgrade forwards it. A child exit code
alone cannot establish whether settings changed. The settings result must survive the parent's success
*and* failure paths — it is preserved even when another recovery surface fails afterwards. No new
persistent reporting subsystem is needed; the existing captured log is the channel, it just has to
carry the distinctions and upgrade has to stop discarding them.

The trailer must render one of these, never a static line:

| Observed outcome | What the summary says | Must NOT say |
|---|---|---|
| Automatic restore merged events | which events were added or repaired, and that intent authorized it | "NOT modified", "run `--wire-hooks`" |
| Already current (no-op) | settings already carried the Flow events; nothing written | a recommendation to rewire |
| No authorization (no ENABLED marker, no `--wire-hooks`) | settings not touched; how to authorize if wanted | that recovery is complete for that surface |
| Minimal settings created, external bytes unresolved | created a minimal file; which external/CLI entries are still unresolved | "fully recovered" |
| Merge failure | the merge failed and settings are in an uncertain state; where the detail is | "unchanged" |
| Later recovery failure after settings changed | settings *were* changed (with the event list) and a later surface failed | "unchanged", "fully recovered" |

(`post-fusebase-update.sh:492-502,744-786` are the branches that produce the last three.)

**Whole trailer, not one clause.** The same block's Git-fallback claim (`upgrade.sh:729-749,803-804`)
must reflect the observed outcome: installed, preserved-custom-hook (not replaced), or installer
failure. "The fixed pre-commit is live" is only printed when the installer reported it live.

**Reporting test.** Drive recovery through each row of the matrix in a fixture consumer and assert the
`upgrade.sh` summary agrees with the recovery outcome; the merged-then-"NOT modified" scenario is the
regression case and must fail against v4.15.3.

**This is the session's recurring class, one more time:** a report keyed to an assumption rather than
to the outcome. Same family as an upgrade reporting success while installing nothing, a phase that
died mid-run and looked finished, and `--wire-hooks` reporting *"applied 7 changes"* while skipping the
one that mattered.

### S2 — apply the publisher predicate in health's partial-upgrade branch — BUILD

Generalize the existing fix rather than writing a second one. `plugin-parity.sh` already encodes both
predicates and the reasoning; health must use the same source of truth, not a parallel copy that can
drift.

**Reuse is technically sound.** `plugin-parity.sh:48-84` is function definitions and reads only — no
writes, no network, no preflight execution. Health `cd`s to the repository root
(`fusebase-flow-health-check.sh:27-28`), matching the helper's relative ledger/manifest paths. Publisher
detection checks ledger **existence**, not contents; `FFPP_LEDGER` overrides it. Consumers without the
ledger return before Python runs. Publishers incur at most six Python field reads versus four today
(timing UNVERIFIED, not expected to matter).

**Two things the reuse must decide explicitly, not inherit:**

1. **Marketplace coverage.** `ffpp_errors` also checks `marketplace.json` (`plugin-parity.sh:78-82`).
   Dropping the helper in as a replacement silently widens what health inspects. Decide marketplace
   inclusion in the decisions record; do not let it arrive as a side effect.
2. **Diagnostic meaning.** A publisher manifest mismatch is valid **packaging drift** but does not
   prove an interrupted upgrade. Health currently labels every such finding `PARTIAL_UPGRADE`
   (`fusebase-flow-health-check.sh:503-508`). Health must share the ownership/publisher scope logic and
   own a **different interpretation** with publisher-appropriate remediation (re-run parity / fix the
   manifests), not "your upgrade was interrupted".

**Retain the consumer adapter checks.** Missing plugin diagnostics must not suppress the independent
adapter checks at `partial-upgrade-check.sh:71-99`; a stale consumer adapter still fails.

Extracting a shared parity function is justified only if the helper's existing coverage/output cannot
serve both callers. If it can, call it; if it cannot, say why in the decisions record rather than
duplicating.

**Consequence to record:** the false warning drove them to hand-copy our manifest bytes twice to get a
clean verdict — *"precisely the consumer-ownership risk that exclusion exists to prevent."* A false
positive that induces the harm the design protects against is worse than a missing check.

### S3 — the notes still promise something no longer true — BUILD (docs, after locating targets)

The consumer reports that the 4.15.x release notes describe default recovery as leaving
`.claude/settings.json` untouched. With an ENABLED marker that is false: recovery now wires
automatically.

**The release-note passages are UNVERIFIED.** The review could not confirm them in its bounded read.
Before editing, the implementer must locate and name the exact current targets and the version
boundary at which the statement stopped being true (the `0829d16` restoration), and record both in the
change note. Descriptions that were accurate for the version they describe are **historical** and stay
as written — correct the current rule, do not rewrite history to match it.

**One stale source explanation IS confirmed:** `post-fusebase-update.sh:135-136` still says default
recovery never changes settings. Fix that comment alongside the notes.

### S4 — E8's actual ask: event-level intent — DECLINED IN THIS TICKET

Nothing in the chain can express an event **subset**: the merger adds every canonical event
(`settings-json-merge.py:92`), `validate_flow_wiring` requires all of them (`:245`),
`recovery-verify.py:134` calls it, and health treats Stop-with-missing-events as drift
(`fusebase-flow-health-check.sh:261`). Their tree wants enforcement only.

**Ruling: no build here; surface-level intent (schema 2 `surfaces`) is retained as-is.** Why, all of it:

- It is a **feature request**, not the cause of either confirmed defect. The consumer has a legitimate
  narrower-use case; it does not belong in a truthfulness/scope ticket.
- Their performance measurements and their claims about which handlers depend on which events are
  **consumer-reported, not independently verified** (`2026-09-09-E8-…md:18-20`).
- **Compatibility trap.** Today's schema-2 reader validates `surfaces` but ignores additional fields
  (`hook-wiring-intent.sh:194-226`). Adding an `events` field to schema 2 could let an **older reader
  silently interpret a subset declaration as whole-surface authorization** — the consumer would
  declare "PreToolUse only" and a pre-feature recovery would wire everything under that authority.
  Any future build needs an explicit compatibility contract (migration, explicit narrowing/widening,
  and agreement across writer, merger, recovery verifier and health) before it starts.
- **The validator does not carry over unchanged.** For a supported PreToolUse-only profile, an absent
  Flow `Stop` would be **expected** while an absent required `PreToolUse` would be drift. The current
  all-events validator stays correct for the full-lifecycle contract but cannot validate the narrower
  one as-is (validator implementation UNVERIFIED in the bounded review).

**If narrower operation is pursued later:** prefer a small set of explicitly supported **profiles**
(full-lifecycle, enforcement-only) after a handler-dependency review — never arbitrary event sets, which
multiply the states health must distinguish on top of the six lie-states from v4.12.0. And never infer
intent from surviving hooks: their withdrawn ask, treating whatever survived as the desired set, would
turn an accidental strip into accepted configuration.

## Acceptance

| Case | Expected |
|---|---|
| Run where recovery merged lifecycle events (the consumer's E8 scenario) | summary names the added events; no "NOT modified"; no `--wire-hooks` advice |
| Run where settings were already current | summary says already current; no rewire recommendation |
| Run with no ENABLED marker and no `--wire-hooks` | summary says not touched, with how to authorize |
| Merge failure / later recovery failure after settings changed | summary preserves the settings result and reports the failure; never "unchanged" or "fully recovered" |
| Git fallback: installer failure or custom hook preserved | trailer reports that outcome; "fixed pre-commit is live" absent |
| Consumer with copied-name manifests (`name: fusebase-flow`, no release ledger) | health does not flag them; manifests stay untouched |
| Publisher manifest mismatch (ledger present) | still fails, with the publisher interpretation and remediation, not `PARTIAL_UPGRADE` |
| Stale consumer adapters | still fail via `partial-upgrade-check.sh:71-99` regardless of plugin diagnostics |
| Health on every path above | remains read-only |
| Reporting test | merged-then-"NOT modified" fails against v4.15.3 and passes after S1 |

Most of these cases are the consumer's own, from their E9 filing (`2026-09-09-E9-…md:21-28`).

## Slice calls

| Slice | Call |
|---|---|
| S1 | BUILD — outcome contract + whole trailer |
| S2 | BUILD — shared scope logic, explicit diagnostic semantics, marketplace decided explicitly |
| S3 | BUILD — after verifying and naming the exact passages and version boundary |
| S4 | NO BUILD — retain surface-level intent; profiles, if ever, in a separate ticket with a compatibility contract |

## Standing wasted-work risk

The three-month regret to watch for: **the two diagnostic fixes become an event-configuration platform
for one atypical consumer**, adding compatibility and verification states while preserving the original
reporting ambiguity. The North Star records that ordinary-consumer benefit is unmeasured
(`docs/north-star.md:43-45`). S4's decline is the guard; if scope starts growing toward event sets,
stop and re-open this line.

## Explicitly NOT doing

| Not doing | Why |
|---|---|
| Treating surviving hooks as the desired set | their own withdrawn ask; converts an accidental strip into consent |
| Duplicating the publisher predicate into health | two copies drift; that divergence was itself the second bypass in v4.14.0 |
| Changing what `--wire-hooks` merges, as part of S1 | S1 is a truthfulness fix; changing behaviour is S4's question, and S4 is declined here |
| Undoing automatic restoration | the trailer went stale at `0829d16`; the restoration itself is authorized by intent |
| Building event-level intent (S4) | feature request, unverified consumer measurements, older-reader compatibility trap |
| A repository-wide claim-vs-outcome audit | the review found the instances it found within one caller family; fixing them does not require one |
| Adding a persistent reporting subsystem for S1 | the captured recovery log already exists; it needs to carry and forward the outcome |
