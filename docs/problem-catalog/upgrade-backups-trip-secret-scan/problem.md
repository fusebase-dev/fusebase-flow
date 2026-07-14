# Problem: upgrade backups trip the pre-commit secret scan and block downstream commits (incl. `fusebase update`'s checkpoint)

**Slug:** `upgrade-backups-trip-secret-scan`
**Filed:** 2026-07-14
**Severity:** high
**Status:** resolved
**Filed by:** operator (field escalation) — downstream consumer repo (fusebase-troubleshooter), Windows 11 / Git-Bash/MSYS, FuseBase CLI edition, 3.30.2 → 4.3.2 upgrade

## Symptom

`upgrade.sh` / `bootstrap-upgrade.sh` (and the `post-fusebase-update.sh` recovery) leave **untracked backup copies of the hook layer** in the worktree: `hooks.pre-upgrade-<ts>/`, `flow-skills.pre-upgrade-<ts>/`, `policies.pre-upgrade-<ts>/`, `templates.pre-upgrade-<ts>/`, `workflows.pre-upgrade-<ts>/`, `agents.pre-upgrade-<ts>/`, `AGENTS.md`/`CLAUDE.md` `.pre-refresh-<ts>`, `hooks/local/*.pre-bootstrap-<ts>`. Those backups include the OLD secret-scan **test fixtures** (fixtures 10/11/12: GitHub-PAT-shaped `ghp_…`, Anthropic-key-shaped `sk-ant-…`, cookie/session values) and `policies.pre-upgrade-<ts>/secret-patterns.yml` — all of which deliberately contain dummy secret literals.

The staged-secret scanner path-excluded the LIVE fixture/policy locations but NOT their renamed backup twins. So the first downstream action that stages the whole tree hit a hard FALSE-POSITIVE `BLOCK` on `github_personal_access_token` / `anthropic_api_key` / `cookie_session_value`.

Real-world trigger: **FuseBase CLI's `fusebase update`** offers "Create a pre-update Git checkpoint commit? → Yes", which runs `git add -A` + commit → the backups get staged → Flow's own pre-commit blocks the CLI's checkpoint. Operator-visible symptom: *"fusebase update doesn't work."* The printed remedy ("rotate the credential") was misleading — there is no real credential.

Aggravation: after the blocked commit, the fixture blobs REMAIN STAGED (`AD` after the files are deleted from disk), so every subsequent commit still blocks until someone knows to `git restore --staged` the backup paths.

## Root cause

