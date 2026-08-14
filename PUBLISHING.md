# Publishing Fusebase Flow as a public GitHub template

This document describes the **history-hygiene step** required before publishing this repo as a public GitHub template.

## Why history hygiene matters

The build of this repo happened across many commits, some of which contained intermediate or non-target artifacts for compatibility surfaces that are **not** public targets. Those artifacts were removed from the final tree (`HEAD`) by the public-surface cleanup step, but they may remain visible in earlier commit objects in the build-time history.

Before publishing the public template, the operator MUST collapse the build history so the public Git tree reflects only the approved compatibility surfaces.

## Approved publication options

### Option 1 — fresh repo from the cleaned final tree (recommended)

```bash
# From the cleaned working tree on `main`:
TMPDIR="$(mktemp -d)"
cp -R . "$TMPDIR/fusebase-flow-template"
cd "$TMPDIR/fusebase-flow-template"
rm -rf .git
git init -b main
git add .
git -c user.email="<your-email>" -c user.name="<your-name>" commit -m "Initial commit — Fusebase Flow v<version>"
git tag v<version>
# Push to a fresh GitHub repository configured as a "Template repository":
git remote add origin git@github.com:<owner>/fusebase-flow-template.git
git push -u origin main
git push origin v<version>
```

Then in the GitHub UI, mark the repository as a **Template repository** so users can click "Use this template".

### Option 2 — squash-rebuild the current branch

```bash
# From the cleaned working tree on `main`:
git checkout --orphan release/v<version>
git add -A
git -c user.email="<your-email>" -c user.name="<your-name>" commit -m "Initial commit — Fusebase Flow v<version>"
# Replace main with this new branch:
git branch -D main
git branch -m main
git tag v<version>
git push -u --force origin main
git push origin v<version>
```

> **Note:** Option 2 force-pushes `main`. If anyone has already cloned the build-time repo, coordinate before force-pushing. Option 1 (fresh repo) avoids this concern entirely.

## Release evidence authority

**Release evidence is the CI `verify` job on the tagged SHA. A local run is never release evidence.**

Pushing a `v*` tag triggers `.github/workflows/fusebase-flow-release.yml`; its `publish` job declares
`needs: verify`, and `verify` calls the reusable `.github/workflows/fusebase-flow-verify.yml` suite
against that exact SHA. Red suite ⇒ no GitHub Release for that SHA.
That `needs: verify` edge, not a terminal on a maintainer's desk, is what a release claim rests on.

A local run (scoped, fast, or full) is **developer feedback**: it runs on an unpinned host, records
neither SHA nor platform in `state/audit/hook-test-results.md`, and gates nothing. Cite the `verify`
run for the tag, never a local result.

**Two-platform gating is enforced.** `fusebase-flow-verify.yml` runs the suite as a two-leg matrix —
`verify-linux` (`ubuntu-latest`) and `verify-windows-msys` (`windows-latest`, `shell: bash` = Git
Bash/MSYS) — both checking out the exact SHA passed by the caller and asserting `git rev-parse HEAD`
equals it. A third job, `verify-gate`, runs `if: always()` and fails unless the matrix aggregate is
`success`, so a leg that is red, cancelled, **timed out, or skipped** is never counted as a pass.
`publish` reaches `gh release create` only when the whole called workflow succeeded. A Windows-only
regression therefore cannot reach a Release — the failure class recorded in
`docs/problem-catalog/ci-linux-msys-test-divergence/problem.md`.

Both legs run with **committed defaults**: no `FF_ONLY`, no `FF_SKIP_*`, no `FF_*_TIMEOUT` override,
and a committed `timeout-minutes: 60` per leg (architecture-review § Bound policy). A phase that
cannot fit its wall leaves the tier; the wall is not raised.

### Publication paths — what the workflow closes, and what it cannot

`gh release create --verify-tag` matches on tag **name** only. A `v*` tag force-moved after CI ran
therefore used to publish a commit no `verify` job ever saw. `publish` now runs
`hooks/local/verify-tag-target.sh`, which re-fetches the tag from the remote, peels it to a commit,
and refuses unless it equals `github.sha` — before creating the Release and again after.

Every route to a Release object, and its status:

