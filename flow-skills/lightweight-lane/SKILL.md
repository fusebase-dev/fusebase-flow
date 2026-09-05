---
name: lightweight-lane
description: Use at Specify to classify a ticket Full vs Lightweight after bounded read-only diagnosis, and whenever a change looks ordinary / reversible / low-risk ("small fix", "tweak", "hotfix", "drop pretty-printing", "bump a constant"). Operationalizes FR-21 — ceremony proportional to objective risk. Defines mechanical and semantic assessment, the change-note artifact, one-pass build→verify→deploy, and objective promotion. Sensitive or cross-cutting triggers take the Full lane; an initially unknown cause or file count alone does not.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.7
risk_level: medium
invocation: automatic
expected_outputs:
  - a tier classification (full | lightweight) with the gate result
  - for lightweight tickets, a single change-note (templates/change-note.md) inline in the commit body or at docs/changes/<date>-<slug>.md
  - a tier/promotion record in the change-note / commit body (optional consolidated ledger if the project keeps one)
related_workflows:
  - lightweight-lane.md
  - eight-phase-flow.md
  - greenlight-deploy.md
hook_dependencies:
  - none
---

# Lightweight Lane (FR-21)

## Purpose

Make ceremony proportional to observed risk. Fusebase Flow's full eight-phase lane is for objective sensitive, release, protected, cross-cutting, or unresolved product-decision triggers, where spec / clarify / decisions / gate de-risk the work. Ordinary reversible work with a complete assessment uses the **Lightweight Lane (LL)**: one product outcome decision, one change-note, one pass. The safety controls remain in both lanes.

This is **not** only for one-line edits. It covers the whole class of **small / minor changes that need no large implementation and no real architectural decisions** — small hotfixes, small bug fixes, small improvements, config/copy tweaks. The discriminator is *implementation size + risk*, not a hard file count.

> The change-note is **Tier 1** in the FR-23 documentation budget (`flow-skills/documentation-budget/SKILL.md`): FR-21 scales *process* ceremony; FR-23 scales *persistent documentation*. A Lightweight ticket's documentation IS the change-note — do not also emit spec/decisions/tasks/handoff docs for it.

## When to classify (every ticket, at Specify)

Run enough bounded read-only diagnosis to identify the behavior, likely diff, and risk evidence before choosing a lane. Then classify **Full** or **Lightweight**. `requirements-specification` calls this gate. Record `change_tier` (in the change-note for LL; in `spec.md` for Full).

## Eligibility gate — Lightweight iff ALL of these hold

| # | Condition | Concrete check |
|---|---|---|
| 1 | Bounded implementation, single product outcome | One coherent outcome and no cross-cutting architecture. File count alone is not a trigger. |
| 2 | Reversible | `git revert` / restore-backup undoes it. **No** DB schema/data migration; **no** hard-to-remove new dependency. |
| 3 | Clear, mechanically-verifiable acceptance | A defined outcome (one or a few sentences) checkable by a gate / probe / measurement. |
| 4 | No sensitive semantic trigger | The diagnosed behavior/diff has no auth, permissions, secrets, data/schema, public-contract, production/release, or protected-path trigger. |
| 5 | No architecture or product-decision trigger | No cross-cutting architecture and no unresolved product decision. |
| 6 | Assessment complete | The path router succeeded and the AI semantic assessor declared every trigger with an evidence path and reason. |

The path router accepts changed paths and emits structured matched paths and trigger IDs. An input error is nonzero and never Lightweight. `NO_MECHANICAL_MATCH` means only that no path rule matched. The AI semantic assessor inspects the diagnosed behavior/diff; sensitive logic in an ordinary filename still activates Full. A mechanical match **or** semantic trigger activates Full. If assessment is incomplete, continue bounded read-only diagnosis; if it remains unresolved, stop at `BLOCKED-AT-lane-assessment`. Never infer safety from missing evidence.

| Objective Full trigger | Evidence examples |
|---|---|
| auth · permissions · secrets | diagnosed logic, configuration, or diff changes access or credential handling |
| data/schema | migration, ownership, persistence, or stored-data contract changes |
| public-contract | API, route, manifest, event, or externally consumed behavior changes |
| production/release | publication, deployment, release identity, or production state changes |
| protected-path | changed path or diagnosed behavior crosses the declared protected boundary |
| cross-cutting architecture | one outcome requires coordinated subsystem design |
| unresolved product decision | the shipped outcome cannot be stated without an operator choice |

