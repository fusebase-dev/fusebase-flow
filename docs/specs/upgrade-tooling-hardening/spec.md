# Spec — upgrade-tooling-hardening

**Status:** DRAFT (plan for Codex adversarial design review)
**Created:** 2026-06-15
**Baseline:** FuseBase Flow v3.24.0 (after health-check-fast-timeout ships)
**Deploy hash:** N/A — framework/tooling change
**Source:** TWO independent consumer upgrade reports (v3.21.1→v3.23.1, both Windows/Git-Bash):
- `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-06-15-upgrade-3.21.1-to-3.23.1-friction-report.md` (I1–I9) + proven patch `2026-06-14-windows-hash-spawn-batch-cost.md`
- WorkHub Managed report (W1–W5), commit `2504584`.

## Problem
The 3.23.1 **content model is correct and well-guarded**, but the **refresh/upgrade scripts forced manual intervention** on Windows: `upgrade.sh` **stalled mid-mirror** (operator killed it + finished by hand), **churned consumer docs**, and **clobbered a project-state file** (`module-size-baseline.txt`). Two independent projects hit the same root causes. Grounded against HEAD:
- `mirror-skills.sh` + `sync-version-strings.sh` spawn a process **per file**; on Windows Git-Bash each spawn ≈0.8–1.4s (fork emulation + AV) → minutes; sync scans **6,974** `.md` → stall. (I1/W1)
- `sync-version-strings.sh:160` `printf '%s' "$after" > "$f"` **strips the EOF newline** → churned 11 consumer docs. (I2)
- `upgrade.sh:128` `CONTENT_DIRS` includes `policies/`, copied wholesale → **overwrites `policies/module-size-baseline.txt`**, dropping project app rows → `check-module-size --all` breaks post-upgrade. (W2)
- `sync-version-strings.sh` prune list covers `docs/{release-notes,handoff,specs,changes,fusebase-health}` but NOT `docs/product-backlog/`, `problem-catalog/`, `product-execution/`, `client-workflows/` → **rewrites FR refs inside consumer historical docs**. (I3/W1)
- `GEMINI.md` **silently stuck at v2.1** for many releases: version regex needs 3-part semver + literal `Fusebase Flow v`, but GEMINI shipped `Fusebase Flow **Local** v2.1`. And GEMINI/copilot/cursor have **no overlay-refresh path** (only AGENTS.md/CLAUDE.md refreshed). (I4/I5/W3)
- Upgrade is **not atomic / no recovery hint**: a mid-run stall left it partially applied with no printed recovery command; health-check doesn't flag "partial upgrade". (W1/W3)
- Windows env: `bash` can resolve to unusable WSL bash; GitHub tag fetch fails on schannel (needs `http.sslBackend=openssl`). (W4)
- Hygiene: no progress output (stall undiagnosable); ~70 unpruned `.pre-*` backups (some dotfile-hidden); `VERSION` ships CRLF (no `.gitattributes`); `.fusebase-flow-source/` fails deploy lint. (I6–I9/W5)

## What works well (DO NOT regress)
Byte-exact content copy; marker-anchored AGENTS/CLAUDE overlay refresh (preserves project rules + `FLOW:PRESERVE` table); `settings.json` left untouched; clean new-skill/command install; strong validation suite (preflight, health-check, 24/24 hook tests, recovery suite); VERSION-bumped-last + `main()` self-overwrite guard.