| Path | Status | Closed by |
|---|---|---|
| Tag push → this workflow, tag unmoved | verified | `needs: verify` on the exact SHA |
| Tag push → this workflow, tag force-moved after CI | **closed** | tag re-fetch + peel + compare, pre- and post-create |
| Annotated tag whose object ≠ its commit | **closed** | the peel (`^{commit}`), mutation-tested |
| Release already exists for the tag (created manually) | **narrowed** | the run now proves the tag targets the SHA it just verified instead of exiting 0 on mere existence |
| Tag moves *between* the check and `gh release create` | **OPEN — operator action** | a repository **tag ruleset** restricting `v*` updates/deletes. The workflow makes the window audible (the post-create re-assert goes red), it cannot remove it |
| A write collaborator creates a Release by hand in the UI/API | **OPEN — operator action** | restrict who may publish; enable **immutable releases** so a published tag cannot be re-pointed |
| Re-running a pre-fix release workflow run (eligible ~30 days) | **OPEN — operator action** | a re-run keeps the ORIGINAL workflow definition, `GITHUB_SHA` and `GITHUB_REF`, so it can verify the old SHA and publish today's moved tag without this check. Audit and delete eligible old runs |
| Any other credential/workflow with `contents: write` calling the Releases API | **OPEN — operator action** | none exists in this tree today; the check cannot enforce repository-wide exclusivity |

### Published tag immutability policy

Published `v*` tags are **immutable**. Once a release is published, its tag must not be moved,
deleted, or re-pointed. Moving a published tag is a **release incident**, not a routine correction.

`VERSION` alone does **not** identify a tree, and never did. The identity of the managed tree is
`audit/managed-content-manifest.json`'s `manifest_self_sha256`; adopters can identify the tree they
hold with the [release fingerprint table](docs/release-fingerprints.md).

**How this is enforced: by operator confirmation, not by a repository ruleset.** No agent or script
moves, deletes or re-points a published `v*` tag on its own; any such operation is proposed to the
operator and executed only on explicit confirmation. That is a deliberate choice — a ruleset would
also block the operator, and this project keeps release control with a human rather than a setting.

**What that control does not cover**, stated so no reader assumes more than exists: a human gate is
not a mechanical one. It cannot stop a tag moved directly on the hosting platform, by a collaborator
who is not following this document, or by an automation that never asks. If you need a guarantee
rather than a practice, the mechanical option is a repository ruleset restricting `v*` update and
delete plus immutable releases — see the publication-paths table above, which records which release
paths each setting closes.

The `v4.7.0` tag move from `664503b` to `bad4d92` is the release incident that prompted this policy,
and it is the reason the fingerprint table exists: with a procedural control, **identification is the
backstop**. Adopters should verify their tree by fingerprint rather than trusting a version string.

The four **OPEN** rows are repository settings and housekeeping, not code. They are listed here
rather than described as closed: a partial fix presented as complete is the failure mode this
section exists to prevent.

> **Unmeasured:** no `windows-latest` run of the full suite exists yet. The only measured MSYS full
> gate is a loaded developer host at ~2h02m before the step-4/step-5 reductions (est. ~1h28m after),
> which is **over** the committed 60-minute wall. If `verify-windows-msys` hits that wall the gate is
> RED and no Release is published — correct fail-closed behaviour, and the thing to fix before a tag.
>
> **How to replace that estimate with a number:** dispatch `fusebase-flow-measure-windows` manually.
> It runs the committed default suite on `windows-latest` at an exact SHA with a 180-minute wall (so
> it finishes rather than re-reporting a timeout) and uploads per-phase wall times, the total and the
> SHA as the `windows-measurement` artifact. It is **non-publishing** and gates nothing — it exists
> only to produce the measurement. Which remedy the number then argues for (a larger absolute wall
> plus a stall watchdog, sharding into independently required jobs, or platform ownership) is
> deliberately **not** decided here: choosing before measuring is what the plan review rejected.

## Local pre-flight — developer feedback, not release evidence

Run all of, so CI fails rarely — not because these authorize anything:

```bash
bash hooks/local/preflight.sh
bash hooks/tests/run-tests.sh              # FAST LOCAL DEFAULT (<=10 min); heavy phases skipped
FF_FULL=1 bash hooks/tests/run-tests.sh    # the full local set, when you want it (hours on MSYS)
bash hooks/local/mirror-skills.sh
git status --short
```

`run-tests.sh` has three tiers: the fast default, `FF_FULL=1` (full unscoped), and
`FF_ONLY="tag1,tag2"` (scoped). Only the full unscoped run is attesting — it alone writes
`state/audit/hook-test-results.md` and prints the strict `[run-tests] N/N PASS`. The other two
write `-fast.md` / `-scoped.md` and print a summary the strict classifier rejects, so a subset
result can never be read as a complete one. CI takes the full path automatically.
None of the three tiers is release evidence — see § Release evidence authority above.

Expected (self-derived — do not hardcode counts that re-stale; the live source is authoritative):

