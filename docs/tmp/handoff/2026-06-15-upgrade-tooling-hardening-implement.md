# Implement handoff — upgrade-tooling-hardening

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.24.0. Self-attest (FR-01..FR-26), IM.1..IM.18.
Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-13 (preflight per commit), FR-22 (comments), FR-25 (module<800).

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-26 (stop at Amendment log)
2. `docs/specs/upgrade-tooling-hardening/spec.md` — **LOCKED** (the design-review-folded plan; U1–U12, the LOCKED U3 merge rule, the U4 allowlist+guard, decisions UG1–UG5, AC1–AC9). Authoritative.
3. The consumer's **proven patch** (reuse it, don't reinvent): `C:/Users/abcpa/Projects/paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-06-14-windows-hash-spawn-batch-cost.md`
4. The scripts you change: `hooks/local/mirror-skills.sh`, `hooks/local/sync-version-strings.sh`, `hooks/local/upgrade.sh`, `hooks/local/post-fusebase-update.sh`, `hooks/local/fusebase-flow-health-check.sh` (for U7), `policies/module-size-baseline.txt`, `GEMINI.md`.
5. `hooks/local/preflight.sh` (mirror contract it validates), `hooks/shared/module_size.py` (baseline parser), `hooks/shared/policy_loader.py` (`.local.yml` deep-merge).
6. `flow-skills/role-discipline/references/ai-developer.md`.

## Scope = HIGH cluster + cheap LOWs (stop at gate). Defer U6 + U12-apply.
Implement the spec's In-scope HIGH cluster (U1,U2,U3,U4,U5,U7) + cheap LOWs (U9,U11,U8-docs,U10). **DEFER U6** (overlay-refresh parity — follow-up) and U12-apply (CLI-owned; doc only).

### Correctness-critical (get these EXACTLY right — the design review's blockers):
- **U3 merge rule (LOCKED, the W2 fix):** `module-size-baseline.txt` — ownership = **upstream-baseline membership, NOT path prefixes**. Merge: upstream line-count for each upstream-baseline row; **preserve verbatim** local rows whose path is NOT in the upstream baseline (project rows); drop a local row that's in the upstream baseline but no longer present upstream; deterministic sort + standard header; **warn, never silently drop** malformed local rows. ALSO: do NOT wholesale-clobber `approval-policy.yml workflow_mode` / `protected-paths.yml worker_undisturbed.paths` project values — require local-only values via `.local.yml` (deep-merged) + add a policy-state-preserve test.
- **U4 allowlist + UNDER-REACH GUARD (anti-GEMINI):** replace the broad `find`+prune with in-script `SYNC_ROOTS`/`SYNC_FILES` (the exact list in spec §U4). Add a TEST that scans those roots for syncable tokens and **FAILS if any token-bearing framework file is omitted** from the allowlist; and that a consumer `docs/{product-backlog,problem-catalog,product-execution,client-workflows}/*.md` with an `FR-..` token is **NOT** synced.
- **U1 bounded copy (preserve manifest contract):** batch the spawns (single chunked `sha256sum` into assoc cache; fork-free loop; `${skill_dir%/}` footgun) BUT keep the copy scope = `SKILL.md`+`references/*` (NOT a blind `cp -R "$CANON"/.` of whole dirs — preflight validates exactly that set). Manifest **byte-identical**. ARG_MAX-safe (chunk via `xargs -0 -n N`).
- **U2 portable newline-preserve:** replace `printf '%s' > "$f"` with the consumer's **committed** explicit newline-state-preserving approach (capture+restore trailing-newline state), NOT a bare `sed -i` (GNU/BSD differ; unproven on NUL/encoding/unterminated-final-line). `grep -lE` prefilter (chunked). Fixtures: EOF-newline preserved for BOTH trailing-newline and no-trailing-newline files.

### The rest:
- **U5:** GEMINI regex `Fusebase Flow (Local )?v[0-9]+(\.[0-9]+){1,2}`.
- **U7:** `upgrade.sh` trap → print exact recovery command(s) on interruption/failure; health-check `PARTIAL_UPGRADE` signal (compare derived facts — VERSION/plugin/adapters/canonical version+FR+skill-count vs live strings; mismatch ⇒ report + repair command). Build on the v3.24.0 health-check engine; keep its verdict/exit contract intact (PARTIAL_UPGRADE is informational/a drift-class — decide exit mapping consistently; do NOT regress the v3.24.0 exit-4 contract).
- **U9** progress output; **U11** `.gitattributes` (`VERSION text eol=lf`, `*.sh text eol=lf`); **U8** Windows docs (Git-Bash, WSL-bash detection message, `http.sslBackend=openssl`); **U10** `.pre-*` retention (keep last N, dotfile-prefixed) if low-risk.

## Worker-undisturbed (FR-07)
Zero diff to: FLOW_RULES.md FR rule rows; the 3 deploy policies' Flow-owned content (U3 changes how upgrade *handles* policy project-state, not the policy rule semantics); `ratchet-governance.yml`. Don't touch the v3.24.0 health-check verdict/exit contract except adding the PARTIAL_UPGRADE signal.

## Tests (Ue — required)
AC2 newline fixtures (both states); AC3 baseline-preserve regression (pre-existing project rows survive upgrade + check-module-size passes); AC4 under-reach guard + consumer-doc-not-synced; AC7 policy-state preserve. Use targeted fixtures; the recovery-sim is the strongest guard but slow (use v3.24.0 timeout knobs).

## Stop at gate
Per FR-05, stop after Ue. Produce the gate report; HALT. Do NOT push/deploy/bump-version.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ U1 manifest byte-identical + copy scope unchanged  ☐ U3 preserves project baseline rows  ☐ U4 under-reach guard FAILS on omission
☐ FR-25 <800  ☐ check-module-size --all exit 0  ☐ commit cites the task
```

## Notes
- Two independent consumer reports drove this; the proven patch (read #3) de-risks U1/U2. The design review's blockers were U4 under-reach + U3 breadth — the tests (AC3/AC4/AC7) are the proof they're closed. A Codex impl review runs after the gate.
