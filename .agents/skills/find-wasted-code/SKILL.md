---
name: find-wasted-code
description: Use ONLY when the operator runs "/find-wasted-code" (or explicitly asks to "scan the repo for dead-end tool calls / broken links / missing helpers / footgun configs / silent push-through"). Statically scans THIS repo for friction footguns and writes a tracked report to docs/wasted-code/report.md. Manual-trigger ONLY — do NOT auto-invoke; the skill carries disable-model-invocation and no hook wires it. Read-only except the one report write. Findings are review candidates, never auto-fixes. Do NOT use for token/transcript economy (/token-waste-audit), for process ceremony (/find-wasted-effort), or for CLI/Flow drift health (/fusebase-health).
disable-model-invocation: true
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: "4.5"
risk_level: low
invocation: manual
expected_outputs:
  - a Mode-A chat summary plus a tracked report at docs/wasted-code/report.md
  - per-rule findings (W1-W4) each labelled broken/confirmed or candidate/inconclusive, evidence + suggested fix + why-it-might-be-intentional
  - a Coverage section (W5 swallow baseline, unresolved references, skipped inputs) — silence is auditable, not clean
related_workflows:
  - eight-phase-flow.md
hook_dependencies:
  - none
---

# Find Wasted Code (static friction-footgun audit)

The **active, static inverse of a papercuts log**. A papercuts tool is *passive* —
an agent must notice friction and file it. This audit *scans the repo* for the
same north-star footguns and writes them down, so nobody has to notice first:

> Agents hit friction constantly — **dead-end tool calls, broken links, missing
> helpers, footgun configs — and silently push through without telling anyone.**

It is the third audit sibling, on a distinct axis:

| | `/find-wasted-code` (this) | `/find-wasted-effort` | `/token-waste-audit` |
|---|---|---|---|
| Axis | code-per-friction (footguns) | process-per-outcome (ceremony) | tokens-per-rule (consumption) |
| Inputs | repo source: docs, skills, commands, hooks, settings | Flow artifacts on disk | Claude transcripts |
| Output | **`docs/wasted-code/report.md` (TRACKED)** | `state/audit/<date>.md` (gitignored) | `state/audit/<date>.md` (gitignored) |
| Trigger | **`/find-wasted-code` ONLY (never auto)** | `/find-wasted-effort` (auto-invocable) | `/token-waste-audit` |

## How to run

1. `python hooks/local/find-wasted-code.py` (if `python` is missing, `python3 …`). Optional: `--print` (summary only, no write), `--date YYYY-MM-DD` (deterministic in-report date), `--selftest` (per-rule golden fixtures), `--root PATH`.
2. Read the report it wrote (`docs/wasted-code/report.md`): the per-rule findings + the Coverage section.
3. Interpret every row as a review **candidate**, never a verdict or an auto-fix. `broken`/`confirmed` = the target is provably absent from repo state; `candidate`/`inconclusive` = needs human judgment. Ambiguous references are listed under **Coverage → Unresolved**, never as defects.
4. Output a Mode-A chat summary: totals by rule/severity, the W5 baseline counts, and the top confirmed `broken` items. Do not paste raw file contents.
5. The report is **tracked** (papercuts philosophy — it shows up in diffs). It is redaction-safe by construction and will not trip the pre-commit secret scanner. Fixes are the operator/PO's call — this audit surfaces, it does not mutate.

## The rules (one per north-star category)

> Per-rule signatures, the conservative confirmed-vs-coverage contract, and the false-positive classes: `references/rule-catalog.md` and `references/false-positive-examples.md`. Cite them; don't restate.

| # | Rule | What it confirms (`broken`) | What it leaves as Coverage |
|---|---|---|---|
| W1 | Dead-end tool/script references | a root-explicit interpreter/`./`-run path (`bash hooks/local/<name>.sh`) that is absent | cwd-ambiguous paths, placeholders, design docs (specs/backlog excluded) |
| W2 | Broken internal links | a Markdown link whose path is absent, or whose anchor no heading yields (target slug-confident) | non-Markdown anchors, slug-ambiguous targets (→ `inconclusive`), external/placeholder dests |
| W3 | Missing helpers | a shell `source` of a static root-explicit script that is absent | `related_workflows`/`hook_dependencies` (ambiguous field shape) → unresolved |
| W4 | Footgun config | a settings hook `command` wired to a handler that does not exist (silently never fires) | dead policy keys (no stdlib YAML) — future |
| W5 | Silent push-through | — (no confirmed findings in v1) | swallowed-error **baseline** (broad/trivial `except`; shell `2>/dev/null`/`\|\| true`/`\|\| return 0`) as review candidates |

## Conservative by construction (load-bearing)

A finding is `confirmed` ONLY when provable from repository state. Everything
ambiguous is Coverage, never a defect — so the audit never blocks or annoys the
operator with a false positive. This is the same "don't block the human operator"
floor the framework holds everywhere. W5 is deliberately a *measured baseline*,
not a finding list: this repo intentionally fails open/closed in many places
(best-effort cleanup, fail-closed scanners), so generic swallow-detection cannot
be low-false-positive — the operator reviews the baseline and annotates
intentional swallows with `find-wasted-code: ignore W5 — <reason>`.

## Trigger isolation

- **Claude Code:** hard guarantee via `disable-model-invocation: true` — the model cannot auto-load this skill; only `/find-wasted-code` runs it.
- **Other adapters (Codex/Cursor/Gemini):** advisory — the narrow description above will not match ordinary work, and no hook wires the analyzer. Invoke by name or `/prompts:find-wasted-code`.
- No lifecycle hook (SessionStart/Stop/PostToolUse/UserPromptSubmit) references this skill or its analyzer. It is inert until the operator triggers it.

## Read-only-to-the-project

The analyzer writes ONLY `docs/wasted-code/report.md`, containment-checked to
inside the repo, symlink/hardlink-refusing, atomic, and sentinel-guarded (it will
not overwrite a hand-authored file lacking its generated-file sentinel). No
memory, overlay, spec, policy, or source edits. Fixes are proposed, never applied.

## Non-Claude surfaces

Invoke the `find-wasted-code` skill by name and run the analyzer directly
(`python hooks/local/find-wasted-code.py`); it is stdlib-only and
surface-independent. Metrics come from repo state, so there is no transcript
dependency.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public agent-friction
and self-improvement projects (papercuts, agentlogs, friction-logging-toolkit,
self_improving_coding_agent, opencode-autolearn) for *concepts only* — the
north-star framing and severity vocabulary. No third-party code, prompts, skill
files, or hook scripts are copied; the analyzer, rule contract, and report format
are clean-room original. See `docs/source-map.md`.
