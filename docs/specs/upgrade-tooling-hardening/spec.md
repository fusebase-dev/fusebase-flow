# Spec — upgrade-tooling-hardening

**Status:** DONE — shipped v3.25.0 (2026-06-15). Codex adversarial design review (RESCOPE) folded; HIGH cluster shipped, U6 deferred to follow-up backlog ticket `docs/backlog/adapter-overlay-refresh-parity/`.
**Created:** 2026-06-15
**Baseline:** FuseBase Flow v3.24.0
**Deploy hash:** `6a8961fb603988c0fbfd460fc16a0b65e2c88f85` (release commit, tag `v3.25.0`)
**Source:** TWO independent consumer upgrade reports (v3.21.1→v3.23.1, both Windows/Git-Bash):
- `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-06-15-upgrade-3.21.1-to-3.23.1-friction-report.md` (I1–I9) + proven patch `2026-06-14-windows-hash-spawn-batch-cost.md`
- WorkHub Managed report (W1–W5), commit `2504584`.
**Design review:** Codex 2026-06-15 → **RESCOPE**; biggest risk = **U4 allowlist under-reach** (recreates GEMINI drift in reverse). Folded: executable under-reach guard; U3 widened to all project-state in `policies/` + upstream-baseline-membership merge rule; U1 bounded-copy (preserve manifest contract); U2 portable newline-state preservation + Git-Bash/macOS fixtures + ARG_MAX chunking.

## Problem (grounded)
The 3.23.x **content model is correct + well-guarded**, but the **refresh/upgrade scripts forced manual intervention** on Windows: `upgrade.sh` **stalled mid-mirror** (operator killed it + finished by hand), **churned consumer docs**, and **clobbered a project-state file** (`module-size-baseline.txt`). Two independent projects, same root causes:
- `mirror-skills.sh` + `sync-version-strings.sh` spawn a process **per file**; Windows Git-Bash spawn ≈0.8–1.4s → minutes; sync scans **6,974** `.md` → stall. (I1/W1)
- `sync-version-strings.sh:160` `printf '%s' "$after" > "$f"` **strips the EOF newline** → churned 11 consumer docs. (I2)
- `upgrade.sh:128` `CONTENT_DIRS` includes `policies/`, copied wholesale → **overwrites `policies/module-size-baseline.txt`** (project state) → `check-module-size --all` breaks post-upgrade. (W2)
- `sync-version-strings.sh` prune list misses `docs/product-backlog/`, `problem-catalog/`, `product-execution/`, `client-workflows/` → **rewrites FR refs in consumer historical docs**. (I3/W1)
- `GEMINI.md` **stuck at v2.1** for many releases (regex needs 3-part semver + literal `Fusebase Flow v`; GEMINI ships `Fusebase Flow **Local** v2.1`); GEMINI/copilot/cursor have **no overlay-refresh path**. (I4/I5/W3)
- Upgrade **not atomic / no recovery hint**; health-check doesn't flag "partial upgrade". (W1/W3)
- Windows env: `bash`→unusable WSL bash; GitHub tag fetch fails on schannel (needs `http.sslBackend=openssl`). (W4)
- Hygiene: no progress output; ~70 unpruned `.pre-*` backups (dotfile-hidden); `VERSION` CRLF (no `.gitattributes`); `.fusebase-flow-source/` deploy-lint. (I6–I9/W5)

## What works well (DO NOT regress)
Byte-exact content copy; marker-anchored AGENTS/CLAUDE overlay refresh (preserves project rules + `FLOW:PRESERVE`); `settings.json` untouched; clean new-skill/command install; strong validation suite; VERSION-bumped-last + `main()` self-overwrite guard. **Mirror contract:** `mirror-skills.sh` copies only `SKILL.md`+`references/*` and preflight validates exactly that set — preserve this.