## What the Lightweight Lane changes

| Step | Full lane | Lightweight lane |
|---|---|---|
| Planning artifacts | spec.md + decisions.md + tasks.md + verification-gate.md | **One change-note** (problem · change · how verified · rollback · tier) — inline in the commit body or `docs/changes/<date>-<slug>.md` |
| Handoffs | implement-handoff + deploy-handoff | **One** combined note, or none (inline) |
| Agent passes | build-agent (stop at gate) → separate deploy-agent | **One agent pass**: build → live-verify → deploy in a single run (no redundant rebuild) |
| Deploy approval | DP.1 JSON artifact + DP.6 deploy phrase (`approve deploy now`) | **One explicit plain operator go-ahead** ("ship it"); no deploy phrase, no hand-authored JSON |
| Verification | full gate report (P1..Pn) | **Live-proof kept**, the 3-question empirical test still applied to the one acceptance criterion, reported in 1–3 lines |
| Traceability | full counter + index + backlog updates | **Minimal**: `change_tier: lightweight` + the commit SHA recorded in the commit body (always); an optional one-line ledger entry if the project keeps one |

## What LL KEEPS (non-negotiable safety floor — both lanes)

- **Live verification / proof it works** (the probe / measurement) — never skipped; the [validation-and-qa](../validation-and-qa/SKILL.md) 3-question empirical test still applies to the acceptance criterion.
- **An explicit operator deploy go-ahead** — never auto-deploy; just lighter than a JSON artifact + magic phrase for a reversible trivial change.
- **FR-07 worker-undisturbed / protected-path check** — cheap and safety-relevant; run it.
- **A documented rollback** — one line in the change-note.
- **One commit per change** (FR-03) + the SHA recorded; lint + typecheck per commit (FR-13).

## What LL DROPS (planning/traceability overhead, not safety)

- Separate spec / decisions / tasks / verification-gate / two handoff docs / DP.1 artifact.
- The DP.6 deploy phrase (replaced by a plain explicit go-ahead).
- The build-then-deploy two-agent split (→ no redundant rebuild).
- The long-form gate report (replaced by a 1–3 line live-proof summary).

## Procedure (Lightweight)

1. **Diagnose, then classify.** When the cause or risk is unclear, perform bounded read-only inspection. Run `hooks/local/lane-router.sh --json` on the changed paths and declare every semantic trigger with evidence path/reason through `hooks/local/lane-assessment.py`. Mechanical or semantic triggers route to Full. Incomplete assessment continues bounded diagnosis, then stops at `BLOCKED-AT-lane-assessment` if unresolved.
2. **Write the change-note** from `templates/change-note.md`: the one product outcome decision, problem, diagnosed evidence, router result, semantic declarations, change, live proof, rollback, and `change_tier: lightweight`. Inline in the commit body for the smallest changes, or save to `docs/changes/<date>-<slug>.md`.
3. **One agent pass.** Pre-task git checkpoint → make the change → lint + typecheck → build once → **live-verify** (run the probe/measurement; apply the 3-question test to the acceptance criterion) → commit (one commit, FR-03) → record the SHA.
4. **Deploy on a plain go-ahead.** Re-run the FR-07 protected-path check. Ask the operator in chat text (FR-19) for an explicit go-ahead ("ship it" / "deploy it" / "go"). **Never auto-deploy.** No DP.6 magic phrase, no separate deploy session. (Hook-wired projects: record the go-ahead with one command — `bash hooks/local/approve-local.sh lightweight_deploy <slug> 'ship it' --command 'fusebase deploy'` — see [release-deploy-reporting](../release-deploy-reporting/SKILL.md) and `policies/approval-policy.yml`. Hooks are opt-in; in the default off setup the chat go-ahead is the gate.) **Trust boundary (decision K5), stated because it is not enforceable:** lane classification is **process-authoritative** — `policies/command-policy.yml`'s `fusebase deploy` rule now accepts `any_of: [production_deploy, lightweight_deploy]`, so the hook cannot verify a change was genuinely LL-eligible. An agent that self-declares Lightweight takes the cheaper gate. The eligibility test above is the control; the artifact is only a record.
5. **Report in 1–3 lines:** what changed, the live-proof result (observed vs expected), the deploy SHA, and the one-line rollback.
6. **Record the tier.** Always put `change_tier: lightweight` + the commit SHA in the change-note / commit body (that is the durable telemetry; git carries it). A consolidated **ledger is opt-in**: if the project keeps one, append one line (date · slug · `lightweight` · SHA). Its location is configurable — default `docs/changes/index.md`, but a repo with a per-app docs layout may set its own path (e.g. `docs/<app>/changes.md`) or skip the file entirely and rely on the commit body. Do **not** assume a repo-root ledger exists; only materialize it on opt-in.

