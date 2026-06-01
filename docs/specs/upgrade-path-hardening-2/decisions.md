# Decisions — upgrade-path-hardening-2

**Letter prefix:** U
**Approval status:** Locked by operator ("another feedback" + standing "fix everything / do it yourself"), 2026-06-01, against verified downstream upgrade feedback.
**Linked spec:** `docs/specs/upgrade-path-hardening-2/spec.md`

| ID | Title | Decision | Lock |
|---|---|---|---|
| U1 | Preserve operator project-values | Wrap `### Project-specific values` in inner `<!-- FLOW:PRESERVE:BEGIN -->…<!-- FLOW:PRESERVE:END -->` markers; `refresh_overlay_block()` carries the existing preserve-region forward into the fresh template (merge-preserve). Chosen over a separate file (keeps values in AGENTS.md, discoverable, no new read path) and over row-diffing (fragile). | LOCKED |
| U2 | Upgrade refreshes hooks/ + self-updates | Add `hooks/` to `upgrade.sh` refreshed content (handlers, shared, git, tests, local `*.sh`), preserving `hooks/local/*.local.*`; never touch CLI-owned `.claude/hooks/**`. Engine scripts copy over themselves (bash already in memory) and print "new logic active next run". | LOCKED |
| U3 | Sync derived attestation facts | Generalize `sync-version-strings.sh` to sync **version + FR-range (`FR-01..FR-NN` from FLOW_RULES.md) + `(NN canonical skills total)`** across all adapters. Fixes GEMINI (and any adapter) drift systemically; idempotent; context-anchored; excludes dated dirs. | LOCKED |
| U4 | Don't pollute consumer docs/ | Default `upgrade.sh` does NOT copy framework `docs/*.md` into the consumer. `--with-framework-docs` namespaces them under `docs/_fusebase-flow/`. | LOCKED |
| U5 | Pre-3.6.0 bootstrap | `hooks/local/bootstrap-upgrade.sh`: clone upstream → `.fusebase-flow-source/`, copy engine scripts into `hooks/local/`, run `upgrade.sh`. README documents a copy-paste one-liner for installs with no engine scripts yet. | LOCKED |
| U6 | LL ledger opt-in / configurable | Ledger defaults to **inline-in-commit**; the `docs/changes/index.md` file is opt-in and its path configurable (env/flag). `lightweight-lane` skill + `change-note` template reworded so a repo-root ledger is no longer assumed. | LOCKED |
| U7 | Legacy migration trims trailing rule | In the begin_line==0 (legacy marker-less) rebuild only, trim a trailing `---` rule (and blanks) from the preserved pre-block region so exactly one `---` remains. Marker-wrapped path trims blanks only (preserves the v3.7.0 byte-exact lock). | LOCKED |
| U8 | Null-byte hygiene | `sync-version-strings.sh` strips null bytes from scanned input (`tr -d '\0'`). | LOCKED |

## U1 — why merge-preserve (option c)
The overlay block is appended to AGENTS.md, which agents read wholesale, so project-values belong there (not a side file an agent might not read). A full-block replace is correct for framework prose but wrong for the operator's data. Inner `FLOW:PRESERVE` markers split the block into "framework-owned, refresh-replaceable" and "operator-owned, refresh-preserved." The refresh builds an *effective template* = the fresh template with its preserve-region swapped for the existing block's preserve-region, then compares/rebuilds against that — so a customized-but-otherwise-current block is a no-op, and a genuine framework-prose update rebuilds while keeping the operator's values verbatim.

## U2 — hooks/ refresh + self-update
v3.7.0 changed `hooks/handlers/stop.py` (tier-aware) and `hooks/local/approve-local.sh` and added fixtures; a downstream that ran only `upgrade.sh` got the new skills/rules but a stale hook layer (tier-aware gate silently inert; run-tests stuck at the old count). The fix refreshes the Flow-owned `hooks/` tree. `hooks/local/*.local.*` (operator overrides) are preserved; `.claude/hooks/**` is CLI-owned (separate tree) and never touched. The engine scripts live in `hooks/local/` — they self-update the same way `upgrade-engine.sh` already does.

## U3 — derived facts, one tool
Version, FR-range, and skill-count are all *derived from the framework* and must match across every adapter on every upgrade. v3.7.0 only synced the version, so the FR-range went stale on adapters without an overlay refresh path (GEMINI). Folding FR-range + skill-count into the same derive-and-sync tool makes all three self-maintaining.

## Lock confirmation
U1..U8 LOCKED 2026-06-01 (operator delegated against verified downstream feedback; U1 data-loss + U2 silent-staleness prioritized). Implementation authorized.
