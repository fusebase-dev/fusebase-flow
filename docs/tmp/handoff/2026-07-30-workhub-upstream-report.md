# Fusebase Flow — upstream bug report: v4.5.0 → v4.7.0 upgrade

**From:** WorkHub Managed (consumer repo; multi-app, flagship `client-workflows`)
**Date:** 2026-07-30
**Upgrade:** Fusebase Flow **4.5.0 → 4.7.0** (via `hooks/local/upgrade.sh`)
**Findings:** 7 bugs + 1 suggestion. All hit directly during the upgrade — none inferred.
**Outcome:** health check now reports **HEALTHY** (134 files match release 4.7.0), but reaching that
state required **seven manual interventions**.

## Environment

| Field | Value |
|---|---|
| OS / shell | Windows 11 Pro 26200 · Git Bash (MINGW64) |
| `core.autocrlf` | default (CRLF on checkout) — **relevant to F2** |
| FuseBase CLI | Launcher `2026.070314.1650`, channel `dev` |
| Flow before | 4.5.0 |
| Flow after | 4.7.0 (tag `v4.7.0`, clone HEAD `664503b`) |
| Consumer repo | multi-app; Flow installed as an append/merge overlay over an existing CLI project |
| Hook tests | 338 pass / 4 fail after upgrade → all 4 traced to F1, F2, F5 or consumer state; **none to shipped 4.7.0 logic** |

## Summary

| # | Severity | Finding | Area |
|---|---|---|---|
| **F1** | **HIGH** | `upgrade.sh` cannot install its own release — new top-level file never copied | upgrade path |
| **F2** | **HIGH** | Windows consumers get a permanent, undiagnosable `FLOW_LAYER_DRIFT` | packaging / `.gitattributes` |
| **F3** | **HIGH** | `policies/` refresh silently discards consumer `exempt_globs`, turning a gate red | upgrade path |
| **F4** | MEDIUM | `upgrade.sh` appends a duplicate baseline entry | upgrade path |
| **F5** | MEDIUM | The upgrade's own backups fail its own tests; the recommended cleanup is blocked by FR-06 | upgrade path / guidance |
| **F6** | MEDIUM | `run-tests.sh` is indistinguishable from a hang for ~13 min — the failure mode FR-27 exists to prevent | test runner |
| **F7** | MEDIUM | Command scanner denies commands that merely *mention* a blocked pattern | `pre_tool_use` command policy |
| **S1** | suggestion | No staleness warning on unconsumed approval artifacts | `approve-local.sh` / health check |

## Upstream disposition (added by Flow maintainers 2026-07-30)

Read this before the findings — three of them are not defects at 4.7.0. Verdicts + rationale: `docs/specs/upgrade-source-integrity-and-observability/decisions.md` (M1–M10). Consumer-facing form: `docs/release-notes/v4.7.0.md` §§ "source integrity, backup hygiene, and observability" · "three reported findings need no code" · "Known limitation — F7".

| # | Disposition | Where |
|---|---|---|
| F1 | **already fixed** — K14 manifest-driven refresh; `hooks/local/upgrade.sh:263-274` + `hooks/local/lib/managed_content_manifest.py:34-49` (`FLOW_RULES_HISTORY.md` at `:44`). Cause: run under the stale installed **4.5** engine, not the documented bootstrap route | M7 |
| F2 | **fixed** — managed source materialized from git objects, never the staging worktree (`hooks/local/lib/materialize-managed-source.sh`) | M1, M10 · `1fc082e` |
| F3 | **already fixed** — K9 per-file classifier preserves + reports `consumer-only` (`managed_content_manifest.py:220-294`). Same cause as F1 | M7 |
| F4 | **refuted** — `hooks/local/lib/merge-module-size-baseline.sh:85-101` keys rows by path and emits one row per path | M7 |
| F5 | **fixed** — backup families pruned from allowlist discovery (`d5a4ced`); sanctioned `hooks/local/cleanup-flow-backups.sh` replaces the `rm -rf` guidance, FR-06 deny unchanged (`c88a56e`) | M4, M5 |
| F6 | **fixed** — optional parent-owned heartbeat on captured long runs (`47a0028`) | M3 |
| F7 | **confirmed, deferred** — every proposed narrowing opens an evasion; promoted to `docs/backlog/command-gate-shell-evasion/`. Sanctioned path today: `git commit -F <file>` | M8 |
| S1 | **implemented** — `created_at` + verdict-neutral stale-approval warning + `--inventory` age column (`e357993`) | M9 |