```
preflight:    0 errors / 0 warnings
hook tests:   0 FAIL. The full run prints "[run-tests] N/N PASS"; the fast default prints the
              same counts with a "(FAST LOCAL DEFAULT …)" suffix. N is whatever the current
              tier totals — a clean run is N/N with 0 FAIL, not a fixed number
mirror:       mirror-skills.sh reports 0 drift; the mirrored file count == the row count
              in audit/skill-mirror-manifest.txt (which == the live canonical set:
              one row per flow-skills/*/SKILL.md + flow-skills/*/references/* × 2 mirrors)
git status:   clean (or only the regenerated mirror manifest, if previously stale)
```

Also verify the **public-surface allowlist guard** passes — every tracked top-level entry must be on the approved allowlist. The allowlist is the same one enforced by `.github/workflows/fusebase-flow-verify.yml`:

```bash
ALLOWED=(
  "AGENTS.md" "CLAUDE.md" "GEMINI.md" "README.md" "PUBLISHING.md" "LICENSE"
  "FLOW_RULES.md" "FLOW_RULES_HISTORY.md" "VERSION" "install.sh"
  "CHANGELOG.md" "CONTRIBUTING.md" "SECURITY.md" "CODE_OF_CONDUCT.md" "ROADMAP.md"
  ".gitignore" ".gitattributes" ".python-version"
  ".agents" ".claude" ".claude-plugin" ".codex-plugin" ".codex" ".cursor" ".github"
  "agents" "audit" "docs" "flow-skills" "hooks" "policies" "state" "templates" "workflows"
)
actual=$(git ls-files | awk -F/ '{print $1}' | sort -u)
for entry in $actual; do
  ok=0
  for a in "${ALLOWED[@]}"; do
    [ "$entry" = "$a" ] && ok=1 && break
  done
  [ "$ok" -eq 0 ] && { echo "Non-approved top-level entry: $entry"; exit 1; }
done
echo "All tracked top-level entries are on the approved allowlist."
```

If any of these checks fail, correct the working tree and re-run before pushing — a red local check
is a red CI check waiting to happen. A green local run does not authorize a release; only the
`verify` run on the tagged SHA does.

**Shipping a new slash command?** The same release MUST ship its installer surface (v3.20.1 rule: *a preflight check may only ship in the same release as its installer step*): the recovery-snapshot copy in `hooks/local/fusebase-flow-overlays/commands/` (this is what `upgrade.sh`/`post-fusebase-update.sh` Step 8 install downstream) plus the command's entry in preflight §8 `FLOW_COMMANDS`. Preflight enforces all three surfaces (live file · snapshot copy · CLAUDE.md reference) per command — an incomplete command surface fails the release here instead of landing BROKEN on every consumer upgrade.

## Release prerequisites (enforced)

Publication is gated **in-repo**: pushing a `v*` tag triggers
`.github/workflows/fusebase-flow-release.yml`, whose `publish` job (the ONLY
`gh release create` under `.github/`) declares `needs: verify`, where `verify`
calls the full `fusebase-flow-verify` suite (hook tests → runner parity →
hook-layer manifest freshness → module-size → mirror → public-surface →
working-tree clean) on the tagged sha, **on Linux and on Windows/MSYS**. The
exact publication-gating condition is:

> `publish` runs **iff** the called `fusebase-flow-verify` workflow result is
> `success`, which requires `verify-linux`, `verify-windows-msys` **and**
> `verify-gate` to all succeed on the SHA passed as `with: sha`.

Any other aggregate — one leg red, cancelled, timed out at its committed
`timeout-minutes: 60`, or skipped — leaves `publish` undispatched ⇒ **no GitHub
Release is ever published for that sha**. This gate travels with **both**
publication options above — `.github/` ships with the published tree, and the
first `v<version>` tag push in the published repo triggers the same gated
workflow there (`uses: ./…` resolves on the same ref, so verify + release always
travel together).

Two consumer-facing surfaces the in-repo gate cannot close by itself — each needs
a one-time repo-admin setting:

**1. The raw `v*` tag ref** (a consumer doing `git clone --branch vX` before or
without the Release gets the tagged tree regardless of CI). Close it with a `v*`
**tag ruleset** requiring the `verify` status check on the tagged commit *before*
the tag can be pushed:

```bash
gh api repos/{owner}/{repo}/rulesets --method POST --input - <<'JSON'
{ "name": "v* tags require green verify on BOTH platforms", "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [ { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "verify-linux" },
                                    { "context": "verify-windows-msys" },
                                    { "context": "verify-gate" } ] } } ] }
JSON
```