## In scope — HIGH cluster (ship first)
- **U1 (I1) — batch the spawns, copy scope unchanged.** Prime a single `sha256sum`/`shasum` (chunked via `xargs -0 -n N` for ARG_MAX safety) into an assoc-array cache (`${line:0:64}`/`${line:66}`; the repo path contains a space — fixed-offset slicing is space-safe; use `--zero` where available for newline-in-path safety, else declare such paths unsupported). Fork-free loop (`${var##*/}`, direct cache reads, `sdir="${skill_dir%/}"` footgun fix). **Copy scope stays `SKILL.md`+`references/*` per mirror** (NOT a blind `cp -R "$CANON"/.` of whole dirs — preserve the manifest/preflight contract; a batched bounded copy, or per-file copy of just those, is fine). Manifest/drift output **byte-identical**. + progress output (U9).
- **U2 (I2) — portable newline-safe batch in `sync-version-strings.sh`.** Replace per-file `printf '%s' > "$f"` with a **portable newline-state-preserving** rewrite — adopt the consumer's **committed** approach (capture each file's trailing-newline state and restore it), NOT a bare `sed -i` (GNU vs BSD `-i ''` differ; behavior around unterminated final lines / NUL / encoding is unproven). Add a `grep -lE "$SUPERSET_RE"` pre-filter (chunked for ARG_MAX). Fixtures prove EOF-newline preserved for BOTH trailing-newline and no-trailing-newline files (on Git-Bash; macOS noted).
- **U3 (W2) — merge-preserve project state in `policies/`.** `module-size-baseline.txt` merge rule (LOCKED): (1) read local + upstream-source baselines; (2) `flow_owned = paths present in the UPSTREAM baseline`; (3) emit: upstream line-count for each upstream row; **preserve verbatim** each local row whose path is NOT in `flow_owned` (project rows); drop a local Flow row absent upstream (file no longer over ceiling); (4) deterministic sort + standard header; (5) warn (never silently drop) malformed local rows. **Ownership = upstream-baseline membership, NOT path prefixes.** ALSO: `approval-policy.yml:workflow_mode` + `protected-paths.yml worker_undisturbed.paths` carry project state — guard them: require local-only values live in `*.local.yml` (deep-merged by `policy_loader.py`) AND add a policy-state-preserve test; do NOT wholesale-clobber committed project values on upgrade.
- **U4 (I3) — executable framework-owned sync allowlist + under-reach guard.** Replace the broad `find`+prune with `SYNC_ROOTS`/`SYNC_FILES` (in-script, not prose): adapters `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`, `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `.cursor/rules/*.mdc`, `FLOW_RULES.md`, `agents/**/AGENT.md`, `flow-skills/**/*.md`, `workflows/*.md`, `templates/*.md`, `hooks/local/fusebase-flow-overlays/**/*.md`, framework docs (`README.md`, `ROADMAP.md`, `docs/{rail-mapping,architecture-overview,framework,compatibility,fusebase-cli-edition}.md`, install docs); plugin metadata via a **parity check**, not sed. **Under-reach guard (the anti-GEMINI):** a test that scans those roots for syncable tokens and FAILS if any token-bearing framework file is not in the allowlist; a release-time grep that fails on a "framework-looking path not classified" (allowlist vs explicit-historical). Consumer `docs/product-backlog|problem-catalog|product-execution|client-workflows/**` NEVER synced.
- **U5 (I4) — GEMINI version regex:** match `Fusebase Flow (Local )?v[0-9]+(\.[0-9]+){1,2}` so the `Local`/two-part header syncs.
- **U7 (W1/W3, minimal) — atomicity + partial-upgrade signal:** `upgrade.sh` trap → on interruption/failure print the **exact recovery command(s)** (`bash hooks/local/upgrade.sh` re-run / `post-fusebase-update.sh --refresh-overlays` / `sync-version-strings.sh`). Add a **health-check `PARTIAL_UPGRADE` check**: compare derived facts (VERSION, plugin manifest, root + cursor/copilot adapters, canonical agents/workflows/templates/overlays version/FR/skill-count) against the live strings; on mismatch report `PARTIAL_UPGRADE` + the repair command. (Builds on the v3.24.0 health-check engine.)

## In scope — cheap LOWs (fold in; ~free)
- **U9 (I6/W5)** progress output in mirror/sync/upgrade (`mirroring N/31…`, `scanning N files…`) + health-check phase progress.
- **U11 (I8)** `.gitattributes`: `VERSION text eol=lf`, `*.sh text eol=lf`.
- **U8 (W4, docs only)** README/install docs: Git-Bash invocation, detect-unusable-WSL-bash message, `git -c http.sslBackend=openssl` fallback for tag/clone failures.
- **U10 (I7)** `.pre-*` backup retention (keep last N; cover dotfile-prefixed) — if low-risk.

## Deferred to follow-up (per RESCOPE)
- **U6 (I5/W3)** full GEMINI/copilot/cursor **overlay-refresh parity** (marker-anchored blocks + refresh path) — needs a marker strategy design; its own ticket.
- **U12 (I9)** `.fusebase-flow-source/` eslint-ignore (CLI-owned — doc only; `upgrade.sh` may offer to remove the clone on success).

## Decisions (UG1–UG5 — revised per design review, LOCKED)
| # | Decision |
|---|---|
| UG1 | Adopt U1 batching, **but keep the bounded copy scope** (`SKILL.md`+`references/*`, manifest contract) — NOT blind `cp -R`; and U2 uses **explicit newline-state preservation** (consumer's committed approach) — NOT bare `sed -i` — with Git-Bash/macOS fixtures + ARG_MAX chunking. |
| UG2 | U4 = **executable allowlist + a FAILING under-reach guard test** (allowlist, not deny-list — consumer doc roots are unbounded). |
| UG3 | U3 merge-preserve **mandatory**, via **upstream-baseline membership** (not prefixes); widened to other `policies/` project-state (`approval-policy.workflow_mode`, `protected-paths` worker_undisturbed) via `.local.yml` + a policy-preserve test. |
| UG4 | **U5 now** (regex); **U6 follow-up** (overlay-refresh parity needs a marker design). |
| UG5 | **Full lane** — upgrade tooling; a bug strands every consumer. |

## Acceptance criteria
- **AC1** mirror/sync batched: manifest **byte-identical**; mirror `git diff` empty; copy scope still `SKILL.md`+`references/*`; measurably fewer spawns. `bash -n` clean. ARG_MAX-safe (chunked).
- **AC2** A token-bearing file retains its **exact EOF-newline state** after sync (both trailing-newline and no-trailing-newline fixtures pass on Git-Bash); would-change set == pre-change `--dry-run`.
- **AC3 (W2 regression)** A repo with **pre-existing project rows** in `module-size-baseline.txt` → after upgrade those rows are **preserved** and `check-module-size.sh --all` passes; Flow rows updated to upstream; a Flow row dropped upstream is removed locally.
- **AC4 (under-reach guard)** The allowlist test FAILS if a token-bearing framework file (any required root) is omitted; PASSES on the full set. A consumer `docs/product-backlog|problem-catalog|product-execution|client-workflows/*.md` with an `FR-..` string is **NOT** synced.
- **AC5** GEMINI `Fusebase Flow Local v2.1` header syncs to the current version (U5).
- **AC6** `upgrade.sh` interruption prints the exact recovery command(s); health-check reports `PARTIAL_UPGRADE` (stale derived facts) + the repair command (U7).
- **AC7** policy-state preserve: a project `workflow_mode`/`worker_undisturbed` value (in `.local.yml`) survives upgrade; `module-size-baseline` project rows survive (AC3).
- **AC8** `.gitattributes` LF pins (U11); progress output present (U9); Windows docs (U8); `.pre-*` retention prunes dotfile-prefixed (U10, if shipped).
- **AC9** Standard gate: preflight 0/0; run-tests PASS (+ new fixtures); recovery-sim PASS (exercises both refresh scripts — strongest guard); health HEALTHY; mirror drift 0; plugin valid; `internal/`+`repo-polish` untracked; FR-25 all modules < ceiling.

## Tasks (shipped — SHAs)
| Task | What | Commit SHA |
|---|---|---|
| **Ua** | mirror-skills.sh batch, bounded copy, ARG_MAX-safe (U1) + progress (U9) | `b6f31a1` |
| **Ub** | sync-version-strings.sh: prefilter + portable newline-preserving rewrite (U1/U2) + executable allowlist `SYNC_ROOTS` (U4) + Local regex (U5) + progress | `37c6706` |
| **Uc** | upgrade.sh: module-size-baseline + policy-state merge-preserve (U3) per LOCKED rule; trap recovery (U7); `.pre-*` retention (U10); progress (U9) | `8ef5d95` |
| **Ud** | GEMINI regex (U5); `.gitattributes` (U11); Windows env docs (U8); health-check `PARTIAL_UPGRADE` signal (U7) | `382a05e` |
| **Ue** | Tests: AC2 newline / AC3 baseline-merge / AC4 under-reach guard + consumer-doc-not-synced / AC7 policy-state | `dc47042` |
| **Ua-fix** | mirror-skills.sh — survive a plain (non-git) dir run (recovery-sim regression) | `0b2b32d` |
| **Ug-A2** | AC3 baseline-merge — shell-redirection fixture + loud setup asserts (round-2 remediation) | `8c401bd` |
| **Ug-B1** | merge-baseline — document canonicalization (preservation is row-per-path) | `b86d9eb` |
| **Ug-B2** | mirror-skills — temp hash cache via mktemp under TMPDIR + EXIT trap | `899a698` |
| **Uf** | Version bump + sync sweep + release notes + CHANGELOG (the release commit) | `6a8961f` |

Gate → deploy: preflight 0/0 · run-tests 79/79 · check-module-size --all 0 · mirror 0 drift · recovery-sim 31/31 (captured) · probes G-M..G-Q PASS. Tag `v3.25.0`. Codex round-2 confirm SHIP, no findings.

## Notes
- Mostly `mirror-skills.sh`, `sync-version-strings.sh`, `upgrade.sh` + GEMINI + `.gitattributes` + health-check (PARTIAL_UPGRADE) + docs. FR-25: watch sizes; extract along seams.
- The **recovery-sim** is the strongest guard (exercises both refresh scripts) but slow on Windows — verify via targeted fixtures + the suite where feasible (use the v3.24.0 timeout knobs).
- Reactive-shipping: two independent consumer reports → one bounded hardening release.