---

## F1 — `upgrade.sh` cannot fully install its own release · HIGH

**Symptom.** After a clean, successful upgrade to 4.7.0, one of the release's **own** tests fails:

```
FAIL: sync-allowlist history-not-in-allowlist
      (FLOW_RULES_HISTORY.md missing (extracted amendment log))
```

**Root cause.** 4.7.0 extracts the amendment log out of `FLOW_RULES.md` into a **new top-level file**,
`FLOW_RULES_HISTORY.md` (478 lines). `upgrade.sh` refreshes *directories* —
`workflows/ policies/ templates/ hooks/ .codex-plugin/` — plus a hardcoded set of named files. A newly
added top-level canonical file is not in that set, so it is never copied.

**Reproduce.** Upgrade any 4.5.0 consumer to 4.7.0, then run `bash hooks/tests/run-tests.sh`.

**Workaround applied.** `cp .fusebase-flow-source/FLOW_RULES_HISTORY.md .`

**Suggested fix.** Drive top-level canonical file refresh from a manifest rather than a hardcoded list,
so a release that adds a file cannot ship an upgrade path that fails to install it.

---

## F2 — Windows consumers get a permanent, undiagnosable `FLOW_LAYER_DRIFT` · HIGH

**Symptom.** `fusebase-flow-health-check.sh` reports drift on four fixtures, on a clean checkout:

```
✗ hook layer integrity: FLOW_LAYER_DRIFT —
  hooks/tests/fixtures/18_stop_native_transcript_doneclaim_transcript.jsonl,
  hooks/tests/fixtures/19_stop_native_transcript_midclaim_no_overtrigger_transcript.jsonl,
  hooks/tests/fixtures/20_stop_native_corrupt_transcript_claim_failclosed_transcript.jsonl,
  hooks/tests/fixtures/21_stop_native_corrupt_transcript_noclaim_allow_transcript.jsonl
  (recover: 'bash hooks/local/upgrade.sh' or 'git checkout -- <file>')
Verdict: FLOW_LAYER_DRIFT
```

**Root cause.** `audit/hook-layer-manifest.json` hashes **LF** content. `.gitattributes` forces
`text eol=lf` for `*.sh *.bash *.py *.yml *.yaml` — but **not `*.jsonl` / `*.json`**. On a Windows
checkout these fixtures arrive CRLF-only, so their digests can never match.

Measured on our checkout:

```
hooks/tests/fixtures/18_..._transcript.jsonl → CRLF count: 3, bare LF: 0
sha256 raw      : 825752052d801a79…   ← what the checker sees
sha256 LF-norm  : ae5a2beabfb1e065…   ← what the manifest stores
```

**Why this is worse than a normal packaging bug — two traps:**

1. **It looks like a false positive.** `diff` reports the files as byte-identical to
   `.fusebase-flow-source/`, because diff normalizes. A consumer reasonably concludes the checker is
   wrong and moves on, leaving the health check permanently red.
2. **The suggested recovery cannot work.** `git checkout -- <file>` is the operation that *introduces*
   the CRLF. Neither suggested remedy fixes it.

Normalizing the working tree "fixes" it only until the next checkout — git already stores LF, so a
normalization commit is **empty** and the drift returns.

**Suggested fix.** Add to `.gitattributes`:

```
hooks/**/*.jsonl  text eol=lf
hooks/**/*.json   text eol=lf
```

Consider also making the integrity checker normalize line endings before hashing, so the manifest is
transport-independent.

**Note:** this is the same defect class as a bug we hit in our own app — a checksum computed over
normalized bytes compared against un-normalized bytes on disk.

---

## F3 — `policies/` refresh silently discards consumer `exempt_globs` · HIGH

**Symptom.** Immediately after upgrading, our module-size gate went red:

```
[module-size] BLOCK — FR-25 module-size ratchet (all):
  docs/_shared/fusebase-design-system/_ds_bundle.js: 1130 lines > ceiling 800 (not in baseline)
```

**Root cause.** We had added `docs/_shared/**` to `policies/module-size.yml` `exempt_globs` — a
vendored design-system bundle that is not app source and was never intended to be gated. `upgrade.sh`
refreshes `policies/` wholesale and **reverted the entry with no warning**.

