# Fusebase Flow Health — deferral artifacts

**Available since:** Fusebase Flow v2.4.0

A **deferral artifact** is an operator-authorized (decided in chat), **agent-authored** JSON file at `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json` that tells the health-check engine: *"this drift is by design — don't classify it as DRIFTED or BROKEN."* The operator decides to defer in chat; the agent writes the file — the operator runs no command.

When all non-OK items are covered by an active deferral artifact, the engine returns verdict `EXCEPTION_IN_EFFECT` (exit code 3) instead of `DRIFTED` (exit 1) or `BROKEN` (exit 2). The drift items show with the `⊘` symbol in the report and are explicitly tagged with the artifact filename for traceability.

> **Exit code 4 (`PARTIAL_UNVERIFIED`, v3.24.0+) is distinct from a deferral.** A deferral (exit 3) says "this drift is by design"; `PARTIAL_UNVERIFIED` (exit 4) says "a critical check could not run (timed out / skipped / no timeout binary), so the verdict is incomplete." Deferrals do not suppress exit 4 — an unverified critical is not drift to defer, it's a check to re-run.

This is the canonical mechanism for situations where an install brief or operator deliberately chose **not** to wire a part of the canonical Fusebase Flow setup — for example:

- A project with existing `.claude/settings.json` lifecycle hooks that the operator wants to preserve, deferring Fusebase Flow's hook wiring
- A project where `.claude/hooks/` is treated as protected per the install brief, deferring the Windows `shell:true` patch
- A project that mirrors a subset of Fusebase Flow flow-skills/agents into provider folders, deferring full mirror coverage

## When to use a deferral artifact

| Situation | Use deferral? |
|---|:---:|
| Install brief deliberately omits a part of canonical setup | ✅ yes — file an artifact |
| You forgot to run the recovery script and got drift | ❌ no — the agent runs the recovery script (`bash hooks/local/post-fusebase-update.sh`) on your go-ahead |
| `fusebase update` reverted parts of the overlay | ❌ no — the agent runs the recovery script on your go-ahead |
| Hook tests are failing on a non-`protected_path_edit` test | ❌ no — those are real failures; investigate them |
| You want to silence health-check noise without thinking about why | ❌ no — that defeats the safety purpose; understand the drift first |

The artifact is for **deliberate**, **documented** deferrals. It is not a "suppress all warnings" knob.

## Artifact file format

**Location:** `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json`

The filename pattern is required (`health_check_deferral-` prefix). The slug + date are operator-chosen to make the artifact discoverable and grep-able later.

**Content:**

```json
{
  "approved_by": "<operator-email-or-name>",
  "scope": "<short description; ASCII-friendly; first 80 chars surfaced in report>",
  "expires_at": "<ISO 8601 UTC timestamp>",
  "reason": "<one-liner explaining why this is deferred>",
  "deferred_checks": [
    "<check_id_1>",
    "<check_id_2>"
  ]
}
```

**Required fields:**

| Field | Type | Notes |
|---|---|---|
| `approved_by` | string | Operator who authorized. Convention: email. |
| `scope` | string | Short description; surfaced in the engine's "Active approval artifacts" output (truncated to 80 chars + ASCII). |
| `expires_at` | string (ISO 8601) | When the deferral lapses. Engine treats expired artifacts as inactive — drift items go back to LOCAL_DRIFT. |
| `reason` | string | Free-form explanation. Not surfaced in the engine output but readable by operators or future agents. |
| `deferred_checks` | array of strings | List of check_ids (see canonical taxonomy below). Engine reclassifies matching drift items to LOCAL_DEFERRED. |

## Canonical check_id taxonomy

The engine recognizes these check_ids in the `deferred_checks` array:

