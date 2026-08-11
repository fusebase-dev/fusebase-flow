# Implement handoff — Phase C Slice 2: release-doc + version-propagation backfill

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.6. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-22. **Synchronous; bound long runs; no runaways; STOP at gate; do NOT bump VERSION/push/tag/deploy.** ONE coherent commit stacked on the current HEAD (S1's commit — the Phase C fix stack). Doc/tooling backfill from the Phase C audit — NO protected paths (CHANGELOG/README/docs/release-notes/marketplace.json/PUBLISHING/compatibility + hooks/local/*.sh are all non-`fusebase_flow_internals`), so NO bootstrap approval needed. NEVER `--no-verify`.

## MEMORY (operator standing rules — apply)
- Always spell **"FuseBase"** (two capitals), never "Fusebase", in any NEW prose you write.
- **Re-read `VERSION` immediately before writing any version number** into a public file (must read 3.30.6).

## Findings (Phase C audit — H4/M8/M12/M9/L15/L17/L18/L20; full detail in tasks/wecmxwyrx.output + docs/tmp/handoff/2026-07-03-phase-c-audit-findings-slices.md §Slice 2)
The release-doc chain was skipped for the last 4 releases; version propagation misses a manifest; two tooling checks swallow failures.

## Scope — ONE commit
1. **CHANGELOG.md:** add entries for **v3.30.3, v3.30.4, v3.30.5, v3.30.6** (the latest existing entry is 3.30.2). Follow the existing CHANGELOG format. Reconstruct content from the release commits + the deploy handoffs (docs/tmp/handoff/*deploy.md) + git log:
   - v3.30.3 (tag v3.30.3, release 989604e): Windows/MSYS + adoption-path hardening — 9 workstreams (bounded-run winpid scoping, test-harness reap, health-check verdict + MSYS timeouts, upgrade busy-loop root fix, preflight↔health-check markers, secret-scan/protected-path adoption, zero-trust liveness FR rule, slash-command naming, problem catalog).
   - v3.30.4 (tag v3.30.4, release 37da04f): opt-in Windows Job Object outer fence (`FFHC_USE_JOB_OBJECT=1`, default OFF) around the bounded run; WS5 upgrade-engine root fix (prune_pre_backups single-pass) + critical/optional bounding + the `set -e` optional-step abort fix.
   - v3.30.5 (tag v3.30.5, release 180f4a1): hook-security hardening — the pre-commit FR-07 protected-path (§3) AND FR-12 secret-scan (§2) controls now fail CLOSED at every reachable load-point (delete/rename, import/enum/SystemExit/BaseException/missing-policy fail-opens, trusted-HEAD extraction under `-S`, sitecustomize/usercustomize + CWD-on-sys.path import-shadow close, git-based unforgeable fallback). No mutable working-tree Python can influence any security check.
   - v3.30.6 (tag v3.30.6, release 82c90dc): gate wall-time optimization (test/tooling only — no runtime behavior change; coverage + fail-closed preserved) — FF_ONLY opt-in scoped gates, preflight mirror-hash batching (~6.7× faster), fixture-loop spawn micro-cuts, adaptive sub-second reap poll in the MSYS bounded-run.
2. **docs/release-notes/v3.30.{3,4,5,6}.md:** create one per release, following the format of an existing docs/release-notes/*.md (e.g. v3.26.0.md). Same content as the CHANGELOG entries, expanded.
3. **README.md badge:** bump the version badge from `3.30.2` to `3.30.6` (re-read VERSION first). Fix any other stale version ref in README.
4. **`.claude-plugin/marketplace.json` (M9):** bump `plugins[0].version` (currently ~`3.10.0`, ~20 minor versions stale) to match VERSION (3.30.6). Extend `hooks/local/preflight.sh` §8 version-parity check to ALSO parity-check marketplace.json against VERSION (one more `python3 -c` json read alongside the plugin.json check) — so this can never silently drift again.
5. **sync-version-strings.sh re-mirror rc (L15):** the re-mirror step swallows mirror-script failures + prints unconditional success. Propagate the mirror scripts' exit codes — on nonzero, print a loud `[sync-version-strings] ERROR: re-mirror FAILED — run mirror-skills.sh/mirror-agents.sh manually` and `exit 1`.
6. **PUBLISHING.md / docs/compatibility.md stale expected-outputs (L17/L18/L20):** the "24/24 tests" / "78 mirror files" hardcoded expectations are ~7 minor versions stale (actual: 86 mirror files, 32 skills, 21 test phases). Replace with SELF-DERIVED expectations ("run-tests prints N/N PASS; mirror file count == manifest row count") or a pointer to the live source — do NOT hardcode new counts that will re-stale.

## Do NOT
Do NOT bump VERSION (stays 3.30.6 — this is doc backfill, not a release; the version bump happens at the eventual v3.30.7 deploy). Do NOT touch protected paths / the pre-commit chain / the handlers (S1 owns those). Do NOT push/tag/deploy. Do NOT `--no-verify`.

## Gate (scoped) — stop, report, HALT
preflight green (incl. the NEW marketplace.json parity check — confirm it PASSES with marketplace.json now == 3.30.6, and would FAIL if mismatched); SINGLE `mirror-skills.sh --check` 0-drift; manifest 86/86/0-dups; `bash -n` sync-version-strings.sh + preflight.sh; markdown sanity (no broken refs); check-module-size --all exit 0. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: commit SHA; the 4 CHANGELOG entries + 4 release-notes files added; README badge 3.30.6; marketplace.json 3.30.6 + the new preflight parity check (PASS + would-FAIL proof); sync-version-strings rc-propagation; PUBLISHING/compatibility de-staled; preflight/mirror/manifest clean; VERSION unchanged (3.30.6). Do NOT push/tag/deploy.