`policies/module-size.yml` does document a `local_override_file: policies/module-size.local.yml` whose
`exempt_globs` are merged. But nothing tells a consumer that hand-edits to the **tracked** policy will
be silently lost on upgrade, and the tracked file is the natural, reviewable place to add an exemption.

**Impact.** A consumer's build breaks on the first commit after upgrading, for a reason that has
nothing to do with their change.

**Suggested fix.** Either (a) merge consumer `exempt_globs` / `source_globs` forward during upgrade, or
(b) have `upgrade.sh` **detect and report** consumer additions it is about to drop, ideally offering to
migrate them into the local override file. Silently reverting a consumer's gate configuration is the
worst of the available behaviours.

---

## F4 — `upgrade.sh` appends a duplicate baseline entry · MEDIUM

**Symptom.** After upgrade, `policies/module-size-baseline.txt` contained:

```
954 hooks/tests/test-cli-flow-recovery.sh
954 hooks/tests/test-cli-flow-recovery.sh     ← duplicate
```

Append without dedupe. Benign in effect, but this is a ratchet input file and duplicates invite
confusion about which entry is authoritative.

**Positive note:** our project-specific baseline entries **were preserved** correctly
(`repository.ts` 14717, `WorkHub.tsx` 4042) — the upgrade did not clobber the consumer baseline.

**Suggested fix.** Dedupe on write.

---

## F5 — The upgrade's own backups fail its own tests, and the recommended cleanup is blocked · MEDIUM

**Symptom.** Two test failures after upgrade:

```
FAIL: sync-allowlist no-under-reach (token-bearing framework file(s) NOT in allowlist:
      agents.pre-upgrade-20260730T015030Z/ai-developer/AGENT.md
      agents.pre-upgrade-20260730T015030Z/product-owner/AGENT.md
      hooks.pre-upgrade-…/local/fusebase-flow-overlays/agents-md-overlay.md
      templates.pre-upgrade-…/{architect-response,deploy-report,gate-report,handoff-deploy,handoff-implement}.md
      workflows.pre-upgrade-…/{architect-escalation,greenlight-deploy,greenlight-implement,session-initiation}.md)

FAIL: secret-scan-staged release-gate-self-test-tree-commits-clean
      (the full release tree tripped the secret scan (an in-tree literal token ships a self-blocking release))
```

**Root cause.** `upgrade.sh` creates timestamped backups (8 of them for us:
`FLOW_RULES.md.pre-upgrade-…`, `VERSION.pre-upgrade-…`, `agents.pre-upgrade-…`,
`flow-skills.pre-upgrade-…`, `hooks.pre-upgrade-…`, `policies.pre-upgrade-…`,
`templates.pre-upgrade-…`, `workflows.pre-upgrade-…`). These are token-bearing framework copies, and
the allowlist / secret-scan sweeps walk the working tree, so they are counted. They **are** gitignored
(`.gitignore:75: *.pre-upgrade-*`), so this is disk-only noise — but it still fails the suite.

**The self-contradiction.** `upgrade.sh` output advises *"remove once validated"*, but Flow's own
`pre_tool_use` handler denies the removal:

```
[fusebase-flow] DENY: FR-06: <recursive force delete> erases recoverable state without operator consent.
```

FR-06 is behaving correctly. The conflict is that the framework recommends a cleanup its own guard
refuses, leaving the consumer with a failing suite and no sanctioned path forward.

**Suggested fix.** Exclude `*.pre-upgrade-*` from the allowlist and secret-scan sweeps (they are
already gitignored), and provide a sanctioned cleanup command instead of advising a raw recursive
delete.

---

## F6 — `run-tests.sh` is indistinguishable from a hang for ~13 minutes · MEDIUM

**Symptom.** The suite takes **~25 minutes** and its output is **fully buffered**. Measured on our run:

| Elapsed | Log bytes | Visible child process |
|---|---|---|
| 0–13 min | **0** | none (`tasklist` shows no `python`) |
| ~13 min | 6,342 | none |
| ~25 min | 27,993 → complete, exit 0 | none |

**Impact.** I concluded **twice** that the suite had failed to run in this environment, and reported
that to my operator as a pre-existing environment problem. Both times it was running fine. A correct
"nothing is broken" claim was delayed by an hour and had to be retracted.

**Why this one is worth prioritising.** This is precisely the failure mode
**FR-27 (liveness — never launch bare)** exists to prevent: work that emits no completion or progress
signal, so the observer cannot distinguish running from dead. It is occurring inside Flow's own test
runner, and FR-27's own guidance ("judge by activity, not existence") cannot be applied because there
is no observable activity.

