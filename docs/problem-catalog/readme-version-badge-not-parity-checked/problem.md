# README shields.io version badge is neither synced nor parity-checked

- **Severity:** low
- **Status:** open (backlog)
- **First noted:** v4.4.1 release (2026-07-14)
- **Surfaces:** `README.md` shields.io badge (`img.shields.io/badge/version-<X.Y.Z>-blue`), `hooks/local/sync-version-strings.sh`, `hooks/local/preflight.sh` §8

## Symptom

During the v4.4.1 bump the README badge (`version-4.4.0-blue`) had to be edited **by hand** — nothing bumps it and nothing catches it if forgotten. It is the only version-bearing surface with **no** automated guard, so a stale badge can ship silently (a cosmetic-but-visible "this repo is vX-1" signal on the front page).

## Why it happens (design map)

The framework deliberately splits version surfaces into two disciplines:

1. **Sed'd by `sync-version-strings.sh`** — live attestation banners, FR-range, skill count in the allowlisted `*.md`/`*.mdc` set. `README.md` **is** in `SYNC_FILES`, but the substitution regex only matches the `Fusebase Flow v<VER>` banner form, **not** the shields.io `version-<X.Y.Z>-blue` slug — so the badge is untouched by the sync pass.
2. **Manual-bump + parity-gated by `preflight.sh` §8** — `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`. These are *intentionally* not sed'd; preflight `err`s in CI if any drifts from `VERSION`. This is exactly what caught the `.codex-plugin` drift in the v4.4.1 verify run (working as designed — the operator just missed the manual bump, and CI blocked it).

The badge falls in **neither** bucket: not in the sync substitution set, not in the preflight §8 parity list. So it is the one surface where drift is neither auto-fixed nor caught.

## Fix options (not yet applied)

- **Preferred (matches existing design):** add a preflight §8 parity check that greps `README.md` for `version-<semver>-blue` and `err`s if it != `VERSION`. Smallest change, catches drift in CI exactly like the plugin.json checks — keeps the badge in the "manual-bump + gated" bucket where the other visible-metadata surfaces already live.
- **Alternative:** teach `sync-version-strings.sh` to also rewrite the badge slug (README.md is already an allowlisted candidate; add a context-anchored `version-[0-9.]\+-blue` → `version-$VER-blue` substitution). Moves the badge into the auto-synced bucket so no manual bump is needed. If taken, the under-reach guard test (`test-sync-allowlist.sh`) should learn the badge token so it isn't seen as an omission.

Either is a self-contained follow-up; the v4.4.1 release itself is unaffected (badge was corrected by hand before tagging).