Two independent gaps:
1. **Scanner scope.** The path-exclusion list (`hooks/tests/fixtures/`, `policies/secret-patterns.yml`) was written for the LIVE paths only; it never accounted for the fact that Flow's own upgrade tooling makes renamed COPIES of those exact files elsewhere in the tree.
2. **Backups live in the worktree, untracked-but-stageable.** Any wholesale `git add -A` (a downstream tool Flow doesn't control) stages them. Flow's backups were never git-excluded.

## Why it matters

A framework upgrade must not leave the repo in a state where the platform's own `fusebase update` (or any `git add -A`) is hard-blocked by the framework's own backups — with misleading "rotate your credential" advice. This is exactly the "don't block the human operator" line.

## Permanent fix (v4.4.1)

| Status | Detail |
|---|---|
| Shipped | **Scanner excludes ONLY the fixture/policy backup TWINS** (not namespace-wide). `hooks/shared/staged_secret_scan.py` adds root-anchored `:(exclude,glob)hooks.pre-upgrade-<ts>/tests/fixtures/**` + `policies.pre-upgrade-<ts>/secret-patterns*.yml` with `<ts>` the EXACT `[0-9]{8}T[0-9]{6}Z`. Deliberately NOT `*.pre-*` NOR a loose `*T*Z` (matches literal `TZ` / any depth) — both are bypasses (Codex-xHigh). SECURITY: these twins are copies of files the live D-A1 excludes already exempt (`hooks/tests/fixtures/`, `secret-patterns.yml`), so this extends that same exemption to their backup copies — not a new content category; pathspec matches by name only, so the exact `[0-9]{8}T[0-9]{6}Z` + root-anchoring keep it as narrow as the live D-A1 set. A `TZ`/non-root/wrong-prefix look-alike, an untimestamped name, or a backup of ANY other file all stay SCANNED. The installed `hooks/git/pre-commit` block message was updated to match. |
| Shipped | **Backups are git-excluded at creation.** `upgrade.sh`, `bootstrap-upgrade.sh`, and `post-fusebase-update.sh` append EXACT-timestamp patterns (`*.pre-upgrade-[0-9]{8}T[0-9]{6}Z` …) to `.git/info/exclude` (`git rev-parse --git-path`, worktree-correct; ensures a trailing newline first so an unterminated line can't swallow the rule) before writing backups, so `git add -A` never stages them (also fixes the `AD` trap). Per-pattern idempotent, `set -e`-safe, honest on failure (WARN + conditioned note); `config.pre-upgrade-template.yml`/`foo.pre-upgrade-TZ` stay visible. |
| Shipped | **Accurate remedy.** The BLOCK message no longer claims a `.pre-*` hit is "not a real secret" (only the exact twins are skipped) — treat a remaining hit as potentially real, inspect it, rotate if real, and separately unstage the exact Flow backup path (`git restore --staged <path>`; see this entry for a safe timestamp-filtered listing). `upgrade.sh` notes add "answer No to the CLI checkpoint prompt mid-ticket" for the separate FR-25-on-WIP-growth interaction. |
| Test | `hooks/tests/test-secret-scan-staged.sh`: the timestamped fixture/policy twins are excluded; a backup of a non-fixture file, a `x.pre-upgrade-1/` name-spoof, and a fixtures path without a real timestamp ALL still block (no namespace bypass). Reviewed by Codex gpt-5.6-sol (High): 1 blocker + 1 high + 3 medium found and fixed. |

## Recurrence triggers (so future sessions recognize this)

- A `BLOCK — secret pattern in staged added lines` on `github_personal_access_token` / `anthropic_api_key` / `cookie_session_value` right after a Flow upgrade, where the hits are under `*.pre-upgrade-*` / `*.pre-bootstrap-*` / `*.pre-refresh-*`.
- "fusebase update doesn't work" after a Flow upgrade.
- A new Flow-generated backup/snapshot family added without a matching scanner exclusion + `.git/info/exclude` entry.

## Recovery (if you're already stuck with leftover backups)

**Review before deleting** — don't blanket-`rm` a `.pre-*` glob (it would delete a legit `config.pre-upgrade-template.yml` and miss nested file backups). List the exact timestamped backups and any staged blobs first:

```bash
# genuine Flow backups (exact YYYYMMDDTHHMMSSZ stamp), tracked-or-untracked:
git ls-files -oc | grep -E '\.pre-(upgrade|bootstrap|refresh)-[0-9]{8}T[0-9]{6}Z(/|$)'
# Flow backup blobs a pre-fix `git add -A` left staged:
git diff --cached --name-only | grep -E '\.pre-(upgrade|bootstrap|refresh)-[0-9]{8}T[0-9]{6}Z(/|$)'
```

Then unstage those blobs (never commit them) and remove only the paths you confirmed are backups:

```bash
git restore --staged <paths from the second command>
rm -rf <paths you confirmed are Flow backups>
```

A hit on a path that is NOT one of the exact `hooks.pre-upgrade-<ts>/tests/fixtures/**` or `policies.pre-upgrade-<ts>/secret-patterns*.yml` twins is **potentially real** — inspect it; rotate only if real.

## Guardrail (the lesson)

Any tool that COPIES scanner-fixture or secret-bearing files inside the worktree (backups, snapshots) must (a) be path-excluded from the secret scan — narrowly, extending only the SAME exemption those live D-A1 files already carry (exact timestamp + root-anchored + fixture/policy shape), never a namespace-wide `.pre-*` (a bypass) — and (b) be git-excluded so a wholesale `git add -A` never stages them. Never let the framework's own housekeeping hard-block the platform's update flow.

## Related

- `docs/problem-catalog/gate-command-operator-friction/problem.md` · `docs/problem-catalog/deploy-approval-terminal-friction/problem.md` (same "don't block the operator" line)
- `hooks/shared/staged_secret_scan.py` (D-A1 exclusion design) · `hooks/local/upgrade.sh` / `bootstrap-upgrade.sh` / `post-fusebase-update.sh` (backup creation)
