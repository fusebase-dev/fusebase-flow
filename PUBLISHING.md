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

## Verification before publication

Run all of:

```bash
bash hooks/local/preflight.sh
bash hooks/tests/run-tests.sh
bash hooks/local/mirror-skills.sh
git status --short
```

Expected (self-derived — do not hardcode counts that re-stale; the live source is authoritative):

```
preflight:    0 errors / 0 warnings
hook tests:   run-tests.sh prints "[run-tests] N/N PASS" (0 FAIL); N is whatever the
              current suite totals — a clean run is N/N with 0 FAIL, not a fixed number
mirror:       mirror-skills.sh reports 0 drift; the mirrored file count == the row count
              in audit/skill-mirror-manifest.txt (which == the live canonical set:
              one row per flow-skills/*/SKILL.md + flow-skills/*/references/* × 2 mirrors)
git status:   clean (or only the regenerated mirror manifest, if previously stale)
```

Also verify the **public-surface allowlist guard** passes — every tracked top-level entry must be on the approved allowlist. The allowlist is the same one enforced by `.github/workflows/fusebase-flow-verify.yml`:

```bash
ALLOWED=(
  "AGENTS.md" "CLAUDE.md" "GEMINI.md" "README.md" "PUBLISHING.md" "LICENSE"
  "FLOW_RULES.md" "VERSION" "install.sh"
  "CHANGELOG.md" "CONTRIBUTING.md" "SECURITY.md" "CODE_OF_CONDUCT.md" "ROADMAP.md"
  ".gitignore" ".gitattributes" ".python-version"
  ".agents" ".claude" ".claude-plugin" ".codex" ".cursor" ".github"
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

If any of these checks fail, do NOT publish; correct the working tree and re-verify.

**Shipping a new slash command?** The same release MUST ship its installer surface (v3.20.1 rule: *a preflight check may only ship in the same release as its installer step*): the recovery-snapshot copy in `hooks/local/fusebase-flow-overlays/commands/` (this is what `upgrade.sh`/`post-fusebase-update.sh` Step 8 install downstream) plus the command's entry in preflight §8 `FLOW_COMMANDS`. Preflight enforces all three surfaces (live file · snapshot copy · CLAUDE.md reference) per command — an incomplete command surface fails the release here instead of landing BROKEN on every consumer upgrade.

## After publication

- Watch the GitHub Action `fusebase-flow-verify` on the first push; it must pass.
- Tag the release (`v<version>`) so consumers can pin a specific version.
- **Create the GitHub Release** (mandatory — tags alone leave the repo's Releases page stale): `gh release create v<version> -t "v<version> — <one-liner>" -F docs/release-notes/v<version>.md`.
- Update `VERSION` only when a new release ships.
- Document any post-publication changes in a `CHANGELOG.md` (planned for v0.2).

## What this template promises consumers

- Approved provider / IDE compatibility surfaces (as listed in `README.md` and `docs/compatibility.md`).
- Stdlib-first Python runtime; PyYAML is the only non-stdlib dependency.
- Local-only hook handlers; no network surface.
- Clean-room original content; no third-party code, prompts, skill files, or hook scripts copied.
- MIT License.