| `check_id` | What it defers |
|---|---|
| `agents_md_overlay` | AGENTS.md overlay block missing (the `## FuseBase Flow — workflow lifecycle overlay` heading + body; the legacy `## Fusebase Flow — …` spelling is also accepted) |
| `claude_md_overlay` | CLAUDE.md overlay block missing (the `## FuseBase Flow — additional rules (overlay)` heading + body; legacy `## Fusebase Flow — …` also accepted) |
| `settings_json_lifecycle_events` | `.claude/settings.json` events count below the upstream-canonical count (auto-discovered from `.claude/settings.json.example`); also covers Fusebase Flow `stop.py` missing from the Stop chain |
| `claude_skills_mirror_count` | `.claude/skills/` mirror count below the upstream skill count |
| `claude_agents_mirror_count` | `.claude/agents/` mirror count below the upstream sub-agent count |
| `windows_shell_patch` | Windows `shell:true` patch on `.claude/hooks/run-typecheck-apps.js` not applied (CVE-2024-27980 mitigation) |

Anything else in `deferred_checks` is silently ignored. Engine prefers explicit, documented check_ids over a wildcard suppression mechanism.

## Check IDs that are NOT defer-able

Some checks represent critical infrastructure or actual failures and cannot be deferred via this mechanism:

| Check | Why not defer-able |
|---|---|
| VERSION file missing | Required for upstream comparison; no project would deliberately omit it |
| AGENTS.md / CLAUDE.md overlay block DUPLICATE | Real config error from a heading rename; fix it manually, not deferable |
| `.claude/skills/fusebase-flow-health-check/` self-presence | This is the skill itself; nonsensical to defer |
| `hooks/local/post-fusebase-update.sh` missing | Critical recovery infrastructure |
| `hooks/local/fusebase-flow-overlays/` missing | Critical overlay templates folder |
| Preflight failures | Must always pass; deferral would mask real issues |
| Hook test failures | Use the existing `protected_path_edit-*.json` mechanism for artifact-attributable test failures |

## Example artifacts

### Example 1 — paperclip+hermes-v1's two deferrals

```json
{
  "approved_by": "operator@example.com",
  "scope": "Fusebase Flow installed without lifecycle-hook wiring + without Windows patch per install brief 2026-05-08",
  "expires_at": "2026-08-10T00:00:00Z",
  "reason": "Project preserves existing quality-check + lint-on-stop hooks (Step 9) and treats .claude/hooks/ as protected (Step 10). Both decisions are load-bearing per the install brief at docs/tmp/handoff/2026-05-08-fusebase-flow-install.md (commit f73e204). Revisit at the next architectural review of this project's hook chain.",
  "deferred_checks": [
    "settings_json_lifecycle_events",
    "windows_shell_patch"
  ]
}
```

Filename: `state/approvals/health_check_deferral-paperclip-install-discipline-20260510.json`

### Example 2 — minimal install (only skills + agents)

```json
{
  "approved_by": "ops@example.com",
  "scope": "Workflow-only install — Fusebase Flow flow-skills/agents/templates without overlay or settings",
  "expires_at": "2027-01-01T00:00:00Z",
  "reason": "This project doesn't use Claude Code or Codex; only the canonical skills/, agents/, workflows/ are needed for human reference. Overlay blocks and settings.json wiring don't apply.",
  "deferred_checks": [
    "agents_md_overlay",
    "claude_md_overlay",
    "settings_json_lifecycle_events",
    "windows_shell_patch"
  ]
}
```

Filename: `state/approvals/health_check_deferral-workflow-only-install-20260510.json`

## How the engine processes deferral artifacts

1. **Section 0 (artifact loading).** Engine scans `state/approvals/*.json` for files matching the `health_check_deferral-*.json` pattern AND with non-expired `expires_at`. Each artifact's `deferred_checks` list is added to a global `DEFERRED_CHECKS` array, with the artifact filename tracked in parallel `DEFERRED_BY_ARTIFACT`.