## In scope
### HIGH (the upgrade-correctness cluster — ship first)
- **U1 (I1/W1) — batch the spawns** in `mirror-skills.sh` + `sync-version-strings.sh` per the proven patch: one `sha256sum`/`shasum` into an assoc-array cache (parse `${line:0:64}`/`${line:66}`); `cp -R "$CANON"/. <mirror>/` per mirror; fork-free loop using `${var##*/}` (not `$(basename)`) + direct cache reads; **the `sdir="${skill_dir%/}"` trailing-slash footgun fix**; `grep -lE "$SUPERSET_RE"` pre-filter in sync. Manifest/drift output MUST stay byte-identical. + a `bash -n` + timing sanity.
- **U2 (I2) — `sed -i` batch** in `sync-version-strings.sh`: replace per-file `printf '%s' > "$f"` with one `sed -i -E "${SED_ARGS[@]}" -- "${MATCHED[@]}"` (FLOW_RULES range-limited separately). **Preserves the EOF newline** (kills the churn) AND collapses the loop to one spawn. Recover the CHANGED list via path-glob + before/after batch hash for reporting.
- **U3 (W2) — merge-preserve `module-size-baseline.txt`:** treat it as **project state, not a replaceable template**. On upgrade, do NOT overwrite it wholesale from upstream — preserve all project-local rows; only add/update Flow-owned hook-script rows. (Same model as `hooks/local/*.local.*` preservation already in upgrade.sh.) 
- **U4 (I3/W1) — tighten `sync-version-strings` scope:** stop rewriting consumer-owned docs. Restrict the scan to **framework-owned roots** (adapters `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` + the copilot/cursor adapters; `flow-skills/`, `agents/`, `workflows/`, `templates/`, `policies/` Flow files, `hooks/local/fusebase-flow-overlays/`, the framework `README`/`ROADMAP`/`docs/rail-mapping` etc.) — a **bounded allowlist** (W's suggestion) — rather than a broad repo scan with an ever-growing prune list. Consumer `docs/**` product/backlog/history is NEVER touched.

### MED
- **U5 (I4) — GEMINI version regex:** match `Fusebase Flow (Local )?v[0-9]+(\.[0-9]+){1,2}` so two-part / "Local" headers sync (or normalize the GEMINI header to canonical 3-part upstream).
- **U6 (I5/W3) — adapter overlay-refresh parity:** give `GEMINI.md` (and verify `.github/copilot-instructions.md`, `.cursor/rules/fusebase-flow-always.mdc`) a marker-anchored overlay block + refresh in `post-fusebase-update.sh` (same pattern as AGENTS/CLAUDE), so structural drift (e.g. GEMINI's pre-v3.9.0 `skills/` path) is fixable, not just version strings. *(If this balloons, ship U5 now + carve U6 to a follow-up ticket.)*
- **U7 (W1/W3) — atomicity + recovery hint:** on `upgrade.sh` interruption/failure, print the **exact recovery command** (re-run upgrade / `post-fusebase-update.sh --refresh-overlays`); make phases as atomic as practical; health-check detects **"partial upgrade: adapter/version strings stale"** and points to the repair command.
- **U8 (W4) — Windows env friction:** detect an **unusable WSL `bash`** and emit a clear message (use Git-Bash); document the Git-Bash invocation; surface the **`git -c http.sslBackend=openssl`** fallback for tag fetch/clone failures.

### LOW
- **U9 (I6/W5) — progress output:** `mirror-skills.sh`/`sync-version-strings.sh`/`upgrade.sh` emit step/phase progress (`mirroring N/31…`, `scanning N files…`); health-check prints phase-level progress + expected runtime.
- **U10 (I7) — backup retention:** prune old `.pre-upgrade-*`/`.pre-refresh-*` (keep last N), covering **dotfile-prefixed** names.
- **U11 (I8) — `.gitattributes`:** `VERSION text eol=lf`, `*.sh text eol=lf` (kill CRLF churn on copy).
- **U12 (I9) — `.fusebase-flow-source/`:** `upgrade.sh` offers to remove the staging clone on success (the eslint-ignore is CLI-owned — out of Flow's tree; document only).

## Out of scope
- The 3.23.x **content model** (correct — don't touch).
- CLI-owned eslint config (U12 is "offer to remove clone" + doc only).
- FR rule rows / deploy policies / `ratchet-governance.yml` (untouched). NOTE: U3 edits how upgrade *handles* `module-size-baseline.txt`, not the deploy policies.

## Decisions (PROPOSED — for Codex design review)
| # | Decision | Open question |
|---|---|---|
| UG1 | Adopt the consumer's **proven batch patch** for U1/U2 (verified byte-identical, manifest-stable). | Any edge the consumer's verification missed (null-byte handling, ARG_MAX on huge repos)? |
| UG2 | U4 = **bounded framework-owned allowlist** for sync scope (not a growing prune list). | Risk of UNDER-reaching (a real framework file not in the allowlist stops syncing — the I4/GEMINI failure mode in reverse). How to guard? |
| UG3 | U3 merge-preserve `module-size-baseline.txt` (+ any other project-state file under `policies/`?). | Are there other project-state files copied wholesale by `CONTENT_DIRS` that need preserving (e.g. `*.local.yml`, baselines)? |
| UG4 | U6 scope — full GEMINI/copilot/cursor overlay-refresh now, or U5 (version regex) now + U6 follow-up? | How big is the GEMINI overlay-block retrofit? |
| UG5 | Lane: Full (it's the upgrade/recovery tooling consumers depend on; U3/U4 have correctness edges). | — |

## Acceptance criteria
- **AC1** `mirror-skills.sh` + `sync-version-strings.sh` batched: manifest **byte-identical** to pre-change; mirror `git diff` empty; counts unchanged; measurably fewer spawns (timing sanity). `bash -n` clean.
- **AC2** A token-bearing doc retains its **trailing newline** after `sync-version-strings` (no EOF churn); the would-change set matches the pre-change `--dry-run`.
- **AC3 (regression test — W2)** A repo with **pre-existing project rows** in `module-size-baseline.txt` → after upgrade those rows are **preserved** and `check-module-size.sh --all` still passes; Flow-owned hook rows updated.
- **AC4** `sync-version-strings` touches **only framework-owned files** — a consumer `docs/product-backlog/*.md` / `problem-catalog/*.md` / `client-workflows/*.md` containing an `FR-..` string is **NOT** rewritten. (Fixture.)
- **AC5** GEMINI version syncs (U5): a `Fusebase Flow Local v2.1` header is updated to the current version on sync; (U6, if in scope) GEMINI/copilot/cursor overlay blocks refresh structurally.
- **AC6** `upgrade.sh` interruption prints the exact recovery command; health-check reports a **partial-upgrade** signal (stale adapter/version strings) with the repair command.
- **AC7** Windows: unusable-WSL-bash detection message; docs cover Git-Bash + `http.sslBackend=openssl`.
- **AC8** Progress output present (U9); `.pre-*` retention prunes dotfile-prefixed dirs (U10); `.gitattributes` LF pins added (U11).
- **AC9** Standard gate: preflight 0/0; run-tests PASS (+ new fixtures); recovery-sim PASS (exercises both refresh scripts — the strongest guard); health HEALTHY; mirror drift 0; plugin valid; `internal/`+`repo-polish` untracked; FR-25 all modules < ceiling.

## Tasks (rough — firm post-review)
- **Ua** mirror-skills.sh batch (U1) + progress (U9).
- **Ub** sync-version-strings.sh batch + `sed -i` newline-preserve (U1/U2) + allowlist scope (U4) + progress (U9).
- **Uc** upgrade.sh: merge-preserve module-size-baseline (U3); interruption recovery hint + atomicity (U7); `.pre-*` retention (U10); offer remove `.fusebase-flow-source/` (U12).
- **Ud** GEMINI version regex (U5) + adapter overlay-refresh parity (U6, scope-dependent).
- **Ue** Windows env detection + docs (U8); `.gitattributes` (U11); health-check partial-upgrade signal + phase progress (U7/U9).
- **Uf** Tests (AC1–AC8 fixtures, esp. AC3 baseline-preserve + AC4 scope + AC2 newline).
- **Ug** Docs + CHANGELOG + release notes + version bump; mirror.
- Gate → deploy.

## Notes
- Mostly 3 scripts (`mirror-skills.sh`, `sync-version-strings.sh`, `upgrade.sh`) + GEMINI adapter + `.gitattributes` + `post-fusebase-update.sh` + docs. FR-25: watch sizes; extract along seams if any script approaches 800.
- The **recovery-sim test suite** is the strongest guard here (it exercises both refresh scripts) — but it's slow on Windows; verify via targeted fixtures + the suite where feasible.
- Reactive-shipping: two independent consumer reports → one bounded tooling-hardening release.
