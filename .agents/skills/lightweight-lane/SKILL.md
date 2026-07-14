---
name: lightweight-lane
description: Use at Specify to classify a ticket Full vs Lightweight, and whenever a change looks small / reversible / low-risk ("small fix", "tweak", "hotfix", "drop pretty-printing", "bump a constant"). Operationalizes FR-21 — ceremony proportional to change size. Defines the eligibility gate, the change-note artifact, the one-pass build→verify→deploy procedure, and mid-flight promotion. Do NOT use for risky/uncertain work, schema/data migrations, security/permission changes, new public contracts needing a decision, unknown-root-cause diagnostics, or large features — those take the Full lane.
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

Make ceremony proportional to risk. Fusebase Flow's full eight-phase lane is calibrated for *uncertain / risky* work, where spec / clarify / decisions / gate genuinely de-risk. For a change that is small, reversible, security-neutral, and has a one-sentence verifiable outcome, that uncertainty is near zero — so the planning + traceability artifacts add cost without reducing risk, and the two-agent deploy split can even *add* risk (redundant rebuild, more surface for mistakes than the change carries). This skill is the single source of truth for the **Lightweight Lane (LL)**: the eligibility gate, the change-note, the one-pass procedure, and mid-flight promotion. Everything that actually controls risk is **kept in both lanes**.

This is **not** only for one-line edits. It covers the whole class of **small / minor changes that need no large implementation and no real architectural decisions** — small hotfixes, small bug fixes, small improvements, config/copy tweaks. The discriminator is *implementation size + risk*, not a hard file count.

> The change-note is **Tier 1** in the FR-23 documentation budget (`flow-skills/documentation-budget/SKILL.md`): FR-21 scales *process* ceremony; FR-23 scales *persistent documentation*. A Lightweight ticket's documentation IS the change-note — do not also emit spec/decisions/tasks/handoff docs for it.

## When to classify (every ticket, at Specify)

Classify **Full** or **Lightweight** when the ticket is opened. `requirements-specification` calls this gate. Record `change_tier` (in the change-note for LL; in `spec.md` for Full).

## Eligibility gate — Lightweight iff ALL of these hold

| # | Condition | Concrete check |
|---|---|---|
| 1 | Small implementation, single coherent concern | Modest code, no large/multi-part build, **no real architectural decision**. A handful of files is fine — the test is *"no large implementation AND no real decision needed,"* not a file count. |
| 2 | Reversible | `git revert` / restore-backup undoes it. **No** DB schema/data migration; **no** hard-to-remove new dependency. |
| 3 | Clear, mechanically-verifiable acceptance | A defined outcome (one or a few sentences) checkable by a gate / probe / measurement. |
| 4 | No new security surface | No authz / permission / protected-path / secret-handling change. |
| 5 | No cross-cutting / public-contract change needing a decision | No new API / route / manifest needing an architectural choice (a routine in-place SKIP-upgrade deploy is fine); no broad refactor. |
| 6 | Root cause already understood | Not a Phase-1 diagnostic. Unknown-cause investigation always uses the Full lane. |

**If ANY condition fails, or it's a large feature you'd want to audit before the next thing ships, or there is genuine doubt → Full lane.** Fail-safe: when unsure, escalate up. The line is *"does this need design / decisions or carry real risk?"* — if no, it's Lightweight regardless of how "important" it feels.

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