2. **Each defer-able check.** When a check finds drift, it calls `record_drift <check_id> <message>`. The helper looks up `<check_id>` in `DEFERRED_CHECKS`. If found, the message is pushed to `LOCAL_DEFERRED` (with `[check_id=...; deferred per <artifact>]` suffix). If not found, the message is pushed to `LOCAL_DRIFT` as before.

3. **Verdict logic.** If `LOCAL_BROKEN` is non-empty → `BROKEN` (deferrals don't override real breakage). If `LOCAL_DRIFT` is empty AND `LOCAL_DEFERRED` is non-empty → `EXCEPTION_IN_EFFECT` (exit 3). Otherwise existing logic applies.

4. **Output.** Deferred items appear in the "Local state" section with the ⊘ symbol. A dedicated "Deferred checks" section explains the mechanism. The "Active approval artifacts" section lists the artifacts that authorized the deferrals.

## Operator workflow

### Adding a deferral

1. Decide what you're deferring and why.
2. Create the JSON file at `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json` using the schema above.
3. Run `bash hooks/local/fusebase-flow-health-check.sh` and verify the engine reports `EXCEPTION_IN_EFFECT` (exit 3) instead of `DRIFTED` / `BROKEN`.
4. Commit the artifact alongside any related code changes (the artifact is a record of the decision).

> **`.gitignore` policy (v2.6.1+).** The upstream template's `.gitignore` excludes `state/approvals/*` wholesale because most artifact families there are ephemeral runtime state (e.g. `production_deploy-*.json` — 60-min auth tokens that must NEVER be in git). v2.6.1 adds a narrow exception so `health_check_deferral-*.json` artifacts are auto-tracked:
>
> ```
> state/approvals/*
> !state/approvals/.gitkeep
> !state/approvals/health_check_deferral-*.json   ← v2.6.1+
> ```
>
> **Why narrow.** The exception is intentionally specific to `health_check_deferral-*.json`. Other artifact families (`production_deploy`, future categories) stay ignored unless explicitly added. This forces every new artifact-family decision to be deliberate.
>
> If you're on a project that hasn't picked up v2.6.1 yet, add the exception manually — `git add state/approvals/health_check_deferral-*.json` will silently no-op without it.

### Removing a deferral (revisiting the decision)

1. Either delete the artifact file OR update its `expires_at` to a past date (engine treats expired artifacts as inactive).
2. If you want the underlying drift to be fixed, run `bash hooks/local/post-fusebase-update.sh` (or apply the specific fix manually). The recovery script is additive + idempotent — it'll wire missing events / apply missing patches.
3. Re-run the health check to confirm `HEALTHY`.

### Tracking deferrals over time

- Artifacts are named with date stamps (`-YYYYMMDD`) so a `state/approvals/` listing shows the deferral history.
- The `expires_at` field forces operators to revisit deferrals on a cadence — set realistic expiration dates (e.g. 90 days, end of quarter) rather than "never."
- The `reason` field documents the WHY for future-you / future agents who don't have your present context.

## Limitations + future work

- **Deferring DUPLICATE blocks isn't supported.** A duplicate marker block in AGENTS.md / CLAUDE.md is a real config error from a heading rename. The engine deliberately doesn't allow deferring it — fix the duplicate manually instead.
- **Deferring critical infrastructure isn't supported.** The recovery script's presence, overlay templates folder presence, preflight failures, and the health-check skill self-check all bypass the deferral mechanism. These represent things that must always be in place for the framework itself to work.
- **No artifact "approves" partial deferrals.** If a check is in your `deferred_checks`, the engine treats the entire check as deferred. There's no way to defer "events count is between 3 and 5 but not exactly 6" — it's a binary deferred-vs-not-deferred decision per check_id.

If you hit a real-world case where the current taxonomy is insufficient (e.g. a new check_id should be added, or a non-defer-able check should become defer-able), file it in `docs/fusebase-health/BACKLOG.md` (operator-local dev notes) for inclusion in a future minor release.