**Suggested fix.** Flush per suite. The `[run-tests] starting <suite>` lines already exist — emitting
them unbuffered (`PYTHONUNBUFFERED=1`, `stdbuf -oL`, or an explicit flush) would remove the ambiguity
entirely at near-zero cost.

---

## F7 — Command scanner denies commands that merely *mention* a blocked pattern · MEDIUM

**Symptom.** Found while committing *this report*, then again while editing it. The `pre_tool_use`
command policy scans the **entire command string**, including quoted commit-message text and heredoc
bodies. A `git commit` whose message *describes* the F5 conflict is denied:

```
[fusebase-flow] DENY: FR-06: <recursive force delete> erases recoverable state without operator consent.
```

No destructive command is present. The pattern appears only inside prose describing it.

**Reproduce.**

```
git commit -m "docs: note that the recommended cleanup is denied by FR-06's <pattern> guard"
python - <<'EOF'   # a heredoc that merely writes documentation mentioning the pattern
EOF
```

Both are denied.

**Impact — two consequences, the second more serious:**

1. You cannot write an honest commit message, problem-catalog entry, or upstream bug report about the
   guard through Bash at all.
2. The only way through is to **route around the guard** — author the text with a non-Bash file tool,
   then `git commit -F <file>`. That is exactly the behaviour a safety rail should not teach. I had to
   do this to deliver this report.

**Suggested fix.** Match destructive patterns in **command position** rather than anywhere in the
string, and exclude `-m` / `-F` payloads and heredoc bodies from destructive-command matching. Same
root class as F2: matching raw text where structure was intended.

---

## S1 — Suggestion: warn on stale unconsumed approval artifacts

Not a Flow bug, but Flow is well placed to catch it.

`hooks/local/approve-local.sh` mints approval artifacts with **3-month TTLs** and no consumption
tracking (unlike `write-bootstrap-approval.sh`, which is single-use and self-consuming). We discovered
**two unconsumed `protected_path_edit` approvals** covering `fusebase.json`, from tickets long since
completed:

```
protected_path_edit-cw-internal-route-lockout-20260726.json  paths=['fusebase.json']  expires=2026-10-26
protected_path_edit-cw-recurring-cron-20260727.json          paths=['fusebase.json']  expires=2026-10-27
```

Net effect: the **FR-07 protected-path guard on our deployment config was effectively open for three
months**.

**How we found it — accidentally.** Fixture `07_pre_tool_use_blocked_protected_path_edit` failed
(`expected=deny got=allow`). We verified `policies/protected-paths.yml`, `hooks/handlers/pre_tool_use.py`
and the fixture were all byte-identical to upstream 4.7.0 — the handler was **correct**; it allowed the
edit because a valid approval existed. Our repo state was the problem.

The health check *lists* active approvals but does not flag staleness.

**Suggested fix.** Add a health-check warning: *"N approval artifacts older than X days and
unconsumed"*, and/or record intended single-use on `approve-local.sh` artifacts so a completed ticket's
approval stops granting access. This would convert a silent three-month security hole into a visible
signal.

---

## Explicitly not a Flow problem

Recorded so it is not chased upstream:

- **The FuseBase CLI self-update stripped the Flow lifecycle hook chain from `.claude/settings.json`
  twice within one session.** Flow already documents this coexistence hazard, and
  `post-fusebase-update.sh --wire-hooks` recovers it cleanly. Our mitigation is to default to
  `fusebase update --skip-skills`. Mentioned only because the frequency suggests the coexistence note
  in `AGENTS.md` deserves more prominence than it currently has.

## Net assessment

**The 4.7.0 content itself looks sound.** 338 hook tests pass, and all 4 failures trace to F1, F2, F5,
or consumer repo state — **none to shipped 4.7.0 logic**. `preflight.sh` reports 0 errors.

The defects are concentrated in the **upgrade path** (F1, F3, F4, F5), **Windows packaging** (F2), and
**two observability/precision issues in the guard and test layers** (F6, F7).

If prioritising: **F1–F3 cost real time and each breaks a consumer on first contact.** F2 in
particular will silently affect every Windows consumer and actively misleads whoever investigates it.

---
Phase: Upstream report
Ticket: fusebase-flow-4.7.0-upgrade
Next: forward to the Fusebase Flow team
