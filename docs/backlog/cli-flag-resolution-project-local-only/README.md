# CLI flag resolution reads project-local config only (cli-flag-resolution-project-local-only)

**Status:** parked — latent, fail-open; BLOCKED on the CLI's effective flag contract
**Filed:** 2026-09-11
**One-liner:** `enabled_flags()` (`hooks/local/check-cli-flow-conflicts.sh:342-364`) reads only `fusebase.json`, `.fusebase/config.json` and `fuse.config.json` under the repo, while the reporter's CLI keeps flags user-globally, so the flag-on `MISSING` finding (`:516-519`) is unreachable on an ordinary install.

## Operator pain (in their words)

fusebase-troubleshooter v4.15.3 escalation, F3: "`enabled_flags()` returns `None` on every ordinary CLI install … the finding at line 519 is unreachable in practice … U10's detection is currently decorative." Their live example (`managed-integrations` flag ON, skill absent) stopped reproducing once a real `fusebase update` installed the skill (F2 retraction), so no current field symptom.

## Why now

The F1-batch premise review (§ E; local artifact, not in this repo) ruled NO-BUILD on the proposed fix; this records why so the next pass does not ship it.

## Architectural sketch (rough)

- The proposed fix (append `$FUSEBASE_HOME/config.json`, `~/.fusebase/config.json`, `%USERPROFILE%\.fusebase\config.json` to the candidate list) is WRONG as written: `enabled_flags()` returns the FIRST recognized flag collection, INCLUDING an empty one, so a local `flags: []` would shadow a global flag, and a local flag ON with the CLI-effective state OFF would raise a false `MISSING`.
- Unverified, and each must be established from the CLI itself before code: effective precedence (local vs global vs per-env), `$FUSEBASE_HOME` support, `--env` selection, Windows home resolution.
- Once the contract is known, resolve flags in the CLI's order; decide union vs override from evidence, never by guess.
- Keep `None` → benign (a flag-gated absence is INFO when flag state is undeterminable). Never invoke the `fusebase` binary from this read-only diagnostic.

## Acceptance criteria (rough)

1. AC1 — flag state resolves exactly as the CLI resolves it, cited to CLI source or observed CLI behavior per case.
2. AC2 — a local empty collection does not hide a flag the CLI treats as enabled, unless the CLI itself gives local precedence.
3. AC3 — undeterminable state still yields `None` → benign INFO.
4. AC4 — a fixture drives the flag-on `MISSING` through the resolved global store (the project-local form is pinned by `cli-flow-recovery-classify.sh` `prov-missing`, T90).

## Out of scope

- Honoring `"required": false` on provider-skill entries (removed in T90; honoring it silences valid `MISSING` rows).
- Advancing the vendored CLI snapshot past `0.29.8` (separate maintenance).

## Risks / unknowns

- Guessed precedence ships a false `MISSING` or keeps the false benign, whichever direction the guess is wrong in.
- Reading another environment's global config can activate the wrong branch.

## Related

- Consumer report: fusebase-troubleshooter `docs/fusebase-flow-v4.15.3-upstream-escalation.md` § F3 and RETRACTION (their repo)
- `docs/backlog/module-size-block-advice-grandfathers-growth/` (filed from the same escalation)
