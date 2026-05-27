---
name: fusebase-flow-health-check
description: Use when operator asks "is Fusebase Flow healthy", "check Fusebase Flow", "did fusebase update break anything", "Fusebase Flow status", "what's broken with Fusebase Flow", "restore Fusebase Flow", or asks to verify the project's Fusebase Flow overlay after running `fusebase update` or any other tool that touches AGENTS.md / `.claude/*`. Reports overlay status (skills/agents mirrors, AGENTS.md overlay, CLAUDE.md overlay, .claude/settings.json events) and compares the local `.fusebase-flow-source/` clone against upstream. Surfaces drift signatures (especially `fusebase update` aftermath). For recoverable drift verdicts (FUSEBASE_UPDATE_AFTERMATH, recoverable DRIFTED), offers recovery in-chat — asks the operator "Run recovery now?" and executes `bash hooks/local/post-fusebase-update.sh` only on affirmative reply (yes / run it / fix it / proceed). Diagnosis is always read-only; recovery is operator-confirmed (engine v2.2). For EXCEPTION_IN_EFFECT and BROKEN verdicts the skill does NOT offer recovery — recovery wouldn't fix them.
source_inspiration: original (operator-maintained recovery infrastructure, contributed to upstream in v2.2.0)
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: low — diagnosis phase is read-only; recovery phase executes hooks/local/post-fusebase-update.sh only after explicit operator affirmative reply in chat
invocation: automatic (description match) — also via /fusebase-health slash command
expected_outputs:
  - Health check report printed to chat (Mode A: visual, tabular)
  - Active approval artifacts surfaced as informational section (if any)
  - Recovery offer if drift is detected (FUSEBASE_UPDATE_AFTERMATH or recoverable DRIFTED)
  - On affirmative reply: recovery executed + re-check + new verdict
related_workflows:
  - hooks/local/post-fusebase-update.sh (recovery script)
  - hooks/local/fusebase-flow-health-check.sh (engine)
  - hooks/local/fusebase-flow-overlays/ (overlay templates + slash command + skill canonical)
hook_dependencies:
  - none
---

# Fusebase Flow — Health Check skill

## Purpose

Diagnostic skill for the operator to verify that the Fusebase Flow overlay on top of agent-managed files (AGENTS.md, CLAUDE.md, `.claude/skills/`, `.claude/agents/`, `.claude/settings.json`, `.claude/hooks/`) is intact, and that the local `.fusebase-flow-source/` clone is in sync with upstream. **Diagnosis is strictly read-only.** When drift is detected and recoverable, the skill **offers** to run the recovery script in-chat with explicit operator confirmation — it never writes without an unambiguous affirmative reply.

The most common breakage cause is `fusebase update` without `--skip-skills`. The current CLI refreshes `AGENTS.md`, `.claude/skills/`, `.claude/agents/`, `.claude/hooks/`, and `.claude/settings.json` from CLI templates. It preserves CLI custom blocks in `AGENTS.md` and skill markdown files, but `.claude/settings.json` and hook helpers still need Flow-side recovery after a full refresh. This skill recognizes those signatures and helps the operator recover.

## When to invoke

The operator asks any of (description-matched, fuzzy):

- "Is Fusebase Flow healthy?"
- "Check Fusebase Flow"
- "Did fusebase update break anything?"
- "Fusebase Flow status"
- "What's broken with Fusebase Flow?"
- "Restore Fusebase Flow"
- "Verify Fusebase Flow"
- "Health check"
- After the operator runs `fusebase update` (full, no `--skip-skills`)
- Before a deploy, if the operator wants to confirm the overlay is intact
- Operator types `/fusebase-health` slash command (Claude Code)

## Do NOT use when

- Operator has not asked. Do not invoke proactively.
- Operator wants the recovery script run unconditionally — surface the diagnosis first, then offer recovery.

## Procedure

1. Read `hooks/local/fusebase-flow-health-check.sh` to confirm the engine is present. If missing, abort with: "Health check engine missing at `hooks/local/fusebase-flow-health-check.sh`. Operator must restore from `.fusebase-flow-source/` (or this project's git history)."

2. Invoke the engine (read-only):

   ```bash
   bash hooks/local/fusebase-flow-health-check.sh
   ```

3. The engine prints a structured report and exits with code:
   - `0` — `HEALTHY` (no drift; upstream in sync)
   - `1` — `DRIFTED` or `FUSEBASE_UPDATE_AFTERMATH` (overlay missing pieces, or upstream newer than local clone)
   - `2` — `BROKEN` (preflight or hook tests genuinely failing — NOT attributable to operator-authored exceptions)
   - `3` — `EXCEPTION_IN_EFFECT` (all drift is attributable to active approval artifacts in `state/approvals/`)

