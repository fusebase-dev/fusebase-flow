# core-hook-inventory

**Status:** open — 6.0.0 rebuild, **wave 1**, with a wave-3 tail. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 11, the hook list and the kept-file edits (R §2). **Surface:** the 34 core hook files (R §3 rows 1-34; row 35 withdrawn), `hooks/local/lib/run-with-timeout.sh` (trim), `hooks/local/lib/agent_tool_profile.py` (helper copy), `hooks/local/run-handler.sh`, `hooks/local/install-git-hooks.sh`, `hooks/local/approve-local.sh`, `hooks/local/lib/approval-receipt.sh`, `hooks/local/po-investigate.sh`; tail: `hooks/local/lib/hook_manifest.py`, `hooks/local/sync-version-strings.sh`. **FR-07:** no for the wave-1 commits (`hooks/local/**` stays unprotected until the release-close commit, ask 10).

## Delivers

- **The list: 34 hook files** (owner, second message): 3 git hooks; `install-git-hooks.sh`, `check-module-size.sh`, `precommit-validator-reuse.sh`, `validator_tier.py`; the 13 `hooks/shared/` modules; `pre_tool_use.py`, `post_tool_use.py`, `run-handler.sh`; `bounded-run.sh` and the trimmed `run-with-timeout.sh`; `approve-local.sh`, `approval_inventory.py`, `write-bootstrap-approval.sh`; `agent_tool_profile.py`; and the five new files `flow_docs.py`, `reader.py` (`--once`, `--watch`), `gate.py`, `checks.py` (the four flags on one slice), `slice.py`. `hooks/requirements.txt` ships beside them. The acceptance states the number `hook_manifest.py` prints, with no "about" (R §3). New files live in `hooks/local/lib/`, which integrity coverage already includes (`hook_manifest.py:101-102`).
- **Decision 4 trim:** the core `run-with-timeout.sh` keeps lines 32-69 under the same name, the three functions `bounded_run` calls (`bounded-run.sh:57, 81, 94`). That drops the source-time FIFO probe and the `job-fence.sh` source from every shell that loads it. The full file is in `maintainer/` with its callers (`maintainer-tree-split`). Plan proposal: a maintainer test asserts lines 32-69 are byte-identical in both copies.
- **Ask 11a helper copy:** `agent_tool_profile.py` stops loading the maintainer helper `recovery-owned-write.py` (`agent_tool_profile.py:51`) and the maintainer file `agent-surface-ownership.json` (`:21`). It carries the five helpers it uses (`native_path`, `reject_symlinks`, `lf_form`, `recovery_lock`, `atomic_bytes`, about 70 lines) and a fixed `app-*` reserved-name pattern. The fixture's copied-file list drops two entries; no assertion changes (owner-approved departure).
- **`run-handler.sh` no-Python marker:** today its only "no Python" warning fires for `session_start.py` (`run-handler.sh:80`), which `stop-gate-retirement` removes. On the first event with no interpreter it writes a marker under `state/` that the reader reports (R §3 row 23). Lands before `session_start.py` goes.
- **Per-clone excludes in `install-git-hooks.sh`:** it writes `/state/audit/liveness/` and `/policies/*.local.yml` into `.git/info/exclude`, as `hooks/local/lib/backup-hygiene.sh:70-73` does today from the upgrader, which moves to `maintainer/` (decision D carried, R §6).
- **Drops:** `hooks/local/lib/approval-receipt.sh` ("it enforces nothing", `:15`) and the `--receipt` arm of `approve-local.sh` (`:54-56`) with their test and tag (ask 5); `hooks/local/po-investigate.sh` with its test and tag (R §3).
- **Wave-3 tail:** `hook_manifest.py` (maintainer) resolves the core set, and the `sync-version-strings.sh` anchors and every count string are re-based to 34 hook files and 7 policies; tests no longer count as consumer files (R §2 WP 11).

**Open item for the owner (not decided here):** `hooks/git/pre-commit:820` tells a user to run `bootstrap-upgrade.sh --repair-managed`, which moves to `maintainer/`. Changing that message touches `pre-commit`, which R §4 keeps byte-identical except its named exceptions; it needs the owner's word, or the message stays and the migration report explains the repair route.

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Second message (34 files; row 35 withdrawn; core `reader.py` and `checks.py` are not the calibration tools) | The list |
| Decision 4 (trim to lines 32-69) | The trim |
| Decision 7 (keep 18 files no WP names; confirmed drops) | Nothing kept is dropped |
| Asks 5, 11a | Receipt drop; helper copy |
| R §4 locks (kernel byte-identical; heartbeat file) | No edit to `pre-commit`, `pre-push` or `hooks/shared/` here |

## Estimate

Share of R §2 WP 11 (21.5 to 29.5 agent-h for the four WP 11 entries): 5.5 to 8 (mid 6.75): trim 1.5, helper copy 1.5, marker and excludes 1, drops 1, tail 1.5 to 2.

## Depends

`maintainer-tree-split` (the full `run-with-timeout.sh` and its callers leave first, or in the same commit). The tail waits for the wave-2 files. Blocks: `stop-gate-retirement` (the marker), `reader-agent-and-dispatch-check` (row 29 edits serialize), `flow-install-declared-providers` (the list).

## Acceptance

1. `hook_manifest.py` prints 34 for the core set; every policy is read by at least one hook (R §3 table; H WP 11).
2. The `bounded-run` and `bounded_wait` rows of `test-liveness-bounded-run.sh` pass unchanged against the trimmed file (hosted `liveness`).
3. The tool-profile fixtures pass with only the two dropped copy entries (ask 11a) and the agent rename.
4. A fresh clone that runs `install-git-hooks.sh` has the three hooks and both exclude lines in one step (fixture).
5. `approve-local.sh` fixtures pass without the receipt arm (`approval-writer`, `approval-binding`, `approval-schema3`, hosted); no file reads `approval-receipt.sh`.
6. `hook_manifest.py` and `sync-version-strings.sh` anchors are updated to the new counts (H WP 11); no stale count string remains.

## Wave split

- **Wave 1**, four commits planned: (a) the trim (after or with the move of the full file); (b) the helper copy into row 29; (c) the marker and the excludes; (d) the receipt and `po-investigate.sh` drops.
- **Wave 3 tail:** manifest resolver, anchors and count strings.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