Require all three: `verify-gate` alone would be satisfiable if a platform leg were
removed from the matrix, and either platform leg alone is single-platform evidence.
Contexts are the JOB names as Actions reports them — for a run dispatched *through*
the release workflow they are prefixed by the calling job (`verify / verify-linux`),
so **confirm the exact strings** against the repo's check runs (`gh api
repos/{owner}/{repo}/commits/<sha>/check-runs`) before saving the ruleset.

**2. A repo admin manually running `gh release create`** in defiance of § After
publication. Close it with **branch protection on `main`** requiring the `verify`
status check (so `main` only advances through green CI):

```bash
gh api repos/{owner}/{repo}/branches/main/protection --method PUT --input - <<'JSON'
{ "required_status_checks": { "strict": true,
    "contexts": ["verify-linux", "verify-windows-msys", "verify-gate"] },
  "enforce_admins": true, "required_pull_request_reviews": null, "restrictions": null }
JSON
```

(UI click-path: Settings → Branches → Add branch protection rule → branch name
pattern `main` → Require status checks to pass → select `verify-linux`,
`verify-windows-msys` and `verify-gate`.)

**Honest boundary:** the `needs: verify` edge in the release workflow is the
PRIMARY enforcement and stands alone even if an operator forgets these settings;
the two settings above close the raw-tag-ref and manual-create surfaces that a
file in the repo cannot. Applying the settings is operator-owned.

## After publication

- Watch the GitHub Action `fusebase-flow-verify` on the first push; **both**
  `verify-linux` and `verify-windows-msys` must pass.
- **Push the `v<version>` tag** (`git push origin v<version>`) — that is the ONLY
  release step. `.github/workflows/fusebase-flow-release.yml` runs the full
  `verify` suite on the tagged sha on both platforms and, ONLY if every leg is
  green, its gated `publish` job creates the GitHub Release from
  `docs/release-notes/v<version>.md` (or `--generate-notes` when that file is
  absent). The `gh release view` guard + `--verify-tag` make a re-run idempotent.
- **After TAGGING — not after publishing — append the tagged tree's fingerprint row.** This step is
  triggered by the tag existing, and by nothing else. Run
  `bash hooks/local/print-release-fingerprints.sh v<version>` and append the emitted row to
  `docs/release-fingerprints.md` on `main` (regenerate, never hand-transcribe). The tagged tree
  cannot contain its own row — the edit changes the digest being identified — so the row lands on
  `main` and ships in the NEXT release. Never move or amend the tag.
  - **A RED release run does NOT excuse the row.** A tag whose workflow failed is still a permanent
    tree an adopter can be holding; label its row an unpublished tagged tree and append it anyway.
    Skipping the row on a red run is exactly how `v4.9.1` shipped inside `v4.9.2` with no row, and
    how `v4.7.1` got none at all (consumer finding N3 — `docs/backlog/fingerprint-row-driven-by-publish-not-tag/`).
  - **Ordering: every prior tag must already have a row before the next tag is cut.** Once the next
    tag exists, the missed row can never be added to the tree that should have carried it.
  - **Enforced, not remembered:** `hooks/local/preflight.sh` fails if any `v*` tag in the table's
    coverage window has no row, naming the tag and the exact command that generates it. The only
    exemption is a tag pointing at `HEAD` (the self-reference limit above). Preflight runs in the
    release gate, so a missed row BLOCKS the next cut instead of being discovered by a consumer.
  - Update the external index too when one exists.
- **Do NOT run `gh release create` manually** — it bypasses the `needs: verify`
  gate (AC4). If a tag went red on a transient failure, fix on `main`, then re-run
  the release workflow from the Actions UI on the same tag.
- Update `VERSION` only when a new release ships. **There are FOUR version carriers**, not three — `VERSION`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and `.claude-plugin/marketplace.json` (`plugins[0].version`). The marketplace one is easy to miss; `preflight.sh` catches it (`marketplace.json plugins[0].version != VERSION`), but bump it with the others rather than discovering it at the gate. Then run `bash hooks/local/sync-version-strings.sh` and restamp **both** audit manifests — `flow_version` is embedded in each, so they change with every bump.
- Document any post-publication changes in a `CHANGELOG.md` (planned for v0.2).

## What this template promises consumers

- Approved provider / IDE compatibility surfaces (as listed in `README.md` and `docs/compatibility.md`).
- Stdlib-first Python runtime; PyYAML is the only non-stdlib dependency.
- Local-only hook handlers; no network surface.
- Clean-room original content; no third-party code, prompts, skill files, or hook scripts copied.
- MIT License.
