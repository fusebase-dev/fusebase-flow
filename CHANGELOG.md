# Changelog

All notable changes to Fusebase Flow Local. Format follows [Keep a Changelog](https://keepachangelog.com/) (lite). This project follows the conventions in `PUBLISHING.md` for cutting releases.

Public release versions ship as annotated git tags on `main`. Per-version detail lives in `docs/release-notes/v<version>.md`.

## [2.4.0] — 2026-05-10

### Added — health-check deferral artifacts (closes BACKLOG B4)

Operator-authored mechanism for marking specific health-check drift items as deliberate-by-design rather than actual drift. When all non-OK checks are covered by an active deferral artifact, the engine returns verdict `EXCEPTION_IN_EFFECT` (exit code 3) instead of `DRIFTED` / `BROKEN`.

#### What ships

- **New artifact category:** `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json`. Lists `deferred_checks` — an array of stable check_ids the engine recognizes. Schema documented at `docs/health-check-deferrals.md`.
- **Engine recognizes 6 defer-able check_ids:**
  - `agents_md_overlay`
  - `claude_md_overlay`
  - `settings_json_lifecycle_events`
  - `claude_skills_mirror_count`
  - `claude_agents_mirror_count`
  - `windows_shell_patch`

  Critical infrastructure checks (preflight, recovery script presence, hook tests, etc.) are deliberately NOT defer-able — see `docs/health-check-deferrals.md` for the rationale.
- **New `LOCAL_DEFERRED` bucket** with `⊘` rendering in the engine output. Each deferred item is tagged with `[check_id=<id>; deferred per <artifact-filename>]` for full traceability.
- **New "Deferred checks" output section** explaining the mechanism when LOCAL_DEFERRED is non-empty.
- **Verdict logic update.** When `LOCAL_DRIFT` is empty AND `LOCAL_DEFERRED` is non-empty → `EXCEPTION_IN_EFFECT`. Genuine breakage (`LOCAL_BROKEN`) still trumps deferrals — operators cannot defer real failures.

#### Why this exists

Real-world driver: `paperclip+hermes-v1` install brief (commit `f73e204`) deliberately deferred two checks per Steps 9 + 10 of its install discipline:
- `.claude/settings.json` lifecycle hooks NOT wired (preserve project's existing quality-check + lint-on-stop hooks)
- Windows `shell:true` patch NOT applied (`.claude/hooks/` listed as protected)

The brief's Step 15 expected `HEALTHY` after install. Pre-v2.4.0 the engine had no concept of "this drift is approved"; it reported `BROKEN` instead. Brief's expectation was correct — the engine was the gap. v2.4.0 closes it.

The mechanism is **explicit and documented**, not a wildcard suppression knob:

- Operator authors a JSON artifact with `approved_by`, `scope`, `expires_at`, `reason`, and `deferred_checks` fields
- Each `deferred_checks` entry must match a canonical check_id (unknown ones are silently ignored — engine prefers explicit taxonomy over wildcard)
- Engine respects `expires_at` — expired artifacts go inactive automatically, drift items go back to `LOCAL_DRIFT`
- Critical infrastructure remains non-deferrable (recovery script presence, overlay templates folder, preflight failures, etc.)

### Fixed — latent v2.2.1 grep-count zero-matches bug

Surfaced during v2.4.0 development: the AGENTS.md / CLAUDE.md overlay-marker count check used `grep -cF ... || echo 0` which produced corrupted `"0\n0"` output when count was 0 (same `set -o pipefail` interaction as v2.3.0's diff-count bug, fixed in v2.3.1). Existed since v2.2.1 but only triggered when a project genuinely lacked overlay markers — uncommon. Surfaced when running v2.4.0 engine in upstream's own working tree (whose AGENTS.md doesn't have the operator-installed overlay block).

**Fix:** replace `|| echo 0` with `|| true` in both AGENTS.md and CLAUDE.md count lines. Same pattern as v2.3.1's fix.

### Changed

- **`hooks/local/fusebase-flow-health-check.sh`** — engine grew ~110 lines net for: deferral artifact loading in Section 0, `record_drift` helper function with check_id lookup, `LOCAL_DEFERRED` bucket, refactored 6 defer-able check sites, verdict logic update, "Deferred checks" output section, recommendations update for the deferred-only case. Plus the latent grep-count bug fix.
- **`README.md`** — added "Deferral artifacts (v2.4.0+)" subsection inside the Health check section. Verdict table updated to mention both v2 and v2.4.0+ artifact types.
- **`docs/health-check-deferrals.md` (new)** — full operator reference for the new mechanism. Schema, taxonomy, examples (including the canonical paperclip+hermes-v1 case), workflow for adding/removing deferrals, limitations.
- **`VERSION`** `2.3.2` → `2.4.0`.

### Validation at release

- preflight: 0 errors / 0 warnings
- hook tests: 14/14 PASS
- skill mirror: 20 files, 0 drift
- agent mirror: 4 files, 0 drift
- bash syntax check on engine: clean
- B4 smoke test in `test project 2`:
  - Pre-deferral baseline (Windows patch reverted): verdict `DRIFTED`, exit 1 ✓
  - Post-deferral artifact (`health_check_deferral-test-windows-patch-20260510.json` listing `windows_shell_patch`): verdict `EXCEPTION_IN_EFFECT`, exit 3, item shown with ⊘ symbol + `[check_id=windows_shell_patch; deferred per <artifact>]` ✓
  - Cleanup (delete artifact, restore patch): verdict back to `HEALTHY`, exit 0 ✓
- Engine in upstream's own working tree (where AGENTS.md genuinely lacks overlay): now reports `DRIFTED` correctly with proper count display (was `BROKEN` with `"0\n0"` corruption pre-v2.4.0)

### Real-world impact

**`paperclip+hermes-v1`** can now author a deferral artifact matching its install brief's Steps 9 + 10:

```json
{
  "approved_by": "pavel.sher@thefusebase.com",
  "scope": "Lifecycle hooks + Windows patch deferred per install brief 2026-05-08",
  "expires_at": "2026-08-10T00:00:00Z",
  "reason": "Project preserves existing hooks per Step 9; .claude/hooks/ protected per Step 10",
  "deferred_checks": ["settings_json_lifecycle_events", "windows_shell_patch"]
}
```

After filing this artifact, the project's health check returns `EXCEPTION_IN_EFFECT` (exit 3) instead of `BROKEN` (exit 2). The brief's Step 15 expected behavior is now achievable.

### Notes for upgraders (v2.3.2 → v2.4.0)

- **Pure additive feature.** No content changes; no migration needed for projects that don't author deferral artifacts.
- Upgrade path: refresh `.fusebase-flow-source/`, run `bash hooks/local/upgrade-engine.sh` — engine self-update picks up v2.4.0 logic.
- Existing `protected_path_edit-*.json` artifacts continue to work unchanged.
- New documentation: read `docs/health-check-deferrals.md` if you have install briefs that deliberately omit parts of the canonical setup.

### What's next

Backlog item **B2** (refresh `docs/fusebase-health/` for v2.3.0 + v2.3.1 + v2.3.2 + v2.4.0) is the docs-sweep follow-up. No release needed; gitignored operator dev notes.

---

## [2.3.2] — 2026-05-10

### Fixed — two engine + recovery edge cases

Bundled patch fixing two cosmetic / classification issues surfaced during real-world use of v2.2.x → v2.3.x.

#### 1. `upgrade-engine.sh` self-update count off-by-one (closes BACKLOG B1)

When `upgrade-engine.sh` upgrades itself (i.e. `hooks/local/upgrade-engine.sh` differs between local and `.fusebase-flow-source/`), the apply-summary previously undercounted by 1:

```
[upgrade-engine] Applied (1):    ← undercount; should be 2
  ✓ VERSION (2.3.0 -> 2.3.1)
```

Root cause: the script overwrites itself via `cp` mid-execution. The cp succeeds and the file on disk is updated correctly, but the running bash process (executing from memory) loses the `APPLIED+=("$f")` accumulation for the self-target on Windows + Git Bash.

**Fix:** restructured to detect + handle `upgrade-engine.sh` self-update OUTSIDE the main `FILES_TO_SYNC` loop. Self-update detection happens in a dedicated pre-loop block (`SELF_NEW`/`SELF_CHANGED` flags); apply happens before the regular loop. APPLIED tracking is now reliable. Apply-summary message also explicitly notes "new logic active on next run" since the running script is the OLD version.

Also extracted the diff-line counting into a `count_diff_lines` helper for consistency.

#### 2. Engine reclassifies missing upstream clone from BROKEN to OK (closes BACKLOG B3)

Pre-v2.3.2 engine code:

```bash
if [ "$EXPECTED_AGENT_COUNT" -eq 0 ]; then
  LOCAL_BROKEN+=(".claude/agents/: cannot determine expected agent set ...")
```

This forced verdict `BROKEN` (exit 2) for any project that intentionally cleaned up `.fusebase-flow-source/` after install (which is the documented norm per `install-fusebase-cli-project.md` and `install-existing-project.md`).

Surfaced empirically during install in `paperclip+hermes-v1` (commit `f73e204`) — the install brief explicitly cleaned up the clone in Step 16, then expected `HEALTHY` in Step 15. With the v2.3.1 engine, the verdict was `BROKEN` instead of `HEALTHY` — a wrong prediction caused by this over-classification.

**Fix:** reclassify `EXPECTED_X_COUNT == 0` from `LOCAL_BROKEN` to `LOCAL_OK` with informational language: `count not verified (no .fusebase-flow-source/ clone available; re-clone to enable upstream comparison)`. Verdict no longer flips to `BROKEN` on this state alone.

The check is informational — the engine still falls back to local `skills/` / `agents/` directories for the actual mirror count (when those exist locally). The reclassification only affects projects that lack BOTH the upstream clone AND root-level `skills/`/`agents/` — typically: post-install-cleanup state without root-level canonical content (rare, but happens).

### Changed

- **`hooks/local/upgrade-engine.sh`** — restructured self-update detection + apply (~30 lines net change). Inline comments explain the on-Windows-self-overwrite fragility for future maintainers.
- **`hooks/local/fusebase-flow-health-check.sh`** — two `LOCAL_BROKEN` calls reclassified to `LOCAL_OK` with informational text (~6 lines net change). Inline comments cite v2.3.2 + reference to install-cleanup discipline.
- **`VERSION`** `2.3.1` → `2.3.2`.

### Validation at release

- preflight: 0 errors / 0 warnings
- hook tests: 14/14 PASS
- skill mirror: 20 files (10 × 2), 0 drift
- agent mirror: 4 files, 0 drift
- bash syntax check on both modified scripts: clean
- B1 smoke test: induced self+other diff in `test project 2`; (will validate after operator pulls v2.3.2)
- B3 smoke test: in `test project 2`, temporarily renamed `.fusebase-flow-source/` away; engine reported `HEALTHY` exit 0 (was `BROKEN` exit 2 pre-fix). Local fallback worked.

### Notes for upgraders (v2.3.1 → v2.3.2)

- Pure engine + script behavior fixes. No content changes; no migration needed.
- Existing projects pulling v2.3.2 will see slightly different output:
  - `upgrade-engine.sh` apply summary now correctly counts self-updates (no off-by-one)
  - Health check no longer reports `BROKEN` purely because `.fusebase-flow-source/` was cleaned up post-install
- Recommended upgrade: refresh `.fusebase-flow-source/`, run `bash hooks/local/upgrade-engine.sh` to pick up both fixes in one pass.

### Real-world impact

Projects affected by these fixes:

- **`paperclip+hermes-v1`** (currently on v2.2.1): once they upgrade to v2.3.2, the BROKEN verdict caused by missing-clone classification will improve to either `DRIFTED` (if other deferred items remain) or `HEALTHY`. The deferred-decision items (settings.json events + Windows patch) still surface as drift — those need backlog item B4 (deferred-decision artifacts) to be marked as approved.

---

## [2.3.1] — 2026-05-10

### Fixed — cosmetic diff-count display in `upgrade-engine.sh`

When `set -o pipefail` is active (it is, in `upgrade-engine.sh`), the line:

```bash
diff_count=$(diff "$src" "$f" 2>/dev/null | grep -cE "^[<>]" || echo 0)
```

produced corrupted output for any file with line differences. `diff` exits non-zero when files differ → pipefail makes the whole pipe exit non-zero → `|| echo 0` fires AND appends "0" to stdout → `diff_count` captures both the real count AND a literal newline + "0".

Render pre-v2.3.1:

```
  • hooks/local/fusebase-flow-health-check.sh (200
0 line diffs)
```

Render in v2.3.1:

```
  • hooks/local/fusebase-flow-health-check.sh (200 line diffs)
```

### Changed

- **`hooks/local/upgrade-engine.sh`** — replace `|| echo 0` with `|| true`. `grep -c` always writes the count to stdout (even when 0), so `|| true` swallows the non-zero exit without polluting stdout. Added inline comment explaining the pipefail interaction.
- **`VERSION`** `2.3.0` → `2.3.1`.

### Validation at release

- preflight: 0 errors / 0 warnings
- hook tests: 14/14 PASS
- skill mirror: 20 files, 0 drift
- Unit test (set -o pipefail + 250-line diff):
  - Pre-fix: captured `"500\n0"` (corrupted)
  - Post-fix: captured `"500"` (clean)
  - Identical files (edge case): captured `"0"` (correct, no false count)
- `bash -n hooks/local/upgrade-engine.sh`: clean

### Notes for upgraders (v2.3.0 → v2.3.1)

- Cosmetic-only patch. No behavior changes; functional logic was already correct.
- Re-running `bash hooks/local/upgrade-engine.sh` after pulling v2.3.1 will pick up the fix on next run (the script syncs itself).

### Discovered during validation

This bug was caught during the v2.3.0 end-to-end smoke test in a downstream project — the upgrade succeeded, but the dry-run preview rendered with a line break in the diff count. v2.3.1 ships within hours of v2.3.0, demonstrating the value of always validating new releases against a real downstream upgrade scenario before declaring done.

---

## [2.3.0] — 2026-05-10

### Added — `hooks/local/upgrade-engine.sh` (operator-explicit engine upgrade)

A new operator-maintained script that closes the loop on engine upgrades. When upstream ships a new health-check engine version (e.g. v2.2.1's duplicate-marker detection), `mirror-skills.sh` and `mirror-agents.sh` only sync `skills/` and `agents/` from the local `.fusebase-flow-source/` clone — they deliberately do NOT touch `hooks/local/*.sh` because those are operator-maintained scripts that may carry local customization.

`upgrade-engine.sh` is the explicit opt-in path for operators who DO want to adopt new upstream engine versions:

- Diffs `hooks/local/fusebase-flow-health-check.sh`, `hooks/local/post-fusebase-update.sh`, and `hooks/local/upgrade-engine.sh` (itself) against `.fusebase-flow-source/hooks/local/`
- Bumps the project's `VERSION` file to match upstream
- Backs up each replaced file with a `.pre-upgrade-<timestamp>` suffix
- Reports diff stats, prompts for confirmation (or accepts `--auto-yes` / `--dry-run`)

### Why this matters

Pre-v2.3.0, an operator who pulled a new upstream version into `.fusebase-flow-source/` had to manually copy the engine + recovery scripts file-by-file. Easy to forget; easy to leave the project on an older engine while thinking it was upgraded. v2.3.0 makes the upgrade a single command:

```bash
cd .fusebase-flow-source && git pull origin main && cd ..
bash hooks/local/upgrade-engine.sh
```

### Usage modes

| Mode | Command | Behavior |
|---|---|---|
| Interactive (default) | `bash hooks/local/upgrade-engine.sh` | Prints diff stats, prompts `y/N` |
| Non-interactive | `bash hooks/local/upgrade-engine.sh --auto-yes` | Applies without prompt |
| Preview only | `bash hooks/local/upgrade-engine.sh --dry-run` | Shows what would change; no writes |

### Files synced

- `hooks/local/upgrade-engine.sh` (itself — so future runs adopt new versions of this script seamlessly)
- `hooks/local/fusebase-flow-health-check.sh`
- `hooks/local/post-fusebase-update.sh`
- `VERSION`

### Files explicitly NOT touched

- `hooks/local/fusebase-flow-overlays/` (operator-customizable overlay templates with project-specific values)
- `skills/`, `agents/` (canonical content; use `mirror-skills.sh` / `mirror-agents.sh`)
- `AGENTS.md`, `CLAUDE.md`, `.claude/*` (managed via `post-fusebase-update.sh`)

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files, 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS
- `bash -n` syntax check on new script: OK

### Notes for upgraders (v2.2.x → v2.3.0)

- **Bootstrap step (one-time):** to get the v2.3.0 `upgrade-engine.sh` script into a project that's currently on v2.2.x, manually copy it once:
  ```bash
  cd .fusebase-flow-source && git pull origin main && cd ..
  cp .fusebase-flow-source/hooks/local/upgrade-engine.sh hooks/local/upgrade-engine.sh
  chmod +x hooks/local/upgrade-engine.sh
  ```
  After that, future engine upgrades (v2.3.1, v2.4.0, ...) are seamless via `bash hooks/local/upgrade-engine.sh`.
- **Recovery script unchanged.** v2.3.0 is purely additive.

---

## [2.2.1] — 2026-05-10

### Added — duplicate-overlay-block detection in health check engine

The health-check engine now counts occurrences of the AGENTS.md and CLAUDE.md heading markers (instead of just checking presence) and flags `DUPLICATE` if more than one copy is found.

#### Why

When upgrading across major heading-marker renames (e.g. v2.1.x → v2.2.0 dropped the "V2" qualifier), an operator who runs `bash hooks/local/post-fusebase-update.sh` without first manually removing the old block ends up with **two overlay blocks** in AGENTS.md (the old "V2" one + a new appended block matching the v2.2.0 heading). Recovery's `grep -qF` for the new heading finds it and skips, but recovery's first run already appended a duplicate.

Pre-v2.2.1, the engine reported `AGENTS.md overlay block: present` — incorrectly green-lighting a state that needs cleanup. v2.2.1 catches this.

#### Changed

- **`hooks/local/fusebase-flow-health-check.sh`** — AGENTS.md and CLAUDE.md overlay-marker checks now use `grep -cF` (count) instead of `grep -qF` (presence). Three states:
  - `0` → `MISSING` (LOCAL_DRIFT — same as before)
  - `1` → `present` (LOCAL_OK — same as before)
  - `>1` → `DUPLICATE (N copies present — likely from a heading-marker rename without first removing the old block; remove the older block manually)` (LOCAL_DRIFT — new state)
- **`VERSION`** `2.2.0` → `2.2.1`.

#### Drift signature behavior

Duplicate state classifies as `DRIFTED` (not `FUSEBASE_UPDATE_AFTERMATH`). The canonical `FUSEBASE_UPDATE_AFTERMATH` signature requires `AGENTS_MISSING` AND `SETTINGS_REDUCED` — duplicates have neither, so they fall through to `DRIFTED` with the descriptive LOCAL_DRIFT message guiding the operator to remove the older block manually.

The skill does not offer auto-recovery for this verdict (recovery wouldn't help — recovery script itself is what could have created the duplicate during a heading rename). Operator removes the old block by hand, then re-runs the health check.

#### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files (10 × 2 mirrors), 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS
- Smoke test: induced 2 copies of the AGENTS.md heading marker in a downstream project; engine correctly reported `DUPLICATE (2 copies present...)`, verdict `DRIFTED`, exit 1
- Single-copy and missing-marker behavior unchanged (regression-free)

#### Notes for upgraders (v2.2.0 → v2.2.1)

- **No content edits required.** Patch only changes the engine; existing AGENTS.md / CLAUDE.md / settings.json content remains valid.
- Pulling v2.2.1 (via re-clone or re-running `mirror-skills.sh`) is sufficient. Recovery script is unchanged.
- If your project currently has a duplicate marker block (carried over from v2.1.x → v2.2.0 without a manual edit), v2.2.1's health check will start reporting it — fix it once by deleting the older block, then re-run health check.

---

## [2.2.0] — 2026-05-10

### Added — Health check & recovery (major feature)

A built-in **health check skill** + **recovery script** that diagnose and repair Fusebase Flow overlay drift. The most common drift cause is `fusebase update` (Fusebase CLI) regenerating `AGENTS.md` / `.claude/settings.json` / `.claude/hooks/` from CLI templates and evicting the Fusebase Flow overlay. The new system handles this end-to-end.

#### What ships

- **`skills/fusebase-flow-health-check/SKILL.md`** (canonical skill, description-matched) plus mirrors at `.claude/skills/fusebase-flow-health-check/SKILL.md` and `.agents/skills/fusebase-flow-health-check/SKILL.md`.
- **`hooks/local/fusebase-flow-health-check.sh`** — read-only diagnostic engine. 12 inventory checks + active-approval-artifact awareness + upstream-comparison via `.fusebase-flow-source/` clone. Exit codes: 0 HEALTHY, 1 DRIFTED / FUSEBASE_UPDATE_AFTERMATH, 2 BROKEN, 3 EXCEPTION_IN_EFFECT.
- **`hooks/local/post-fusebase-update.sh`** — idempotent recovery script. 10 steps restore: skills + sub-agents mirrors, AGENTS.md + CLAUDE.md overlay blocks, `.claude/settings.json` lifecycle events, Windows shell:true patch on the typecheck hook (CVE-2024-27980 mitigation), the health-check skill mirror, and the `/fusebase-health` slash command.
- **`hooks/local/fusebase-flow-overlays/`** — overlay templates (the canonical content the recovery script appends/restores):
  - `agents-md-overlay.md` — `## Fusebase Flow — workflow lifecycle overlay` block for AGENTS.md
  - `claude-md-overlay.md` — `## Fusebase Flow — additional rules (overlay)` block for CLAUDE.md
  - `settings-json-merge.py` — Python merger (no `jq` dependency; auto-discovers events from upstream's `.claude/settings.json.example`)
  - `skills/fusebase-flow-health-check/SKILL.md` — skill template
  - `commands/fusebase-health.md` — slash command template
- **`.claude/commands/fusebase-health.md`** — `/fusebase-health` slash command (Claude Code).

#### Skill behavior — diagnose then offer

The skill is **read-only during diagnosis**. When drift is detected and recoverable, the skill **offers** recovery in chat with a yes/no confirmation:

```
Run recovery now? It will:
  • Restore AGENTS.md overlay block
  • Merge .claude/settings.json lifecycle events
  • Re-apply Windows shell:true patch
  • Re-mirror Fusebase Flow skills + sub-agents

Reply `yes` / `run it` / `fix it` / `proceed` to execute.
Reply anything else to halt and decide later.
```

On affirmative reply → recovery executes + re-check + report new verdict. On any non-affirmative reply (silence, `no`, a question) → halt. Operator authority preserved (PO.5 from `role-discipline` skill); friction reduced — no terminal context-switch needed for most cases. **EXCEPTION_IN_EFFECT** (drift attributable to active approval artifacts in `state/approvals/`) and **BROKEN** verdicts do NOT trigger the recovery offer (recovery wouldn't fix them).

#### Auto-discovery for upstream upgrades

The engine and the merger auto-discover canonical sets at runtime from `.fusebase-flow-source/`:

- **Skill names** from `skills/*/`
- **Agent names** from `agents/*/`
- **Lifecycle event names** from `.claude/settings.json.example`
- **Hook handler commands + matchers** from the same example file

Patch / minor upstream releases (new skill / agent / event) require **zero maintenance** to this system. Only major-version semantic changes (heading marker rename) require manual edits.

#### Heading marker convention

This release standardizes on `## Fusebase Flow — workflow lifecycle overlay` (AGENTS.md) and `## Fusebase Flow — additional rules (overlay)` (CLAUDE.md). The previous internal "V2" qualifier was dropped per the standard "Fusebase Flow" naming.

### Changed

- **`VERSION`** `2.1.1` → `2.2.0`.
- **`README.md`** — added "Health check & recovery (v2.2+)" section with quick reference, verdicts table, recovery flow, auto-discovery posture, and file inventory.
- **`docs/install-fusebase-cli-project.md`** — heading marker text updated to `## Fusebase Flow — workflow lifecycle overlay` (was `# Fusebase Flow Local — workflow discipline overlay`); recovery section added.
- **`docs/install-existing-project.md`** — health check + recovery section added.

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files (10 × 2 mirrors), 0 drift (after regen)
- agent mirror: 4 files, 0 drift (after regen)
- hook tests: 14/14 PASS
- Health check end-to-end test: HEALTHY → fusebase update → FUSEBASE_UPDATE_AFTERMATH → recovery offer → affirmative → recovery executed → HEALTHY (exit 0)
- Idempotency: 2nd recovery run reports "already in place" for all restorable items, byte-identical no-op on settings.json merge

### Notes for upgraders (v2.1.x → v2.2.0)

- **Heading marker change:** if you have an existing v2.1.x project with `## Fusebase Flow V2 — workflow lifecycle overlay` in your AGENTS.md, edit it to drop the "V2 ": `## Fusebase Flow — workflow lifecycle overlay`. Same for CLAUDE.md (`## Fusebase Flow V2 — additional rules (overlay)` → `## Fusebase Flow — additional rules (overlay)`). The recovery script and engine grep for the new heading; without this edit they'll think the marker is missing and append a duplicate block.
- **`stop.py` statusMessage:** the merger now writes `"Fusebase Flow stop hook…"` (was `"Fusebase Flow V2 stop hook…"`). Existing settings.json entries with the old text continue to work but will not match the merger's substring check on the next merge — re-run `bash hooks/local/post-fusebase-update.sh` to pick up the updated text.
- **No skill / agent rename:** existing skills and sub-agents keep their names. The new `fusebase-flow-health-check` skill is additive.
- **Fresh installs:** `bash install.sh` works as before; new health check files are picked up automatically by the existing mirror-skills step.

---

## [2.1.1] — 2026-05-09

### Added — defense-in-depth refinements to the v2.1.0 sub-agent design

Two post-release hardening changes from independent v2.1.0 evaluation feedback. Both move guarantees from prompt-level (LLM judgment) to structural (tool / control flow).

- **`hooks/local/po-investigate.sh` (new)** — allowlisted, read-only investigation wrapper for the Product Owner sub-agent. Allowed subcommands: `status`, `diff`, `log`, `show`, `blame`, `ls`, `cat`, `head`, `tail`, `find`. Anything else exits non-zero. The PO sub-agent's tool surface still includes Bash, but its system prompt now mandates **wrapper-only** Bash usage and explicitly denies direct calls to `git`, `npm`, `node`, `python`, `cat`, `bash -c`, etc. Mutating commands (`git stash`, `git commit`, `npm install`, `node -e "fs.writeFileSync(...)"`, etc.) are not reachable through the wrapper because they aren't allowlisted subcommands.

- **`DP.6` deploy-time operator confirm** — new Deploy phase don't-list rule. Before the deploy command runs, the agent must obtain the operator typing the literal phrase `APPROVE-DEPLOY-NOW`. Anything else (`yes`, `y`, `ok`, partial matches) aborts the deploy. Mirrors the existing `APPEND-ONLY` pattern in `install.sh`. Adds ~5 seconds of structural friction to keep a human at the keyboard for production cutover moments. Codified in `skills/role-discipline/SKILL.md` (Deploy phase section), `agents/ai-developer/AGENT.md` (Deploy phase ownership table + don't-list + stop conditions), and `workflows/greenlight-deploy.md` (procedure step 4).

### Changed

- **`agents/product-owner/AGENT.md`** — Bash row in tool-surface table now mandates the `po-investigate.sh` wrapper. Direct Bash calls added to the Denied table.
- **`agents/ai-developer/AGENT.md`** — Deploy phase ownership table includes the new DP.6 step between DP.2 (worker-undisturbed re-check) and the deploy command run; don't-list expanded from `DP.1..DP.5` to `DP.1..DP.6`; stop-conditions table includes the abort-on-non-matching-phrase row.
- **`skills/role-discipline/SKILL.md`** — Deploy phase don't-list adds DP.6 with refusal phrasing for the "just deploy, I'm watching" violation request, plus recovery note.
- **`workflows/greenlight-deploy.md`** — procedure list inserts step 4 (operator confirm); subsequent steps renumbered 5–10. Self-attestation phrase updated `DP.1..DP.5` → `DP.1..DP.6`.
- **`VERSION`** `2.1.0` → `2.1.1`.
- **Mirrors regenerated** by `mirror-skills.sh` and `mirror-agents.sh`.

### Why these changed

Both refinements address ergonomic-vs-structural tradeoffs identified during external evaluation of v2.1.0. The PO wrapper closes a fuzzy "read-only Bash" boundary that the prompt-level instruction couldn't fully police (`git stash` mutates; `node -e "..."` is one keystroke from a write). The DP.6 confirm closes the "operator distracted at moment of production cutover" failure mode that purely automated deploys can hit. Both are minimal-surface additions that preserve v2.1.0's architectural shape (two sub-agents, role-discipline-driven, handoff-on-disk).

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 18 files, 0 drift (after regen)
- agent mirror: 4 files, 0 drift (after regen)
- hook tests: 14/14 PASS
- `po-investigate.sh`: syntax OK; smoke-tested allowlisted (`status`, `log`) and rejected (`nonsense` → exit 2) paths

### Notes for upgraders

- **PO sub-agent users:** if you've started a session before this upgrade, restart it so the v2.1.1 prompt loads (the wrapper-only Bash rule is in the system prompt; cached prompts won't have it).
- **Deploy automation:** the DP.6 pause adds a single round-trip to every Deploy phase invocation. For automated CI/CD that needs no-pause deploys, that path is an Operator-attested action (the operator runs deploys directly), not a Deploy-phase sub-agent invocation. The DP.6 rule applies only to sub-agent / role-attested deploys.

---

## [2.1.0] — 2026-05-09

### Added — Sub-agents (major feature)

- **Two role-shaped sub-agents** that cover the full eight-phase ticket lifecycle:
  - **Product Owner** (`agents/product-owner/AGENT.md`) — drives Specify, Clarify, Plan, Decisions, Tasks, draft-verification-gate, post-implement code-review and security-permissions-review, deploy-handoff drafting, and the spec DRAFT→DONE flip. Absorbs Architect responsibilities inline when escalation triggers fire (>10 files, cross-cutting refactor, platform blocker, blocked migration). Never edits application code.
  - **AI Developer** (`agents/ai-developer/AGENT.md`) — executes Implementer or Deploy-phase handoffs. Self-attests by handoff filename: `*-implement.md` → Implementer (runs the T-chain, stops at the gate); `*-deploy.md` → Deploy phase (runs deploy command, captures hash, runs probes). Never drafts specs; STOPS and asks if no handoff is provided.
- **Provider parity** via canonical → mirror pattern (parallel to skills):
  - `agents/<name>/AGENT.md` (canonical)
  - `.claude/agents/<name>.md` (Claude Code — auto-discovered)
  - `.codex/agents/<name>.md` (Codex — operator-referenced in fresh session)
- **`hooks/local/mirror-agents.sh`** regenerates both provider mirrors from canonical; parallel to `mirror-skills.sh`.
- **`audit/agent-mirror-manifest.txt`** sha256 manifest for drift detection.
- **`hooks/local/preflight.sh`** new step 5b verifies agent mirror parity (warn-level on drift).
- **`install.sh`** new step 4 (4/4) offers to mirror agents alongside skills. Prompts renumbered 1/3..3/3 → 1/4..4/4.
- **`README.md`** — sub-agents row added to the enforcement table; tree shows `agents/`, `.claude/agents/`, `.codex/agents/`, `audit/agent-mirror-manifest.txt`; how-to-use section added under "Filing your first ticket".

### Changed

- **Self-attestation phrase** updated from `Fusebase Flow v0.1` to `Fusebase Flow v2.1` across all canonical files: `FLOW_RULES.md`, `CLAUDE.md`, `AGENTS.md` (where present), `GEMINI.md`, `.github/copilot-instructions.md`, `agents/*/AGENT.md`, `workflows/architect-escalation.md`, `workflows/greenlight-deploy.md`, `workflows/greenlight-implement.md`, `workflows/session-initiation.md`. Mirrors regenerated automatically.
- **Skill frontmatter** `fusebase_flow_version: 0.1` → `fusebase_flow_version: 2.1` across all 9 canonical skills + `templates/skill-template.md`. Mirrors regenerated.
- **`VERSION`** `0.1.2` → `2.1.0`.

### Coverage walkthrough (verified at release)

| Phase / cross-cut | Sub-agent | Verified |
|---|---|---|
| 1 Specify | Product Owner | ✓ |
| 2 Clarify | Product Owner | ✓ |
| 3 Plan | Product Owner | ✓ |
| 4 Decisions (recommend; operator locks) | Product Owner | ✓ |
| 5 Tasks | Product Owner | ✓ |
| 6a Draft verification gate | Product Owner | ✓ |
| 6b Run gate | AI Developer | ✓ |
| 6c Code review + security review | Product Owner | ✓ |
| 7 Implement | AI Developer (Implementer attestation) | ✓ |
| 8a Draft deploy handoff | Product Owner | ✓ |
| 8b Run deploy command | AI Developer (Deploy-phase attestation) | ✓ |
| 8c Spec DRAFT→DONE flip | Product Owner | ✓ |
| Architect escalation | Product Owner inline (AR.1..AR.6 additive) | ✓ |
| Live-user verification | AI Developer | ✓ |
| Knowledge curation | Product Owner | ✓ |
| Violation recovery | both (own role section) | ✓ |

### Validation at release

- preflight: 0 errors / 0 warnings (now includes step 5b agent-mirror check)
- skill mirror: 18 files, 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS

### Notes for upgraders

- Previous self-attestation phrases referencing `Fusebase Flow v0.1` are now `Fusebase Flow v2.1`. Sessions that run from cached prompts may need to be restarted to load the new phrasing.
- Sub-agents are **opt-in** — the framework remains fully usable via the existing skill-and-workflow flow without invoking sub-agents at all. Sub-agents are an additional entry point, not a replacement.
- Codex does not auto-discover `.codex/agents/` — operators reference the file in their first message of a fresh session (e.g., `Read .codex/agents/product-owner.md and operate as Product Owner`).

---

## [0.1.2] — 2026-05-09

### Added

- Sub-agents foundation (commit `937f658`) — superseded by the `2.1.0` release on the same day; effectively folded into v2.1.0.

## [0.1.1] — 2026-05-09

### Added

- `skills/role-discipline` (mandatory 8th canonical skill — actually 9th) with per-role don't-lists and exact refusal phrasing for Product Owner, Implementer, Architect (escalation), Deploy phase, and Operator.
- `workflows/live-user-verification.md` — 8-step procedure with verbatim consent flow, cookie sanity test, masked smoke output, end-of-work cleanup phrase that the stop hook checks for.
- `workflows/violation-recovery.md` — per-FR rule recovery procedures plus per-hook-event recovery.
- `docs/architecture-overview.md`, `docs/operator-discipline.md`, `docs/tradeoffs.md`, `docs/constitution.md`.
- `hooks/handlers/stop.py` — `cleanup_marker_present` and `live_user_verification_used` signals.
- `hooks/shared/secret_scanner.py` — `pattern_overrides` precedence (per-pattern escalation in tool context).
- `policies/secret-patterns.yml` — `cookie_session_value` pattern now blocks (not warns) in `pre_tool_use` and `git_pre_commit` contexts.
- 3 new deterministic hook test fixtures (12, 13, 14) covering cookie escalation and cleanup-marker gating.

### Changed

- Self-attestation phrase appended `I will apply the role-discipline skill section for {role}.`
- Implementer / Deploy / Architect role-specific self-attestation phrases now reference numbered sections (`IM.1..IM.10`, `DP.1..DP.5`, `AR.1..AR.6`).
- `skills/requirements-specification`: skip-clarify gate, Phase 1/2 split, abort-ticket failure case, scope-disagreement escalation.
- `skills/validation-and-qa`: 3-question empirical-coverage test for ACs; Sub-mode D test-data hygiene cleanup.
- `templates/smoke-test-playwright.md`: when-to-skip table, one-time setup block, CDP-vs-Playwright trade-offs.
- Various count updates triggered by adding the role-discipline skill (skills 8 → 9; mirrors 16 → 18; workflows 10 → 12; fixtures 11 → 14).

## [0.1.0] — Initial release

- Fusebase Flow Local v0.1 — repo-local workflow framework for AI coding agents and IDEs.
- 8 canonical skills, 10 workflows, 6 policies, 13 templates.
- Hook handlers for `session_start`, `user_prompt_submit`, `pre_tool_use`, `post_tool_use`, `stop`, `pre_compact`.
- Provider mirrors for Anthropic Claude Code (`.claude/skills/`, `.claude/settings.json.example`) and OpenAI / ChatGPT Codex (`.agents/skills/`, `.codex/{config.toml,hooks.json}.example`).
- Cursor rules (`.cursor/rules/*.mdc`).
- GitHub Copilot / VS Code instructions (`.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`).
- 11 deterministic hook test fixtures.
- CI workflow `.github/workflows/fusebase-flow-verify.yml`.
- Clean-room license attestation (`docs/clean-room.md`).
- MIT license.