4. Parse the report and surface to the operator in **Mode A** (visual, tabular, brief). Use the engine's output verbatim as the data source — do not paraphrase findings; the engine is authoritative.

5. **Diagnostic phase = read-only. Recovery phase = operator-confirmed in chat.**

   The skill never *unilaterally* runs `bash hooks/local/post-fusebase-update.sh`. After surfacing the diagnosis where recovery is the right answer (verdict `FUSEBASE_UPDATE_AFTERMATH` or `DRIFTED` with a recoverable signature), the skill **explicitly offers** to execute recovery in-chat with a yes/no confirmation:

   > "Recovery would restore [N] drift items: AGENTS.md overlay, settings.json events, Windows shell:true patch.
   >
   > **Run it now?** Reply `yes` (or `run it` / `fix it` / `proceed`) and I'll execute `bash hooks/local/post-fusebase-update.sh` then re-run the health check.
   >
   > Reply anything else (`no`, `wait`, `let me investigate`, ...) and I'll halt — you can run the script yourself when ready."

   On explicit affirmative reply → run recovery, re-run health check, report HEALTHY (or surface remaining drift).

   On any non-affirmative reply (silence, "no", a question, an unrelated request) → halt and respect the operator's call. Do not nag.

   This preserves PO.5 (operator decides) but reduces friction.

6. **For `EXCEPTION_IN_EFFECT` and `BROKEN` verdicts: do NOT offer recovery.** Recovery doesn't fix artifact-attributable drift (recovery doesn't touch `state/approvals/`) and doesn't fix genuine breakage. Surface the diagnosis and let the operator investigate.

## Recovery offer flow (engine v2.2)

When the verdict warrants recovery, present this to the operator after the diagnosis:

```
Run recovery now? It will:
  • Restore AGENTS.md overlay block in a CLI-preserved custom wrapper (if missing)
  • Merge .claude/settings.json lifecycle events (if reduced)
  • Re-apply Windows shell:true patch (if missing)
  • Re-mirror Fusebase Flow skills + sub-agents (no-op if already present)

Reply `yes` / `run it` / `fix it` / `proceed` to execute.
Reply anything else to halt and decide later.
```

**Affirmative replies that authorize execution:** `yes`, `y`, `run`, `run it`, `run the recovery`, `fix it`, `apply`, `proceed`, `go ahead`, `do it`, `restore it`.

When affirmative:
1. Execute `bash hooks/local/post-fusebase-update.sh` via the Bash tool.
2. Capture stdout + exit code.
3. Re-run `bash hooks/local/fusebase-flow-health-check.sh` to verify.
4. Report the new verdict in Mode A.

When NOT affirmative (silence, "no", "wait", a counter-question, an unrelated topic):
- Halt. Respect the operator's call.
- Do not re-prompt unless asked again.
- Print a one-liner: "Halted. Run `bash hooks/local/post-fusebase-update.sh` yourself when ready, or ask me to re-check anytime."

## Legacy refusal phrasing (when operator pushes auto-repair WITHOUT seeing the offer first)

Edge case — operator says "just fix it" / "auto-repair" before any diagnosis has been shown. In that case:

> "Let me run the diagnosis first so we both see what's actually drifted. Running the health check now…"

Then proceed with the normal procedure (diagnose → offer → execute on confirm).

## Knowledge — the canonical `fusebase update` recovery context

When drift signature matches `fusebase update` aftermath (`.claude/settings.json` reduced, with the AGENTS overlay either missing on legacy installs or preserved by the custom-block wrapper on current installs), the operator's situation is:

- They ran `fusebase update` without `--skip-skills` (or another tool that regenerates agent-managed files).
- Latest archive check (2026-05-27): the CLI agent-asset refresh copies or extracts `AGENTS.md`, `.claude/skills/`, `.claude/agents/`, `.claude/hooks/`, and `.claude/settings.json`; `--skip-skills` skips that stage.
- The CLI captures `<!-- CUSTOM:SKILL:BEGIN --> ... <!-- CUSTOM:SKILL:END -->` blocks from `AGENTS.md` and `.claude/skills/**/*.md` before refresh, then restores them. Fusebase Flow therefore appends the AGENTS overlay inside that wrapper.
- `.claude/settings.json` is still replaced by the CLI template and must be merged back with Flow lifecycle events. `.claude/hooks/run-typecheck-features.js` may still need the Windows `shell:true` patch.
- Skills and sub-agents are re-mirrored defensively because the CLI refreshes those directories and may overwrite same-name template files or future behavior may become more destructive.