## Worked example

An error message is wrong and the cause is initially unknown. A bounded read-only trace identifies one formatter and a reversible copy correction. The path router returns `NO_MECHANICAL_MATCH`; the semantic assessor declares no sensitive trigger and marks the assessment complete. The change-note records one outcome decision — show the accurate message — plus the diagnosis, declarations, proof, and rollback. One agent implements, verifies, commits, and deploys after the operator's plain go-ahead. If the trace instead showed an auth branch or left the behavior unresolved, the final lane would be Full or `BLOCKED-AT-lane-assessment`.

## FR-25 interplay (module-size ratchet)

The module-size ratchet applies in **both lanes**. If an LL change would grow an over-ceiling file (or push a file past the ceiling), extracting the addition into a new module along a responsibility seam is **part of the LL change, not scope creep and not by itself a promotion trigger** — the extra file the extraction creates does not fail eligibility condition 1. Promote only if the extraction itself surfaces a real architectural decision or risk (then the normal promotion rule applies). Never satisfy the gate with a mechanical `utils2` split or an agent-initiated baseline/exemption edit — see `flow-skills/module-size-discipline/SKILL.md`. **If the pass extracted a module, name the responsibility seam in the change-note's `Change:` line** (LL has no review step — the named seam is what lets the operator judge the split at a glance).

## Mid-flight promotion (mandatory)

If any objective Full trigger appears while doing an LL change, **STOP and promote to the Full lane.** Run the same path and semantic assessment against the diagnosed diff. If the assessment cannot be completed after bounded read-only diagnosis, stop at `BLOCKED-AT-lane-assessment`. More files or a deeper cause alone does not promote the ticket.

On promotion: stop coding, open a Full-lane spec (`requirements-specification`), carry over what you learned, and record the promotion (`promoted: lightweight→full — <trigger-id> · <evidence-path> · <reason>`) in the promoting commit body, plus the project's ledger if it keeps one.

## Telemetry

The **durable** record is always in git: `change_tier: lightweight` + the SHA in the commit body / change-note, and `promoted lightweight→full — <reason>` in the promoting commit. That alone makes the tier split and any mis-tiering auditable via `git log`.

A **consolidated ledger is optional and path-configurable** — it just makes the history easier to skim. Default location `docs/changes/index.md`; a project with a per-app docs convention may point it elsewhere (e.g. `docs/<app>/changes.md`) or omit it. One line per LL ticket (`<date> · <slug> · lightweight · <SHA>`) and one per promotion. Keep it minimal; it is a ledger, not a report. Never assume a repo-root ledger exists — create/append only where the project has opted in.

## Anti-patterns

- Do **not** route a mechanical or semantic Full trigger through LL because the patch looks small.
- Do **not** drop any safety-floor item (live proof, explicit go-ahead, FR-07 check, rollback, one-commit) — those are not ceremony.
- Do **not** auto-deploy because the change is trivial — the human go-ahead is always required (FR-12 spirit; FR-05).
- Do **not** keep coding past a surfaced objective trigger or incomplete assessment — promote or block (FR-21 + FR-20).
- Do **not** batch several LL changes into one commit — one change = one commit (FR-03).
- Do **not** silently downscope a Full-lane ticket to LL to avoid the gate — classification is at Specify and changes only via explicit promotion/demotion the operator can see.

## Clean-room note

Original Fusebase Flow content. The change-size tiering concept is common to mature CI/CD + code-review practice (ceremony proportional to blast radius); no third-party code, prompts, or skill files are copied. See `docs/source-map.md`.