1. **Classify** with the gate above. If any condition fails or there is doubt → Full lane (use `requirements-specification` → `implementation-planning`).
2. **Write the change-note** from `templates/change-note.md`: problem · the change · how it's verified (the live proof) · rollback · `change_tier: lightweight`. Inline in the commit body for the smallest changes, or save to `docs/changes/<date>-<slug>.md`.
3. **One agent pass.** Pre-task git checkpoint → make the change → lint + typecheck → build once → **live-verify** (run the probe/measurement; apply the 3-question test to the acceptance criterion) → commit (one commit, FR-03) → record the SHA.
4. **Deploy on a plain go-ahead.** Re-run the FR-07 protected-path check. Ask the operator in chat text (FR-19) for an explicit go-ahead ("ship it" / "deploy it" / "go"). **Never auto-deploy.** No DP.6 magic phrase, no separate deploy session. (Hook-wired projects: record the go-ahead with one command — `bash hooks/local/approve-local.sh lightweight_deploy <slug> 'ship it'` — see [release-deploy-reporting](../release-deploy-reporting/SKILL.md) and `policies/approval-policy.yml`. Hooks are opt-in; in the default off setup the chat go-ahead is the gate.)
5. **Report in 1–3 lines:** what changed, the live-proof result (observed vs expected), the deploy SHA, and the one-line rollback.
6. **Record the tier.** Always put `change_tier: lightweight` + the commit SHA in the change-note / commit body (that is the durable telemetry; git carries it). A consolidated **ledger is opt-in**: if the project keeps one, append one line (date · slug · `lightweight` · SHA). Its location is configurable — default `docs/changes/index.md`, but a repo with a per-app docs layout may set its own path (e.g. `docs/<app>/changes.md`) or skip the file entirely and rely on the commit body. Do **not** assume a repo-root ledger exists; only materialize it on opt-in.

## FR-25 interplay (module-size ratchet)

The module-size ratchet applies in **both lanes**. If an LL change would grow an over-ceiling file (or push a file past the ceiling), extracting the addition into a new module along a responsibility seam is **part of the LL change, not scope creep and not by itself a promotion trigger** — the extra file the extraction creates does not fail eligibility condition 1. Promote only if the extraction itself surfaces a real architectural decision or risk (then the normal promotion rule applies). Never satisfy the gate with a mechanical `utils2` split or an agent-initiated baseline/exemption edit — see `flow-skills/module-size-discipline/SKILL.md`. **If the pass extracted a module, name the responsibility seam in the change-note's `Change:` line** (LL has no review step — the named seam is what lets the operator judge the split at a glance).

## Mid-flight promotion (mandatory)

If, while doing an LL change, ANY of these appears → **STOP and promote to the Full lane:**
- it touches more than a couple files, or
- it surfaces a risk (security, data, protected path, cross-cutting), or
- it needs a real architectural decision, or
- the "one-line" fix reveals a deeper bug.

On promotion: stop coding, open a Full-lane spec (`requirements-specification`), carry over what you learned, and record the promotion (`promoted: lightweight→full — <reason>`) in the promoting commit body, plus the project's ledger if it keeps one. Promotion is a success, not a failure — it is the gate working. (Real example: a "trivial" assignment fix surfaced a same-class recovery-path bug; that *should* promote.)

## Telemetry

The **durable** record is always in git: `change_tier: lightweight` + the SHA in the commit body / change-note, and `promoted lightweight→full — <reason>` in the promoting commit. That alone makes the tier split and any mis-tiering auditable via `git log`.

A **consolidated ledger is optional and path-configurable** — it just makes the history easier to skim. Default location `docs/changes/index.md`; a project with a per-app docs convention may point it elsewhere (e.g. `docs/<app>/changes.md`) or omit it. One line per LL ticket (`<date> · <slug> · lightweight · <SHA>`) and one per promotion. Keep it minimal; it is a ledger, not a report. Never assume a repo-root ledger exists — create/append only where the project has opted in.

## Anti-patterns

- Do **not** route risky/uncertain work through LL because it "feels small." The gate is conjunctive; if you're arguing yourself into LL, that doubt means Full.
- Do **not** drop any safety-floor item (live proof, explicit go-ahead, FR-07 check, rollback, one-commit) — those are not ceremony.
- Do **not** auto-deploy because the change is trivial — the human go-ahead is always required (FR-12 spirit; FR-05).
- Do **not** keep coding past a surfaced risk / decision / deeper bug — promote (FR-21 + FR-20).
- Do **not** batch several LL changes into one commit — one change = one commit (FR-03).
- Do **not** silently downscope a Full-lane ticket to LL to avoid the gate — classification is at Specify and changes only via explicit promotion/demotion the operator can see.

## Clean-room note

Original Fusebase Flow content. The change-size tiering concept is common to mature CI/CD + code-review practice (ceremony proportional to blast radius); no third-party code, prompts, or skill files are copied. See `docs/source-map.md`.