The recovery is well-defined and bundled into one script:

```
bash hooks/local/post-fusebase-update.sh
```

That script is idempotent and restores six layers:
1. Re-mirrors all Fusebase Flow skills via upstream `mirror-skills.sh`
2. Re-mirrors all Fusebase Flow sub-agents via upstream `mirror-agents.sh`
3. Re-appends the `## Fusebase Flow — workflow lifecycle overlay` block to `AGENTS.md` inside the CLI-preserved custom wrapper (only if missing)
4. Re-appends the `## Fusebase Flow — additional rules (overlay)` block to `CLAUDE.md` (only if missing)
5. Re-merges `.claude/settings.json` to add the missing lifecycle event keys + appends the Fusebase Flow `stop.py` to the Stop chain (only if missing)
6. Re-applies the Windows `shell:true` patch on `.claude/hooks/run-typecheck-features.js` (only if Windows AND patch missing)

Plus the health check skill itself + the `/fusebase-health` slash command get re-mirrored in steps 9 and 10 of the recovery script.

## Avoiding this drift in the first place

The skill should always remind the operator (when it sees drift caused by `fusebase update`):

> "To avoid this in future: prefer `fusebase update --skip-skills` for routine updates. That flag tells the CLI to skip the AGENTS.md / `.claude/*` regeneration. You only need to run a full `fusebase update` (without `--skip-skills`) when you actively want CLI-side skill / hook updates AND are prepared to spend ~5 seconds on the recovery script."

## Output style

Use **Mode A** (visual, tabular, brief). Example response after the engine runs cleanly:

```
Fusebase Flow health check — 2026-05-09 21:30 UTC

Local state:
  ✓ VERSION: 2.2.0
  ✓ AGENTS.md overlay: present
  ✓ CLAUDE.md overlay: present
  ✓ .claude/settings.json: 6/6 events wired (incl. Fusebase Flow stop.py)
  ✓ .claude/skills/: N/N Fusebase Flow skills mirrored
  ✓ .claude/agents/: N/N sub-agents mirrored
  ✓ Windows shell:true patch: applied
  ✓ preflight: clean
  ✓ hook tests: passing

Upstream:
  upstream in sync — local commit = origin/main (2.2.0)

Verdict: HEALTHY — no action needed.
```

Or for `fusebase update` aftermath:

```
Fusebase Flow health check — 2026-05-09 21:35 UTC

Local state:
  ✗ or ✓ AGENTS.md overlay: missing on legacy installs, preserved after custom-wrapper recovery
  ✗ .claude/settings.json: only 1/6 events wired
  ✗ Windows shell:true patch on run-typecheck-features.js: MISSING
  ✓ .claude/skills/: N/N Fusebase Flow skills mirrored
  ✓ .claude/agents/: N/N sub-agents mirrored

Verdict: FUSEBASE_UPDATE_AFTERMATH

Diagnosis: drift signature matches the `fusebase update` aftermath pattern
(.claude/settings.json reduced after agent-asset refresh).

Run recovery now? It will restore the AGENTS.md overlay wrapper if needed,
settings.json events, and the Windows shell:true patch in ~5 seconds.

Reply `yes` / `run it` / `fix it` / `proceed` to execute.
Reply anything else to halt and decide later.

Avoidance for next time:
  fusebase update --skip-skills    ← preserves Fusebase Flow overlay; default-recommended
```

Or for `EXCEPTION_IN_EFFECT` (a deliberate operator-authored security exception is active):

```
Fusebase Flow health check — 2026-05-10 01:21 UTC

Local state:
  ✓ (most checks pass)
  ✗ hook tests: 1 failure(s) attributable to active approval artifact(s); see Active Approvals section

Active approval artifacts (1):
  • protected_path_edit-<slug>-<date>.json: paths=N expires=<ISO8601> scope="..."

Verdict: EXCEPTION_IN_EFFECT

Diagnosis: hook test failure is caused by your active approval artifact, which
authorizes edits the test expects to be denied. This is the protected-paths
exception mechanism working as designed.

Recommended action (NOT recovery):
  • If the protected work is done: delete the listed artifact
  • Or wait until expires_at passes
  • The recovery script will NOT fix this — it doesn't touch state/approvals/
```

## Related skills / workflows

- `hooks/local/post-fusebase-update.sh` — the actual recovery script
- `hooks/local/fusebase-flow-overlays/` — overlay templates + canonical skill + slash command
- `skills/communication/SKILL.md` — Mode A pattern library (always loaded)
- `skills/role-discipline/SKILL.md` — PO.5 authority constraint (this skill respects it)
