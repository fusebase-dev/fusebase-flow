# Changelog

All notable changes to Fusebase Flow. Format follows [Keep a Changelog](https://keepachangelog.com/) (lite). This project follows the conventions in `PUBLISHING.md` for cutting releases.

Public release versions ship as annotated git tags on `main`. Per-version detail lives in `docs/release-notes/v<version>.md`.

## [Unreleased]

## [4.3.2] — 2026-07-10

### Changed — operator-gate friction removed framework-wide · Fixed — mirror robustness + FR-25 `--write-baseline` hardening

Generalizes v4.3.0's deploy-approval ergonomics into one governing rule and closes two robustness gaps flagged by v4.3.1's review. Multi-model adversarial review (Codex gpt-5.6-sol xhigh + a 4-lens Opus-4.8-max / Fable-5 workflow — the safety-regression lens independently confirmed **no self-approval loophole**) caught 2 HIGH + several MEDIUM issues in the first-draft fixes, all closed before ship.

- **Operator Gate Protocol (new; every role loads it).** The operator's only gate/approval action is a decision **in chat**; the **agent** runs every command it requires (mint the FR-07 bootstrap approval, run FR-25 `--write-baseline`, `git add`/`commit`, `--consume`, deploy). The deploy path already worked this way (v4.3.0) — this extends it to FR-07 protected-path adoption and FR-25 baseline adoption, which still printed "operator-run / never agent-initiated" terminal rituals from hook stderr. Keystroke ownership changes, **not** role authority: only the Deploy session runs a Full-lane deploy, only the AI Developer a Lightweight one; PO/Architect never perform side effects. Reworded ~30 carriers (`FLOW_RULES.md` FR-25, the `module-size-discipline` skill, `module_size.py`/`check-module-size.sh`, `write-bootstrap-approval.sh`, `upgrade.sh`/`post-fusebase-update.sh`, `command_policy.py` deny reason, `policies/module-size.yml` + `protected-paths.yml`, both install guides, the health-check family, provider security rules). **No enforcement logic changed** — the git-hook protected-path block, secret scan, and `--no-verify` deny are unchanged; self-approval (acting with no operator authorization, or adopting on the agent's own initiative to dodge a block) stays forbidden.
- **Mirror-manifest robustness.** `mirror-skills.sh` + `mirror-agents.sh` now build the manifest in memory and write it once via a temp-file + atomic rename (no per-row `>>` that two concurrent runs could interleave into duplicate rows — the v4.3.1 CI-drift incident); `mirror-skills.sh --check` now also detects duplicate manifest rows (the hash map silently collapsed them).
- **FR-25 `--write-baseline` HEAD-derivation + fail-closed.** The write target is derived from the HEAD-committed policy (not the worktree), so a worktree `baseline_file:` redirect can't even create a stray file; write-mode **fails closed** (exit 2) when the policy can't be loaded, and the wrapper consumes the engine's printed resolved-path marker instead of independently reparsing the policy — so the staged/mint target can never diverge from where the engine wrote. Containment rejects absolute / Windows-drive-relative / UNC / repo-escaping committed values. New tests: `test-module-size.sh` S11a/b/c + S12 (missing-policy fail-closed) → 21/21.
- **Problem-catalog.** Filed `gate-command-operator-friction` (the deploy-only fix was never generalized).

Protected-path edits: FR-25 text (`FLOW_RULES.md`), `hooks/**`, `policies/*.yml` — all intentional; no approval-enforcement logic changed. The shipped `policies/module-size-baseline.txt` header was refreshed to match the generator (also drops one genuinely-stale row — `fusebase-flow-health-check.sh`, now 764 ≤ ceiling).

## [4.3.1] — 2026-07-10

### Fixed — FR-25 `--write-baseline` refuses to clobber a non-baseline file (redirect-DoS)

Closes the residual deferred from v4.3.0's review: `module_size.py --write-baseline` derives its target from the (worktree) policy `baseline_file`, so a tampered worktree `policies/module-size.yml` (e.g. `baseline_file: policies/approval-policy.yml`) could make it overwrite an arbitrary file with baseline text — a recoverable but real DoS. Now `--write-baseline` refuses (exit 2) to write when the target exists and is NOT a module-size baseline (does not start with the `# FR-25 module-size baseline` header); a first write (absent target) or a legitimate re-write (header present) proceeds. v4.3.0's self-approval fix (HEAD-derived, fail-closed mint scope) already prevented the *approval* from being redirected; this closes the file-overwrite half. Test: `hooks/tests/test-module-size.sh` S11.

## [4.3.0] — 2026-07-10

### Changed — FR-25 delta-aware adoption + deploy-approval ergonomics · Fixed — cross-platform mirror determinism

Two consumer-reported upgrade-friction defects and a CI-flake root cause, closed under a multi-model adversarial review (Codex / Fable 5 / Opus 4.8-max) that caught and fixed **three** successive real security holes in the first-draft fixes before ship.

- **FR-25 delta-aware ratchet (upgrade adoption).** Enabling the module-size ratchet on an existing repo no longer hard-blocks the first touch of a pre-existing monolith: in a change gate (`--staged`/`--worktree`) a PRE-EXISTING over-ceiling file (over the ceiling at HEAD, not baselined) may be **touched or shrunk** — only NEW-over-ceiling files and GROWTH block; `--all` stays an absolute audit. A renamed-and-grown monolith still blocks (`--no-renames`), and a symlink→file typechange still blocks (`--diff-filter=ACMT`). Zero impact on the framework's own gating (its two over-ceiling files are baselined).
- **Smooth FR-07-sanctioned adoption, fail-closed.** `check-module-size.sh --write-baseline` (operator-run) auto-mints the single-use FR-07 approval for the protected baseline — but **fail-closed**: it mints only after affirmatively verifying (env-passed, injection-proof) that the baseline is the sole staged protected path, and it derives the baseline path from the **committed** policy (HEAD) so a worktree edit can't redirect the mint. Any failure refuses and prints the manual steps. Closes the FR-25 ↔ FR-07 circular dead-end.
- **Deploy-approval ergonomics (FR-12 / DP.1).** After the operator types the DP.6 phrase `APPROVE-DEPLOY-NOW`, the Deploy session **authors every required approval artifact on the operator's behalf** (`production_deploy` + any `database_migration` / `auth_or_permission_change` / `protected_path_edit`) — for ALL tickets, never forcing the operator to run terminal commands after they've approved in chat. Safety boundary preserved: authoring WITHOUT the phrase is self-approval and forbidden; the full scope is presented in chat before the phrase, and an action not presented is not covered. Swept consistently across `role-discipline/deploy.md`, `release-deploy-reporting`, `ai-developer` AGENT, `greenlight-deploy`, the canonical `templates/handoff-deploy.md`, the `approval-policy.yml` comment, and the Cursor/Copilot security instructions. **Enforcement (`command_policy.py`) unchanged** — this is a discipline change (the gate never checked the artifact's author).
- **Cross-platform mirror determinism.** `mirror-skills.sh` + `mirror-agents.sh` emit their manifests under `LC_ALL=C sort`, so a Windows regen and Linux CI produce byte-identical order (fixes the v4.2.2 mirror-drift CI flake); `mirror-agents.sh` rejects unknown args.
- **Problem-catalog.** Filed `fr25-upgrade-adoption-collision` and `deploy-approval-terminal-friction`.

Protected-path edits: FR-25 text (`FLOW_RULES.md`), `hooks/shared/module_size.py` (delta logic), `policies/approval-policy.yml` (comment) — all intentional; no approval-enforcement logic changed.

## [4.2.2] — 2026-07-09

### Fixed — third-reviewer (Opus 4.8 max) findings on v4.2.1 + MAX_PATH manifest hardening

An independent Opus 4.8 (max-effort) confirmation pass over v4.2.1 found it functionally sound but caught two follow-ups both prior reviewers (Codex xhigh, Fable 5) missed, plus Fable 5's deferred manifest fix now lands.

- **Completed the lock-vocabulary sweep.** v4.2.1 claimed "no fictional `Locked: yes`", but that sweep used a `*.md`-only grep and missed non-`.md` surfaces: `.cursor/rules/fusebase-flow-specs.mdc` (a condensed mirror of `communication`'s Mode-B principles) and `docs/specs/delegation-resilience/spec.md` still carried the removed marker. Both now use `Lock status: LOCKED`; a repo-wide grep across ALL file types confirms zero real occurrences remain.
- **MAX_PATH manifest coverage (`hook_manifest.py`).** On Windows with long paths disabled, `collect_assets()` silently dropped covered files whose absolute path exceeded ~260 chars — `pathlib.is_file()` swallows the `WinError 3` to `False`, so an over-limit covered file vanished from the manifest at stamp time with no error (a latent coverage/tamper-detection hole; end-user verify already fails closed via a loud DRIFT). Fixed at the root with a Windows extended-length (`\\?\`) resolved-root helper applied at all four stamp/verify entry points. Byte-identical manifest at normal depths (D1 preserved); also removes a spurious DRIFT false-positive at deep consumer installs.

Known / tracked (design-first spec planned, NOT in this release): the **FR-25 upgrade-adoption gap** — v4.2.0 enables the module-size ratchet and ships a non-empty baseline (Flow's own two files), which defeats the "warn-only while no baseline" grace for a consumer with pre-existing over-ceiling files; and the FR-25 "re-key the baseline" remedy self-collides with FR-07 (`policies/module-size-baseline.txt` is a protected path). Consumer workaround meanwhile: operator-run `check-module-size.sh --write-baseline` + a bootstrap approval for the commit.

## [4.2.1] — 2026-07-09

### Fixed — adversarial-review hardening: test rigor + skill build-correctness

A multi-model adversarial pass (Codex `gpt-5.6-sol` xhigh + Fable 5) over the v4.2.0 work and the `flow-skills` catalog surfaced tests that passed without pinning their contract, plus skill matcher/body inconsistencies. All closed; each tightened test is regression-proven (reverting the code it guards makes it fail).

- **Release-gate integrity.** `run-tests.sh` now exits boolean (`fail>0 ⇒ 1`) instead of `exit $fail` — 8-bit truncation meant exactly 256 failures exited 0, so CI (which judges the step by exit code) could go green with 256 real failures.
- **Fixture coverage can no longer silently vanish.** `run_hook_tests.py` treats malformed-JSON / missing-`_handler` fixtures as FAIL (was silent SKIP), enforces an expected-fixture floor (21) in both normal and `--compare-subprocess` modes, and fails `--compare-subprocess` on an in-process handler crash BEFORE the parity check (previously identical crashes reported "parity 21/21 identical" and exited 0).
- **`--run-hook-tests` deep diagnostic no longer under-reports a crash.** The full path requires `rc==0` alongside a strict `N/N PASS` (a PASS line then a signal/nonzero exit is BROKEN, matching the main engine); the MSYS fast path flags any nonzero rc and treats empty `0/0` output as broken. New permanent, platform-independent regression tests (`mv_deeprun_unit_*` in `test-health-check-timeout.sh`) lock the contract.
- **Test rigor.** `test-hook-manifest.sh` now locks the covered-set contract (asserts `.jsonl` inclusion, `*.local.*`/`__pycache__` exclusion, and a deleted listed file ⇒ DRIFT); `test-bootstrap-exception.sh` scenario 8 asserts the masked git lists the staged file, the python3-absent path is non-blocking (`NOPY_RC==0`), and matches the EXACT non-enforcement warning (was a loose `python3|FR-07` grep a hard-block could satisfy).
- **Skill build-correctness (Fable 5 catalog rating).** `client-vs-internal` — the operator-explicit trigger is now reachable end-to-end (skill body, `requirements-specification` consumer gate, `README`, `audience.md`); `communication` — description/anti-pattern reflect the v2.9.0 `references/patterns.md` lazy-load; `comment-policy` — FR-22 reference de-brittled; spec-status + lock vocabulary across `code-review`/`implementation-planning`/`task-delegation`/`requirements-specification`/`communication`/`templates/spec.md` aligned to the real `decisions.md` convention (`Lock status: LOCKED`; no fictional `Locked: yes`); `business-logic-guardian` — mandated impact-verdict block emitted AFTER the code check; `fusebase-flow-health-check` — `PARTIAL_UNVERIFIED` surfaced + `risk_level` normalized; worked examples added to the two materially-changed skills.
- **Problem-catalog.** `ci-linux-msys-test-divergence` root cause corrected (git-less pre-commit exits at the top `git rev-parse` guard, not `git diff --cached`); `transient-subagent-retry-discipline` extended with the non-rate-limit silent-wedge failure mode + poll-every-turn / self-verify-from-source discipline.

No FR-07 protected logic changed (handlers / shared / git hooks / policies / `FLOW_RULES.md` untouched except the version banner). Manifest re-stamped; skill mirrors re-synced (0 drift). Known deferred: `hook_manifest.py` `collect_assets` silently omits covered files whose absolute path exceeds Windows `MAX_PATH` (harmless at normal install depths; pre-existing).

## [4.2.0] — 2026-07-09

### Added — hook-layer manifest verification + single-process test runner (`hook-manifest-verify`)

Windows/Git-Bash operators can reach full **HEALTHY** without the fork-heavy hook-test suite, and GitHub Release publication is gated in-repo on the full verify suite.

- **Manifest-verify critical.** The health check's hook-test CRITICAL is replaced by a **byte-stable** content-hash manifest of the Flow-owned hook layer (`audit/hook-layer-manifest.json`, committed, NO timestamps — a pure function of covered bytes + `VERSION`). `bash hooks/local/verify-hook-manifest.sh` is a seconds-long, OS-independent hash compare (exit `0/1/2/4` = MATCH/DRIFT/BROKEN/ABSENT; exit 3 reserved) that also catches local tampering. Full HEALTHY / exit 0 is now reachable on stock Win11 + Git-Bash (< 60 s). Two DRIFT scans flag injected extras (import-adjacent `hooks/handlers|shared/*.py`; recursive `sitecustomize.py`/`usercustomize.py` anywhere under `hooks/`). New: `hooks/local/lib/hook_manifest.py`, `stamp-hook-manifest.sh`, `verify-hook-manifest.sh`, and the sourced engine lib `hooks/local/lib/hook-integrity-check.sh`.
- **Single-process fixture runner.** `hooks/tests/run_hook_tests.py` imports each handler and drives `main()` in-process (same 21 fixtures + assertions as the retired fork-per-case loop); `--compare-subprocess` proves in-process ≡ subprocess for the **(exit_code, decision, rule_id)** triple — 21/21 on MSYS and in CI. The MSYS fixture phase drops from minutes to ~0 s. Handlers/shared unmodified (FR-07).
- **Two new default-suite phases.** `test-git-hooks-smoke.sh` (git-wrapper smoke) and `test-hook-manifest.sh` (stamp/verify self-test); the default `run-tests.sh` is now a strict SUPERSET (24 tags) with per-phase `took Ns` timing on stderr.
- **In-repo release gate.** `.github/workflows/fusebase-flow-verify.yml` becomes reusable (`workflow_call:`) and gains runner-parity + manifest-freshness steps; NEW `.github/workflows/fusebase-flow-release.yml` publishes the GitHub Release only via a `publish` job gated `needs: verify` — a red suite ⇒ no Release for that tag. Manual `gh release create` is forbidden; `PUBLISHING.md` § Release prerequisites documents the `v*` tag-ruleset + `main` branch-protection backstops.
- **Optional deep run (platform-adaptive).** `--run-hook-tests` runs the FULL `run-tests.sh` on POSIX/Linux/macOS and, on MSYS/Git-Bash, a FAST subset (single-process fixtures + git-smoke + hook-manifest self-test) completing **< 120 s** (measured ~52 s end-to-end) — the AC3 resolution for Windows, where the full suite is ~950–1085 s under MSYS spawn overhead. `--run-hook-tests-full` / `FFHC_RUN_HOOK_TESTS_FULL=1` forces the full suite on MSYS too. Observed FAIL/crash ⇒ BROKEN; timeout/skip ⇒ NOTE only (never forces PARTIAL). The DEFAULT `run-tests.sh` + CI stay FULL and unchanged (CI Linux is the authoritative full-suite proof).
- **Upgrade propagation.** `upgrade.sh` carries `audit/hook-layer-manifest.json` in its copy-set (with an `audit/` mkdir guard) so consumers pick up integrity verification with no manual step.

## [3.30.7] — 2026-07-04

### Fixed — Phase C Fable whole-system audit fixes (live enforcement fires + fail-closed tooling + po-investigate hardening + release-doc/consistency)

**PATCH (enforcement-liveness fix; makes several SHIPPED gates actually fire in live Claude Code sessions).** Phase C = an independent Fable whole-system audit (9 subsystems) → 40 findings → 6 Opus-implemented fix slices (S1/S2/S4/S5/S6) + S1b (deploy-gate review close). No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged). The v3.30.5 fail-closed FR-07 §3 / FR-12 §2 pre-commit chain (`hooks/git/pre-commit` + `hooks/shared/**`) is UNTOUCHED (empty diff 82c90dc..HEAD; verified by both reviewers across the whole stack). The consolidated adversarial review (Codex + a 3-lens Opus panel) converged SHIP.

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved).

- **(S1) CRITICAL — live enforcement was inert (`4acb535`).** The `UserPromptSubmit` + `Stop` handlers read Flow-schema keys (`user_prompt`/`agent_message`) the Claude Code runtime never sends (it sends `prompt`/`transcript_path`), with no normalization shim — so the FR-12 pasted-secret warning, bypass detection, `/product-owner` reminder, and the FR-04/05/14 done/deploy-complete deny gate never fired on real prompts (the suite was green only on synthetic fixtures). Fix: handlers read the native shapes (dual-key `prompt`; parse the final assistant message from `transcript_path`); warns via `hookSpecificOutput.additionalContext`, denies via stderr. **No gate weakened — the deny/warn logic is unchanged; only the input source was fixed.** New native-shape fixtures close the synthetic-only coverage gap.
- **(S4) fail-closed tooling (`9424df8`).** preflight skill-frontmatter + orphaned-approval checks now actually fail the exit code (a pre-`$?` `|| true` had made them false-clean); the health engine reads a completed run-tests with visible INCONCLUSIVE rows as UNVERIFIED (not false-BROKEN) while a genuine crash still BROKEN; verify-gate runs from any subdirectory.
- **(S5) po-investigate hardening (`1523a86`).** The PO read-only investigation wrapper (`po-investigate.sh`) now refuses git write/exec escapes (`--output`, `--ext-diff`/`GIT_EXTERNAL_DIFF`, `-c *.external`, pager) + scrubs the env — the read-only guarantee is now structural.
- **(S2) release-doc backfill (`92135f4`).** Backfilled the release-doc chain (CHANGELOG + release-notes for v3.30.3–v3.30.6, README/marketplace badges) + a marketplace.json version-parity preflight check.
- **(S6) doc/rule/path consistency (`eb50078`).** Doc/rule-text/path consistency sweep (the v3.9.0 `skills/`→`flow-skills/` rename residue, FLOW_RULES status/labels, rail-mapping hook-claims, catalog counts, dangling rule-IDs) — docs/text only, no enforcement change.
- **(S1b) Stop fail-closed edge (`9790c90`).** The consolidated deploy-gate review (Codex) found + closed a corner-case in S1: the Stop done/deploy gate fell open when the transcript was corrupt/wrong-shape/format-drifted (the final assistant message couldn't be extracted) even though the raw transcript contained a done-claim. `stop.py` now FAILS CLOSED there (deny "could not verify — unverifiable transcript") without re-introducing over-trigger in the normal path. No worse than baseline; now a hard-closed edge.

Verified: preflight 0/0 (incl. marketplace.json parity) · mirror-skills 32 skills / 0 drift · mirror-agents 0 drift · manifest 86/86/0-dups (before AND after sync) · plugin.json == marketplace.json == VERSION == 3.30.7 · the v3.30.5 pre-commit security chain UNTOUCHED. Deploy smoke (LIGHT — loaded-host discipline): preflight 0/0 + health-check + tag/release verification. Consumer-verify (POST-release): full `run-tests.sh` on a quiet MINGW64 box (incl. `test-po-investigate` + native-shape fixtures) + confirm the live hooks fire on real Claude Code events. Release commit `aabbadc` (tag `v3.30.7`). Detail: `docs/release-notes/v3.30.7.md`.

## [3.30.6] — 2026-07-03

### Changed — gate wall-time optimization (FF_ONLY scoped gates + preflight batch + adaptive reap poll)

**PATCH (test/tooling only — no runtime behavior change; coverage + fail-closed preserved).** Phase B of the operator's optimization mandate: the saturated-host gate is ~90% of session wall time, so this release cuts gate wall-time without touching any runtime behavior. No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged). The v3.30.5 fail-closed FR-07 §3 / FR-12 §2 pre-commit chain (`hooks/git/pre-commit` + `hooks/shared/**`) is UNTOUCHED. Independently reviewed (Codex + a 3-lens Opus panel): no coverage loss, no fail-closed/security weakening; the 13 full-gate FAILs are pre-existing host-saturation artifacts (reproduce identically on the baseline), not regressions.

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved).

- **FF_ONLY opt-in scoped gates (F2).** `run-tests.sh` gains `FF_ONLY` — run only named suites during the implement loop. Unset ⇒ byte-identical full gate. Scoped ⇒ fail-closed by construction: the scoped summary deliberately fails the strict `N/N PASS` classifier, writes a separate results file, and exits 2 on an unknown/empty tag, so a scoped run can never be mistaken for a clean full pass. New `test-ff-only.sh` suite guards the contract. The final pre-commit / pre-deploy gate MUST still be a full unscoped run.
- **preflight mirror-hash batching (F4).** Preflight now runs one `sha256sum` per root instead of ~270 per-file spawns (~6.7× faster preflight; repairs the default health-check preflight budget). Drift/missing detection is byte-identical.
- **spawn micro-cuts (F5).** Fixture hot-loop spawn cuts — builtin file reads + a metadata pre-pass replace per-fixture `$(echo|sed)`/python invocations.
- **adaptive sub-second reap poll (F3).** The MSYS bounded-run reap loop uses a spawn-free FIFO nap ladder with `EPOCHREALTIME` accounting — the deadline is preserved as a hard FLOOR (never reaps early), falling back verbatim to the prior `sleep 1` on any host without the builtin nap.

Verified: preflight 0/0 · `check-module-size --all` exit 0 · mirror 0 drift (32 Flow skills) · manifest 86/86/0-dups · plugin == VERSION == 3.30.6 · README badge 3.30.6 · the v3.30.5 pre-commit security chain UNTOUCHED (`hooks/git/pre-commit` == source) · `git grep -ni headroom` in code = 0. Deploy smoke (LIGHT — full `run-tests.sh` deferred to a quiet MINGW64 box per the loaded-host discipline): preflight 0/0 + health-check + tag/release verification. Consumer-verify (POST-release): full `run-tests.sh` on a quiet box (test count ≥ pre-change; the FAIL set is the known host-saturation class) + an `FF_ONLY` scoped run. Release commit `82c90dc` (tag `v3.30.6`). Spec: `docs/tmp/handoff/2026-07-03-v3306-fable-optimization-spec.md`. Detail: `docs/release-notes/v3.30.6.md`.

## [3.30.5] — 2026-07-03

### Changed — hook-security hardening (FR-07 protected-path + FR-12 secret scan fail CLOSED at every load-point)

**PATCH (security hardening; fixes a SHIPPED FR-07 protected-path bypass found by the whole-roadmap review).** No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged). Both pre-commit security controls — the FR-07 §3 protected-path guard AND the FR-12 §2 secret scanner — now FAIL CLOSED at every reachable load-point: no mutable working-tree Python (code, patterns, startup file, env var, or import path) can influence any security check. Converged over TEN adversarial rounds; the final deploy-gate confirm was SHIP from two independent reviewers (Codex companion, zero findings + a 3-lens Opus panel, RED→GREEN PoCs, all SHIP).

**FR-07-clean:** the enforcement code is hardened; no FR rule rows changed, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved).

- **Staged delete / rename coverage.** The protected-path check now covers staged DELETES (`git rm`) and RENAMES of protected files (was `--diff-filter=ACM` only), via `path_policy.staged_change_paths` (A/C/M→path, D→deleted, R→old+new); the single-use digest-bound exception is extended to delete/rename, never weakened.
- **Import / enumeration / exception fail-opens closed.** Import error (e.g. missing PyYAML) ⇒ BLOCK with an FR-07 diagnostic (was silent fail-open); missing python3 ⇒ loud WARN; enumeration failure ⇒ BLOCK (was silent []-pass); `BaseException`/`SystemExit(0)` from a tampered module ⇒ BLOCK; `git name-status` nonzero rc ⇒ raise/BLOCK.
- **Policy-present + additive-only override.** Missing/empty/malformed `protected-paths.yml` ⇒ BLOCK (was a total FR-07 disable); `protected-paths.local.yml` can no longer erase/relax protected categories (additive-only).
- **Trusted-HEAD enforcement.** The check runs FR-07 (and, in `-S`, the FR-12 scanner + its patterns) from a TRUSTED committed HEAD copy extracted into a fresh `mktemp` dir, under `python3 -S` with a scrubbed env (`unset PYTHONPATH/PYTHONSTARTUP/PYTHONHOME`, `PYTHONNOUSERSITE=1`), with the trusted-vs-fallback decision made by git (unforgeable). Closes the mutable-Python load-point class: staged/unstaged tamper, `sitecustomize.py`/`usercustomize.py` startup injection, a hostile `PYTHONPATH`, and (the deepest tail) a repo-root `pathlib.py`/`yaml.py` that shadows a stdlib/site import when CWD is on `sys.path[0]` under `python3 -S -` — fixed by running the §2/§3 MAIN checks as trusted FILE SCRIPTS from the temp dir (CWD never added), plus `PYTHONSAFEPATH=1` and prepend-site-packages. Also converts the `$(git ls-tree)` sentinel loops to file-redirect to end an intermittent MSYS command-substitution hang.
- **Hook-install call-site rc.** No silent "installed" on failure.

Accepted out-of-model residuals (a discipline guardrail cannot mechanically stop these): `--no-verify` (rule-forbidden), deleting/replacing `.git/hooks/pre-commit`, a full repo write bypassing the hook, or writing into real site-packages / OS-git-python compromise.

Verified: preflight 0/0 · `check-module-size --all` exit 0 · mirror 0 drift (32 Flow skills) · manifest 86/86/0-dups · plugin == VERSION == 3.30.5 · README badge 3.30.5 · `.git/hooks/pre-commit` == source · bootstrap-exception 22/22, hook-install-rc 7/7 (single-use NOT weakened) · `git grep -ni headroom` in code = 0. Deploy smoke (LIGHT per the loaded-host discipline): preflight 0/0 + health-check + tag/release verification. Ticket smoke: a real protected delete/rename blocked; a tampered-enforcer / repo-root-`pathlib.py` PoC no longer self-passes (RED→GREEN end-to-end). Consumer-verify (POST-release): full `run-tests.sh` on a quiet MINGW64 box + a protected delete/rename commit on a wired-hook clone. Release commit `180f4a1` (tag `v3.30.5`). Detail: `docs/release-notes/v3.30.5.md`.

## [3.30.4] — 2026-07-02

### Changed — WS2-hard opt-in Windows Job Object fence + WS5 upgrade bounded exit

**PATCH (default behavior byte-unchanged from v3.30.3 — the Job Object fence is opt-in, default OFF).** The final two workstreams of the Windows/MSYS hardening roadmap. No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged). Three review passes on the corrected diff (Codex full BLOCK→fixed, Workflow BLOCK→fixed, Codex re-review SHIP) — all findings folded.

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved).

- **WS2-hard — opt-in Windows Job Object outer fence.** `FFHC_USE_JOB_OBJECT=1` (default OFF) wraps the bounded run in a Windows Job Object outer fence — an atomic, strictly-scoped kill of the assigned child tree. The mechanism is proven on MSYS+PowerShell; the reliability discriminator (Cummings-class ac3d→rc137; Job-Object vs `timeout -k` kill) is CONSUMER-GATED (best-effort launch→assign race documented). Default behavior is unchanged from v3.30.3.
- **WS5 — upgrade engine Windows-safe bounded exit.** `prune_pre_backups` busy-loop ROOT FIX (per-stem full-tree find → single-pass O(M)); critical-vs-optional bounding (an optional step's failure/timeout warns and continues, a critical step fails with a recovery hint); timestamp-safe prune glob.
- **Review corrections.** Fence opt-in hang fix; the `set -e` optional-step abort fix, now tested under `set -e`.

Verified: preflight 0/0 · `check-module-size --all` exit 0 · mirror 0 drift (32 Flow skills) · manifest 86/86/0-dups · plugin == VERSION == 3.30.4 · README badge 3.30.4 · `git grep -ni headroom` in code = 0. Deploy smoke: preflight 0/0 + health-check (`PARTIAL_UNVERIFIED` known-benign on the saturated host) + tag/release verification. Consumer-verify (operator distributes): full `run-tests.sh` on a quiet MINGW64 box; `FFHC_USE_JOB_OBJECT=1` validation on a real Cummings-class host; full `upgrade.sh --auto-yes` end-to-end. This release COMPLETES the roadmap (all 9 workstreams shipped across v3.30.3 + v3.30.4). Release commit `37da04f` (tag `v3.30.4`). Detail: `docs/release-notes/v3.30.4.md`.

## [3.30.3] — 2026-07-01

### Changed — Windows/MSYS + adoption-path hardening (WS1-WS9)

**PATCH (Windows/MSYS hardening across nine workstreams + adversarial-review corrections).** No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged). Two independent adversarial reviews (Codex + FuseBase workflow) of the full corrected diff returned SHIP; all findings folded.

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved).

- **WS1 — secret-scan + protected-path adoption.** Secret-scan handles runtime tokens; a single-use digest-bound protected-path exception + a safe git-hook (re)install path.
- **WS2-core / WS3 — MSYS bounded run + harness.** Strict winpid scoping for the MSYS bounded run; test-harness reap; the fixture-phase stdin fix so the fixture phase completes under the bounded wrapper.
- **WS4 — health-check verdict robustness + MSYS timeout defaults.** A killed/unparseable hook-test run reclassifies to an advisory verdict instead of a false BROKEN; MSYS-tuned timeout defaults.
- **WS6 — backward-compatible dual-marker migration.** The overlay heading marker accepts the legacy `## Fusebase Flow —` and the new `## FuseBase Flow —` form (preflight ⟷ health-check agree).
- **WS7 — problem catalog.** `docs/problem-catalog/` seeded as the recurring-problem record of truth.
- **WS8 — zero-trust liveness (FR-27 extension).** The zero-trust sub-agent liveness rule (poll git-progress, never passively wait) codified.
- **WS9 — slash-command naming.** Command naming aligned.
- **Review corrections.** Glob-bypass close, unique hook marker, trap re-verify, test fidelity.

Verified: preflight 0/0 · `check-module-size --all` exit 0 · mirror 0 drift (32 Flow skills) · manifest 86/86/0-dups · plugin == VERSION == 3.30.3 · README badge 3.30.3 · the POSIX `run_with_timeout` path preserved · `git grep -ni headroom` in code = 0. Deploy smoke: preflight 0/0 + health-check + tag/release verification. Consumer-verify (operator distributes): full `run-tests.sh` on a quiet MINGW64 box — the fixture phase now passes under the bounded wrapper. Release commit `989604e` (tag `v3.30.3`). Detail: `docs/release-notes/v3.30.3.md`.

## [3.30.2] — 2026-06-30

### Changed — secret-scan self-trip + MSYS bounded-run hang/false-BROKEN fixes

**PATCH (fixes two consumer-reported Windows/MSYS bugs; additive/advisory).** No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged); the FFHC **verdict ENUM + exit codes (0/2/3/4) are UNCHANGED**, the `ffhc_*` API + rc(124/137) are preserved, and the **POSIX `run_with_timeout` path is byte-identical** to v3.30.1. Root cause corrected by real MINGW64 consumer field evidence. Dual-reviewed: Codex design ×2 (RESCOPE folded) + FuseBase impl (SHIP) + Codex final (BLOCKER fixed) + **Codex re-validation (SHIP, no regressions)**.

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved). Health-check stays **read-only**.

- **Bug A — pre-commit secret-scan self-trip.** `hooks/git/pre-commit` (via new `hooks/shared/staged_secret_scan.py`) now scans only **added (`+`) lines** and path-excludes the scanner's own designed-token files (`policies/secret-patterns.yml`, `.local`, `hooks/tests/fixtures/`). `secret_scanner.scan()` is unchanged; **no whitelist needed** (avoids the fixture-breaking trap). A Flow upgrade that edits `secret-patterns.yml` no longer BLOCKs; a real secret on a `+` line in a normal file still blocks; fixtures 10/11 still detect. Two consumers corroborated. Misleading "just whitelist it" guidance stripped; the excluded-file gap + the PreToolUse write-limitation documented.
- **Bug B — MSYS bounded-run hang (B1) + health-check false-BROKEN (B2), one root cause.** On MINGW64 a pipe-holding native grandchild survives POSIX `timeout` cleanup → any bounded `$(…)` capture blocks past the deadline (B1) and surfaces an unrecognized rc → non-deterministic false BROKEN (B2). Fix: **tempfile capture** at `ffhc_run_bounded` + the conflict reporter (guaranteed anti-hang — the parent never starves a pipe; robust template + fail-to-SKIP, never false BROKEN) + **MSYS best-effort process-tree kill** (winpid captured at launch → `taskkill //F //T` on timeout) to reap native runaways. **POSIX `run_with_timeout` byte-unchanged.** Health-check reclassifies a killed/unparseable hook-test run (no `FAIL:` + no strict PASS + `rc==124||rc>=128`) to advisory `HOOK_TESTS_INCONCLUSIVE` → `PARTIAL_UNVERIFIED` (exit 4), with a no-strict-PASS guard so a crash-after-PASS stays BROKEN (exit 2). `--skip-hook-tests` alias for `--fast` (Windows escape); `upgrade.sh` Step 2 progress echoes. Honest limit: the MSYS tree-kill is BEST-EFFORT (Windows doesn't reparent orphans) — the tempfile capture is the guaranteed anti-hang.
- **Docs / tests.** New `test-secret-scan-staged.sh` (8) + `test-msys-tree-cleanup.sh` (6) wired into `run-tests.sh`; `test-health-check-timeout.sh` gains the B2 RED-then-GREEN trio; the AC3d MSYS-guard dropped (already passes on all platforms); `run-with-timeout.sh` lib seam extracted.

Verified: preflight 0/0 · `bash -n` on all changed shells OK · **POSIX `run_with_timeout` byte-identical** (SHA-256 `a9ec76d9…`) · `ffhc_*` API + rc(124/137) + verdict ENUM + exit codes intact · `check-module-size --all` exit 0 · mirror 0 drift (32 Flow skills) · plugin == VERSION == 3.30.2 · **GEMINI.md = v3.30.2** · README badge 3.30.2 · the 5 FR-07 surfaces UNCHANGED · `git grep -ni headroom` in code = 0. Gate (host CPU-saturated — proven green via targeted bounded per-phase runs, 0 FAIL each): JSON **16/16**, module-size **8/8**, health-check-timeout HT1-12+spoof **20/20**, **B2 trio 3/3**, secret-scan **8/8**, msys-tree **6/6**, liveness/AC3d (rc 137) + FFHC API green, bootstrap-hop **13/13**. Ticket smoke: Bug A (edit-not-blocked + real-secret-still-blocks + fixtures 10/11); Bug B (native-descendant returns at deadline 4s≤6s, rc 124 preserved, tempfile 4s < pipe 8s; B2 trio exit 4/2/2). **Consumer re-test is POST-release** (D-VALIDATION — operator chose "ship now"). Feature commits `83b15f5..a7735a1`. Spec: `docs/specs/secret-scan-and-msys-liveness-fix/spec.md`. Detail: `docs/release-notes/v3.30.2.md`.

## [3.30.1] — 2026-06-30

### Changed — health-check baseline + custom-flag hardening (advisory-only)

**PATCH (hardening, advisory-only).** Closes the two non-blocking follow-ups filed by the FuseBase adversarial review of `cli-0.25.9-vendor-refresh` (v3.30.0): `healthcheck-diff-source-hardening` (MED) + `cli-custom-at-risk-overflag` (LOW). No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged); the FFHC **verdict ENUM + exit codes (0/1/2) are UNCHANGED** — the two new findings are advisory, like `CLI_SNAPSHOT_STALE`. Dual-reviewed: Codex design RESCOPE folded (advisory-only) + FuseBase adversarial impl review **SHIP, zero findings**.

**FR-07-clean / advisory-only:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched (only the FLOW_RULES version-attestation line moved). Health-check stays **read-only**.

- **M — durable updater-written receipt** closes the v3.30.0 silent-non-detection blind spot. `settings-json-merge.py --baseline-out` (via `post-fusebase-update.sh --wire-hooks`, on real-merge AND no-op) writes the CLI-owned Stop commands it preserved to `state/audit/cli-stop-baseline.json` (`stop.py` excluded), replacing the ephemeral `.pre-flow-merge` diff source that the no-op path `rm -f`'d. Self-refreshing (re-run the updater to re-baseline). Never an on-disk-`.claude/hooks/` fallback (would re-introduce the `run-typecheck-apps.js` false positive).
- **Advisory-only reclassification — the v3.30.0 exit-1 path is REMOVED.** Reporter now reads the receipt: `has_flow_stop` + no receipt → advisory `CLI_STOP_UNVERIFIED`; receipt present + a baselined CLI Stop hook missing now → advisory `CLI_STOP_BASELINE_DRIFT`. **No `SHARED_MERGE_DRIFT`/exit-1 for a missing CLI Stop hook** (preserve-only merge ⇒ a missing hook is never a merge fault). A project carrying only these findings stays HEALTHY / exit 0.
- **L — `CLI_CUSTOM_AT_RISK` sha-gate.** Fires only when the CLI-owned skill's sha256 ≠ bundled provenance (operator content at risk); sha == provenance → CLI-shipped → skip; provenance-unavailable → conservative flag. The pristine-`app-dev-practices` over-flag is gone; genuine signal preserved. Advisory-only contract unchanged.
- **Docs / tests.** New `test-cli-0259-compat.sh` cases (AC-M1..M4, AC-L1); the v3.30.0 "still-flags-dropped" assertion updated to the advisory model. Backlog READMEs `healthcheck-diff-source-hardening` + `cli-custom-at-risk-overflag` → DONE.

Verified: preflight 0/0 · `bash -n check-cli-flow-conflicts.sh post-fusebase-update.sh` OK · `py_compile settings-json-merge.py` OK · run-tests **182/182 PASS** · `test-cli-flow-recovery.sh` **31/0** to completion · `check-module-size --all` exit 0 · mirror 0 drift (4 health-check skill copies byte-identical) · plugin == VERSION == 3.30.1 · **GEMINI.md = v3.30.1** · README badge 3.30.1 · the 5 FR-07 surfaces UNCHANGED · advisory-only invariant intact (verdict ENUM + exit codes unchanged) · `git grep -ni headroom` in code = 0. Ticket smoke: receipt written (3 CLI hooks, excludes `stop.py`) + durable across a no-op; dropped baselined hook → `CLI_STOP_BASELINE_DRIFT` advisory exit 0; deleted receipt → `CLI_STOP_UNVERIFIED` advisory exit 0; pristine sha==provenance not flagged, drifted flagged; NO input forces exit-1. Feature commits `a0d2e62..363b9be`. Spec: `docs/specs/healthcheck-baseline-and-custom-flag-hardening/spec.md`. Detail: `docs/release-notes/v3.30.1.md`.

## [3.30.0] — 2026-06-29

### Changed — FuseBase CLI 0.25.9 vendor refresh + de-staled CLI-Stop-hook model

**Refresh (additive + a behavior fix that only removes noise).** Flow v3.29.0 already **ran** with FuseBase CLI 0.25.9, but its vendored snapshot and hardcoded Stop-hook model were stale → a **proven false `SHARED_MERGE_DRIFT`** (phantom "CLI Stop hooks not preserved: run-typecheck-apps.js") and a **redundant double-typecheck on restore**. No new FR rule (FR-01..FR-27 unchanged), no new Flow skill (32 unchanged — the **20** is the CLI-provider count, separate). Dual-reviewed against the real 0.25.9 CLI: Codex design RESCOPE folded + FuseBase adversarial impl review **SHIP** (1 tracked MED + 2 LOW, none blocking).

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched. The re-vendored CLI assets stay **CLI-owned** (clean-room boundary) — not under the Flow clean-room attestation.

- **B — de-staled CLI-Stop-hook model (diff-framed, version-agnostic).** `settings-json-merge.py` is now **preserve-only**: appends `stop.py` once (idempotent) + preserves every existing Stop hook + `enabledMcpjsonServers`; no longer re-injects `run-typecheck-apps.js` from a static name; never removes an existing hook (older-CLI projects keep theirs). `check-cli-flow-conflicts.sh` flags `SHARED_MERGE_DRIFT` only when Flow's merge actually **dropped** a CLI Stop command wired in the pre-merge `.claude/settings.json` (`.claude/hooks/` only classifies an already-wired command). No false positive on 0.25.9's 3-hook set; a genuinely-dropped hook is still flagged.
- **H1 — `.claude/settings.json.example`.** Stop chain aligned to 0.25.9: `[run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js, stop.py]`; no `run-typecheck-apps.js`; "deprecated" comments removed; `stop.py` stays discoverable.
- **A — full re-vendor to 0.25.9.** 20 provider skills (adds `app-api-contract-testing`), 4 `.claude/hooks` (adds `run-lint-on-stop.sh`, `run-typecheck-on-stop.sh`), 2 app-agents; `stamp-cli-provenance.sh` re-run → fresh `cli-vendor-manifest.json` (62/62 byte-match; no `CLI_SNAPSHOT_STALE`).
- **H2 — flag-gate the new skill.** `app-api-contract-testing` added to `known_names` (both surfaces) + `flag_gated_skills` (flag `cross-app-api-calls-analysis`, verified vs CLI `copy-template.ts`) → absence-when-flag-off is benign INFO, not false `CLI_LAYER_DRIFT`. CLI-skill count 19→20 in the catalog.
- **C — docs.** `compatibility.md` (19→20, `40=20×2`, 0.25.9 wired-hook set), `source-map.md`, `README.md`, `fusebase-cli-edition.md`, `audit/README.md`, `stamp-cli-provenance.sh` comments.
- **D — tests.** New `hooks/tests/test-cli-0259-compat.sh` (12); `test-cli-flow-recovery.sh` updated to the 0.25.9 model. No-regression: 26 health-check timeout tests + benign non-FuseBase/0-present behavior + FFHC read-only guarantee intact.

Verified: preflight 0/0 · `bash -n check-cli-flow-conflicts.sh stamp-cli-provenance.sh` OK · `py_compile settings-json-merge.py` OK · run-tests **164/164 PASS** · `check-module-size --all` exit 0 · mirror 0 drift (32 Flow skills) · plugin == VERSION == 3.30.0 · **GEMINI.md = v3.30.0** · README badge 3.30.0 · the 5 FR-07 surfaces UNCHANGED (only the FLOW_RULES version-attestation line moved) · `cli-vendor-manifest.json` fresh (no `CLI_SNAPSHOT_STALE`) · AGENTS.md command-equivalents table byte-unchanged after the sweep · T3 doc 19→20 not clobbered · `git grep -ni headroom` = 0. Real-CLI ticket smoke (against the extracted 0.25.9 CLI): merge appends `stop.py` once + preserves the 3 CLI hooks + `enabledMcpjsonServers` + adds 0 `run-typecheck-apps.js` + idempotent; health-check **HEALTHY** (`shared_merge_drift:0`, `cli_snapshot_stale:0`); example wired; 20 skills; manifest 0-diff. Feature commits `1d3780d..d0b25e4`. Spec: `docs/specs/cli-0.25.9-vendor-refresh/spec.md`. Detail: `docs/release-notes/v3.30.0.md`.

## [3.29.0] — 2026-06-26

### Added — Codex / cross-agent slash-command parity

**Feature (additive).** Flow's **6 slash commands** were Claude-Code-only; this release ships **command parity** across Codex / Cursor / Copilot / Gemini in two arms. No new FR rule (FR-01..FR-27 unchanged), no new skill (32 unchanged). Independently **Codex-SHIP'd** (design RESCOPE folded + impl review LOW hardened → `cdf7bf6`, bite-verified).

**FR-07-clean / additive:** no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml` touched. The `AGENTS.md` command table sits **outside** the version-swept region and **outside** `FLOW:PRESERVE`.

- **B — command-equivalents table (primary, repo-portable)** (`AGENTS.md` + overlay source → propagated `CLAUDE.md` / `GEMINI.md`) — a compact **6-row** table (`Command · Claude /cmd · Codex /prompts:cmd if installed · Portable = invoke the skill / type the command`) replacing the single "slash commands" sentence. Repo-committed, every agent reads it, no native mechanism required; matches Codex's own **skills** model. Pointer-style — no command-body re-paste (FR-23/FR-26).
- **A — opt-in native Codex installer (per-machine polish)** (`hooks/local/install-codex-prompts.sh`) — single-sources native Codex custom prompts from the 6 canonical command bodies (transform: keep `description:`, repoint `.claude/agents` → `.codex/agents`, preserve the PO-boot block + markers) and writes them to `$CODEX_HOME/prompts/` where Codex surfaces them as `/prompts:<cmd>`. Each file **marked** Flow-generated; **idempotent**; **refuses** UNMARKED collisions without `--force`; **hard-fails** on a frontmatter-less body. **Never default-on** — not called by `post-fusebase-update.sh` or any default path (it writes user-global files).
- **Ground truth (verified, Codex CLI 0.128.0):** native Codex prompts are `$CODEX_HOME/prompts/*.md` — **user-global, NOT repo-shared, deprecated** in favor of skills; invoked `/prompts:<basename>` (namespaced); YAML frontmatter kept; repo-local `.codex/prompts/` is not a read path; plugins bundle skills/mcp/apps/hooks, not commands. Net: B is the genuine repo-portable parity; A is optional per-machine polish, honestly labeled.
- **Possible follow-up:** a Codex-**plugin** packaging of Flow's skills/agents (via `codex plugin marketplace`) — out of scope (plugins don't carry commands); filed to backlog.

Clean-room: no third-party code/prompt/text/dependency copied or vendored; prior clean-room state intact (`git grep -ni headroom` = 0).

Verified: preflight 0/0 · `bash -n install-codex-prompts.sh` OK · run-tests **151/151 PASS** · `check-module-size --all` exit 0 · mirror 0 drift (32 skills + agents) · plugin == VERSION == 3.29.0 · **GEMINI.md = v3.29.0** · README badge 3.29.0 · sync `--dry-run` framework-scoped (no consumer doc touched; under-reach guard passes) · **AGENTS.md command table byte-unchanged after the sweep** · `git grep -ni headroom` = 0 · **FR-07 clean** (5 surfaces unchanged; only the FLOW_RULES version-attestation line moved). FR range FR-01..FR-27, 32 skills unchanged. B smoke: AGENTS.md carries the 6-row table + all 6 commands + the Portable column, byte-unchanged after `sync --dry-run`. A smoke: `CODEX_HOME=<tmp>` install → 6 marked prompts, 0 `.claude/agents` leak, idempotent re-run, unmarked-collision refused, frontmatter-less fixture hard-fails. Feature commits `528219d..cdf7bf6`. Spec: `docs/specs/codex-slash-command-parity/spec.md`. Detail: `docs/release-notes/v3.29.0.md`.

## [3.28.0] — 2026-06-17

### Added — FR-27 liveness discipline (anti-hang)

**Feature (additive).** The first always-on rule added since FR-26. Driver: a real consumer hang — a background re-verify probe **HUNG** (no internal timeout; stalled against a cold-start proxy), emitted no completion event, so the agent was never re-invoked and idled silently until the operator nudged it. The framework already named this failure but only for **delegated sub-agents** (`task-delegation`); the agent's **own** probe/script/deploy/fetch-loop/browser work was uncovered, with no canonical home.

**FR-07-clean / additive:** FR-27 is an **APPEND** to the FR table — existing FR-01..FR-26 rows are byte-unchanged; the 3 deploy-policy semantics + `ratchet-governance.yml` + `run-with-timeout.sh` (`ffhc_*` API) untouched. Double-reviewed by Codex (design RESCOPE folded + implementation review: stale-count DO-NOT-SHIP → fixed `9361526` → re-confirm **SHIP**).

- **FR-27 rule** (`FLOW_RULES.md`) — any long/silent background work (the agent's own probe/script/deploy/fetch-loop/browser-automation, a sub-agent, or a workflow) must be made observable BEFORE launch — bounded by a timeout/watchdog, OR completed in-turn, OR returned as `BLOCKED-AT-<gate>` + a record-then-read pointer. A task that cannot signal its own completion-or-death must never be launched bare.
- **`liveness-discipline` skill** (`flow-skills/liveness-discipline/SKILL.md`) — the **32nd** canonical skill carrying the full protocol + a compact `bounded-run` example + cross-links to `task-delegation` (`BLOCKED-AT`) and `smoke-testing` (record-then-read).
- **`bounded-run.sh` structural helper** (`hooks/local/lib/bounded-run.sh`) — **reuses** the health-check's `run-with-timeout.sh` core (preserving the `ffhc_*` API) and adds a wall-clock **deadline** emitting a terminal **timeout line** + **incremental heartbeat** so a monitored background launch reaches completion-or-death instead of a silent idle.
- **3-tier present-by-construction delivery** — Tier 1: FR-27 row in the role-discipline § Write-time discipline digest; Tier 2: a `session_start.py` reminder line; Tier 3: the liveness/`BLOCKED-AT` clause promoted into the handoff Role-bootstrap **Hard-invariants** (the MAIN session carries it).
- **Honest model:** **no blocking gate, no verification hook** — a hang is undetectable by construction (no idle event; `post_tool_use` can't fire for a call that never returns; a "watchdog: applied" signal would be attestation theatre). Enforcement = safe-default tooling + present-by-construction delivery. The tooling claim is **qualified**: it bounds the monitored process; it does NOT kill an `&`-detached grandchild or prove host re-invocation.
- **Deferred:** `fr27-prelaunch-nudge` (D3 — the warn-only `pre_tool_use` nudge; must ship as allow+warning, never a block); D4 Python watchdog helper; D5 `templates/bounded-script.sh` skeleton.

Clean-room: no third-party code/prompt/text/dependency copied or vendored; prior clean-room state intact (`git grep -ni headroom` = 0).

Verified: preflight 0/0 · `bash -n bounded-run.sh` OK · run-tests **132/132 PASS** · `check-module-size --all` exit 0 · mirror 0 drift (32 skills + agents) · plugin == VERSION == 3.28.0 · **GEMINI.md = v3.28.0** · README badge 3.28.0 · sync `--dry-run` framework-scoped (no consumer doc touched) · `git grep -ni headroom` = 0 · **FR-07 clean** (5 surfaces unchanged; FR-27 is an append; `run-with-timeout.sh` byte-unchanged, `ffhc_*` intact). Feature smoke: `sleep 30` through `bounded-run.sh` with a ~2s deadline → `bounded-run: TIMEOUT` line + **rc 124** + heartbeat; health-check timeout suite still passes. Spec: `docs/specs/liveness-discipline/spec.md`. Detail: `docs/release-notes/v3.28.0.md`.

## [3.27.0] — 2026-06-17

### Added — FR-22 delivery guarantee + PO verifiable boot

**Feature (additive).** Two tickets in the **FR-22 family** — *"mandatory" without a delivery guarantee + artifact-level verification is just "optional with extra words."* Both **warn-only** (no deny gate loosened) and **FR-07-clean** (no FR rule rows, no deploy-policy rule semantics, no `ratchet-governance.yml`). Both independently **Codex-SHIP'd** (design RESCOPE folded + impl review). No new FR rule, no new skill — FR range (FR-01..FR-26) and skill count (31) unchanged.

**1. FR-22 delivery guarantee (Phase 1, A–E)** — the comment-policy is now delivered + verifiable at the **artifact level**, never gating on comment **content** (FR-22's no-content-gate stays intact):
- **Present-by-construction handoff block** (`templates/handoff-implement.md`) — the FR-22 Delegation push-block text is a literal, non-optional section in every authored implement handoff, not a "remember to inline" line a long autonomous run forgets.
- **Write-time digest** (`flow-skills/role-discipline/SKILL.md`) — carries the full two-kinds FR-22 rule **and** an explicit "does **not** auto-propagate to sub-agents — inline the comment-policy push block when delegating code-writing" note.
- **`comment_policy_review_applied` warn-signal** (`policies/required-artifacts.yml` + `hooks/handlers/stop.py`) — a transcript marker (`comment-policy review: applied (FR-22)` / `… N/A (FR-22; no code diff)`) recording the review **ran**, never what comments say; absence → **warn**, never block.
- **Artifact-vs-content distinction doc** (`flow-skills/comment-policy/SKILL.md` + `docs/comment-policy.md`) — content-gating forbidden, artifact-level checks encouraged.
- **Carve-out clarity** (`policies/comment-policy.yml`) — opt-in posture preserved; clearer "derive at Specify" trigger + tighter commented starter set. No gate.
- **Deferred:** `fr22-predelegation-hook` (the pre-delegation PreToolUse check) — inert under the shipped matchers (Bash/Edit/Write only, not Task/Agent); needs host-matcher coverage + explicit delegation markers + warn-only telemetry first. Its own ticket.

**2. PO verifiable boot** — `/product-owner` opens with a verifiable activation boot:
- **Command boot block + ASCII marker** (`.claude/commands/product-owner.md` + overlay) — a 6–8 line operating-rules checklist the PO echoes as its first reply, ending in `[[ PO-ACTIVATED | FuseBase Flow <VERSION> | … ]]` (grep-stable). Pointers to FLOW_RULES, not a re-paste.
- **Same boot in the canonical agent** (`agents/product-owner/AGENT.md` → mirror) — boots-by-construction via the slash command **or** the Agent tool / description match; a drift-guard test asserts the two boot blocks match.
- **UserPromptSubmit detection** (`hooks/handlers/user_prompt_submit.py`) — `/product-owner` → non-blocking reminder + supplemental `po_activation_requested` event.
- **Dedicated PO-activation Stop check** (`hooks/handlers/stop.py`) — a **separate** path outside `CLAIM_PATTERNS` (fires on a PO first reply, which has no done/deploy claim): activation present, marker absent → **warn + Stop ALLOWS**; literal transcript scan only; existing deny gates untouched. Enforceable where FR-22 hook F was not, because it rides the already-wired `UserPromptSubmit`/`Stop` events (no new matcher needed).

Clean-room: no third-party code/prompt/text/dependency copied or vendored; prior clean-room state intact (`git grep -ni headroom` = 0).

Verified: preflight 0/0 · `py_compile stop.py + user_prompt_submit.py` OK · run-tests **118/118 PASS** · `check-module-size --all` exit 0 · mirror 0 drift (skills + agents byte-identical) · plugin == VERSION == 3.27.0 · **GEMINI.md = v3.27.0** · README badge 3.27.0 · sync `--dry-run` framework-scoped (no consumer doc touched) · `git grep -ni headroom` = 0 · FR-07 clean (5 surfaces unchanged; only the FLOW_RULES version-attestation line moved). Feature smoke: FR-22 push block present in the rendered handoff; `comment-policy review: applied (FR-22)` detected; `/product-owner` activation with no marker → warn + allow (rc 0); a required done-gate signal missing → still deny (rc 2). Feature commits `b7b2d87..35d9a82` + `8b79af3..eea8bd9`. Specs: `docs/specs/fr22-delivery-guarantee/spec.md`, `docs/specs/po-verifiable-boot/spec.md`. Detail: `docs/release-notes/v3.27.0.md`.

## [3.26.0] — 2026-06-15

### Added — FR-26 context-compression discipline (large-output / repeat-output audit, MCP coverage)

**Feature (additive).** Extends **FR-26** from read-side hygiene to **large context and large output** — when loading a big input or tool result whole is itself the waste. New **`## Context compression discipline`** section in `flow-skills/token-economy/SKILL.md` plus **two new `/token-waste-audit` candidate classes**. Clean-room original, MIT, stdlib-only, **no new dependency**. No new FR rule and no new skill — it extends the existing FR-26 / `token-economy` carrier, so the FR range (FR-01..FR-26) and skill count (31) are unchanged. Routing, not a budget: the Guardrail still governs (quality outranks tokens; no needed read or verification is skipped).

- **`## Context compression discipline`** — behavioral rules with per-row quality guards: content-route-before-consuming, extract-before-reasoning, preserve-the-retrieval-path (every summary keeps a handle back to ground truth), original-before-edit, summary-is-not-authority, stable-context-floor, cross-agent dedupe, reference-an-in-context-body-once, large-output hygiene (anticipate then narrow), generated/vendored restraint, compression-is-not-verification.
- **`large-output` audit class** — flags tool results ≥20k chars from **any** output-producing tool, built-in **and MCP** (write tools excluded). Corrects a real coverage gap: the prior allowlist silently missed MCP tools.
- **`repeat-output` audit class** — flags the same large body re-sent across turns, fingerprinted by a **one-way stdlib hash**; the body is **never emitted** into the report.
- All findings stay **candidates that MAY indicate** an FR-26 rule (never verdicts; known false-positive classes listed in the report header).

Clean-room: no third-party code/prompt/text/dependency copied or vendored; **no third-party tool named** in any shipped artifact; attestation in `docs/source-map.md`. Triple-validated: gap-analysis workflow + **two Codex SHIP reviews** + a name/license firewall audit (reference is Apache-2.0; nothing copied; the firewall-term grep over the repo returns 0).

Verified: preflight 0/0 · `py_compile token-waste-audit.py` OK · `check-module-size --all` exit 0 · mirror 31 skills / 0 drift (byte-identical) · firewall-term grep = 0 · LICENSE untouched · plugin == VERSION == 3.26.0 · **GEMINI.md = v3.26.0** · README badge 3.26.0 · sync `--dry-run` framework-scoped (no consumer doc touched) · FR-07 clean (version-string sweep only). Feature smoke: synthetic transcript fires `large-output` ≥1 (incl. the MCP tool) + `repeat-output` ≥1, content marker 0× in report. Detail: `docs/release-notes/v3.26.0.md`.

## [3.25.1] — 2026-06-15

### Fixed — adoption-hop baseline merge-preserve (the v3.25.0 U3/W2 merge now runs on the FIRST upgrade adopting v3.25.x)

**Hotfix.** v3.25.0 shipped the U3/W2 `module-size-baseline.txt` + policy-state **merge-preserve** rule, but a **post-ship Codex adversarial review** found it was **skipped on the adoption hop** — the first upgrade that brings a project onto v3.25.x. Root cause: `upgrade.sh` sourced the merge lib from the **local** (pre-upgrade) tree before `hooks/` was refreshed, and `bootstrap-upgrade.sh` didn't stage `hooks/local/lib/`, so the new merge code wasn't on disk when the merge had to run → a project's own baseline rows were **clobbered on adoption**. Bounded to **how/when the lib is sourced** + bootstrap staging + routing docs + a new test; **the LOCKED merge rule itself is unchanged**.

- **P1 — `bootstrap-upgrade.sh` stages `hooks/local/lib/`** so the new `upgrade.sh` finds its merge code before handoff. (`49f335c`)
- **P2 — `upgrade.sh` sources the merge lib from the authoritative target tree** (`$SOURCE_CLONE/hooks/local/lib/`) with a local fallback, **re-sources before Step 1a**, and prints a **loud no-skip warning** if the lib can't load — a silent skip can never recur. (`b562166`)
- **P3 — README routing:** pre-v3.25 installs go through `bootstrap-upgrade.sh` for the v3.25.x hop (the merge ships in the target version; a clobbered baseline is recoverable from the `.pre-upgrade` backup). (`5324358`)
- **P4 — RED-then-GREEN adoption-hop integration test** `hooks/tests/test-bootstrap-baseline-hop.sh` (13 cases) wired into `run-tests`: pre-fix engine loses the row (RED), fixed engine preserves it (GREEN) + P1 staging preconditions. (`28fe2ea`)
- **ACCEPTED-RISK:** an old already-installed `upgrade.sh` run directly (not via bootstrap) still can't run the target-version merge code; mitigated by the P3 bootstrap routing. Only residual Codex flagged.

Verified: preflight 0/0 · run-tests **92/92 PASS** (79 + 13 new adoption-hop) · `check-module-size --all` exit 0 · mirror 31 skills / 0 drift (byte-identical) · sync `--dry-run` framework-scoped (consumer excluded) · plugin == VERSION == 3.25.1 · GEMINI synced v3.25.1 · **recovery-sim 31/31 exit 0** · FR-07 clean (version-string sweep only; LOCKED merge rule untouched — only lib sourcing). Credit: post-ship Codex adversarial review. Spec: `docs/specs/upgrade-baseline-bootstrap-hop/spec.md`. Detail: `docs/release-notes/v3.25.1.md`.

## [3.25.0] — 2026-06-15

### Changed — upgrade-tooling hardening (Windows perf, baseline/policy merge-preserve, sync allowlist, GEMINI sync, PARTIAL_UPGRADE)

The 3.23.x **content model is correct and well-guarded**, but the **refresh/upgrade scripts** forced manual intervention on Windows. **Two independent consumer projects** (paperclip+hermes-v1 and WorkHub Managed) filed the same friction on a `v3.21.1 → v3.23.1` upgrade: `upgrade.sh` stalled mid-mirror, churned consumer docs on an EOF-newline strip, rewrote FR refs in historical consumer docs, and clobbered `policies/module-size-baseline.txt` (breaking `check-module-size --all`). This is a reactive, bounded hardening of the three refresh scripts plus GEMINI, `.gitattributes`, and the health check — the content model, the byte-exact copy contract, and the marker-anchored overlay refresh are unchanged.

- **U1 — batched mirror/sync spawns (Windows perf).** `mirror-skills.sh` and `sync-version-strings.sh` spawned a process per file (≈0.8–1.4s each on Windows Git-Bash → minutes for a 6,974-`.md` scan). Now a single chunked `sha256sum`/`shasum` primes an assoc-array cache and the loop is fork-free. **Copy scope unchanged** (still `SKILL.md` + `references/*`, a bounded copy not a blind `cp -R`) — manifest stays **byte-identical**. Windows ~5 min → seconds.
- **U2 — portable EOF-newline-preserving sync.** Replaced `printf '%s' > "$f"` (which stripped the trailing newline and churned 11 consumer docs) with explicit trailing-newline-state capture/restore (not a bare `sed -i`). Chunked `grep -lE` superset pre-filter. Fixtures prove both trailing-newline and no-trailing-newline files round-trip.
- **U3 — `module-size-baseline.txt` + policy-state merge-preserve on upgrade.** `upgrade.sh` no longer wholesale-clobbers project state in `policies/`. Merge rule (LOCKED): ownership = **upstream-baseline membership** (not path prefixes); upstream rows take upstream counts, **project rows absent upstream are preserved verbatim**, a Flow row dropped upstream is removed, malformed local rows warn. Also guards `approval-policy.yml:workflow_mode` and `protected-paths.yml worker_undisturbed` via `*.local.yml` + a policy-state-preserve test.
- **U4 — executable framework-owned sync allowlist + under-reach guard.** Broad `find`+prune replaced with an in-script `SYNC_ROOTS`/`SYNC_FILES` allowlist; plugin metadata via a parity check, not sed. The **under-reach guard** test FAILS if any token-bearing framework file is omitted (the anti-GEMINI). Consumer roots (`docs/product-backlog|problem-catalog|product-execution|client-workflows/**`) are NEVER synced.
- **U5 — GEMINI version regex.** Now matches `Fusebase Flow (Local )?v[0-9]+(\.[0-9]+){1,2}` so GEMINI's `Local v2.1`-style header syncs (it had been stuck for releases). Confirmed live: GEMINI.md → v3.25.0.
- **U7 — upgrade trap recovery + health-check `PARTIAL_UPGRADE`.** `upgrade.sh` prints the exact recovery command(s) on interruption/failure; the health check compares derived facts vs live strings and reports `PARTIAL_UPGRADE` + the repair command on mismatch (builds on the v3.24.0 engine).
- **U9 — progress output** in mirror/sync/upgrade (`mirroring N/31…`, `scanning N files…`) — the silent multi-minute window is gone.
- **U11 — `.gitattributes` LF pins** (`VERSION`, `*.sh`, hook scripts, config/doc formats) so Windows clones don't rewrite CRLF and churn diffs.
- **U8 — Windows docs** (docs only): Git-Bash invocation, unusable-WSL-bash detection, `git -c http.sslBackend=openssl` fallback for schannel tag/clone failures.
- **Deferred:** U6 (full GEMINI/copilot/cursor overlay-refresh parity — needs a marker-strategy design) ships as a follow-up ticket `docs/backlog/adapter-overlay-refresh-parity/`.

Verified: preflight 0/0 · run-tests 79/79 PASS (new AC2/AC3/AC4/AC7 fixtures) · `check-module-size --all` exit 0 · mirror 31 skills / 0 drift · agent mirrors byte-identical · **recovery-sim 31/31 exit 0** · plugin == VERSION == 3.25.0 · GEMINI synced · FR-07/FR-25 clean (version-string sweep only). Credit: paperclip+hermes-v1 + WorkHub Managed. Spec: `docs/specs/upgrade-tooling-hardening/spec.md`. Detail: `docs/release-notes/v3.25.0.md`.

## [3.24.0] — 2026-06-15

### Added — health check fast/bounded execution + `PARTIAL_UNVERIFIED` (exit 4)

`hooks/local/fusebase-flow-health-check.sh` could exceed two minutes and **appear to hang** on a network-impaired or large-repo host (unbounded `git fetch` + slow `preflight` / `run-tests` / `check-cli-flow-conflicts` sub-invocations). The fix bounds every slow op and adds a verdict that distinguishes "a critical check didn't run" from "healthy" — the design-review blocker was a **false `HEALTHY`** when a critical check is skipped/timed-out.

- **New `PARTIAL_UNVERIFIED` verdict + exit code 4** (and a `LOCAL_UNVERIFIED` tracking array). **Exit 0 only when every CRITICAL check (preflight, hook tests, conflict reporter) actually ran and passed.** A timed-out/skipped critical ⇒ `PARTIAL_UNVERIFIED`/exit 4 — never `HEALTHY`/0. Precedence: BROKEN > real drift > EXCEPTION > PARTIAL_UNVERIFIED > HEALTHY.
- **Upstream comparison is optional** — the `git fetch` timing out is a "upstream not verified (fetch timed out)" note only; it never becomes UNVERIFIED and never forces exit 4. `GIT_TERMINAL_PROMPT=0` + low-speed config make the fetch fail fast instead of blocking on a prompt.
- **`run_with_timeout` helper** (extracted to `hooks/local/lib/run-with-timeout.sh` per FR-25): detects `timeout` → `gtimeout`; `-k` grace; rc 124 = timeout; **preserves the wrapped command's own rc otherwise**. If neither binary exists ⇒ bounded ops are skipped ⇒ `PARTIAL_UNVERIFIED` (opt into unbounded with `FFHC_ALLOW_UNBOUNDED=1`).
- **Fixed a pre-existing run-tests rc-masking false-HEALTHY (H6):** a harness crash (rc≠0 with no parsable `FAIL:` line) previously read OK via `|| true`; it is now `BROKEN`/2.
- **Flags:** `--no-upstream` (full **local** verdict, exit 0 OK) and `--fast` (skips the slow hook tests — keeps preflight — for a quick verdict; **explicitly partial: exit 4, never 0**, prints "fast mode — not a full health verdict").
- **SLO-budgeted, env-overridable timeouts:** `FFHC_FETCH_TIMEOUT` (15s), `FFHC_PREFLIGHT_TIMEOUT` (30s), `FFHC_CONFLICT_TIMEOUT` (30s), `FFHC_TESTS_TIMEOUT` (60s); worst-case bounded full run ≈ 155s. The conflict reporter's wildcard matcher now scopes its scan to the static path prefix instead of walking the whole tree (behavior-preserving; `--json` output byte-identical).
- **AC8 exit-code contract:** any caller/recovery flow that branches on the health-check exit code must treat **exit 4 = partial/unverified** (not full health, not a hard failure). Swept — no code caller currently branches on the exit code; the recovery test harness keys off the `Verdict:` line, not the code. Docs updated (skill, README, deferrals).
- **Tests:** 7 new fixtures in the recovery suite (fetch-timeout-not-hang → bounded+note+exit0; critical-timeout → exit 4; real-preflight-fail → BROKEN; run-tests harness-crash → BROKEN; `--fast` → exit 4; no-timeout-binary → partial; unbounded-opt-in → HEALTHY). Stubbed sub-scripts/git — no real network. Drift detection unchanged (existing U/F engine tests still pass).

Spec: `docs/specs/health-check-fast-timeout/spec.md`. Detail: `docs/release-notes/v3.24.0.md`.

## [3.23.1] — 2026-06-14

### Fixed — `/find-wasted-effort` containment hardening (atomic write, hardlink/symlink fail-closed)

Patch hardening of the `/find-wasted-effort` audit's on-disk write path. Additive and read-only-safe — the analyzer still writes **nothing outside the gitignored `state/audit/`** directory and applies nothing; no behavior change to verdicts or proposals.

- **Atomic contained write** — `write_audit_file()` writes a fresh temp file *inside* the resolved `state/audit/` dir, then `os.replace()`s it onto the target. The replace rebinds the directory entry to a NEW inode, so any pre-planted hardlink/alias at the target is severed and the outside file it aliased is never modified (same-filesystem temp keeps the rename atomic and contained).
- **Hardlink/symlink fail-closed** — the target is rejected up front if it is a symlink (`is_symlink()`) or a hardlink alias (`lstat().st_nlink > 1`), raising `RootError` — the audit refuses to write *through* a planted alias. Defeats a pre-planted-alias write-through that could otherwise have modified a file outside `state/audit/`.
- **Honest fail-closed fixture** — the `g2` selftest now asserts the TRUE contract: a pre-planted-at-rest hardlink at the target ⇒ `RootError` (fail-closed) AND the outside aliased file is byte-unchanged. Drops the prior dishonest "report still lands despite planted hardlink" claim (it masked the fail-closed reality by removing the alias first). The severed-alias/new-inode happy path stays proven by `g3` (`st_nlink == 1`, no temp turd left).
- **Documented at-rest threat model (FR-22)** — `write_audit_file()` / `contained_audit_path()`: containment defends pre-planted symlink/hardlink/traversal targets AT REST; active concurrent FS races mid-run (e.g. renaming `state/audit/` between temp-create and replace) are OUT OF SCOPE for a local single-operator read-only audit tool.

`--selftest` 155 passed, 2 skipped (skips = host lacks symlink/hardlink privilege). Read-only invariant unchanged; counts unchanged (31 skills, FR-01..FR-26). Detail: `docs/release-notes/v3.23.1.md`.

## [3.23.0] — 2026-06-14

### Added — `/find-wasted-effort` proposal output (read-only-safe) — ceremony-efficiency Phase 2A

Phase 2A of the ceremony-efficiency-middle-lane ticket. Additive, read-only-safe: `/find-wasted-effort` now emits schema'd proposals; the analyzer still writes **nothing outside the gitignored `state/audit/`** directory and applies nothing. Per the Codex Phase-2 design review (2026-06-14) the read-only→write flip is **descoped from the framework** — the memory write-apply (Phase 2B) and the Middle Lane (Phase 3) are routed to the `paperclip+hermes-v1` consumer repo as hard-gated prototypes, upstreamed only once proven.

- **Proposal output** — a *Proposed memory entries* section in the contained `state/audit/<date>.md` report + an optional sibling gitignored `state/audit/find-wasted-effort-proposals-<date>.json` (`--no-proposals-json` skips the JSON). A `confirmed` finding → a recommendation proposal; a rule-6 review-candidate → a `prune_review_candidate`; `inconclusive`/`dismissed` → none. Defined schema: `proposal_id`, `rule`, `verdict`, `raw_evidence_refs`, `target_kind`, `target_path`, `exact_patch`, `operator_confirmation_required: true`, `source: "audit"`.
- **Self-output quarantine (Codex finding 5)** — proposals cite raw on-disk artifacts as evidence, never a prior audit report/proposal; the evidence collectors do not read `state/audit/` (the audit cannot cite itself). `prune_review_candidate` only — never an auto-prune or recorded prune decision (the PO owns subtraction; `policies/ratchet-governance.yml`).
- **Read-only to the project (tested)** — a hard test asserts a full run modifies no memory/overlay/spec/provider/policy file; golden-proposal fixtures (confirmed → proposal, review-candidate → proposal, inconclusive → none). **Not** the read-only→write flip — that is Phase 2B (deferred, consumer-repo, AC2b).
- **Containment hardening (Codex Phase-2A LOW)** — `contained_audit_path` resolves the target before the relative check and rejects an absolute / `..` / path-separator basename at the boundary (raises `RootError`). Both real callers pass fixed flat basenames (a no-op for them); closes internal-misuse traversal in the containment helper. +6 selftest fixtures.

`--selftest` 151 passed, 2 skipped (+6 over v3.22.0 = the new basename-hardening fixtures). Spec: `docs/specs/ceremony-efficiency-middle-lane/spec.md` (Phase 2A; cites D7, AC2 Phase-2A clause). Detail: `docs/release-notes/v3.23.0.md`.

## [3.22.0] — 2026-06-13

### Added — ratchet governance (A3) + `/find-wasted-effort` read-only ceremony audit (A2) — ceremony-efficiency Phase 1

Phase 1 of the ceremony-efficiency-middle-lane ticket (solves PR-2 + PR-3; Phase 2 = audit writes, Phase 3 = the Middle Lane / `middle_deploy` — both deferred to their own gates). Low-risk, additive, no deploy-authority change.

- **A3 ratchet governance** — `policies/ratchet-governance.yml`: the `prevents: <incident-class>` annotation convention + the `catastrophic-low-frequency` severity tag (makes a control harder to prune; a clean window is expected for rare-but-severe controls). A 9-class incident taxonomy is the WHY-home; a D5-scoped coverage map (deploy/gate controls + the elements rule 6 reads) states its own scope (silence ≠ safety). Scoped `prevents:` markers added to `templates/{handoff-deploy,handoff-implement,gate-report,verification-gate}.md` + `workflows/{greenlight-deploy,eight-phase-flow}.md`. **Pruning is PO-owned and never automatic** — an un-annotated, non-firing element is a *review candidate* only (needs named incident-class, severity, window, negative examples, operator confirmation).
- **A2 `/find-wasted-effort` (31st skill, read-only)** — the **process-per-outcome** ceremony sibling of `/token-waste-audit` (**tokens-per-rule**). Different axis, different inputs (Flow artifacts on disk vs transcripts), **shared discipline**: it reuses the shipped `token-economy` substrate (FP header, read-only-first posture, gitignored `state/audit/<date>.md` output) — not reinvented. 6 active rules (rule 4 **CUT** — already in token-waste-audit's v3.21.0 cross-session aggregate; rule 7 scoped to the cross-session ceremony layer only), each emitting **confirmed / dismissed / inconclusive** with required contrary-evidence + per-rule FP examples.
- **`hooks/local/find-wasted-effort.py` + `hooks/local/find_wasted_effort/` package** — deterministic, stdlib-only, **READ-ONLY** analyzer (thin CLI orchestrator + a 6-module package split along the per-rule + test-layer seam; every module under the FR-25 800-line ceiling). Reads gate/deploy reports, handoffs, approval artifacts, git log, and `prevents:` annotations; writes only its own gitignored report. NO memory/overlay/spec writes, NO prune/reclassify recommendations (those are Phase 2/3, gated on per-rule FP fixtures — D4). `--selftest` runs synthetic + evidence-sourcing/scoping + end-to-end + path-containment + parser fixtures (**116 passed, 2 skipped** — skips = host-symlink fixtures).
- **`/find-wasted-effort`** (6th command) + recovery snapshot; skill mirrored to `.claude/skills/` + `.agents/skills/`; counts swept 30 → **31** skills, 8 → **9** policies.

Spec: `docs/specs/ceremony-efficiency-middle-lane/spec.md` (decisions D1..D7; Phase 1 cites D5, D7). Detail: `docs/release-notes/v3.22.0.md`.

## [3.21.1] — 2026-06-12

### Fixed — delegation residuals (downstream post-delivery verification)

Downstream verified v3.20.1 + v3.21.0 (all 10 prior asks confirmed delivered) and reported 4 second-order residuals — one silent-failure fix, three "the rule exists but doesn't reach the surface that needs it" fixes:

- **Recovery call surfaced** — `upgrade.sh` step 4 ran the overlay/command recovery fully silenced (`>/dev/null 2>&1 || true`); a mid-run recovery crash half-applied (downstream: 2 of 5 command files stale) with the root cause masked. Now: success prints the recovery's actions-taken summary; non-zero exit prints a loud HALF-APPLIED warning + last output lines + the literal re-run command. Sim-proven both paths.
- **Deploy sessions inherit the delegation contract** — `templates/handoff-deploy.md` (the prompt a delegated Deploy session actually reads) gains the turn-completion + progress-ledger + BLOCKED-AT invariant bullet, and `workflows/greenlight-deploy.md` joins its mandatory-reads list (the v3.21.0 push-not-pull fix covered implement handoffs only).
- **Self-recording clause for reports** — `gate-report.md` + `deploy-report.md` headers + `validation-and-qa`: if the system under test has durable evidence surfaces, report fields carry POINTERS — transcribe only what no system records (extends the v3.21.0 pointers rule from returns to reports; FR-23).
- **Ground-truth rule in the return shape** — a state-change claim (launched/deployed/completed) names the verification performed (system surface read + what it showed); an attempted action or look-alike artifact is not evidence (downstream: a false "launched" survived ~19h). Short form added to the push block + implement-handoff quote.

Spec: `docs/specs/delegation-residuals/spec.md` (S1–S5; independent review pre-ship).

## [3.21.0] — 2026-06-12

### Added — delegation resilience + return contracts

Six evidence-backed residuals from live delegated-run experience (downstream proposal paperclip+hermes-v1 2026-06-12). Double-review protocol: independent plan review (REVISE-FIRST, 13 findings — incl. two blockers: contract text that would never reach the worker sessions it binds, and an archive-flood/filename-collision in the run-ledger design) → spec self-correction → implementation → independent implementation review.

- **Progress-ledger contract** (`task-delegation` §3 + `greenlight-deploy` step 7): delegated sessions write durable facts AS THEY OCCUR (deploy hash at deploy moment; probe rows as each lands; skeleton first, rows as earned) — never end-loaded; sessions die mid-work and end-loaded reporting loses everything. Successor contract: resume from records, last durable fact, never redo verified steps.
- **Blocked-return semantics**: at an UNBOUNDED wait (human gate, no-ETA event) the honest return is `BLOCKED-AT-<gate>` + what-cleared-looks-like + state pointer — never fake-complete, never burn an open watch.
- **Delegated return shape** (`task-delegation` §5): verdict (`DONE`|`BLOCKED-AT-<gate>`|`FAILED-<reason>`) · per-task SHAs · count deltas · artifact POINTERS · residual risk; never re-paste a body an artifact already holds. Delegated returns only — gate reports keep PASS/FAIL.
- **Delegation contract push block** (the plan-review blocker fix): workers never load skills, so the whole contract rides the delegating prompt — named quotable block in `task-delegation` §3; `templates/handoff-implement.md`'s push line upgraded to it.
- **Restart vs run-ledger split** (`handoff` skill + `templates/handoff.md`): header `Mode: restart | run-ledger`. Restart stays operator-triggered (`invocation: manual`); run-ledger is the sole sanctioned autonomous write (long-run continuity, announced in chat — dissolves the "why did you write it without the slash command?" confusion). Run-ledger updates supersede IN PLACE; archive fires on restart supersede / mode transition only (no archive flood, no same-minute filename clobber). Legacy files without `Mode:` = restart.
- **Procedure-freshness line** (`handoff` Procedure + `handoff-implement` + `handoff-deploy` headers): before executing a reused procedural block, check whether a shipped capability supersedes it (e.g., self-recording deploys obsolete poll-watching).
- **Cross-session aggregate in `/token-waste-audit`**: report section (≥2 sessions parsed, no new flag) — files/commands recurring across sessions, top-N capped; framing header maps recurring rules/handoff reads + session-initiation Bash floor to **FR-23 session-floor discipline** (by-design), not FR-26 violations, and states the Read-tool-only visibility limit. Live-proven on 3 real transcripts.

Spec: `docs/specs/delegation-resilience/spec.md` (R1–R7 + full plan-review fold-in record).

## [3.20.1] — 2026-06-12

### Fixed — upgrade installer parity for slash commands + self-overwrite-safe engine

Downstream defect reports (paperclip+hermes-v1, 2026-06-07 + recurrence 2026-06-12): `upgrade.sh` upgrades crossing a command-adding release (3.14.x `/handoff`, 3.20.0 `/token-waste-audit`) left consumers BROKEN by their own preflight. Root cause was singular: the installer chain already existed (`upgrade.sh` → `post-fusebase-update.sh` Step 8, data-driven) but the recovery snapshot `hooks/local/fusebase-flow-overlays/commands/` was never updated for new commands, and no check enforced it.

- **Recovery snapshot backfilled** — 5/5 commands present (added `handoff.md`, `token-waste-audit.md`), byte-identical to `.claude/commands/` (preflight 5d `cmp` enforces).
- **Write-time gate (the recurrence killer)** — preflight §8 is now data-driven over one `FLOW_COMMANDS` array; per command three ERROR checks: live file · **recovery-snapshot copy** · CLAUDE.md reference. *A command surface may only ship with its installer step* — forgetting the snapshot now fails the release upstream instead of landing BROKEN downstream.
- **Self-overwrite-safe engine (found by the E2E sim; worse than reported)** — `upgrade.sh` refreshes `hooks/` including its own running file; bash streams scripts incrementally, so pre-3.20.1 engines can abort mid-upgrade with a syntax error at a stale byte offset (deterministic on the 3.19.1→3.20.1 hop). The body now lives in a `main()` wrapper (whole file parsed before step 1 runs). Upgrading FROM ≤3.20.0: use `bootstrap-upgrade.sh -- --auto-yes` (stages the new engine first → harmless) or re-run `upgrade.sh` after an abort (idempotent completion). README documents both.
- **Actionable instead of silent** — upgrade.sh step 4b warns when CLAUDE.md lacks a `/command` reference after the overlay refresh; plan output names the command-restore step; `post-fusebase-update.sh` comments de-enumerated (the Step 8 loop was already data-driven).
- **Process rule (PUBLISHING.md)** — shipping a new slash command requires the snapshot copy + `FLOW_COMMANDS` entry in the same release; preflight enforces.
- **Second parity gap, same class (found by the E2E sim):** preflight requires `.claude-plugin/plugin.json` version == VERSION (3.14.1+), but `upgrade.sh` never refreshed `.claude-plugin/` — every 3.14.1+ consumer upgrade landed with a version-mismatch ERROR. `.claude-plugin` added to the refresh list.
- Verified end-to-end against the **real v3.19.1 engine** (`git archive v3.19.1`, git-inited consumers, final tree): direct-upgrade abort→re-run, bootstrap one-shot, and wrapped-engine byte-diff immunity — all three observed at preflight **0 errors / 0 warnings** with `/token-waste-audit` installed, CLAUDE.md ref present, plugin.json parity, zero manual wiring.
- **Independent review (FIX-FIRST → resolved)** — all mechanical claims verified; review-driven hardenings folded in: the attestation sweep no longer rewrites version strings inside `*.pre-upgrade-*`/`*.pre-bootstrap-*` backup dirs (pre-existing bug — rollback backups stay pristine), command-ref greps gained word boundaries (`/onboard` no longer satisfied by `/onboarding`), `upgrade.sh --help` prints the full usage header.

Spec: `docs/specs/upgrade-installer-parity/spec.md` (decisions U1–U8 + review record).

## [3.20.0] — 2026-06-11

### Added — FR-26 token-efficient execution + `token-economy` skill + `/token-waste-audit`

Closes the last uncovered token-leak class: implementation sessions consuming context without considering efficiency — read-side waste (re-reads, whole-file reads for one fact, generated-file reads, re-derived IDs), retry storms, whole-file rewrites — and the root cause: **no measurement**. Built under a double-review protocol (independent plan review → spec corrections → implementation → independent implementation review).

- **FR-26 (token-efficient execution)** — completes the economy family (FR-21 process · FR-23 docs · FR-25 modules · FR-26 execution). **Quality-first guardrail is the rule's first clause**: cut REDUNDANT consumption only — never skip a needed first-read, never thin verification, never truncate reasoning; on conflict the correctness/safety floor wins. Deliberately NOT a gate (a token budget trains truncation). One FR-24 digest line.
- **30th skill `token-economy`** — execution rules with explicit quality guards from the plan review: scoped reads (fact-finding vs edit-context — never grep-and-edit blind), no re-reads of unchanged in-context files (re-read REQUIRED after invalidation events incl. parallel agents, hooks, failed Edit match, compaction), generated/vendored read ban (subject-of-task exception), two-strike retry rule (FR-10 3/3 reproduction + test-reruns-after-change + labeled flaky retries are NOT strikes), targeted edits (FR-18 rewrites exempt), pointers to the canonical pre-cached-IDs and record-then-read homes.
- **`/token-waste-audit`** (5th command) + `hooks/local/token-waste-audit.py` (351 lines, stdlib) — parses the project's local session transcripts: per-session deduped token totals (**requestId dedupe — naive summation overcounts ~2.4×**, the plan review's blocker catch), cache-growth visibility, and leak-candidate signatures (identical-window re-reads, no-edit-between polling runs, top sinks, large rewrites) framed as candidates with documented false-positive classes. Privacy: no message/thinking/result text in reports; commands truncated. Portable degradation: repo-side fallback on non-Claude surfaces. Live-proven on this repo's own transcripts + empty/nonexistent/malformed-input paths.
- Counts: skills 29 → **30** (mirrors 60; 78 mirrored files); commands 4 → **5**; FR range FR-01..FR-26. Implementation review: 1 count blocker + 1 count word fixed pre-ship.
- **Verified:** preflight 0/0 (incl. new §8 lines); run-tests 24/24; `--all` green. Spec: `docs/specs/token-economy/spec.md`. Detail: `docs/release-notes/v3.20.0.md`.

## [3.19.1] — 2026-06-11

### Added — delegation turn-completion rule + verification cost discipline (downstream proposal)

From a formal downstream proposal (paperclip+hermes-v1 autonomous multi-slice run; both gaps hit repeatedly, neither project-specific):

- **Turn-completion rule (binding, `task-delegation`):** a delegated session's deliverable must be COMPLETE within its turn — delegated sessions cannot self-resume; their context dies at turn end. Wait-dependent work polls with bounded sleeps IN-TURN or restructures as record-then-read. Never end a delegated turn with "running in background — I'll resume when it completes" (observed 3× in one run; each was a silent partial-completion risk). One-sentence push added to delegating prompts (`handoff-implement` delegation line) and to the deploy workflow's probe step.
- **Verification cost discipline (`smoke-testing` § new, cross-ref'd from `validation-and-qa`):** default = **record-then-read** — let the system run unobserved and read its durable evidence surfaces (journals, run records, logs) once afterward, instead of agent-side polling (measured ~10× cost, linear with wall-clock). No durable evidence surface = an observability-gap finding. Sole exception: the first live drive of freshly-changed code hunting unknown failure modes, bounded. Long-running verification plans state their mode.
- **Verified:** preflight 0/0; run-tests 24/24. Change-note: `docs/changes/2026-06-11-delegation-verification-discipline.md`.

## [3.19.0] — 2026-06-11

### Added — `app-quality-patterns`: cross-project behavioral quality library (29th skill)

Operator-driven: the same behavioral defects recur across consumer projects — view state not encoded in the URL (refresh/share loses filters/reports), deletes leaving orphaned records, chevron misalignment — and LLMs only apply such requirements when they're in context at the right lifecycle moment.

- **The library:** `flow-skills/app-quality-patterns/` = thin router SKILL.md + `references/{state-and-navigation,data-integrity,ui-polish}.md` (lazy-loaded per category). **14 seeded patterns** (QP-01..04 · QP-10..14 · QP-20..24), each: Trigger · Requirement · **Verify (copy-ready smoke recipe)** · Anti-pattern. Includes the three operator-observed defects plus empty/loading/error states, mutation cache-invalidation, double-submit guards, optimistic rollback, destructive-action scope confirm/undo, unsaved-changes guard, deep-link guards, back/forward, list-position restore, form-validation UX, timezone correctness.
- **Enforcement = AC-injection (no new gates):** `requirements-specification` scans the category index on app-feature tickets; every matching pattern becomes a spec **AC citing its QP ID** — which then rides the existing tasks → gate → smoke → review machinery. `implementation-planning` design briefs cite the IDs; `code-review` checks QP-ACs semantically; `smoke-testing` copies Verify lines as S(n).
- **Growth rule:** a defect seen across ≥2 projects = one new table row, shipped in the next release; project-specific patterns live in that project's `docs/skills/`. Boundary: QP owns WHAT must be true; CLI skills (`app-ui-design` etc.) own HOW on the stack (overlap-map row added).
- Counts: skills 28 → **29** (mirrors 58; 76 mirrored files incl. 18 references). Independent pre-ship review: 12/12 seeds judged sound (0 drops), 1 count blocker + nits fixed, 2 reviewer-suggested patterns added.
- **Verified:** preflight 0/0; run-tests 24/24; `--all` green; AGENTS inline overlay byte-matches canonical. Spec: `docs/specs/app-quality-patterns/spec.md`. Detail: `docs/release-notes/v3.19.0.md`.

## [3.18.2] — 2026-06-11

### Added — handoff paper trail: predecessors archived, every handoff timestamped

Operator-surfaced gap: `docs/tmp/handoff.md` supersedes in place, and the "audit trail = git history" assumption fails exactly when handoffs are written — mid-session, often uncommitted — so prior restart state could be silently lost.

- **Archive-on-supersede:** the `handoff` skill + `/handoff` command now move the existing `docs/tmp/handoff.md` to `docs/tmp/handoff/archive/<YYYY-MM-DD-HHMM>-handoff.md` before writing fresh. Archives are dated history — agents never load them (zero context cost); the operator may prune anytime. The live file keeps its stable name (the session-initiation read path is unchanged) and its mandatory `Updated:` timestamp header.
- **Scope note:** formal implement/deploy relays are unchanged — a revision of the same relay correctly supersedes in place per FR-18; the active handoff is a different snapshot each time, hence the archive.
- **PUBLISHING.md:** `gh release create` codified as a mandatory release step (this cycle's 9 releases had shipped tags-only until backfilled).
- Carriers updated: `flow-skills/handoff` (+2 mirrors), `templates/handoff.md`, `.claude/commands/handoff.md`, `AGENTS.md` continuity row, `documentation-budget` Tier-2 row.
- **Verified:** preflight 0/0; run-tests 24/24. Change-note: `docs/changes/2026-06-11-handoff-paper-trail.md`.

## [3.18.1] — 2026-06-11

### Fixed — post-ship audit nit-sweep (9 nits + 3 pre-existing finds; no behavior change)

Independent post-ship audit of v3.18.0 (first independent eyes on that diff): 0 blockers. All findings fixed: waiver-path consistency (the DP.6 prompt no longer claims "artifact verified" pre-stamp on `dp1_waiver: eligible` deploys; stamp step explicit in the response line; mandatory-read 7 + `release-deploy-reporting` step 1 carry the waiver branch); gate-field restatements in the ai-developer agent + IM.9 pointer-ized — the agent's copy had **already drifted** (missing `implementation_summary`), proving the restatement hazard; README conditional-security-review residue (:230/:334); `task_complete` removed from the event-schema enum; carrier count corrected 5→7 in the same-release notes; producer line added — omitting `decisions.md` requires the literal `no real decisions` in spec.md (what `required-artifacts.yml: optional_when` consumes); both handoff-drafting steps repointed at the canonical templates (`handoff-implement.md` / `handoff-deploy.md`, were "handoff-folder-README shape"); gate-report placeholder attestation made sweep-maintained; `required-artifacts.yml` header consumer corrected (stop.py only). Verified: preflight 0/0 · 24/24 · `--all` green. Change-note: `docs/changes/2026-06-11-v3181-nit-sweep.md`.

## [3.18.0] — 2026-06-10

### Changed — integration-debloat: procedure layer de-duplicated, 3 contradictions fixed, deploy ceremony right-sized

From a capability-integration audit (functional overlap + velocity lens across all 10 capability groups). No rule text changed; ~9.3KB (−20%) cut from per-ticket-read procedure files; 2 operator touches removed from the common deploy.

- **3 live cross-surface contradictions fixed:** FR-14 docs-commit owner is the **Deploy session** (the enforced path) — both sub-agent files corrected; the decisions requirement is now **tier-aware** ("LOCKED *if present*; absence valid per FR-23 when spec records 'no real decisions'") in `greenlight-implement` + `required-artifacts.yml`; **security review is conditional** on its own trigger list in all carriers (else `security: N/A` recorded) instead of unconditional on every deploy.
- **Gate contract canonical = `gate-contracts.yml` (machine) + `templates/gate-report.md` (producer)** — 7 restating carriers (verification-gate workflow + template, greenlight-implement, tasks/handoff templates, cursor/copilot adapters) → pointers. **Smoke canonical = `smoke-testing` skill** — workflow shrunk to mechanics; validation-and-qa sub-mode B → 3-line pointer. ~130 lines of self-declared "legacy reference" handoff snippets deleted from both greenlight workflows.
- **Review boundary:** `code-review` now trusts the recorded validation-and-qa gate verdict for deterministic/cross-artifact fields and reviews only semantic dimensions — eliminates a full duplicated diff pass per ticket.
- **Reversible-deploy waiver:** on `dp1_waiver: eligible` handoffs (reversible, no protected-path/security/migration surface) the Deploy agent stamps the DP.1 artifact itself upon the operator's typed DP.6 phrase. Artifact + hook semantics unchanged; human gate unchanged; deploy-intent confirmations 3 → 2. Excluded classes keep operator-run DP.1.
- **Machinery hygiene:** `task_complete.py` retired (wired nowhere); `session-initiation` now reads `state/context-summary.md` (pre-compact output was written but never read); preflight gains an overlay-copy drift check; `upgrade-engine.sh` → deprecation shim; orphan templates `research.md`/`data-model.md` deleted (24→22), `audience.md` wired into `project-onboarding`; knowledge-capture routing cross-pointers (documentation-budget ↔ knowledge-curation); **`workflows/git-workflow.md` renamed `git-discipline.md`** (name collision with the CLI provider skill confused retrieval).
- **Verified:** preflight 0/0; run-tests 24/24; `--all` green; mirrors clean. Spec: `docs/specs/integration-debloat/spec.md`. Detail: `docs/release-notes/v3.18.0.md`.

## [3.17.1] — 2026-06-10

### Fixed — post-ship audit nit-sweep + references/ drift gate

An independent post-ship audit of the v3.16.0→v3.17.0 chain returned **ALL CORRECT, zero blockers**, with residual nits and one real gap — all closed here:

- **`references/*.md` now drift-gated** — `mirror-skills.sh` hashes + manifests every references file (manifest 56 → 68 entries) and `preflight.sh` §5 verifies them across both mirrors. The per-role don't-lists moved there in v3.17.0; previously only `SKILL.md` files had a drift gate.
- **6 residual stale pointers** still claiming role don't-lists live in `role-discipline/SKILL.md` repointed to `references/<role>.md`: `skill-authoring` (×2 — one also carried a retired `skills/` path), both agent context-load tables, the claude overlay's mandatory-skill bullet (canonical edited, inline re-spliced), `violation-recovery`, `operator-discipline`, the parked architect-sub-agent ticket.
- **PUBLISHING.md** — expected mirror output 56 → 68; the inline public-surface allowlist copy synced to the live CI one (was missing `ROADMAP.md`, `.claude-plugin`, `flow-skills`; still listed retired `skills`).
- **`install-existing-project.md:328`** — installer description "copies `skills/`" → `flow-skills/`.
- **Verified:** preflight 0/0 (now incl. references drift checks); run-tests 24/24; `--all` green; CLAUDE inline overlay byte-matches canonical after re-splice.

## [3.17.0] — 2026-06-10

### Changed — context-floor reduction: always-on session cost cut ~30% (no rule semantics changed)

Implements the structural half of the framework-wide efficiency audit (the repairs were v3.16.4). Measured baseline floor: ~34.5k tokens/session (Claude Code) / ~27.9k (Codex). Measured reduction: **~8k tokens/session** (PO −8.0k · AI-Dev −7.9k · Deploy −8.5k). Independent reviewer attested per-rule that **no FR semantics were lost**; an independent implementer built it; spec: `docs/specs/context-floor-reduction/spec.md`.

- **`role-discipline` split per-role (C1):** the 4 role sections moved to `flow-skills/role-discipline/references/{product-owner,ai-developer,architect,deploy}.md` (lazy-loaded on role match — same pattern as `communication/references/`); SKILL.md (50.3KB → 23.4KB) keeps all shared protocols (Operator Relay, Chat-Text, Forward Momentum, Supersede, FR-24 digest) + a role→file index. All 55 rule IDs verified exactly-once; mirrors carry `references/` byte-identical.
- **FLOW_RULES FR-16..24 compressed to house style (C2):** rows + implications deduplicated against the protocols role-discipline already delivers mandatorily (live region −8.2KB). FR-01..15, FR-25, attestation, amendment log byte-identical. Every dropped clause verified surviving in its enforcement-pointer target (FR-21 safety floor + FR-22 storage≠retrieval/carve-outs/not-retroactive kept verbatim-equivalent).
- **Adapter dedup (C3/C4):** CLAUDE/AGENTS base sections that duplicated their overlay blocks → single pointers (attestation, footer, operator-questions, project-values, active-context each now have exactly one in-file copy; overlays stay byte-identical to the canonical templates). Canonical `claude-md-overlay.md` 28-bullet catalog → 3-line pointer (Claude Code injects every skill description; the AGENTS comma list is kept — load-bearing on Codex).
- **Install copy excludes upstream dev history (C5):** README + `install-existing-project.md` copy blocks now copy only the live `docs/*.md` framework docs (consumers no longer inherit ~7.4MB of FuseBase Flow's own specs/changes/release-notes/assets). Also fixed: a form-feed corruption in the install doc's PowerShell line (introduced v3.16.4).
- **Review fixes folded in:** 11 stale pointers into the moved role sections repointed (`references/<role>.md`) across workflows/templates/agents/`command_policy.py`/rail-mapping; CLAUDE.md attestation-pointer wording corrected.
- **Verified:** preflight 0/0; run-tests 24/24; `--all` green; inline overlays byte-match canonical; health-check anchors + preflight §8 intact. Detail: `docs/release-notes/v3.17.0.md`.

## [3.16.4] — 2026-06-10

### Fixed — efficiency repairs: two broken consumer paths + drift sweep (audit-driven; no rule change)

A framework-wide independent efficiency audit (follow-up to the FR-25 token audit) found two outright **bugs** plus accumulated drift:

- **Existing-repo install was broken** — `docs/install-existing-project.md` copy blocks (bash + PowerShell) still copied the retired `skills/` directory and never `flow-skills/` (canonical since v3.9.0): a consumer following the docs landed with **zero Flow skills**. Fixed.
- **Hook quick-activation was broken** — `.claude/settings.json.example` used `${PROJECT_DIR}`, which Claude Code never sets; the documented `cp` activation left **all six Flow lifecycle hooks silently dead**. Now `"$CLAUDE_PROJECT_DIR"` (the real runtime var); `settings-json-merge.py` still normalizes the legacy placeholder in old installs.
- **Inline overlay blocks re-synced to canonical** — the template's own AGENTS.md/CLAUDE.md overlay copies had drifted (missed the v3.16.3 amendment-log stop; CLAUDE's inline block lacked the `CUSTOM:SKILL` markers the recovery refresh anchors on; AGENTS's lacked `FLOW:PRESERVE`).
- **Deprecated jq/bash Stop scripts removed** (`run-lint-on-stop.sh`, `run-typecheck-on-stop.sh` — deprecated since v3.2.0, shipped 14 releases since); CLI vendor provenance re-stamped; the settings merger still strips them from older downstream installs.
- **Stale-facts sweep** — 9 files still naming canonical `skills/` (framework.md, constitution, tradeoffs, problem-catalog/skills READMEs, skill-template, eight-phase-flow, knowledge-curation, install doc); README's false "fresh install ships no docs/specs" claim corrected; `role-discipline` scoped-loading token claim replaced with measured numbers.
- **`docs/rail-mapping.md` rows FR-20..25 added** (the table was 6 releases behind its own "every new rule adds a row" contract); surface counts now 25-base; dead `open-questions.md` reference removed; ROADMAP radar updated.
- **Verified:** preflight 0/0; run-tests 24/24; `--all` green; settings example parses as valid JSON with all 6 handlers on `$CLAUDE_PROJECT_DIR`. Change-note: `docs/changes/2026-06-10-flow-efficiency-repairs.md`.

## [3.16.3] — 2026-06-10

### Changed — token-trim: session reads stop at the amendment log (no semantics change)

An independent token-economy audit of FR-25 (verdict: **NET POSITIVE — 4-6× cost coverage — with waste**; break-even at only 5-6 avoided monolith slice-reads per 100 sessions) surfaced one framework-wide find and two FR-25 dupes:

- **Amendment log no longer session-loaded** — the audit's biggest find: session-start instructions said "load `FLOW_RULES.md`" unbounded, so the amendment log (~4.1k tokens, ~40% of the file, pure dated history) was paid by **every compliant session in every consumer repo** (~410k tokens/100 sessions). All read instructions (AGENTS/CLAUDE/GEMINI/copilot/cursor adapters, `session-initiation`, `handoff-implement`, both overlay templates) now say stop at `## Amendment log`; a boundary marker sits under the heading (heading text unchanged — it anchors the sweep guard). `role-discipline:50`'s contradictory "not injected — read on demand" load-model row corrected.
- **FR-25 row + implication deduplicated** to house style (1,626→~700 and 1,348→~700 chars; ~47k tokens/100 sessions) — all operative semantics preserved; restated rationale cut (the spec owns it).
- **role-discipline write-preamble** collapsed into the digest table it pointed at (~12k/100 sessions).
- Correctness riders: `module-size-discipline` decisions **M4 superseded in place** (FR-18 — was stale against the v3.16.2 shipped baseline); gate stderr now states "extraction is in-scope for the current task" (saves operator round-trips).
- Audited net: **~470k tokens saved /100 compliant sessions per consumer repo**, zero behavior change. Change-note: `docs/changes/2026-06-10-flow-token-trim.md`.

## [3.16.2] — 2026-06-10

### Changed — FR-25 hardening: the gate is now live by default (no rule text change)

Driven by a post-ship stress test: an empirical probe of the motivating consumer repo (its monoliths grew 14,202→15,616 and 10,434→10,840 lines in the days since the audit — steering alone demonstrably doesn't stop growth) plus an independent devil's-advocate review whose verdict was "right call, wrong delivery posture."

- **Template ships its own baseline** (`policies/module-size-baseline.txt`, dogfood: 1 row) — the gate is **live from commit #1** on greenfield instantiations instead of dormant until an operator runs `--write-baseline`. Retrofit installs re-key once (one command, now a step in both install docs; the block message prints it too).
- **Local override hardened (kill-switch closed):** `module-size.local.yml` is now **additive-only** — `exempt_globs`/`source_globs` entries are appended; `enforcement`/`ceiling`/`baseline_file` cannot be overridden locally (a gitignored REPLACE-semantics file could silently flip block→warn, invisible to diff and review). The engine prints a notice whenever a local override is active. New gate scenario S7 proves a local `enforcement: warn` is ignored.
- **`--write-baseline <path>` single-file re-key** — the rename remedy and targeted refresh; a full regen grandfathers every accumulated violation (global amnesty), so refreshes can now stay surgical. New scenario S8 proves one row tightens without touching others.
- **Baseline path protected** (`fusebase_flow_internals`) — the ratchet's state ledger is no longer freely agent-editable.
- **CI surface:** `fusebase-flow-verify.yml` gains a "Module-size ratchet `--all`" step — local `--no-verify`/partial-stage dodges no longer survive to main unnoticed.
- **Default test-file exemptions** (`**/*.test.*`, `**/*.spec.*`, `**/__tests__/**`) — kills the likeliest early-false-block → exemption-bleed path.
- **LL split-quality hook:** an LL pass that extracts a module must name the responsibility seam in its change-note (LL has no review step — the named seam is the operator's at-a-glance check).
- **Observable mechanical-split criterion** in `code-review` 5c + the skill: extraction landing in `utilsN`/`helpersN`/`misc`/`extra`-style names = blocker; no intent inference (the two surfaces previously phrased this differently).
- Gate scenarios 6 → **8**; totals **24/24**. `FLOW_RULES.md` Status `v0.17 → v0.18` (no rule text changed). Change-note: `docs/changes/2026-06-10-fr-25-hardening.md`. Detail: `docs/release-notes/v3.16.2.md`.

## [3.16.1] — 2026-06-10

### Added — public roadmap + parked backlog published (docs-only; no rule/behavior change)

Formalizes the roadmap publication (`ad1fb7f` + `2b02db7`) as a release and brings all live attestation strings to v3.16.1.

- **`ROADMAP.md`** (new, root) — public view of what's likely next, rewritten to the v3.16.0 baseline: released arc v3.2→v3.16; **Next likely**: architect sub-agent, role × path hook enforcement (now easier — FR-25 shipped the glob/policy-gate plumbing); **radar**: rail-mapping FR-20..25 rows, `.claude/commands` refresh path, baseline rename handling, dogfood baseline, new provider surfaces; corrected non-goals (Claude Code plugin + slash commands are optional conveniences, never the primary path; regex gates only for objectively countable rules).
- **`docs/backlog/`** — `architect-sub-agent` + `role-path-hook-enforcement` tickets harvested from the stranded pre-v3.2 local line (d8f24f5, never pushed) and refreshed (flow-skills/ paths, 22/22 test baseline, `docs/tmp/handoff` relays, `*.local.yml` gitignore); `index.md` created (3 parked tickets).
- **CI** — `ROADMAP.md` added to the public-surface allowlist; README public-docs list + CONTRIBUTING before-you-start gain roadmap pointers.
- Housekeeping: local `main` fast-forwarded to origin/main (stranded line archived locally); attestation strings swept to v3.16.1; `FLOW_RULES.md` Status `v0.16 → v0.17` (no rule text changed).
- **Verified:** preflight 0/0; run-tests 22/22; CI green incl. public-surface guard. Detail: `docs/release-notes/v3.16.1.md`.

## [3.16.0] — 2026-06-10

### Added — FR-25 module-size ratchet (first deterministic write-time gate)

Closes the structural blind spot: nothing in the lifecycle looked at file size. Consumer audit (paperclip+hermes-v1) found 19,026 / 14,202 / 10,434 / 5,363-line source files accreted under full Flow discipline — tasks say WHAT never WHERE, every gate is behavioral, FR-21 makes mid-task extraction look like scope creep; the monolith is the integral of N reasonable diffs. Source is AI-read (FR-22/FR-24 audience principle) → over-ceiling files degrade every future session. Unlike FR-22/FR-23 (semantic), line count is objective — so this rule ships a real gate.

- **`FLOW_RULES.md`** — new **FR-25 (module-size ratchet)** + implication; Status `v0.15 → v0.16`; amendment entry.
- **Gate (new):** `policies/module-size.yml` (ceiling 800 · source/exempt globs · local override) + `hooks/shared/module_size.py` (wrapper `hooks/local/check-module-size.sh`; modes `--staged`/`--worktree`/`--all`/`--write-baseline`) wired into `hooks/git/pre-commit`. **Ratchet semantics:** new file > ceiling → block; baselined over-ceiling file may shrink, never grow; **no baseline → warn-only** (adoption-safe); `--write-baseline` is operator-run and activates block mode.
- **Tests:** `hooks/tests/test-module-size.sh` (6 scenarios) + `run-tests.sh` phase 2 — totals **22/22** (16 fixtures + 6).
- **Plan-time:** `implementation-planning` + `templates/tasks.md` — every task names target file(s); over-ceiling target → extraction (named seam) or one-line operator exemption.
- **Steering:** 28th skill `flow-skills/module-size-discipline`; FR-25 line in the FR-24 write-time digest (`role-discipline`); `code-review` 5c dimension (over-ceiling growth = blocker; mechanical `utilsN` split check — split quality stays semantic, review-only); `lightweight-lane` interplay (extraction-to-satisfy-ratchet is in-scope, not promotion); `handoff-implement` checklist + `session_start.py` reminder broadened.
- **Not done (deliberately):** no forced refactor of existing monoliths; no regex split-quality gate; no `*.md` gating (FR-23 owns docs); no template-shipped baseline.
- Skill count 27 → **28** (mirrors 56); overlay templates backfilled with `documentation-budget`/`handoff` (pre-existing drift); FR range swept to FR-01..FR-25; VERSION → 3.16.0.
- **`sync-version-strings.sh`** — two history-falsification guards: `docs/changes/**` (dated Lightweight-lane ledger) added to the never-touch prune list, and the `FLOW_RULES.md` dated amendment log (below `## Amendment log`) excluded from substitutions; the v3.14.0 amendment entry was restored to its true `FR-01..FR-23` text (corrupted by the v3.15/v3.16 sweeps).
- **Independent pre-release review (4 blockers fixed, plus hardening):** PUBLISHING.md expected counts 22/22 + 56; `.claude/commands/{onboard,product-owner}.md` attestation ranges FR-01..FR-22 → FR-01..FR-25 (3 generations stale); `policies/*.local.yml` actually gitignored (a committed override could silently neutralize the gate); `run-tests.sh` crash guard (scenario-script death can no longer report green); `core.quotepath=off` on git calls (non-ASCII filenames no longer skip the gate); unknown gate args exit 2 instead of silently running `--staged`; rename tripwire documented in the skill; stale "20 always-on rules" prose → 25 in `.cursor`/`.github`/architecture-overview.
- **Verified:** preflight 0/0; run-tests **22/22**. Spec: `docs/specs/module-size-discipline/spec.md`. Detail: `docs/release-notes/v3.16.0.md`.

## [3.15.0] — 2026-06-08

### Added — FR-24 write-time discipline delivery (write-time rules reach the writing agent)

Closes a **class** of delivery gaps surfaced by a consumer (WorkHub Managed): after upgrading to v3.14.2, an operator-launched AI-Developer fix chain still produced verbose human-oriented comments — FR-22's carrier skill is description-matched and never loaded in that flow. Zoom-out (FR-20): FR-22 is one symptom; the write-time rules **FR-09 (Mode B), FR-18 (supersede), FR-22 (comments), FR-23 (documentation budget)** all share the same "is the rule in the writing agent's context at write time?" hole — and FR-23 (the documentation rule itself) is exposed identically.

- **`FLOW_RULES.md`** — new **FR-24 (write-time discipline delivery)** + implication; title/Status `v0.14 → v0.15`; amendment entry. Codifies *one* systemic delivery mechanism instead of per-rule patches.
- **`flow-skills/role-discipline/SKILL.md`** — new always-on, role-scoped **§ Write-time discipline digest**: a **pointer index** (FR-09/18/22/23, one line + skill pointer each — not duplicated bodies, honoring FR-23) delivered in every writing session's context. Replaces the old description-match-dependent FR-22 pull-directive.
- **`templates/handoff-implement.md`** — hard-invariants broadened from FR-22-only to the digest (FR-09/18/22/23); delegation push-block now inlines the digest for sub-agents (which don't inherit the always-on path).
- **`hooks/handlers/session_start.py`** — FR-22 reminder broadened to the write-time set (FR-24).
- **Audience principle codified:** dev artifacts (comments, specs, decisions, tasks, handoffs, business-logic *index*) are AI-consumed → optimize for AI only; the human-facing surface (README/onboarding/legal/translations, opt-in `business-logic.md` narrative) stays human-readable.
- **Not done (deliberately):** no new skill; no `mandatory_load` change (the 3rd-always-on-skill option was already rejected as self-contradictory context bloat); no regex/lint comment gate (semantic). FR range swept to FR-01..FR-24; baselines + VERSION → 3.15.0.
- **Verified:** preflight 0/0; run-tests 16/16. Spec: `docs/specs/write-time-discipline-delivery/spec.md`. Detail: `docs/release-notes/v3.15.0.md`.

## [3.14.2] — 2026-06-07

### Fixed — doc-consistency sweep (counts + canonical-path refs)

Polish pass correcting stale prose counts/paths the version-string sweep doesn't reach. No behavior change.

- **Skill/mirror/hook counts corrected** to the v3.14 baseline (27 Flow skills · 54 mirrors = 27 × 2 · 16/16 hook tests) in: `audit/README.md`, `docs/fusebase-cli-edition.md`, `docs/source-map.md`, `docs/compatibility.md` (already), `PUBLISHING.md` (hook tests 14→16, mirror 18→54), README catalog (already).
- **Canonical skill path corrected** `skills/` → `flow-skills/` (canonical since v3.9.0) in `docs/source-map.md` and `docs/clean-room.md` attestation-scope sections.
- **Translated READMEs** (`docs/translations/{de,es,fr,ja,pt-BR,zh-Hans}`) audited — intentionally version-free summaries that point to the canonical English README; correctly need no per-release count/version edits (no drift by design).
- `.claude-plugin/plugin.json` / README badge / VERSION → 3.14.2; attestation strings swept; `FLOW_RULES.md` Status `v0.13 → v0.14` + amendment entry.
- **Verified:** preflight 0/0 (incl. §8); run-tests 16/16. Detail: `docs/release-notes/v3.14.2.md`.

## [3.14.1] — 2026-06-07

### Fixed — release-hygiene polish (no model/behavior change)

Small consistency patch over v3.14.0. The handoff model is unchanged; this corrects surface metadata and adds a guard so it can't silently drift again.

- **`/handoff` vs `handoff` skill clarified** — `/handoff` is the **Claude Code** slash command; the `handoff` **skill** is the portable cross-agent workflow. `AGENTS.md` now states the non-Claude invocation explicitly ("invoke the `handoff` skill and write `docs/tmp/handoff.md`" on Codex / Cursor / Copilot / Gemini); `CLAUDE.md` bullet clarified.
- **`.claude-plugin/plugin.json`** version `3.10.0` → `3.14.1` (was badly stale).
- **README** version badge `3.11.1` → `3.14.1`; existing-repo copy block fixed to `cp -R $SRC/flow-skills ./` (was `skills/`).
- **`docs/compatibility.md`** refreshed: 27 Flow skills (was 14), mirror count 54 = 27 × 2 (was 28 = 14 × 2), hook tests 16/16 (was 14/14), canonical source is `flow-skills/` (was `skills/`), `/handoff` listed.
- **`preflight.sh` §8 (new)** — command-surface consistency guard: `.claude/commands/handoff.md` exists, `CLAUDE.md` lists `/handoff`, `AGENTS.md` explains the portable invocation, and `.claude-plugin/plugin.json` version == `VERSION`. (Verified: negative test fails preflight, positive passes.)
- Version-string sweep brought live attestation strings to v3.14.1; `FLOW_RULES.md` Status `v0.12 → v0.13`.
- **Verified:** preflight 0/0; run-tests 16/16. Detail: `docs/release-notes/v3.14.1.md`.

## [3.14.0] — 2026-06-07

### Added — handoff procedure finalized (`handoff` skill + `/handoff` command + template) + version-string sweep

Completes the active-continuity half of FR-23 Tier 2 (formal relays already moved to `docs/tmp/handoff/` in v3.13.0) and brings every live attestation string current. No FR added/removed.

- **`flow-skills/handoff/SKILL.md`** (new) — operator-triggered (`invocation: manual`) skill that writes the active session restart state to `docs/tmp/handoff.md` for the next AI coding agent (16 sections, Mode B, supersede-in-place per FR-18, pointers-not-reprints per FR-23). Distinct from the formal implement/deploy relays.
- **`templates/handoff.md`** (new) — the 16-section Mode B substrate (Session Role → Completion Criteria) the skill fills.
- **`.claude/commands/handoff.md`** (new) — `/handoff` slash command (4th command).
- **Version-string sweep** (`hooks/local/sync-version-strings.sh`) — brought all live attestation/banner strings to **v3.14.0 / FR-01..FR-23 / 27 skills** across adapters, agents, workflows, templates, overlays, and framework docs (history preserved: release-notes/specs/handoff archives pruned). This was the deferred mechanical hygiene from the v3.12–v3.13 line.
- Canonical skill count **26 → 27**; `CLAUDE.md`/`AGENTS.md` skill catalogs + `/handoff` wired; README counts corrected (skills 25→27, templates 14→24); `FLOW_RULES.md` Status `v0.11 → v0.12` + amendment entry. Mirrors regenerated (54 = 27 × 2).
- **Verified:** preflight 0/0; run-tests **16/16 PASS**. Detail: `docs/release-notes/v3.14.0.md`.

## [3.13.0] — 2026-06-07

### Changed — handoff artifacts consolidated under `docs/tmp/handoff`

All handoff artifacts now live under `docs/tmp/handoff` (handoffs are operational/transient AI-workflow artifacts, not durable product docs). Deferred from the v3.12.1 patch because formal relays are load-bearing for the deploy-safety gate; done atomically here with full gate validation. No FR added/removed.

- **Path model:** active restart state = `docs/tmp/handoff.md` (single file, superseded each session); formal implement/deploy/architect relays = `docs/tmp/handoff/<date>-<slug>-<stage>.md` (dated siblings). `docs/tmp/` is git-tracked → audit trail preserved.
- **Deploy-safety gate rewired (atomic):** `policies/required-artifacts.yml` (`before_deploy_command` path_glob + `smoke_results_present` signal), `policies/gate-contracts.yml` (smoke-dir pattern), `hooks/handlers/stop.py` (smoke regex), and fixtures 13/14 → `docs/tmp/handoff`. Semantics unchanged.
- **References updated:** all workflows, agents (+ `.claude`/`.codex` mirrors), templates, flow-skills (+ mirrors), `AGENTS.md`, `README.md`, `.cursor` rules, `.github` instructions, live docs, and the FR-23 row + implication in `FLOW_RULES.md`.
- **`hooks/local/sync-version-strings.sh`** — prune list note + explicit `docs/tmp/handoff` entry so dated formal relays are protected from the version-string sweep.
- **`docs/handoff/`** retained as a frozen historical archive (README redirects to `docs/tmp/handoff/`); existing dated artifacts preserved in place.
- **Preserved history:** CHANGELOG, release-notes, `docs/specs/*`, `docs/changes/*`, and the FLOW_RULES amendment log were NOT rewritten.
- `FLOW_RULES.md` Status `v0.10 → v0.11` + amendment-log entry; canonical baselines (FLOW_RULES/AGENTS/CLAUDE/GEMINI) + VERSION → v3.13.0. Spec: `docs/specs/handoff-path-migration/spec.md`.
- **Verified:** preflight 0/0; run-tests **16/16 PASS** (deploy-gate fixtures green post-migration). Detail: `docs/release-notes/v3.13.0.md`.

## [3.12.1] — 2026-06-07

### Fixed — FR-23 wiring completeness (post-release review patch)

A corrective patch closing gaps an independent review found after v3.12.0. No new rule; FR-23 semantics unchanged.

- **`GEMINI.md`** — baseline was stale (`v3.11.1` / `FR-01..FR-22`, no documentation-budget). Swept to `v3.12.1` / `FR-01..FR-23` so the AGENTS/CLAUDE/GEMINI always-on trio is consistent. (FLOW_RULES.md was already correct at v3.12.0.)
- **`flow-skills/requirements-specification/SKILL.md`** — fixed a stale `skills/lightweight-lane/SKILL.md` reference → `flow-skills/...`; added an FR-23 documentation-budget pre-write classifier (Tier 0/1/2 → no spec artifacts; only Tier 3/4 drafts a full spec).
- **`flow-skills/implementation-planning/SKILL.md`** — added an FR-23 documentation tier gate: `decisions.md` only when a real decision exists, `verification-gate.md` only when lane/policy requires, the implement handoff points to canonical spec/decisions/tasks and must not reprint them. Fixed two stale `skills/` references → `flow-skills/`.
- **`flow-skills/communication/SKILL.md`** — Mode-B prose intro now lists `docs/tmp/handoff.md` (active restart state) alongside `docs/handoff/` (formal relays).
- **`flow-skills/product-docs-first/SKILL.md`** — gating extended to "already-scoped implementation work".
- **`flow-skills/business-logic-guardian/SKILL.md`** — now guards on **either** `docs/<app>/business-logic-index.md` (AI-default) **or** `docs/<app>/business-logic.md` (human narrative); index is primary when both exist.
- Version strings on the canonical baselines (FLOW_RULES/AGENTS/CLAUDE/GEMINI) → v3.12.1; mirrors regenerated; manifest updated.
- **Deferred (unchanged):** formal implement/deploy handoff relays remain `docs/handoff/*` because they are wired into the deploy-safety gate (`policies/required-artifacts.yml`, `policies/gate-contracts.yml`) + ~18 workflow/agent/template files; migrating them to `docs/tmp/handoff` is a separate ticket (operator confirmation pending). The repo-wide `sync-version-strings.sh` attestation sweep also remains deferred. preflight 0/0; run-tests 16/16. Detail: `docs/release-notes/v3.12.1.md`.

## [3.12.0] — 2026-06-07

### Added — FR-23 documentation budget (+ documentation-budget skill)

Documentation-overhead reduction. PO and AI Developer sessions create AI-consumed artifacts that cost context on every future load and spawn stale conflicting copies — `decisions.md` with no real decision, handoffs that reprint the full spec, product docs expanded for small fixes, narrative-heavy business-logic docs. FR-23 makes documentation proportional to risk/value: classify each artifact by tier before writing, honor canonical ownership, prefer pointers over restatement. It is the documentation-axis complement to FR-21 (which scales process ceremony); Tier 1 == the Lightweight change-note.

- **`flow-skills/documentation-budget/SKILL.md`** (new) — pre-write classifier: tiers 0-4 (0 none · 1 change-note · 2 active handoff · 3 spec+tasks · 4 full pack), canonical artifact-ownership table, pointer-over-duplication rule, product-doc gating (defers to `product-docs-first`), business-logic-index rule, anti-patterns. Active session continuity is `docs/tmp/handoff.md`; formal implement/deploy relays stay at `docs/handoff/*`.
- **`FLOW_RULES.md`** — FR-23 row + implication paragraph; Status `v0.9 → v0.10`; title + self-attestation `FR-01..FR-22 → FR-01..FR-23`, `v3.11.1 → v3.12.0`; amendment-log entry. **FR-01..FR-22 rule rows/implications unchanged.**
- **`templates/business-logic-index.md`** (new) — AI-readable retrieval index (tables + source paths), the default business-logic format for AI workflows. The human-narrative `templates/business-logic.md` is **preserved** as the explicit human-readable option.
- **Cross-references** (one-line, non-duplicating) added to `communication` (`docs/tmp/handoff.md` in the Mode B list + "FR-23 governs whether an artifact exists"), `lightweight-lane` (change-note = Tier 1), `product-docs-first` (don't expand for small fixes), `business-logic-guardian` (index template default).
- **`CLAUDE.md` / `AGENTS.md`** — version, FR range, attestation bumped to v3.12.0 / FR-23; on-demand skill catalog `25 → 26` with `documentation-budget`; active-vs-formal handoff rows.
- Canonical skill count **25 → 26**. Mirrors regenerated (52 = 26 × 2); manifest updated.
- **Not done (deferred):** the repo-wide `sync-version-strings.sh` attestation sweep (workflows/agents/templates still read v3.11.1 / FR-01..FR-22) — separate follow-up. No safety gate weakened; Full lane + FR-05/FR-07/FR-12 unchanged. Independently adversarially reviewed (one AGENTS.md sweep blocker found + fixed). preflight 0/0; run-tests 16/16; health HEALTHY (26 skills). Detail: `docs/release-notes/v3.12.0.md`.

## [3.11.1] — 2026-06-06

### Fixed — `sync-version-strings` nested-docs prune (+ FLOW_RULES v0.9)

`sync-version-strings.sh` rewrites live attestation strings while never touching dated history (handoffs, specs, release-notes). Its prune list used exact top-level `-path` patterns, but `find`'s `-path` is exact (no implicit depth), so **per-app layouts** (`docs/<app>/handoff`, `docs/<app>/specs`, …) escaped the prune and the rewrite falsified their historical attestation versions. Reproduced by the Product Owner before the fix.

- **`hooks/local/sync-version-strings.sh`** — prune list extended with depth-tolerant `./docs/*/{release-notes,handoff,specs,fusebase-health}` siblings (spans any nesting depth ≥1; flat case still covered). One-line FR-22 tripwire above the `find` block. No other engine script touched.
- **`FLOW_RULES.md`** — Status `v0.8 → v0.9` + one amendment-log entry. FR-01..FR-22 rule rows/implications unchanged.
- VERSION 3.11.0 → 3.11.1. Live acceptance gate: fixtures under `docs/_acctest/{handoff,specs}/` carrying old attestation are NOT in the `--dry-run` would-change list (pruned); framework live files still bump. preflight 0/0; health HEALTHY (25 skills). Detail: `docs/release-notes/v3.11.1.md`.

## [3.11.0] — 2026-06-06

### Added — FR-22 write-time delivery (carrier skill; semantics unchanged)

Closes the **delivery gap** in FR-22 (the code-comment policy shipped in v3.10.0). FR-22 shipped as a correct *rule* but had no **write-time carrier** — its body never reached a code-*writing* agent's context at the moment comments are written. A v3.10.0 consumer (`WorkHub Managed`) proved the gap in production: a delegated AI Developer sub-agent wrote default JSDoc-heavy comments — the exact density-ratchet FR-22 was authored to break — because the breaker was never loaded. FR-22's semantics are unchanged; only delivery (carrier, pointers, push) changed.

- **`flow-skills/comment-policy/SKILL.md`** (new) — description-matched write-time carrier; carries FR-22's two comment kinds, remove-list, density-override, storage≠retrieval subtlety, carve-out pointer, and a **Delegation push block**. Plus `references/audit-prompt.md` bundled so it rides the mirror into every consumer.
- **`flow-skills/role-discipline/SKILL.md`** — corrected the false ":50 already-loaded" claim (the hook existence-checks, does not inject) that suppressed the workaround; added an AI-Developer directive to load `comment-policy` before writing code.
- **`flow-skills/task-delegation/SKILL.md`** — mandatory clause: a delegated code-writing slice MUST carry the Delegation push block (push, not pull); read-only/triage delegation exempt.
- **`FLOW_RULES.md` / `policies/comment-policy.yml`** — FR-22 audit-prompt pointers re-pointed from the undelivered `docs/comment-policy.md` to the delivered `flow-skills/comment-policy/references/audit-prompt.md`. FR-01..FR-21 byte-unchanged.
- **Behavioral proof** — V7 (pull) NEGATIVE: an unprimed sub-agent wrote ~49 comment lines (~90% removable); V8 (push) PASS with the block inlined. Drove the push decision. Canonical skill count 24 → **25**.
- **Not done** — no regex/lint comment-gate (semantic, not pattern-matchable); not retroactive. preflight 0/0; run-tests 16/16; health HEALTHY (25 skills). Detail: `docs/release-notes/v3.11.0.md`.

## [3.10.0] — 2026-06-04

### Added — FR-22 code-comment policy (tripwire + retrieval-pointer only)

A new always-on rule. Flow source files are read by AI agents, not humans (a human asks an agent to explain rather than opening the file), so WHAT-restating prose, recorded-elsewhere rationale, and changelog comments serve an absent audience and cost context on every load — measured ~45% of comments removable in trust-critical files across two independent projects (paperclip+hermes-v1 + AssetWatch Prod). Two framework-level root causes: the base "match surrounding comment density" instruction is a one-directional ratchet (now explicitly overridden), and every Stop-hook gate is comment-blind so over-commenting is invisible to the loop.

- **FR-22 (FLOW_RULES.md)** — write only two comment kinds: a one-line **tripwire** (a non-obvious constraint an editing agent could violate; ≤~4 lines only for security/auth/concurrency/platform-quirk) and a ≤1-line **retrieval pointer** to the external WHY-home (`(decision B2)`, `backlog 156`). Remove WHAT-restating, recorded-elsewhere rationale (→ pointer), and changelog/history (→ git). Includes the explicit **density-override** clause that breaks the ratchet.
- **Two subtleties preserved.** *Storage ≠ retrieval* — the pointer is NOT a duplicate; deleting it orphans the external record the agent has no in-context trigger to open (kill the prose, keep the pointer). *Architecture-dependent* — carve-outs are project-settable, not hardcoded.
- **`code-review` skill — the enforcement layer.** New comment-policy dimension flags WHAT-restating / duplicated-rationale / changelog comments AND verifies tripwires + pointers were retained (catches the symmetric **over-trim** failure: a deleted pointer/tripwire is a blocker). Plus a failure-case row and an anti-pattern forbidding a regex/lint gate.
- **`policies/comment-policy.yml`** — declarative `trust_critical_globs` (auth/identity/session/gate, migrations; opt-in/commented like `protected-paths.yml`) + `local_override_file`. The project-settable carve-out source.
- **`docs/comment-policy.md`** — rationale, cross-project evidence, and a reusable **independent-audit prompt** (run per-project to derive carve-outs). Plugin-specific clause generalized.
- **`templates/handoff-implement.md`** — FR-22 added to hard invariants + a pre-commit checklist line.
- **Not a gate.** Distinguishing a tripwire from a restate-WHAT comment is semantic, not pattern-matchable; enforcement is write-time (FR-22) + review-time (code-review), never a regex/lint hook. Not retroactive — existing files are cleaned only via an explicit Lightweight pass (comments strip from build output, so no deploy).

Spec: `docs/specs/comment-policy-fr22/`. FR-range auto-synced FR-01..FR-22 across adapters; skill count unchanged (24). Tests: preflight 0/0; run-tests 16/16; recovery sim 31/31; health HEALTHY; plugin valid. VERSION 3.9.0 → 3.10.0.

## [3.9.0] — 2026-06-04

### Changed — canonical skills relocated `skills/` → `flow-skills/` (resolves the U12 CLI collision end-state)

The FuseBase CLI deprecates the root `./skills` folder (`⚠️ The ./skills folder is obsolete and should be deleted`), which Flow had used as its **canonical** source. v3.8.3 shipped a non-foreclosing guard (health flags deletion + docs say ignore the CLI warning); this release resolves the standing collision by moving Flow's canonical store to a Flow-namespaced path the CLI never touches. The collision can no longer exist under any CLI behavior.

- **Canonical is now `flow-skills/`** (was root `skills/`). Chosen over `.fusebase-flow/skills/` because `.fusebase-flow/` is already gitignored as a runtime-state namespace (`.gitignore`); a visible top-level `flow-skills/` avoids a fragile ignore-exception and the runtime/source confusion. `agents/` is **not** moved — the CLI doesn't deprecate it.
- **Zero-touch migration.** `bash hooks/local/upgrade.sh` (and `bootstrap-upgrade.sh` via it) lands canonical at `flow-skills/` from upstream, then retires a legacy root `skills/` (backed up `skills.pre-upgrade-<ts>`), and re-mirrors. Idempotent. Every reader prefers `flow-skills/` and falls back to legacy `skills/`, so a partially-migrated tree still works.
- **Readers repointed:** `mirror-skills.sh`, `fusebase-flow-health-check.sh`, `check-cli-flow-conflicts.sh`, `preflight.sh`, `upgrade.sh` (`CONTENT_DIRS`), `sync-version-strings.sh` (skill-count), `session_start.py`, `command_policy.py`, `upgrade-engine.sh`. CI public-surface allowlist now accepts `flow-skills` (rejects a stray `skills/` reappearing).
- **U12 guard inverted (not removed).** Canonical absent (`flow-skills/`) while mirrors exist → loud, recoverable `FLOW_LAYER_DRIFT` naming the restore path. A leftover legacy root `skills/` alongside `flow-skills/` is now a **benign INFO** advising the (idempotent) migration — the CLI's "delete ./skills" warning is finally correct for Flow too.
- **Provider mirrors + plugin unchanged.** `.claude/skills/` and `.agents/skills/` keep their paths (generated by skill name); `.claude-plugin/plugin.json` is unaffected. Docs/overlays/install guides repointed; the README/AGENTS "don't delete root skills/" guard note is replaced with the relocation explainer.

Spec: `docs/specs/u12-canonical-skills-relocation/`. Tests: recovery sim **31/31** — incl. **U12** (deleted `flow-skills/` → `FLOW_LAYER_DRIFT`), **U19** (legacy leftover benign), **U20** (real `upgrade.sh` run: migrates root `skills/` → `flow-skills/`, retires old dir w/ backup, re-mirrors, idempotent). run-tests 16/16; preflight 0/0; health HEALTHY (24 skills); mirror drift 0; plugin valid. VERSION 3.8.7 → 3.9.0.

## [3.8.7] — 2026-06-01

### Fixed — downstream install/upgrade review against v3.8.5 (Windows overlay) — F1–F4 (+F5 doc)

A downstream verified v3.8.4/U14 fixed, and surfaced 5 more (2 High). All confirmed against the cited locations and fixed.

- **F1 [High] — install doc omitted `agents/` from the additive-copy list.** `docs/install-fusebase-cli-project.md` "Safe additive copies" listed `skills/ workflows/ policies/ templates/ hooks/ audit/ state/` but not `agents/` — and `hooks/local/mirror-agents.sh` requires canonical `agents/`. Following the doc literally → mirror-agents aborts, `.claude/agents/` empty, health → `FLOW_LAYER_DRIFT` (0/2 sub-agents). Added `agents/` to the list + both bash and PowerShell blocks.
- **F2 [High] — U11 was only half-applied.** The conflict checker treated deliberate hooks-off as benign (U11), but the **main** engine (`fusebase-flow-health-check.sh`) still `record_drift`-ed the same state → an overlay-only opt-in install verdicted `SHARED_MERGE_DRIFT` and couldn't reach HEALTHY without wiring hooks (defeating "opt-in"). The main engine is now U11-consistent: settings.json with CLI hooks but **no** Flow `stop.py` and no Flow events wired = benign opt-in (LOCAL_OK), not drift. Drift is reserved for the genuine cases — events wired but `stop.py` missing (U14-style mis-wire) or `stop.py` present with an incomplete event set. **Root-cause hardening:** the health check has *two* independent engines (`check-cli-flow-conflicts.sh` and `fusebase-flow-health-check.sh`); U11 had only fixed the first. Audited the main engine for every other by-design class and added behavioral regression tests that run the **main** engine — **U16** (hooks-off → no `SHARED_MERGE_DRIFT`), **U17** (flag-gated absence → HEALTHY), **U18** (`.agents` CLI-provider gap → HEALTHY) — so a future divergence between the two engines is caught. (The CLI-layer cases reach the main engine via a fold that filters to `MISSING`/`DRIFT`, so the conflict checker's `INFO` classifications stay benign there — confirmed by U17/U18.)
- **F3 [Med] — `.gitattributes` (and `LICENSE`/`PUBLISHING.md`/`.python-version`) removed from the unconditional copy list.** Flow's `.gitattributes` has repo-wide `* text=auto`/`eol=lf`; copied into an existing (esp. Windows) repo it renormalizes line endings across every file → massive spurious diff. Moved those four into a new "Copy only after review" section with the reason for each (`.gitattributes` eol bomb; `LICENSE` overwrites yours; `PUBLISHING.md` Flow-internal; `.python-version` pins Python).
- **F4 [Low] — upstream comparison misreported on a shallow/tag staging clone.** A `--depth 1`/`--branch <tag>` `.fusebase-flow-source` (the bootstrap default) can't resolve `origin/main` or traverse history → the engine printed a spurious "upstream NEWER … behind by ? commits". Now detects shallow/detached/unresolvable state and prints "upstream comparison unavailable (shallow/tag staging clone …)" with the staged source VERSION + how to get a precise compare (`git fetch --unshallow`).
- **F5 [Low] — documented** the intended behavior: `--wire-hooks` injects the canonical **node** Stop hooks; if a deprecated `*-on-stop.sh` duplicate is also wired you get a double typecheck. Captured in the maintenance notes (node hooks are canonical; the jq/bash duplicates are deprecated). No code change.
- Out of scope (routed to the FuseBase CLI repo): the CLI's `project-template/eslint.config.mjs` ignores `.claude/**` but not `.codex/**` while emitting `require()`-style `.codex/hooks/*.js` → not a Flow issue.

Tests: recovery sim 27/27 (new U16 main-engine hooks-off; U15 retained). run-tests 16/16; health HEALTHY; plugin valid. VERSION 3.8.6 → 3.8.7; plugin manifests bumped.

## [3.8.6] — 2026-06-01

### Fixed — downstream install/upgrade UX (1 deploy blocker + 2 minor)

From a live overlay project (Vite/React/TS, ESLint flat config, deploy via `fusebase deploy`).

- **[BLOCKER] `.fusebase-flow-source/` fails the project's ESLint → breaks `fusebase deploy`.** The staging clone holds **CLI-owned CommonJS** hooks (`require()`), which trip `@typescript-eslint/no-require-imports`. The path is gitignored, but **ESLint flat config doesn't read `.gitignore`**, and the CLI's `eslint.config` only ignores `.claude/**` — so the clone gets linted and `npm run lint` (hence deploy) exits 1 even with zero app errors. Flow has no eslint config of its own and the hooks are CLI-owned (can't be rewritten — `fusebase update` would re-clobber), so the fix is to stop the staging clone from being linted: new **`hooks/local/eslint-ignore-flow-paths.sh`** (opt-in; idempotent; backs up) adds `".fusebase-flow-source/**"` to the project's flat-config `ignores` right after `".claude/**"`. `upgrade.sh` / `bootstrap-upgrade.sh` now print a loud note (the clone is transient — `rm -rf .fusebase-flow-source` after an upgrade, or run the helper), and AGENTS-overlay maintenance + README document it. Regression test U15.
- **[MINOR] project-values placeholders now point at `/onboard`.** The `### Project-specific values` table read "(customize during install)"; it now reads "(run `/onboard` or edit)" with a note that `/onboard` is the canonical fill step and values are preserved across upgrades (U1 `FLOW:PRESERVE`).
- **[MINOR] cold-start docs layout documented.** README now states `docs/specs/`, `docs/handoff/`, `docs/changes/`, `docs/backlog/` are created on demand (nothing to scaffold), so the expected layout is discoverable before the first PO session. (No empty `.gitkeep` clutter shipped.)

Tests: recovery sim 26/26 (new U15); U1/U9 setups made robust to the placeholder wording. run-tests 16/16; health HEALTHY; plugin valid. VERSION 3.8.5 → 3.8.6; plugin manifests bumped.

## [3.8.5] — 2026-06-01

### Fixed — U14: `--wire-hooks` mis-wired the shared Stop event onto a chain with existing CLI hooks

Downstream report (reproduced): on a project whose `.claude/settings.json` already had CLI Stop hooks, `post-fusebase-update.sh --wire-hooks` produced a Stop entry **labeled** as the Flow hook but carrying the **CLI** `run-typecheck-apps.js` command — so `stop.py` was never wired (Flow's end-of-turn enforcement silently didn't run, and a CLI typecheck ran twice). 5 of 6 events wired correctly; only the shared Stop event was wrong.

Root cause: `settings-json-merge.py`'s `discover_flow_config_from_upstream()` read each event's command as `handlers[0].command`. For Flow-only events that's the Flow handler, but the upstream example's **Stop** chain lists CLI hooks *before* `stop.py` (`[run-typecheck-apps.js, quality-check-apps.js, stop.py]`), so `handlers[0]` was the CLI command — discovered as the "Stop" Flow command and then appended under the Flow label. (The existing recovery test missed it because it runs without a `.fusebase-flow-source/`, so discovery fell back to the correct hardcoded `stop.py` default.)

Fix: discovery now picks the **Flow** handler in each event's chain — the one whose command is under `hooks/handlers/` — instead of `handlers[0]`, falling back to `handlers[0]` only if none match. So the Stop event resolves to `stop.py` regardless of CLI-hook ordering. Regression test added (U14): merge onto a settings.json with pre-existing CLI Stop hooks **and an upstream example present**, asserting the Stop chain's Flow entry is `stop.py`, the CLI typecheck is preserved exactly once, and `stop.py` is in the chain. 25/25 recovery-sim assertions; run-tests 16/16; health HEALTHY. VERSION 3.8.4 → 3.8.5; plugin manifests bumped.

## [3.8.4] — 2026-06-01

### Fixed — Issue 2: false CLI_LAYER_DRIFT for the non-authoritative `.agents/`/`.codex/` provider mirrors

Downstream report (verified against the FuseBase CLI source, `lib/copy-template.ts` + `lib/commands/product.ts`): `fusebase update` writes CLI provider skills/agents to **`.claude/` only** — never `.agents/skills/` or `.codex/agents/`. Combined with Flow's standing guardrail (Flow never writes CLI provider skill text), the `.agents/.codex` CLI-provider mirrors are maintained by **neither** tool — so the health check's `MISSING` → `CLI_LAYER_DRIFT` for them was a false positive, and its "run `fusebase update`" remediation a dead end (the CLI won't touch those paths). Same by-design-≠-drift family as F4/U10/U11.

- `check-cli-flow-conflicts.sh`: `.claude/skills` and `.claude/agents` are the **authoritative** CLI-provider surfaces (full F4/U10 drift logic kept — genuine `.claude` provider drift still escalates with the correct `fusebase update` advice). The **non-authoritative** mirrors (`.agents/skills`, `.codex/agents`) now report a single **benign INFO** ("N/M present, K absent — expected; the CLI maintains provider skills in `.claude/` only; copy from `.claude/` for Codex parity"), never `MISSING`/`CLI_LAYER_DRIFT`.
- The `feature-*` vs `app-*` orphan duplication needs no Flow change — Flow only checks the current `app-*` `known_names`, so CLI-renamed `feature-*` orphans are invisible to it (no churn).
- Tests: recovery sim gains U13 (.agents partial CLI-provider gap is benign); AC4 now checks per-agent cli-owned attribution on the authoritative `.claude/agents` only; the CUSTOM:SKILL-at-risk test moved to `.claude/skills` (the surface the CLI actually refreshes). Precision retained (missing `.claude` provider skill still `CLI_LAYER_DRIFT`). 24/24 sim assertions; run-tests 16/16; health HEALTHY. VERSION 3.8.3 → 3.8.4; plugin manifests bumped.

> **Note on Issue 1 (CLI deprecating root `./skills`):** the v3.8.3 guard (health flags a deleted `skills/`; docs say ignore the CLI warning) stands. The CLI source confirms the deprecation is real and directional, which **rules out** mirroring into `.claude/skills/` as Flow's source (the CLI owns and rewrites that dir on every update). The remaining end-state choice — keep root `skills/` (guarded) vs. move Flow's canonical store to a Flow-namespaced path the CLI ignores — is still an open operator decision.

## [3.8.3] — 2026-06-01

### Fixed — U11 (hooks-off ≠ drift) + U12 guard (don't delete root skills/)

Two downstream findings. **U11:** a `.claude/settings.json` that exists (CLI hooks present) but doesn't wire Flow's `stop.py` was reported as `SHARED_MERGE_DRIFT` — but hook wiring is opt-in (F3), so the deliberate hooks-off default now reads as a **benign INFO** ("not wired — opt-in; enable with `--wire-hooks`"), not drift. A Flow merge that *clobbered* existing CLI Stop hooks is still flagged. Same by-design-≠-drift shape as F4/U10.

**U12 (guard for the FuseBase CLI's `skills/` deprecation):** recent CLI versions warn "the ./skills folder is obsolete and should be deleted." For a Flow install, root `skills/` is the **canonical source** that `mirror-skills.sh`, `upgrade.sh`, and the health mirror-count build on — deleting it breaks Flow, and `fusebase update` won't restore it. This ships the **safe, non-foreclosing guard** the report recommended:
- `check-cli-flow-conflicts.sh` now flags an empty/absent root `skills/` while Flow mirrors still exist as a loud, recoverable `FLOW_LAYER_DRIFT` ("do not delete; the CLI 'obsolete ./skills' warning does not apply to Flow installs; restore with `upgrade.sh` / `bootstrap-upgrade.sh` / `git checkout -- skills/`").
- The AGENTS.md overlay "Maintenance posture" section + README document the do-not-delete / ignore-the-CLI-warning guidance, so downstreams don't self-break.
- The larger architectural question (move Flow's canonical store off root `skills/`, or mirror into `.claude/skills/` as source-of-truth) is **deliberately not done here** — it depends on the CLI team's intended end-state and is left as an open decision.

Tests: recovery sim gains U11 + U12 assertions (and the existing precision cases still pass). run-tests 16/16; health HEALTHY; plugin valid. VERSION 3.8.2 → 3.8.3; plugin manifests bumped.

## [3.8.2] — 2026-06-01

### Fixed — U10: flag-gated CLI skills no longer cause a chronic false-positive CLI_LAYER_DRIFT

Downstream report: the health check flagged a permanent `CLI_LAYER_DRIFT` for CLI provider skills that are **absent by design** — the FuseBase CLI gates several skills behind config flags and deletes them when the flag is off, so `fusebase update` (the advised remediation) can never restore them. Same class as F4 (absent-by-design ≠ drift), affecting essentially every downstream that didn't opt into every optional flag. Fixed:

- `agent-surface-ownership.json` gains a `flag_gated_skills` map (skill → enabling flag(s), mirroring the CLI's `FLAG_GATED_SKILLS`: `portal-specific-apps`, `managed-integrations`, `git-init`/`git-debug-commits`, `app-business-docs`, `mcp-gate-debug`).
- `check-cli-flow-conflicts.sh` now treats an absent flag-gated skill as a **benign INFO** naming the correct remediation (`fusebase config set-flag <flag>`), not a `MISSING`/`CLI_LAYER_DRIFT`. An absent skill whose flag is **provably on** (best-effort read of `fusebase.json`) is still genuine drift; non-flag-gated absences are unaffected (precision retained, proven by the existing `fusebase-cli`-removed → `CLI_LAYER_DRIFT` test).
- Recovery sim gains a U10 assertion (remove a flag-gated skill from a complete install → stays non-drift with a `set-flag` INFO). README health section documents the behavior. Dogfooded through the Lightweight Lane. VERSION 3.8.1 → 3.8.2; plugin manifests bumped.

## [3.8.1] — 2026-06-01

### Fixed — U9: the first preserve-aware upgrade is now lossless

Follow-up from a downstream 3.7.0 → 3.8.0 upgrade: the U1 `FLOW:PRESERVE` carry-forward only matched when the live block already had the markers, so the **first** preserve-aware upgrade (a pre-markers block) still reset operator project-values once. `refresh_overlay_block()` now **seeds the new preserve region from a legacy (marker-less) `### Project-specific values` table** — detecting it by its heading + "…rules win." footer and wrapping it in the template's `FLOW:PRESERVE` markers — so even the transition from a pre-3.8.0 block keeps the operator's values. Recovery sim asserts a customized legacy value survives the first preserve-aware refresh and the markers are added. Dogfooded through the Lightweight Lane (`docs/changes/2026-06-01-u9-legacy-project-values-seed.md`). VERSION 3.8.0 → 3.8.1; plugin manifests bumped.

## [3.8.0] — 2026-06-01

### Fixed — upgrade-path hardening 2 (from a live 3.5.2 → 3.7.0 in-place upgrade)

A downstream ran the real in-place upgrade on a heavily-customized pre-3.6.0 install and confirmed F2/F3/F4 held up — while surfacing 8 upgrade-path gaps (1 data-loss, 1 functional-staleness, plus consistency/pollution/UX). All fixed. Spec: `docs/specs/upgrade-path-hardening-2/`.

- **U1 (High, data loss) — overlay refresh no longer wipes operator values.** The `### Project-specific values` table is now wrapped in inner `<!-- FLOW:PRESERVE:BEGIN -->…<!-- FLOW:PRESERVE:END -->` markers; `refresh_overlay_block()` carries the existing preserve-region forward into the fresh template (merge-preserve). A refresh updates framework prose **without** overwriting operator-filled project values. New recovery-sim assertion proves the value survives a drift refresh.
- **U2 (High) — `upgrade.sh` now refreshes `hooks/`.** Previously it refreshed `skills/agents/workflows/policies/templates` but not `hooks/`, so a downstream got new skills/rules but a stale hook layer (the v3.7.0 tier-aware deploy gate silently inert) and the upgrade tooling couldn't update its own home. `hooks/` is now in the refreshed set; `hooks/local/*.local.*` overrides are preserved and CLI-owned `.claude/hooks/**` is untouched; engine scripts self-update (new logic active next run).
- **U3 (Med) — adapters no longer drift to a stale FR-range/skill-count.** `sync-version-strings.sh` is generalized to sync **derived attestation facts** — version **+** `FR-01..FR-NN` (from FLOW_RULES.md) **+** `(NN canonical skills total)` — across all adapters incl. GEMINI.md, which has no overlay-refresh path. No more "v3.x … FR-01 through FR-(N-1)".
- **U4 (Med) — `upgrade.sh` stops polluting the consumer `docs/`.** Framework dev-docs are no longer copied into `docs/` by default; `--with-framework-docs` stages them under `docs/_fusebase-flow/` (namespaced).
- **U5 (Med) — pre-3.6.0 bootstrap.** New `hooks/local/bootstrap-upgrade.sh` stages a source clone, copies the engine scripts in, and runs `upgrade.sh`; README documents a copy-paste one-liner for installs that lack even the bootstrap.
- **U6 (Low) — LL ledger is opt-in / path-configurable.** The durable record is `change_tier` + SHA in the commit body; the consolidated `docs/changes/index.md` is now opt-in with a configurable path (skill + change-note template reworded; no repo-root ledger assumed).
- **U7 (Low) — legacy CLAUDE.md migration no longer doubles `---`.** The begin-line-0 rebuild trims a trailing `---` rule from the preserved region so exactly one separator remains (marker-wrapped byte-exactness from v3.7.0 still holds).
- **U8 (Low) — null-byte warning silenced** in `sync-version-strings.sh` (`tr -d '\0'`).
- Tests: recovery sim gains U1 (preserve) + U7 (single-rule) assertions; run-tests still 16/16; the v3.7.0 F2 byte-exact lock still passes. VERSION 3.7.0 → 3.8.0; plugin manifests bumped. No skills added/removed (still 24 canonical).

## [3.7.0] — 2026-06-01

### Added — Lightweight Lane (FR-21): ceremony proportional to change size

Production feedback (a one-line, reversible edit that ran the full lifecycle at ~10–16 min wall-clock, ~98% process/build/verify/approval and ~2% the change) showed Fusebase Flow applied the same full ceremony to every change regardless of risk. v3.7.0 adds a two-tier model so ceremony scales with risk. Spec: `docs/specs/lightweight-lane/`.

- **FR-21 (new always-on rule) — ceremony proportional to change size.** Every ticket is classified **Full** or **Lightweight** at Specify. The safety floor is kept in BOTH lanes (live proof, an explicit operator deploy go-ahead, FR-07 protected paths, a documented rollback, one-commit-per-change with the SHA). Fail-safe-up + mandatory mid-flight promotion. Self-attestation range is now `FR-01..FR-21`.
- **`lightweight-lane` skill (24th canonical).** Single source of truth for the eligibility gate (6 conjunctive conditions), the change-note artifact, the one build→verify→deploy pass, and mid-flight promotion. Referenced by `requirements-specification`, `validation-and-qa`, `release-deploy-reporting`, `role-discipline`, and both agents.
- **A Lightweight ticket** replaces the spec/decisions/tasks/verification-gate chain + two handoff docs with **one change-note** (`templates/change-note.md`), runs build→verify→deploy in **one agent pass** (no two-agent split, no redundant rebuild), and deploys on a **plain explicit operator go-ahead** — no DP.6 magic phrase, no hand-authored DP.1 JSON (DP.12). Verification is compressed (live proof + the 3-question empirical test on the one acceptance criterion, reported in 1–3 lines), not skipped. Tier + any promotion are logged in `docs/changes/index.md`.
- **role-discipline:** PO.16 (classify; don't over/under-tier), IM.18 (one-pass LL; keep the floor; promote if it grows), DP.12 (plain go-ahead replaces DP.1/DP.6 for LL). DP.1/DP.6 scoped to Full lane.
- **Tier-aware hook layer (opt-in, off by default):** `approval-policy.yml` gains `lightweight_deploy` (a one-command stamp authored from the operator's go-ahead); `required-artifacts.yml` `before_deploy_command` accepts `production_deploy` OR `lightweight_deploy`, and `before_deploy_complete_claim` waives the Full-lane-only signals (probes table, post-deploy docs commit, smoke) for LL while keeping the safety-floor signals (deploy hash + rollback). `stop.py` is tier-aware via a lightweight-lane transcript marker. Two new hook-test fixtures (15: LL deploy-complete allowed; 16: LL still blocked without rollback). Tests now 16/16.
- **Docs/workflows:** `workflows/lightweight-lane.md`; lane selection added to `workflows/eight-phase-flow.md`; AGENTS/CLAUDE/GEMINI overlays + README document the two lanes; skill count 23→24. VERSION 3.6.0 → 3.7.0; plugin manifests bumped.
- **Also fixed (v3.6.0 F2 cosmetic nit, from a downstream re-review):** `refresh_overlay_block()` no longer leaves a stray blank line before `<!-- CUSTOM:SKILL:BEGIN -->` on a drift-rebuild — it trims trailing blank lines from the preserved pre-marker region so the rebuild is byte-identical to a freshly-appended block. `test-cli-flow-recovery.sh` gained a byte-exactness lock (AGENTS.md sha after a drift refresh == the clean post-recovery block). Dogfooded through the new Lightweight Lane (`docs/changes/2026-06-01-overlay-refresh-trailing-blank.md`).

## [3.6.0] — 2026-05-31

### Added / Fixed — upgrade-path hardening

Verified operator feedback (upgrading a live project from an older Flow to 3.5.x) showed the **in-place upgrade path** was the remaining gap: the install path was mature, but upgrading an already-installed overlay had eight rough edges. All eight were checked against the code and fixed (spec `docs/specs/upgrade-path-hardening/`).

- **F1 — `hooks/local/upgrade.sh` (new keystone):** the missing in-place *content* upgrade. Refreshes canonical `skills/ agents/ workflows/ policies/ templates/ FLOW_RULES.md` + framework `docs/*.md` from `.fusebase-flow-source/`, re-mirrors, syncs embedded version strings, then bumps `VERSION` **last** — so VERSION can never advance ahead of content (the root cause of stale-skills-with-new-version). Backups (`.pre-upgrade-<ts>`), `--dry-run`, `--auto-yes`.
- **F2 — version-aware overlay refresh (marker-anchored, idempotent):** `post-fusebase-update.sh --refresh-overlays` detects a *present-but-drifted* AGENTS.md/CLAUDE.md Flow overlay block and replaces it (with a `.pre-refresh-<ts>` backup) instead of skipping. The detection/replacement is anchored on the `CUSTOM:SKILL:BEGIN`/`END` markers (not the heading — the templates wrap the heading inside the markers, so the earlier heading-anchored check was always-true and duplicated the block on every run). The CLAUDE.md overlay template is now wrapped in the same markers as AGENTS.md (gaining the same CLI custom-block preservation); a legacy marker-less block is migrated to the wrapped form on first refresh. Refreshing a current block is a verified no-op (BEGIN/END stay balanced at 1); recovery's missing→append path is unchanged.
- **F3 — hook wiring is now genuinely opt-in:** `post-fusebase-update.sh` no longer merges `.claude/settings.json` by default. It prints a loud "settings.json NOT modified — re-run with `--wire-hooks`" notice; the merge runs only with `--wire-hooks`. This makes CLAUDE.md's "hooks are opt-in" contract true. CLI Stop hooks are still preserved when you do opt in.
- **F4 — no more false `CLI_LAYER_DRIFT` for single-provider projects:** `check-cli-flow-conflicts.sh` now treats a wholly-absent CLI provider surface (**0 of N** known provider skills/agents present) as a single benign INFO ("not installed — benign for non-FuseBase-Apps / single-provider projects"), not per-item MISSING. **Partial** installs still report genuine drift. A Claude-only project no longer reads RED after a clean upgrade.
- **F5 — plain-dir upstream accepted:** `upgrade-engine.sh` and `upgrade.sh` no longer FATAL when `.fusebase-flow-source/` lacks `.git` (the documented install end-state). They warn and fall back to VERSION-file comparison; a `.git` clone still enables HEAD/diff.
- **F6 — `.pyc` scrub** on upgrade (gitignore rule was already present).
- **F7 — `hooks/local/sync-version-strings.sh` (new, context-safe):** derives the live `Fusebase Flow vX.Y.Z` self-attestation/banner strings from `VERSION` across **all** canonical + adapter surfaces an agent actually reads — `agents/**/AGENT.md` (+ re-mirrored provider copies), `workflows/*.md`, `templates/handoff-*.md`, `FLOW_RULES.md`, `.github/copilot-instructions.md`, `.cursor/rules/*.mdc`, AGENTS/CLAUDE/GEMINI, and the overlay templates. It rewrites only the two live phrasings (`under Fusebase Flow v…`, `runs **Fusebase Flow v…**`), so historical/provenance refs (`Shipped … v2.3.0+`, `Available since v2.4.0`, `DEPRECATED (… v3.2.0)`, `v2 (… v2.7.0+)`) are preserved. Corrected ~12 files still self-attesting `v3.5.0` under a 3.6.0 install.
- **F8 — docs:** the canonical→mirror order and the new upgrade path are documented in `upgrade.sh` and the README.
- **Tests:** `test-cli-flow-recovery.sh` gained assertions for F3 (settings untouched by default; merged under `--wire-hooks`) and F4 (0-present benign vs partial-drift). VERSION 3.5.2 → 3.6.0; plugin manifests bumped. No skills added/removed (still 23 canonical).

## [3.5.2] — 2026-05-31

### Fixed — recovery/overlay refresh for downstream installs

A health/recovery audit found the recovery overlay templates had not kept pace with the v3.3–v3.5 additions (latent — affected a downstream project running recovery after `fusebase update`, not this repo).

- **R-1:** `post-fusebase-update.sh` Step 8 now restores **all** `.claude/commands/*.md` (loop, not just `fusebase-health.md`) — `/onboard` and `/product-owner` are now recoverable. Added their templates to `hooks/local/fusebase-flow-overlays/commands/`. Verified: a simulated wipe restored 2 of 3 commands correctly.
- **R-2:** AGENTS.md + CLAUDE.md overlay templates' skills lists refreshed to all 23 canonical skills; added the "Active project context" discovery instruction.
- **R-3:** CLAUDE.md overlay self-attestation/labels swept `FR-19`/`v3.1` → `FR-20`/`v3.5.0`.
- VERSION 3.5.1 → 3.5.2; plugin manifests bumped. No skills added/removed.

## [3.5.1] — 2026-05-31

### Fixed — post-implementation audit corrections

- **Implemented two skill extensions that prior v3.3.0 release notes claimed but had not actually shipped:** `skill-authoring` now has a **Domain-expert skill mode**; `design-discovery-ideation` now has a **Prototype before build** section. (An independent audit caught the claim/file mismatch; the dead cross-references in `product-docs-first` / `project-onboarding` now resolve.)
- **FR-20 consistency sweep:** `FR-01..FR-19` → `FR-01..FR-20` and stale `v3.1`/`v3.2.0` self-attestation labels → `v3.5.0` across ~32 non-historical files (adapters, agents, workflows, templates, role-discipline, overlays). Historical release notes/handoffs left intact; legitimate mentions of the FR-19 *rule* preserved. A fresh agent now self-attests to FR-20.
- **README:** corrected stale skill counts (14 → 23), added the 9 new skills to the catalog, version badge → 3.5.1.
- **session_start.py:** project-artifact scan now uses `rglob` so nested app layouts (`docs/apps/<app>/product.md`) are surfaced.
- VERSION 3.5.0 → 3.5.1; plugin manifests bumped. No skills added/removed (still 23 canonical; manifest 46 lines).

## [3.5.0] — 2026-05-31

### Added — input-dependent skills (client-facing delivery)

- **`client-vs-internal`** — simple-for-client / robust-for-internal posture; gated on `docs/audience.md`.
- **`product-docs-first`** — design per-app product docs before code; gated on `docs/<app>/product.md`.
- **`business-logic-guardian`** — protect documented business logic during fixes (pairs with FR-20); gated on `docs/<app>/business-logic.md`.
- **`product-apps-decomposition`** — product→focused-apps guidance (reliability + token economy); generic-with-enhancement.
- `templates/audience.md`, `templates/product.md`; `session_start.py` scan extended.
- All reuse the v3.4.0 artifact-gated pattern (absent → silent no-op). Flow skills 19 → 23; manifest 38 → 46. Completes the Tier-1/2 gap batch. Full detail: `docs/release-notes/v3.5.md`.

## [3.4.0] — 2026-05-31

### Added — onboarding keystone + North Star

- **`project-onboarding` skill + `/onboard`** — PO-owned discovery interview that writes `docs/north-star.md` and fills AGENTS project-values. Operator-triggered, optional, re-runnable.
- **`north-star` skill** — artifact-gated: steers work to `docs/north-star.md` when present; silent no-op when absent (the canonical "ship complete, stay dormant until fed" pattern).
- **3-layer universal artifact discovery** (hook-independent): AGENTS.md "Active project context" instruction + `session_start.py` scan + per-skill existence-guard.
- **`/product-owner` command**, **`templates/north-star.md`**.
- Flow skills 17 → 19; manifest 34 → 38. Absent-by-default: a fresh install has no project artifacts and runs generically. Input-dependent skills (client-vs-internal, product-docs, business-logic-guardian, product→apps) follow next. Full detail: `docs/release-notes/v3.4.md`.

## [3.3.0] — 2026-05-31

### Added — generic flow skills + FR-20

- **FR-20 (zoom out, don't patch-myopically)** — new always-on rule; zoom out to root cause before applying a narrow patch. Self-attestation → FR-01..FR-20.
- **`zoom-out` skill** — operationalizes FR-20.
- **`phase-audit` skill** — independent sub-agent audits all slices of a phase.
- **`git-history-diagnostic` skill** — regression archaeology (locate the causing commit).
- **`skill-authoring`** extended with a domain-expert skill authoring mode.
- **`design-discovery-ideation`** extended with prototype-before-build.
- Flow skills 14 → 16; mirror manifest 28 → 32 lines. Input-dependent skills (north-star, client-vs-internal, product-docs, business-logic-guardian, product→apps) deferred to the onboarding keystone. Full detail: `docs/release-notes/v3.3.md`.

## [3.2.0] — 2026-05-29

### Added — provider-skill drift guards (Fusebase CLI edition)

The CLI edition vendors a second copy of FuseBase CLI-owned assets (19 provider skills + their `references/`, 2 app-agents, 4 quality hooks). Those copies are written by two independent tools — `fusebase update` and the frozen Flow snapshot — with no provenance, no freshness signal, and no content-drift detection. v3.2.0 closes the residual drift-visibility and install-overwrite gaps without de-vendoring (the offline/template UX is preserved).

Key additions:

- **Provenance manifest (B2).** Added `hooks/local/stamp-cli-provenance.sh`, which stamps `audit/cli-vendor-manifest.json`: per-file sha256 of every vendored CLI-owned asset, a `generated_at` date, and `source_cli_version: "unknown"` (UNVERIFIABLE_LOCALLY — freshness is advisory only). The manifest is a committed document of record (like `skill-mirror-manifest.txt`); it does NOT fold CLI assets into the Flow mirror manifest.
- **Drift-aware conflict reporter (B3).** `check-cli-flow-conflicts.sh` now hashes each present CLI asset against the provenance manifest and emits an advisory `CLI_SNAPSHOT_STALE` finding when it differs, plus a `CLI_CUSTOM_AT_RISK` finding for any CLI-owned skill carrying a `CUSTOM:SKILL` block. Both are informational only — they never change the verdict or exit code. `MISSING → CLI_LAYER_DRIFT` semantics are unchanged.
- **CLI app-agents pinned by name (B4).** Replaced the `app-*.md` wildcard in `agent-surface-ownership.json` with explicit `known_names: ["app-architect","app-create-checker"]`; the checker iterates the list instead of globbing, so a future Flow agent named `app-*` is no longer misattributed cli-owned.
- **Non-clobber install (B6).** The documented install copy steps now copy CLI-owned provider paths only-if-absent (`cp -Rn` / no PowerShell `-Force`); Flow-owned paths copy normally. Added a "Two-writer hazard" section to `docs/fusebase-cli-edition.md`.

### Changed

- **Stop-hook consolidation (B5).** `.claude/settings.json.example` now wires only the cross-platform node Stop hooks (`run-typecheck-apps.js` — CVE-2024-27980 `shell:win32` patch — plus `quality-check-apps.js`). The jq/bash duplicates (`run-lint-on-stop.sh`, `run-typecheck-on-stop.sh`) are **deprecated and unwired** (kept on disk one release with a deprecation header, because no node hook covers lint). The settings-merge recovery and conflict reporter were aligned to the node hooks; merge still never removes a hook a downstream wired.
- **Doc-accuracy stragglers (B7).** Corrected `run-typecheck-features.js` → `run-typecheck-apps.js` in current-shipped docs (`README.md`, `docs/health-check-deferrals.md`) and `FR-01..FR-18` → `FR-01..FR-19` in `docs/install-existing-project.md`. Dated historical narratives left intact.
- **Health-check skill text.** Documents the new advisory signals (`CLI_SNAPSHOT_STALE`, `CLI_CUSTOM_AT_RISK`), that they never trigger Flow recovery, and the `stamp-cli-provenance.sh` re-stamp path. Mirrored to `.claude`/`.agents` + overlay restore template.
- **README "Health check & recovery"** refreshed for the provenance manifest, the drift advisory, and the node Stop-hook consolidation.
- **Tests.** `hooks/tests/test-cli-flow-recovery.sh` extended (not rewritten) with cases for: explicit `known_names` attribution + glob-retirement, provenance stale advisory (non-failing), `CUSTOM:SKILL` at-risk, and missing-vs-stale escalation. `preflight.sh` gains an advisory (non-failing) provenance-manifest check.

Baseline protections re-verified non-regressed: `mirror-skills.sh` canonical-only (14 Flow skills); 19 CLI provider skills stay `flow_write_mode:"never"`; `post-fusebase-update.sh` CLI-exclusion intact; `audit/skill-mirror-manifest.txt` still 28 lines.

See `docs/release-notes/v3.2.md`.

## [3.1] — 2026-05-27

### Added - Fusebase CLI edition packaging

This release now has a dedicated Fusebase CLI edition that layers Fusebase Apps CLI provider assets on top of the Flow lifecycle framework.

Key additions:

- Added `docs/fusebase-cli-edition.md` with the Flow/CLI boundary map, overlap table, and role applicability.
- Added 19 CLI provider skills to `.claude/skills/` and `.agents/skills/`, alongside the 14 canonical Flow mirrors.
- Added CLI app agents `app-architect` and `app-create-checker` to `.claude/agents/` and `.codex/agents/`.
- Added CLI Claude Code quality hooks under `.claude/hooks/`.
- Updated `.claude/settings.json.example` to merge CLI MCP server hints and Stop hooks with Flow lifecycle hooks.
- Updated clean-room and source-map docs so copied CLI provider assets are clearly separated from canonical Flow clean-room files.
- Updated health check behavior so source-template / edition projects validate as `HEALTHY` without requiring downstream overlay markers.

### Added — FR-19 chat-text questions, no popup menus

Operators reported that clickable popup menus are hard to copy, forward, scroll back to, and follow up on across the Product Owner / AI Developer / Deploy relay loop. v3.1 adds **FR-19**: every operator question, clarify prompt, option choice, deploy confirmation, and recovery decision must be written as normal chat text.

Key changes:

- Added FR-19 to `FLOW_RULES.md`.
- Added Chat-Text Questions Protocol to `skills/role-discipline/SKILL.md`.
- Added Mode A question-shape guidance to `skills/communication/SKILL.md`.
- Removed `AskUserQuestion` from the AI Developer agent tool grant.
- Updated deploy confirmation wording so DP.6 requires a chat-text typed phrase, not a popup confirm.
- Added `design-discovery-ideation` skill so PO can turn "show options" / "try alternatives" requests into clean-room product/UI/workflow option briefs before decisions lock.
- Strengthened frontend/UI handoffs: design briefs now capture product identity, surface map, data/API contracts, applicable stack conventions, stable selector strategy, trust-critical interactions, and non-goals before AI Developer implementation.
- Added `smoke-testing` skill so PO defines outcome-based S1..Sn and AI Developer / Deploy phase cannot claim smoke PASS from supporting checks alone.
- Added `task-delegation` skill so PO can delegate read-only/doc-only work and AI Developer can delegate independent implementation/test slices without overlapping writes or bypassing verification.
- Added `skill-authoring` skill so PO classifies clean-room reusable skill changes and AI Developer implements canonical-first edits with mirror/source-leak/count validation.
- Strengthened UI/E2E validation guidance across smoke and QA: browser tests now require route, viewport, stable locators, auth/test-data plan, backend diagnostics, unique data, cleanup, and side-effect controls.
- Updated Fusebase Flow health-check recovery for the latest Apps CLI agent-asset refresh: AGENTS overlay recovery now appends inside the CLI-preserved `CUSTOM:SKILL` wrapper, and the health-check engine treats reduced `.claude/settings.json` as the core recoverable `fusebase update` aftermath signal even when AGENTS survives through that wrapper.
- Updated provider adapters, overlay templates, handoff templates, and release docs.

See `docs/release-notes/v3.1.md`.

## [2.9.0] — 2026-05-10

### Added — FR-18 (supersede, don't accumulate) + 5 token-efficiency themes

Token-efficiency initiative. Operator surfaced concrete bloat in real-world artifacts (paperclip+hermes-v1 deploy handoff at 25KB with ~50% dead "ORIGINAL HANDOFF BODY" content; communication SKILL.md loading 3300 tokens of pattern-library content at every session start regardless of whether visuals would be used). v2.9.0 ships six coordinated changes that reduce per-session and per-ticket token cost without losing any functional content.

### FR-18 — Supersede, don't accumulate

New 18th always-on rule:

> **FR-18 — Supersede, don't accumulate.** When revising a handoff, gate report, decision, or spec post-abort or post-correction, REPLACE the stale content with the corrected version. Audit trail lives in git history (every revision is a commit), not in the live file. Exception: when human-readable diff is essential, use the `## Superseded sections (audit only — agents skip)` heading the agent recognizes and skips during reads.

Self-attestation language bumped framework-wide: "FR-01 through FR-18" (was FR-01..FR-17). 26 source-of-truth files touched (38 replacements). Mirrors regenerated.

Role-discipline gets 4 new don't-list entries: **PO.12**, **IM.13**, **AR.7**, **DP.8** — all forbidding the accumulate-instead-of-supersede pattern. New **Supersede Convention** section in `skills/role-discipline/SKILL.md` with:

- Concrete REPLACE vs PRESERVE comparison table (4 scenarios)
- The `## Superseded sections (audit only — agents skip)` heading convention with example markup
- "What goes in git, not in the file" decision table
- Self-correction refusal phrasing for when the agent catches itself drafting accumulated content

### Six token-efficiency themes (combined)

| # | Theme | Change |
|---|---|---|
| 1 | **De-duplicate self-attestation** | Replaced embedded ~250-token paragraph in 4 source files (handoff preludes + workflow self-attestation sections) with one-line reference: `Per FLOW_RULES.md § Self-attestation (FR-01..FR-18); name your role.` Canonical paragraph stays in FLOW_RULES.md only. |
| 2 | **Lazy-load patterns library** | Moved 8-pattern Mode A visual library (`skills/communication/SKILL.md` lines 144-336) into `skills/communication/references/patterns.md`. Main SKILL.md shrinks from 559 → 367 lines. Patterns load on demand only when a visual is actually warranted. |
| 3 | **Per-role scoped loading in role-discipline** | New preamble after `## Procedure` documents which sections each role should load. PO loads PO section + Operator Relay Protocol + Forward Momentum Protocol + Supersede Convention. AI Developer loads only AI Developer section + the 3 shared protocols. Skips ~3000 tokens of irrelevant cross-role content per session. |
| 4 | **FR-18 supersede discipline** | See "FR-18" section above. |
| 5 | **Extract template fill-in checklists** | Moved "Fill-in checklist" sections out of `templates/gate-report.md`, `templates/deploy-report.md`, `templates/architect-response.md` into `templates/references/<name>-checklist.md`. Templates shrink ~10-14 lines each. Checklists are fill-time aids; downstream consumers of filled artifacts no longer pay token cost for them. |
| 6 | **Tighten handoff template preludes** | `templates/handoff-implement.md` and `templates/handoff-deploy.md` preludes no longer paraphrase FR rules (which the agent already loaded from FLOW_RULES.md). Replaced "Hard invariants" bullet lists with one-line FR citations. ~150 tokens saved per filled handoff. |

### Combined savings (estimated)

| Per session start (mandatory skill load) | Per ticket artifacts (5-10 generated files) |
|---|---|
| ~3300 tokens (Theme 2 lazy-load) | ~750 tokens (Theme 1 de-dup × N handoffs) |
| ~3000 tokens (Theme 3 role-filter) | ~400 tokens (Theme 5 checklist extraction × N filled artifacts) |
|  | ~150 tokens (Theme 6 prelude tightening × N filled handoffs) |
|  | ~1500-3500 tokens (Theme 4 supersede discipline × N revised artifacts) |
| **~6300 tokens / session** | **~2800-4800 tokens / ticket** |

### What did NOT change

- Engine bytes (`hooks/local/fusebase-flow-health-check.sh`) — byte-identical to v2.8.0 / v2.7.1 / v2.7.0 / v2.6.1 / v2.6.0 / v2.5.0 / v2.4.1 (**8th release in a row with no engine change**)
- Recovery script — identical
- `upgrade-engine.sh` — identical
- All policy files (`policies/*.yml`) — unchanged
- Self-attestation requirement itself — unchanged; just no longer duplicated across files

### Backward compatibility — strict superset

- Existing handoffs, templates, and reports continue to work unchanged (older filled artifacts with embedded attestation paragraphs are fine; they just carry slightly more content than v2.9.0 templates would produce).
- Older sessions attesting "FR-01 through FR-17" still function — FR-18 is additive.
- Agents that don't yet honor per-role scoped loading (Theme 3) still get correct behavior; they just load more than necessary. Compliance is opt-in via the preamble.

### Drivers (operator-surfaced friction, 2026-05-10)

> "Reconsider the file creation and information exchange from the perspective of token usage. Is there too much, too extensive information? Can it be optimized for more efficiency? ... We can also analyze it and see if there is any redundancy that can be optimized without losing any quality of use-based flow execution."

The audit on paperclip+hermes-v1 found:
- deploy handoff: 25KB / ~6000 tokens, ~50% stale content from accumulating "RESUMPTION NOTES" + "ORIGINAL HANDOFF BODY"
- Self-attestation paragraph duplicated in 3 generated files per ticket
- Communication skill loading 3300 tokens of pattern library at every session start

### Verification

- `bash hooks/local/preflight.sh` → 0 errors, 0 warnings
- `bash hooks/tests/run-tests.sh` → 14/14 PASS
- `bash hooks/local/fusebase-flow-health-check.sh` → DRIFTED (expected; same baseline as v2.8.0 on upstream tree)
- `grep -rn "FR-01 through FR-17"` outside historical/CHANGELOG/release-notes → 0 matches
- Mirrors regenerated cleanly; `references/patterns.md` propagated to `.claude/skills/communication/references/` and `.agents/skills/communication/references/`
- New `templates/references/` checklists present

## [2.8.0] — 2026-05-10

### Added — FR-17: Forward momentum, never retreat

The headline change. New 17th always-on rule in `FLOW_RULES.md`:

> **FR-17 — Forward momentum, never retreat.** Agents present the next forward action. Don't suggest closing the session, "letting it bake," resting, postponing, or wrapping up — those are presumptuous behavioral suggestions that mask agent caution as operator advice. If there is genuinely no next action, state that fact neutrally ("no pending action") and let the operator decide whether to close. Operators do not need agents to tell them when to stop working.

Self-attestation language updated framework-wide: "FR-01 through FR-17" (was FR-01..FR-16). 26 source-of-truth files touched (38 replacements). Mirrors regenerated.

### Added — anti-retreat role-discipline entries

`skills/role-discipline/SKILL.md` extended with per-role don't-list entries:

| # | Role | Rule |
|---|---|---|
| PO.11 | Product Owner | Don't suggest closing / let-it-bake / wrap-up; always present the next forward action; "no pending action" if genuinely nothing. |
| IM.12 | AI Developer | Same; "produce gate report and stop at gate" is a forward action, not a retreat. |
| DP.7 | Deploy phase | Same; always a forward action through deploy completion or rollback decision. |

Plus a new **Forward Momentum Protocol** section in the skill with:
- Concrete `forward action` vs `retreat-disguised-as-advice` comparison table
- Anti-pattern phrase catalog (12 forbidden phrases: "let it bake," "save it for tomorrow," "close session?", etc.)
- Edge case: legitimate engineering judgment ("observe real signal first") vs unprompted retreat suggestion
- Rule of thumb: if the operator didn't ask "should I stop?", the agent doesn't suggest stopping
- Self-correction refusal phrasing for catching retreat phrases mid-draft

Anchored at don't-list level via PO.11, IM.12, DP.7 (mapped to FR-17). Cross-referenced from agent definitions.

### Added — IM.11: per-task wall-clock recording (retrospective time tracking)

`skills/role-discipline/SKILL.md` adds **IM.11**: AI Developer records UTC `started_at` when picking up a task and `committed_at` when the commit lands. Wall-clock = `committed_at − started_at` per task. Sum of wall-clocks = **net active development time**, naturally excluding wait-for-operator time (which happens between tasks). Both timestamps go into the gate report and (for deploy-phase tasks) the deploy report.

### Updated — return-path templates carry the new time data

`templates/gate-report.md`:
- **Per-task commit table** grows three columns: `Started (UTC)`, `Committed (UTC)`, `Wall-clock` (the active task time)
- **New section 1b "Time totals"** showing total elapsed (wall), total active development (sum of wall-clocks), wait time (elapsed − active), tasks completed, average task wall-clock
- **Section 9 operator-relay block** includes the time totals so operator can paste them to PO without scanning the technical body
- **Fill-in checklist** adds two items requiring time data

`templates/deploy-report.md`:
- **Section 7** renamed from "Total deploy duration" to "Net deploy duration breakdown" with two sub-tables:
  - 7a per-phase elapsed (deploy command, probes, smoke, FR-14 commit) with start/end UTC timestamps and per-phase wall-clock
  - 7b net active vs wait breakdown (total elapsed, active work, wait time, deploy-command-only duration)
- **Section 8 operator-relay block** expanded with new time line (elapsed / active / wait split)
- **Fill-in checklist** adds three items requiring time data

### Updated — agent definitions cross-reference the new rules

- `agents/ai-developer/AGENT.md` — new phase-7 row "every task" explicitly invoking IM.11 (timestamp recording). Existing FR-count bumped to FR-17.
- `agents/product-owner/AGENT.md` — PO don't-list grows to PO.1..PO.11 (was PO.1..PO.10). New PO.11 row for FR-17.

### What did NOT change

- Engine bytes (`hooks/local/fusebase-flow-health-check.sh`) — identical to v2.7.1 / v2.7.0 / v2.6.1 / v2.6.0 / v2.5.0 / v2.4.1 (7th release in a row with no engine change)
- Recovery script — identical
- `upgrade-engine.sh` — identical
- All policy files (`policies/*.yml`) — unchanged from v2.7.0
- `templates/handoff-implement.md`, `templates/handoff-deploy.md` — only FR-count bump
- DP.6 magic phrase, DP.1 approval artifact, all other deploy gates — unchanged
- TTL config, `.gitignore`, all other infrastructure — unchanged

### Backward compatibility — strict superset

- Existing handoffs, templates, and reports continue to work unchanged.
- Older sessions attesting "FR-01 through FR-16" still function — FR-17 is additive.
- Older gate / deploy reports without time columns continue to work; new reports authored from v2.8.0+ templates carry the new data.
- Existing PO sessions that accidentally suggest "let's close" still produce valid output (operator can ignore); but post-v2.8.0 PO sessions following the protocol won't.

### Drivers (operator-surfaced friction)

1. **FR-17 (anti-retreat)** — operator-observed pattern: "AI always tries to avoid continue working, [tries to make the] operator stop. It constantly engages in things like 'You are done,' 'Go to rest,' 'Let's postpone,' 'Let's close the day.' This is not productive... the operator thinks that all was done, but in [reality the] AI just tries to postpone things."
2. **IM.11 (time tracking)** — operator-observed gap: deploy reports show timestamps but no per-task or aggregate active-time data. "Let's add the time which was taken to execute the task. Excluding the wait time when the AI Developer waits for feedback, we need to check the net time of actual development. That's going to help in the future to do retrospective analysis and improve the flow."

### Verification

- `bash hooks/local/preflight.sh` → 0 errors, 0 warnings
- `bash hooks/tests/run-tests.sh` → 14/14 PASS
- `bash hooks/local/fusebase-flow-health-check.sh` → as-expected verdict (DRIFTED on upstream tree; same baseline as v2.7.1)
- `grep -rn "FR-01 through FR-16"` outside CHANGELOG / release-notes / fusebase-health → 0 matches
- Mirrors regenerated cleanly (skills 20/2; agents 4/2)
- Forward Momentum Protocol section present in role-discipline skill + mirrors

### Why ship as v2.8.0 (minor) not v2.7.2 (patch)

This adds two distinct framework capabilities (new always-on rule + new mandatory measurement). Minor version reflects the additive scope.

### Engine bytes — 7th release in a row with no change

Today's release sequence: v2.4.1 → v2.5.0 → v2.6.0 → v2.6.1 → v2.7.0 → v2.7.1 → v2.8.0. All seven share byte-identical engine code. The framework has been iterating heavily on operator-experience policy / role-discipline / templates while keeping the diagnostic engine stable.

## [2.7.1] — 2026-05-10

### Fixed — `AskUserQuestion` popup tools removed from PO (conflict with FR-16)

Resolves a behavior conflict between the v2.6.0 Operator Stewardship initiative (FR-16 / Operator Relay Protocol) and the pre-v2.6.0 PO agent definition. The PO's allowed-tools list previously included `AskUserQuestion` for "every clarify Q-and-A; recommendations with 2–3 options + tradeoff." That guidance was written before FR-16 codified "the operator is a thin relay" and before the Operator Relay Protocol required options to be **scrollable, copyable, and forwardable** Mode A chat-text.

**The conflict in real use** (observed in `paperclip+hermes-v1` deploy session, 2026-05-10):

| Operator need (per FR-16) | Mode A chat text | `AskUserQuestion` modal |
|---|---|---|
| Scroll back to compare options | ✓ | ✗ — closes after click |
| Copy options into another session for context | ✓ | ✗ — uncopyable modal |
| Ask a follow-up before deciding | ✓ | ✗ — modal forces single answer |
| Preserve in conversation history | ✓ — text persists | ✗ — only the selected answer survives |
| Forward options to AI Developer / Deploy session | ✓ | ✗ |

The modal popup pattern is a v1-era affordance that worked when the operator was the only consumer of the question. Post-FR-16, options are part of a **relay** the operator may need to forward, discuss with a teammate, or revisit — that needs persistent chat-text, not a one-shot modal.

**The fix.** Four coordinated edits — critically, both the **machine-readable frontmatter** (which is what Claude Code actually reads to grant sub-agent tools) and the **human-readable documentation tables** are aligned:

1. **`agents/product-owner/AGENT.md` YAML frontmatter `tools:` field** — `AskUserQuestion` removed. This is the **actual enforcement point**: when an `Agent({subagent_type: "product-owner"})` sub-agent invocation fires, Claude Code reads this list to decide which tools the sub-agent has access to. Pre-v2.7.1: `tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion`. Post-v2.7.1: `tools: Read, Glob, Grep, Bash, Write, Edit`.
2. **`agents/product-owner/AGENT.md` Allowed table (documentation)** — `AskUserQuestion` row removed for consistency with the frontmatter.
3. **`agents/product-owner/AGENT.md` Denied table** — new row added explicitly forbidding `AskUserQuestion` for PO, with FR-16 rationale. Other roles (AI Developer, Deploy phase, Architect) may still use it for narrow non-relay cases — the restriction is PO-only.
4. **`skills/role-discipline/SKILL.md`** —
   - Operator Relay Protocol step 3 explicitly says "Mode A chat-text tables" and "never use modal popup tools."
   - PO.10 don't-list entry expanded to forbid popup tools.
   - New PO.10 refusal phrasing for the "use a popup for me" request.

### Why this is a patch (v2.7.1) not minor

- Closes a behavior conflict between v2.6.0 and pre-v2.6.0 design intent — semantically a fix, not a new feature.
- No schema changes, no template additions, no engine changes.
- Strict superset: existing handoffs, templates, and reports continue to work.
- Trivially backward compatible — projects on v2.6.x already had FR-16; v2.7.1 closes the gap with the older agent-definition guidance.

### What did NOT change

- Engine bytes (`hooks/local/fusebase-flow-health-check.sh`) — identical to v2.7.0 / v2.6.1 / v2.6.0 / v2.5.0 / v2.4.1 (6th release in a row with no engine change)
- All policy files (`policies/*.yml`) — unchanged from v2.7.0
- Templates — unchanged
- Other roles' tool surfaces — unchanged (they may still use `AskUserQuestion` for narrow non-relay cases)
- DP.6 magic phrase mechanism — unchanged (typed phrase, not a modal)

### Verification

- `bash -n hooks/local/fusebase-flow-health-check.sh` → OK
- `bash hooks/local/preflight.sh` → 0 errors, 0 warnings
- `bash hooks/tests/run-tests.sh` → 14/14 PASS
- Mirrors regenerated (skills 20/2; agents 4/2)
- `grep -n "AskUserQuestion" agents/product-owner/AGENT.md` shows 1 match (the new Denied entry); 0 matches in Allowed

### Migration for downstream consumers

Pull `agents/product-owner/AGENT.md` (and its mirrors `.claude/agents/product-owner.md`, `.codex/agents/product-owner.md`) plus `skills/role-discipline/SKILL.md` (and its mirrors). Or run `bash hooks/local/post-fusebase-update.sh` after upgrading framework files. The recovery script re-mirrors skills + agents from their canonical sources.

For the immediate workaround if a downstream PO is still using popups (before pulling v2.7.1), paste this in their PO chat:

> Per FR-16 + PO.10 (v2.7.1+), stop using `AskUserQuestion` popups. Re-issue your last question as a Mode A chat-text table with options marked ⭐ for the recommendation, rationale inline. I'll reply with the option letter.

## [2.7.0] — 2026-05-10

### Added — workflow-mode-aware `artifact_ttl_minutes` for `production_deploy`

The `production_deploy.artifact_ttl_minutes` field in `policies/approval-policy.yml` can now be a **mode-keyed object** with separate TTLs for `direct_to_main` and `branch_pr` workflow modes. The reader (`hooks/local/approve-local.sh`) looks up the project's `workflow_mode` and applies the matching value.

```yaml
require_approval:
  production_deploy:
    enforce: true
    artifact_ttl_minutes:
      direct_to_main: 129600   # 90 days; cookie-like; DP.6 is the real gate
      branch_pr: 60            # 60 min; stale-state protection for team contexts
    rationale: "..."
```

**Why.** Real-world friction observed during `paperclip+hermes-v1` deploy: operator hit multiple approval-window expirations during a complex deploy debugging session (3 aborts due to cookie capture issues, SSH tunnel wedged, VS Code zombie listener captured fake cookie). The 60-min default was burning out before the operator could complete the deploy steps.

The PO downstream session correctly diagnosed: in solo direct-to-main mode, the **DP.6 magic phrase** (`APPROVE-DEPLOY-NOW` typed at deploy time, non-delegable, non-bypassable) is the real per-deploy gate. The artifact's TTL serves only stale-state protection — barely matters for one operator iterating on one machine. 60 min was over-engineered for solo and produced friction during multi-attempt deploy debugging.

In team `branch_pr` mode, multiple operators may interact with stale approvals from days-old PR reviews; short TTL forces fresh approval against current state. The two contexts deserve different defaults — that's what mode-aware TTL gives them.

### Backward compatibility — strict superset

The field accepts both shapes:

| Shape | Behavior |
|---|---|
| Flat integer (legacy v1 schema) | Used as-is regardless of `workflow_mode` |
| Mode-keyed object (v2 schema) | Reader looks up `workflow_mode`, falls back to `direct_to_main` if mode key missing, falls back to 60 if both missing |

Existing projects with flat-int form continue to work unchanged. Only `production_deploy` becomes mode-aware in this release; other operations (`database_migration`, `destructive_file_delete`, etc.) keep flat-int form because they don't have the same DP.6-equivalent gate dynamic.

`schema_version` field bumped from `1` to `2` to reflect the new shape support.

### Migration path for downstream projects

| Starting state | What to do |
|---|---|
| Project on v2.6.1 with default flat-int 60 min | Pull `policies/approval-policy.yml` from upstream (or merge selectively); your `direct_to_main` mode gets the 90-day default automatically |
| Project on v2.6.x with manual flat-int override (e.g., operator already set to 129600) | Either keep your local override (works fine; matches `direct_to_main` value upstream now) or migrate to mode-keyed form for cleaner semantics |
| Project on `branch_pr` mode | Pull upstream; your TTL stays at 60 min (mode-aware default) |
| Project that customized the field locally via `policies/approval-policy.local.yml` | Local override still works; takes precedence; reader handles whichever shape you used |

### What did NOT change

- Engine bytes (`hooks/local/fusebase-flow-health-check.sh`) — identical to v2.6.1 / v2.6.0 / v2.5.0 / v2.4.1 (5th release in a row with no engine change)
- Recovery script (`hooks/local/post-fusebase-update.sh`) — identical
- `upgrade-engine.sh` — identical
- All other `require_approval.<action>.artifact_ttl_minutes` fields — flat int, unchanged
- TTL enforcement code (`hooks/shared/command_policy.py`) — already reads `expires_at` from authored artifacts, which is mode-agnostic; no change needed

### Verification

- `bash -n hooks/local/approve-local.sh` → OK
- 6-case schema reader test (flat int, mode-keyed `direct_to_main`, mode-keyed `branch_pr`, missing field, unknown mode → fallback to `direct_to_main`, no fallback → 60) — all pass
- End-to-end: `bash hooks/local/approve-local.sh production_deploy v2.7.0-smoke "smoke test"` produces artifact with `expires_at` ≈ 90 days from now (correct for upstream's `direct_to_main` mode + new mode-keyed default)
- preflight: 0 errors, 0 warnings
- hook tests: 14/14 PASS

## [2.6.1] — 2026-05-10

### Fixed — `.gitignore` exception for `health_check_deferral-*.json` (closes BACKLOG B5)

The wholesale rule `state/approvals/*` (with only `.gitkeep` exempted) was authored before v2.4.0 introduced the `health_check_deferral-*.json` artifact category. It treated all `state/approvals/` artifacts as ephemeral runtime state — correct for `production_deploy-*.json` (60-min auth tokens that must NEVER be in git), wrong for `health_check_deferral-*.json` (90-day documents-of-record that MUST be in git for fresh clones to reproduce the `EXCEPTION_IN_EFFECT` verdict and PR review to audit which deferrals are active).

**First observed downstream:** 2026-05-10 by `paperclip+hermes-v1` receiving agent during v2.4.1 adoption. Workaround applied per-project (narrow `.gitignore` exception) and filed as B5 for upstream back-port.

**Fix:** add narrow exception to upstream `.gitignore`:

```
state/approvals/*
!state/approvals/.gitkeep
!state/approvals/health_check_deferral-*.json   ← added
```

The exception is intentionally narrow — `production_deploy-*.json` and any future ephemeral artifact families stay gitignored unless explicitly added. This forces every new artifact-family decision to be deliberate.

**Verification:**

```
$ git check-ignore -v state/approvals/health_check_deferral-test.json
.gitignore:13:!state/approvals/health_check_deferral-*.json    state/approvals/health_check_deferral-test.json
↑ tracked (negation rule applies)

$ git check-ignore -v state/approvals/production_deploy-test.json
.gitignore:5:state/approvals/*    state/approvals/production_deploy-test.json
↑ ignored (wholesale rule still applies)
```

### Updated — `docs/health-check-deferrals.md`

Adds a **`.gitignore` policy** callout to the operator workflow section explaining the new exception, why it's narrow, and what to do on projects that haven't yet picked up v2.6.1.

### What did NOT change

- Engine bytes (`hooks/local/fusebase-flow-health-check.sh`) — identical to v2.6.0 / v2.5.0 / v2.4.1
- All other framework / template / skill / agent files — identical to v2.6.0
- Existing in-flight deferral artifacts on downstream projects — unaffected; if they're already gitignored locally and have a per-project exception, that exception remains valid (and matches what v2.6.1 ships in upstream)

### Backward compatibility

Strict superset of v2.6.0. Downstream projects that already added the exception manually are now redundant with upstream — they can keep the local exception (no harm) or remove it after pulling v2.6.1 (cleaner; matches upstream byte-for-byte).

## [2.6.0] — 2026-05-10

### Added — FR-16: Operator is a thin relay (Operator Stewardship initiative)

The headline change. Adds a 16th always-on rule to `FLOW_RULES.md`:

> **FR-16 — Operator is a thin relay.** The human operator's job is (1) product/business decisions, (2) gate approvals, and (3) physically moving messages between sessions. Every other cognitive task — interpreting status, recommending next steps, composing prompts to paste back — is the agent's job, especially the PO's.

Self-attestation language updated framework-wide: every role now declares "I will follow FR-01 through FR-16" (was FR-01..FR-15). Sessions that don't honor FR-16 are drifting.

**Why it exists.** During paperclip+hermes-v1's deploy phase, the operator hit a friction loop where PO responded to operator confusion with framework jargon ("DP.6 is non-delegable... type APPROVE-DEPLOY-NOW... approval artifact expires...") instead of plain action steps. It took 4+ rounds of operator clarification to get to the actual next move. The framework offered no behavioral discipline that prevented this.

FR-16 closes the gap by codifying the principle: operator attention is the most expensive resource; the framework must protect it.

### Added — Operator Relay Protocol (PO mandatory ritual)

Added to `skills/role-discipline/SKILL.md` PO section. When the operator pastes any output from another role (AI Developer gate report, Deploy report, Architect response, or any cross-session artifact), the PO MUST follow this 5-step ritual every time:

1. **Analyze** the pasted content per Flow rules
2. **Brief in Mode A** (2–4 sentences max, no framework jargon, visual)
3. **Recommend with #1 marked** ⭐ (options table with one-line rationale)
4. **Wait for explicit approval** (silence ≠ approval)
5. **Generate verbatim paste-back prompt** (copy-ready, no placeholders)

Anti-patterns are codified explicitly: 600-word coaching responses, single-option-no-choice replies, "what should I send back?"-leaving-it-to-operator, framework jargon dumps. Refusal phrasing added for the case where PO drifts and operator says "I don't understand."

Anchored at the don't-list level: **PO.10** added to PO's role-discipline don't-list, mapping to FR-16. Cross-referenced from `agents/product-owner/AGENT.md`.

### Added — return-path templates (cross-IDE structural enforcement)

Three new template files structurally enforce the relay-block pattern. Every gate report, deploy report, and architect response **must** include an operator-relay block at the bottom — the operator copies that block into PO chat instead of digesting the technical body.

| Template | Author | When written | What the operator copies |
|---|---|---|---|
| `templates/gate-report.md` | AI Developer | After T<gate>; before halting per FR-05 / IM.8 | Section 9 operator-relay block |
| `templates/deploy-report.md` | AI Developer (Deploy phase) | After T<deploy> + probes + FR-14 docs commit | Section 8 operator-relay block |
| `templates/architect-response.md` | Architect (escalated session) | After investigation; before reporting back | Section 12 operator-relay block |

Each template ends with a fenced operator-relay block. Section structure makes it impossible to ship a report without filling the relay block — by the time the AI Developer / Deploy / Architect reaches the end of the template, they've authored what the operator pastes to PO. Operator scrolls to bottom → copies the block → PO runs the Operator Relay Protocol on it. **Cross-IDE: works in Claude Code, Codex, Cursor, anything that reads markdown.**

### Updated — workflows reference the new return-path templates

- `workflows/greenlight-implement.md` — gate report step now points at `templates/gate-report.md` and explicitly mentions the section-9 operator-relay block (mandatory per FR-16).
- `workflows/greenlight-deploy.md` — deploy report step now points at `templates/deploy-report.md` (section 8 relay block).
- `workflows/architect-escalation.md` — architect response step points at `templates/architect-response.md` (section 12 relay block).

Cross-references added: each workflow's "Related" section now lists `skills/role-discipline/SKILL.md` (the Operator Relay Protocol) and the corresponding return-path template.

### Updated — agent definitions cross-reference return-path templates + Protocol

- `agents/ai-developer/AGENT.md` — gate report step (phase 7) and deploy report step (phase 8b) now reference the new templates and the section-N relay block.
- `agents/product-owner/AGENT.md` — don't-list bumped to PO.1..PO.10 (was PO.1..PO.9). New PO.10 entry maps to FR-16. New "Operator Relay Protocol" section added with the 5-step summary and a pointer to the full body in `skills/role-discipline/SKILL.md`.

### What did NOT change

- Engine bytes (`hooks/local/fusebase-flow-health-check.sh`) — identical to v2.5.0 / v2.4.1
- Recovery script (`hooks/local/post-fusebase-update.sh`) — identical
- `upgrade-engine.sh` — identical
- Existing handoff prelude templates (`templates/handoff-implement.md`, `handoff-deploy.md`) — only the FR-15 → FR-16 attestation count changed
- Existing self-attestation phrasing — only the count changed (FR-01 through FR-15 → FR-01 through FR-16)

**Backward compatibility:** strict superset. Older sessions that attest "FR-01 through FR-15" still work — FR-16 is an additive rule and doesn't deprecate any v2.5.0 behavior. Older gate / deploy / architect reports without the operator-relay block continue to work, but new reports authored from v2.6.0+ templates carry the structure.

### Why ship as v2.6.0 (minor) rather than patch

The Operator Stewardship initiative is a deliberate framework-design statement: the operator's role narrows; the AI's role expands to absorb cognitive load. That's a meaningful new commitment, not a bug fix. Minor version reflects the new always-on rule (FR-16) and the new mandatory PO ritual.

### Verification

- `bash hooks/local/preflight.sh` → 0 errors, 0 warnings
- `bash hooks/tests/run-tests.sh` → 14/14 PASS
- `bash hooks/local/fusebase-flow-health-check.sh` → as-expected verdict (DRIFTED on upstream's own working tree; same baseline as v2.4.1 / v2.5.0)
- `grep -rn "FR-01 through FR-15\|FR-01\.\.FR-15"` outside CHANGELOG / release-notes / fusebase-health → 0 matches
- Mirrors regenerated cleanly (skills 20 / 2 mirrors; agents 4 / 2 mirrors)

## [2.5.0] — 2026-05-10

### Changed — role rename: "Implementer" → "AI Developer" (framework-wide)

The role previously called "Implementer" in narrative text is now uniformly called "AI Developer" across the framework. The agent identifier was always `ai-developer` (e.g., `.claude/agents/ai-developer.md`); narrative text used "Implementer" inconsistently. v2.5.0 consolidates the terminology.

**What changed:**

- All occurrences of `Implementer` (as a role/actor noun) replaced with `AI Developer` in: `FLOW_RULES.md`, `workflows/*.md`, `templates/*.md`, `policies/*.yml`, `skills/<name>/SKILL.md` (10 skills), `agents/<name>/AGENT.md` (2 agents), `README.md`, `AGENTS.md`, `docs/architecture-overview.md`, `docs/operator-discipline.md`, `docs/rail-mapping.md`, `docs/handoff/README.md`, `hooks/local/fusebase-flow-overlays/*-overlay.md`, IDE configs (`.cursor/rules/*.mdc`, `.github/instructions/*.md`, `.github/copilot-instructions.md`).
- All mirrored copies (`.claude/skills/`, `.agents/skills/`, `.claude/agents/`, `.codex/agents/`) regenerated via `mirror-skills.sh` + `mirror-agents.sh`.
- Self-attestation language updated: `"Operating as Implementer..."` → `"Operating as AI Developer..."`.
- `IM.1..IM.10` role-discipline section identifiers retained (they stand for "Implement Mode" — a phase descriptor, not a role descriptor; renaming them would have been gratuitous churn).

**What did NOT change:**

- Filenames: `*-implement.md` handoff slug pattern, `agents/ai-developer/`, `workflows/greenlight-implement.md`. These describe the *artifact* (an implement-phase handoff), not the *role*; the slug is fine.
- Phase names: `Implement` stays a phase verb (one of the 8 phases — Specify / Clarify / Plan / Decisions / Tasks / Verify / Implement / Deploy).
- Agent identifier: `ai-developer` was already canonical.
- Historical CHANGELOG entries and release notes (v2.1.0 etc.) — kept as-is for historical accuracy.

**Migration impact for downstream projects:** none structurally. Existing handoffs authored before v2.5.0 still work — the AI Developer role recognizes the older "Implementer" attestation as equivalent. New handoffs authored from the v2.5.0 templates will use the new language.

**Why this matters:** consistent terminology removes a source of operator confusion and makes the framework's role taxonomy easier to reason about. Was a long-standing inconsistency between "machine-readable" identifier and "human-readable" narrative.

### Added — handoff prelude templates (`templates/handoff-implement.md`, `templates/handoff-deploy.md`)

Two new template files containing **role-bootstrap preludes** that make handoff files self-bootstrapping in any AI agent (Claude Code, Codex, Cursor, anything that reads markdown). Eliminates the operator burden of retyping role-attestation prompts every time a fresh chat is opened for an implement or deploy phase.

**Problem this closes:** before v2.5.0, every fresh AI Developer or Deploy chat required the operator to manually paste a role-declaration prompt — slash commands and SessionStart hooks (alternative solutions considered) only work in Claude Code; the framework needed a cross-IDE answer. The handoff-prelude approach works anywhere a session can read markdown.

**How it works:**

1. PO authors handoff files by copying `templates/handoff-implement.md` (or `-deploy.md`) and filling in placeholders.
2. The template's top section is a "Role bootstrap" prelude with the canonical self-attestation language, hard invariants, and refusal phrasing.
3. Operator pastes a short trigger — "Execute `docs/handoff/<path>`" — into any fresh chat.
4. Session reads the file, sees the role bootstrap at the top, self-attests correctly, then reads the rest as normal.

**What ships:**

- `templates/handoff-implement.md` — full template for AI Developer Implement-phase handoffs. Includes role bootstrap, mandatory pre-execution reads, ticket header, pre-cached identifiers table, production-state section, tracks, worker-undisturbed posture, stop-at-gate reminder, per-output state announcement, per-commit pre-attestation, gate-report contract.
- `templates/handoff-deploy.md` — full template for AI Developer Deploy-phase handoffs. Includes role bootstrap, DP.6 magic-phrase confirmation prompt, DP.1 approval-artifact verification, probe table, smoke pointers, single docs commit (FR-14), rollback procedure, deploy-report contract.
- `workflows/greenlight-implement.md` and `workflows/greenlight-deploy.md` updated to instruct PO sessions to author from the new templates rather than hand-rolling from the embedded snippet (snippets retained for legacy reference).

**Cross-IDE benefit:** unlike slash commands or SessionStart hooks (Claude Code-specific), handoff files are plain markdown — they work identically in Claude Code, Codex, Cursor, and any other agent that reads files.

### Why ship together

The rename and the handoff prelude are independent improvements but ship in one minor release because:

1. The new prelude templates are the cleanest place to bake the new "AI Developer" language. Shipping the rename without the templates would mean the canonical role-attestation snippet would still live embedded in workflow files (where the inconsistency was hardest to catch).
2. Both are zero-impact for in-flight tickets: existing handoffs continue to work, new handoffs use the new templates.
3. One release = one set of upgrade-engine.sh runs across downstream projects.

### Verification

- `bash hooks/local/preflight.sh` → 0 errors, 0 warnings
- `bash hooks/tests/run-tests.sh` → 14/14 PASS
- `bash hooks/local/fusebase-flow-health-check.sh` (run on upstream tree) → DRIFTED (expected — upstream's own AGENTS.md/CLAUDE.md don't carry installed overlay markers; same as v2.4.1 baseline)
- `grep -rn "Implementer"` outside of CHANGELOG.md, docs/release-notes/, and docs/fusebase-health/ → 0 matches

## [2.4.1] — 2026-05-10

### Fixed — Windows CRLF leak from Python helpers into bash arrays

Surfaced one day after v2.4.0 by `paperclip+hermes-v1` receiving agent on Windows: the engine's deferral mechanism silently failed to match `check_id` strings whenever a `health_check_deferral-*.json` artifact listed **two or more** `deferred_checks`. Single-entry artifacts worked. Multi-entry artifacts caused the engine to classify `claude_skills_mirror_count` (last entry in upstream's example) as `LOCAL_DRIFT` even though the operator had explicitly authorized it.

**Root cause.** Python's `print()` on Windows emits `CRLF` (`\r\n`). Bash command substitution `$()` strips trailing `LF` from the captured stdout but leaves `CR` characters embedded between lines. The engine then read each line with `read -r`, which strips the trailing `LF` but **does not** strip `CR`. Result: every entry except the last gained a trailing `\r`, so `${DEFERRED_CHECKS[$i]}` held literal `"agents_md_overlay\r"` while `record_drift` was comparing against `"agents_md_overlay"`.

The bug was previously masked because:
- v2.4.0's smoke test on Linux/macOS passed (no CRLF emission).
- A single-entry deferral list also passed on Windows because the lone entry has no `\r` suffix.
- The receiving agent caught it within hours of v2.4.0 landing on `paperclip+hermes-v1` because the install brief defers exactly two checks.

**Fix.** Defensive `\r` strip applied at every Python-to-bash boundary in the engine:

1. `cid="${cid%$'\r'}"` after `read -r cid` in the deferred-checks while-loop (load-time fix; the original bug site).
2. `EXPECTED_EVENTS_STR="${EXPECTED_EVENTS_STR//$'\r'/}"` before the events for-loop (parallel boundary, theoretical bug — events string is whitespace-split so a trailing `\r` would attach to the last event name).
3. `summary="${summary//$'\r'/}"` after the summary capture (cosmetic — would have only caused a trailing `\r` in `ARTIFACT_NOTES` console output, not a logic bug; included so all three boundaries are uniformly defended).

All three are idempotent on Linux/macOS — no `\r` to strip, no behavior change. On Windows they restore correct behavior.

**Verification.** Smoke test in test project 2 with a multi-entry `deferred_checks: ["agents_md_overlay","claude_md_overlay","claude_skills_mirror_count"]` artifact confirms all three classify as `LOCAL_DEFERRED` (verdict `EXCEPTION_IN_EFFECT` exit code 3) instead of dropping the last two into `LOCAL_DRIFT`.

### Coordination note

`paperclip+hermes-v1` carries the same fix as a local engine patch (commit on its branch documenting the deviation against upstream v2.4.1). Operators who upgrade `paperclip+hermes-v1` to upstream v2.4.1 via `bash hooks/local/upgrade-engine.sh` can drop the local patch — upstream and downstream converge on the same engine bytes.

## [2.4.0] — 2026-05-10

### Added — health-check deferral artifacts (closes BACKLOG B4)

Operator-authored mechanism for marking specific health-check drift items as deliberate-by-design rather than actual drift. When all non-OK checks are covered by an active deferral artifact, the engine returns verdict `EXCEPTION_IN_EFFECT` (exit code 3) instead of `DRIFTED` / `BROKEN`.

#### What ships

- **New artifact category:** `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json`. Lists `deferred_checks` — an array of stable check_ids the engine recognizes. Schema documented at `docs/health-check-deferrals.md`.
- **Engine recognizes 6 defer-able check_ids:**
  - `agents_md_overlay`
  - `claude_md_overlay`
  - `settings_json_lifecycle_events`
  - `claude_skills_mirror_count`
  - `claude_agents_mirror_count`
  - `windows_shell_patch`

  Critical infrastructure checks (preflight, recovery script presence, hook tests, etc.) are deliberately NOT defer-able — see `docs/health-check-deferrals.md` for the rationale.
- **New `LOCAL_DEFERRED` bucket** with `⊘` rendering in the engine output. Each deferred item is tagged with `[check_id=<id>; deferred per <artifact-filename>]` for full traceability.
- **New "Deferred checks" output section** explaining the mechanism when LOCAL_DEFERRED is non-empty.
- **Verdict logic update.** When `LOCAL_DRIFT` is empty AND `LOCAL_DEFERRED` is non-empty → `EXCEPTION_IN_EFFECT`. Genuine breakage (`LOCAL_BROKEN`) still trumps deferrals — operators cannot defer real failures.

#### Why this exists

Real-world driver: `paperclip+hermes-v1` install brief (commit `f73e204`) deliberately deferred two checks per Steps 9 + 10 of its install discipline:
- `.claude/settings.json` lifecycle hooks NOT wired (preserve project's existing quality-check + lint-on-stop hooks)
- Windows `shell:true` patch NOT applied (`.claude/hooks/` listed as protected)

The brief's Step 15 expected `HEALTHY` after install. Pre-v2.4.0 the engine had no concept of "this drift is approved"; it reported `BROKEN` instead. Brief's expectation was correct — the engine was the gap. v2.4.0 closes it.

The mechanism is **explicit and documented**, not a wildcard suppression knob:

- Operator authors a JSON artifact with `approved_by`, `scope`, `expires_at`, `reason`, and `deferred_checks` fields
- Each `deferred_checks` entry must match a canonical check_id (unknown ones are silently ignored — engine prefers explicit taxonomy over wildcard)
- Engine respects `expires_at` — expired artifacts go inactive automatically, drift items go back to `LOCAL_DRIFT`
- Critical infrastructure remains non-deferrable (recovery script presence, overlay templates folder, preflight failures, etc.)

### Fixed — latent v2.2.1 grep-count zero-matches bug

Surfaced during v2.4.0 development: the AGENTS.md / CLAUDE.md overlay-marker count check used `grep -cF ... || echo 0` which produced corrupted `"0\n0"` output when count was 0 (same `set -o pipefail` interaction as v2.3.0's diff-count bug, fixed in v2.3.1). Existed since v2.2.1 but only triggered when a project genuinely lacked overlay markers — uncommon. Surfaced when running v2.4.0 engine in upstream's own working tree (whose AGENTS.md doesn't have the operator-installed overlay block).

**Fix:** replace `|| echo 0` with `|| true` in both AGENTS.md and CLAUDE.md count lines. Same pattern as v2.3.1's fix.

### Changed

- **`hooks/local/fusebase-flow-health-check.sh`** — engine grew ~110 lines net for: deferral artifact loading in Section 0, `record_drift` helper function with check_id lookup, `LOCAL_DEFERRED` bucket, refactored 6 defer-able check sites, verdict logic update, "Deferred checks" output section, recommendations update for the deferred-only case. Plus the latent grep-count bug fix.
- **`README.md`** — added "Deferral artifacts (v2.4.0+)" subsection inside the Health check section. Verdict table updated to mention both v2 and v2.4.0+ artifact types.
- **`docs/health-check-deferrals.md` (new)** — full operator reference for the new mechanism. Schema, taxonomy, examples (including the canonical paperclip+hermes-v1 case), workflow for adding/removing deferrals, limitations.
- **`VERSION`** `2.3.2` → `2.4.0`.

### Validation at release

- preflight: 0 errors / 0 warnings
- hook tests: 14/14 PASS
- skill mirror: 20 files, 0 drift
- agent mirror: 4 files, 0 drift
- bash syntax check on engine: clean
- B4 smoke test in `test project 2`:
  - Pre-deferral baseline (Windows patch reverted): verdict `DRIFTED`, exit 1 ✓
  - Post-deferral artifact (`health_check_deferral-test-windows-patch-20260510.json` listing `windows_shell_patch`): verdict `EXCEPTION_IN_EFFECT`, exit 3, item shown with ⊘ symbol + `[check_id=windows_shell_patch; deferred per <artifact>]` ✓
  - Cleanup (delete artifact, restore patch): verdict back to `HEALTHY`, exit 0 ✓
- Engine in upstream's own working tree (where AGENTS.md genuinely lacks overlay): now reports `DRIFTED` correctly with proper count display (was `BROKEN` with `"0\n0"` corruption pre-v2.4.0)

### Real-world impact

**`paperclip+hermes-v1`** can now author a deferral artifact matching its install brief's Steps 9 + 10:

```json
{
  "approved_by": "operator@example.com",
  "scope": "Lifecycle hooks + Windows patch deferred per install brief 2026-05-08",
  "expires_at": "2026-08-10T00:00:00Z",
  "reason": "Project preserves existing hooks per Step 9; .claude/hooks/ protected per Step 10",
  "deferred_checks": ["settings_json_lifecycle_events", "windows_shell_patch"]
}
```

After filing this artifact, the project's health check returns `EXCEPTION_IN_EFFECT` (exit 3) instead of `BROKEN` (exit 2). The brief's Step 15 expected behavior is now achievable.

### Notes for upgraders (v2.3.2 → v2.4.0)

- **Pure additive feature.** No content changes; no migration needed for projects that don't author deferral artifacts.
- Upgrade path: refresh `.fusebase-flow-source/`, run `bash hooks/local/upgrade-engine.sh` — engine self-update picks up v2.4.0 logic.
- Existing `protected_path_edit-*.json` artifacts continue to work unchanged.
- New documentation: read `docs/health-check-deferrals.md` if you have install briefs that deliberately omit parts of the canonical setup.

### What's next

Backlog item **B2** (refresh `docs/fusebase-health/` for v2.3.0 + v2.3.1 + v2.3.2 + v2.4.0) is the docs-sweep follow-up. No release needed; gitignored operator dev notes.

---

## [2.3.2] — 2026-05-10

### Fixed — two engine + recovery edge cases

Bundled patch fixing two cosmetic / classification issues surfaced during real-world use of v2.2.x → v2.3.x.

#### 1. `upgrade-engine.sh` self-update count off-by-one (closes BACKLOG B1)

When `upgrade-engine.sh` upgrades itself (i.e. `hooks/local/upgrade-engine.sh` differs between local and `.fusebase-flow-source/`), the apply-summary previously undercounted by 1:

```
[upgrade-engine] Applied (1):    ← undercount; should be 2
  ✓ VERSION (2.3.0 -> 2.3.1)
```

Root cause: the script overwrites itself via `cp` mid-execution. The cp succeeds and the file on disk is updated correctly, but the running bash process (executing from memory) loses the `APPLIED+=("$f")` accumulation for the self-target on Windows + Git Bash.

**Fix:** restructured to detect + handle `upgrade-engine.sh` self-update OUTSIDE the main `FILES_TO_SYNC` loop. Self-update detection happens in a dedicated pre-loop block (`SELF_NEW`/`SELF_CHANGED` flags); apply happens before the regular loop. APPLIED tracking is now reliable. Apply-summary message also explicitly notes "new logic active on next run" since the running script is the OLD version.

Also extracted the diff-line counting into a `count_diff_lines` helper for consistency.

#### 2. Engine reclassifies missing upstream clone from BROKEN to OK (closes BACKLOG B3)

Pre-v2.3.2 engine code:

```bash
if [ "$EXPECTED_AGENT_COUNT" -eq 0 ]; then
  LOCAL_BROKEN+=(".claude/agents/: cannot determine expected agent set ...")
```

This forced verdict `BROKEN` (exit 2) for any project that intentionally cleaned up `.fusebase-flow-source/` after install (which is the documented norm per `install-fusebase-cli-project.md` and `install-existing-project.md`).

Surfaced empirically during install in `paperclip+hermes-v1` (commit `f73e204`) — the install brief explicitly cleaned up the clone in Step 16, then expected `HEALTHY` in Step 15. With the v2.3.1 engine, the verdict was `BROKEN` instead of `HEALTHY` — a wrong prediction caused by this over-classification.

**Fix:** reclassify `EXPECTED_X_COUNT == 0` from `LOCAL_BROKEN` to `LOCAL_OK` with informational language: `count not verified (no .fusebase-flow-source/ clone available; re-clone to enable upstream comparison)`. Verdict no longer flips to `BROKEN` on this state alone.

The check is informational — the engine still falls back to local `skills/` / `agents/` directories for the actual mirror count (when those exist locally). The reclassification only affects projects that lack BOTH the upstream clone AND root-level `skills/`/`agents/` — typically: post-install-cleanup state without root-level canonical content (rare, but happens).

### Changed

- **`hooks/local/upgrade-engine.sh`** — restructured self-update detection + apply (~30 lines net change). Inline comments explain the on-Windows-self-overwrite fragility for future maintainers.
- **`hooks/local/fusebase-flow-health-check.sh`** — two `LOCAL_BROKEN` calls reclassified to `LOCAL_OK` with informational text (~6 lines net change). Inline comments cite v2.3.2 + reference to install-cleanup discipline.
- **`VERSION`** `2.3.1` → `2.3.2`.

### Validation at release

- preflight: 0 errors / 0 warnings
- hook tests: 14/14 PASS
- skill mirror: 20 files (10 × 2), 0 drift
- agent mirror: 4 files, 0 drift
- bash syntax check on both modified scripts: clean
- B1 smoke test: induced self+other diff in `test project 2`; (will validate after operator pulls v2.3.2)
- B3 smoke test: in `test project 2`, temporarily renamed `.fusebase-flow-source/` away; engine reported `HEALTHY` exit 0 (was `BROKEN` exit 2 pre-fix). Local fallback worked.

### Notes for upgraders (v2.3.1 → v2.3.2)

- Pure engine + script behavior fixes. No content changes; no migration needed.
- Existing projects pulling v2.3.2 will see slightly different output:
  - `upgrade-engine.sh` apply summary now correctly counts self-updates (no off-by-one)
  - Health check no longer reports `BROKEN` purely because `.fusebase-flow-source/` was cleaned up post-install
- Recommended upgrade: refresh `.fusebase-flow-source/`, run `bash hooks/local/upgrade-engine.sh` to pick up both fixes in one pass.

### Real-world impact

Projects affected by these fixes:

- **`paperclip+hermes-v1`** (currently on v2.2.1): once they upgrade to v2.3.2, the BROKEN verdict caused by missing-clone classification will improve to either `DRIFTED` (if other deferred items remain) or `HEALTHY`. The deferred-decision items (settings.json events + Windows patch) still surface as drift — those need backlog item B4 (deferred-decision artifacts) to be marked as approved.

---

## [2.3.1] — 2026-05-10

### Fixed — cosmetic diff-count display in `upgrade-engine.sh`

When `set -o pipefail` is active (it is, in `upgrade-engine.sh`), the line:

```bash
diff_count=$(diff "$src" "$f" 2>/dev/null | grep -cE "^[<>]" || echo 0)
```

produced corrupted output for any file with line differences. `diff` exits non-zero when files differ → pipefail makes the whole pipe exit non-zero → `|| echo 0` fires AND appends "0" to stdout → `diff_count` captures both the real count AND a literal newline + "0".

Render pre-v2.3.1:

```
  • hooks/local/fusebase-flow-health-check.sh (200
0 line diffs)
```

Render in v2.3.1:

```
  • hooks/local/fusebase-flow-health-check.sh (200 line diffs)
```

### Changed

- **`hooks/local/upgrade-engine.sh`** — replace `|| echo 0` with `|| true`. `grep -c` always writes the count to stdout (even when 0), so `|| true` swallows the non-zero exit without polluting stdout. Added inline comment explaining the pipefail interaction.
- **`VERSION`** `2.3.0` → `2.3.1`.

### Validation at release

- preflight: 0 errors / 0 warnings
- hook tests: 14/14 PASS
- skill mirror: 20 files, 0 drift
- Unit test (set -o pipefail + 250-line diff):
  - Pre-fix: captured `"500\n0"` (corrupted)
  - Post-fix: captured `"500"` (clean)
  - Identical files (edge case): captured `"0"` (correct, no false count)
- `bash -n hooks/local/upgrade-engine.sh`: clean

### Notes for upgraders (v2.3.0 → v2.3.1)

- Cosmetic-only patch. No behavior changes; functional logic was already correct.
- Re-running `bash hooks/local/upgrade-engine.sh` after pulling v2.3.1 will pick up the fix on next run (the script syncs itself).

### Discovered during validation

This bug was caught during the v2.3.0 end-to-end smoke test in a downstream project — the upgrade succeeded, but the dry-run preview rendered with a line break in the diff count. v2.3.1 ships within hours of v2.3.0, demonstrating the value of always validating new releases against a real downstream upgrade scenario before declaring done.

---

## [2.3.0] — 2026-05-10

### Added — `hooks/local/upgrade-engine.sh` (operator-explicit engine upgrade)

A new operator-maintained script that closes the loop on engine upgrades. When upstream ships a new health-check engine version (e.g. v2.2.1's duplicate-marker detection), `mirror-skills.sh` and `mirror-agents.sh` only sync `skills/` and `agents/` from the local `.fusebase-flow-source/` clone — they deliberately do NOT touch `hooks/local/*.sh` because those are operator-maintained scripts that may carry local customization.

`upgrade-engine.sh` is the explicit opt-in path for operators who DO want to adopt new upstream engine versions:

- Diffs `hooks/local/fusebase-flow-health-check.sh`, `hooks/local/post-fusebase-update.sh`, and `hooks/local/upgrade-engine.sh` (itself) against `.fusebase-flow-source/hooks/local/`
- Bumps the project's `VERSION` file to match upstream
- Backs up each replaced file with a `.pre-upgrade-<timestamp>` suffix
- Reports diff stats, prompts for confirmation (or accepts `--auto-yes` / `--dry-run`)

### Why this matters

Pre-v2.3.0, an operator who pulled a new upstream version into `.fusebase-flow-source/` had to manually copy the engine + recovery scripts file-by-file. Easy to forget; easy to leave the project on an older engine while thinking it was upgraded. v2.3.0 makes the upgrade a single command:

```bash
cd .fusebase-flow-source && git pull origin main && cd ..
bash hooks/local/upgrade-engine.sh
```

### Usage modes

| Mode | Command | Behavior |
|---|---|---|
| Interactive (default) | `bash hooks/local/upgrade-engine.sh` | Prints diff stats, prompts `y/N` |
| Non-interactive | `bash hooks/local/upgrade-engine.sh --auto-yes` | Applies without prompt |
| Preview only | `bash hooks/local/upgrade-engine.sh --dry-run` | Shows what would change; no writes |

### Files synced

- `hooks/local/upgrade-engine.sh` (itself — so future runs adopt new versions of this script seamlessly)
- `hooks/local/fusebase-flow-health-check.sh`
- `hooks/local/post-fusebase-update.sh`
- `VERSION`

### Files explicitly NOT touched

- `hooks/local/fusebase-flow-overlays/` (operator-customizable overlay templates with project-specific values)
- `skills/`, `agents/` (canonical content; use `mirror-skills.sh` / `mirror-agents.sh`)
- `AGENTS.md`, `CLAUDE.md`, `.claude/*` (managed via `post-fusebase-update.sh`)

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files, 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS
- `bash -n` syntax check on new script: OK

### Notes for upgraders (v2.2.x → v2.3.0)

- **Bootstrap step (one-time):** to get the v2.3.0 `upgrade-engine.sh` script into a project that's currently on v2.2.x, manually copy it once:
  ```bash
  cd .fusebase-flow-source && git pull origin main && cd ..
  cp .fusebase-flow-source/hooks/local/upgrade-engine.sh hooks/local/upgrade-engine.sh
  chmod +x hooks/local/upgrade-engine.sh
  ```
  After that, future engine upgrades (v2.3.1, v2.4.0, ...) are seamless via `bash hooks/local/upgrade-engine.sh`.
- **Recovery script unchanged.** v2.3.0 is purely additive.

---

## [2.2.1] — 2026-05-10

### Added — duplicate-overlay-block detection in health check engine

The health-check engine now counts occurrences of the AGENTS.md and CLAUDE.md heading markers (instead of just checking presence) and flags `DUPLICATE` if more than one copy is found.

#### Why

When upgrading across major heading-marker renames (e.g. v2.1.x → v2.2.0 dropped the "V2" qualifier), an operator who runs `bash hooks/local/post-fusebase-update.sh` without first manually removing the old block ends up with **two overlay blocks** in AGENTS.md (the old "V2" one + a new appended block matching the v2.2.0 heading). Recovery's `grep -qF` for the new heading finds it and skips, but recovery's first run already appended a duplicate.

Pre-v2.2.1, the engine reported `AGENTS.md overlay block: present` — incorrectly green-lighting a state that needs cleanup. v2.2.1 catches this.

#### Changed

- **`hooks/local/fusebase-flow-health-check.sh`** — AGENTS.md and CLAUDE.md overlay-marker checks now use `grep -cF` (count) instead of `grep -qF` (presence). Three states:
  - `0` → `MISSING` (LOCAL_DRIFT — same as before)
  - `1` → `present` (LOCAL_OK — same as before)
  - `>1` → `DUPLICATE (N copies present — likely from a heading-marker rename without first removing the old block; remove the older block manually)` (LOCAL_DRIFT — new state)
- **`VERSION`** `2.2.0` → `2.2.1`.

#### Drift signature behavior

Duplicate state classifies as `DRIFTED` (not `FUSEBASE_UPDATE_AFTERMATH`). The canonical `FUSEBASE_UPDATE_AFTERMATH` signature requires `AGENTS_MISSING` AND `SETTINGS_REDUCED` — duplicates have neither, so they fall through to `DRIFTED` with the descriptive LOCAL_DRIFT message guiding the operator to remove the older block manually.

The skill does not offer auto-recovery for this verdict (recovery wouldn't help — recovery script itself is what could have created the duplicate during a heading rename). Operator removes the old block by hand, then re-runs the health check.

#### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files (10 × 2 mirrors), 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS
- Smoke test: induced 2 copies of the AGENTS.md heading marker in a downstream project; engine correctly reported `DUPLICATE (2 copies present...)`, verdict `DRIFTED`, exit 1
- Single-copy and missing-marker behavior unchanged (regression-free)

#### Notes for upgraders (v2.2.0 → v2.2.1)

- **No content edits required.** Patch only changes the engine; existing AGENTS.md / CLAUDE.md / settings.json content remains valid.
- Pulling v2.2.1 (via re-clone or re-running `mirror-skills.sh`) is sufficient. Recovery script is unchanged.
- If your project currently has a duplicate marker block (carried over from v2.1.x → v2.2.0 without a manual edit), v2.2.1's health check will start reporting it — fix it once by deleting the older block, then re-run health check.

---

## [2.2.0] — 2026-05-10

### Added — Health check & recovery (major feature)

A built-in **health check skill** + **recovery script** that diagnose and repair Fusebase Flow overlay drift. The most common drift cause is `fusebase update` (Fusebase CLI) regenerating `AGENTS.md` / `.claude/settings.json` / `.claude/hooks/` from CLI templates and evicting the Fusebase Flow overlay. The new system handles this end-to-end.

#### What ships

- **`skills/fusebase-flow-health-check/SKILL.md`** (canonical skill, description-matched) plus mirrors at `.claude/skills/fusebase-flow-health-check/SKILL.md` and `.agents/skills/fusebase-flow-health-check/SKILL.md`.
- **`hooks/local/fusebase-flow-health-check.sh`** — read-only diagnostic engine. 12 inventory checks + active-approval-artifact awareness + upstream-comparison via `.fusebase-flow-source/` clone. Exit codes: 0 HEALTHY, 1 DRIFTED / FUSEBASE_UPDATE_AFTERMATH, 2 BROKEN, 3 EXCEPTION_IN_EFFECT.
- **`hooks/local/post-fusebase-update.sh`** — idempotent recovery script. 10 steps restore: skills + sub-agents mirrors, AGENTS.md + CLAUDE.md overlay blocks, `.claude/settings.json` lifecycle events, Windows shell:true patch on the typecheck hook (CVE-2024-27980 mitigation), the health-check skill mirror, and the `/fusebase-health` slash command.
- **`hooks/local/fusebase-flow-overlays/`** — overlay templates (the canonical content the recovery script appends/restores):
  - `agents-md-overlay.md` — `## Fusebase Flow — workflow lifecycle overlay` block for AGENTS.md
  - `claude-md-overlay.md` — `## Fusebase Flow — additional rules (overlay)` block for CLAUDE.md
  - `settings-json-merge.py` — Python merger (no `jq` dependency; auto-discovers events from upstream's `.claude/settings.json.example`)
  - `skills/fusebase-flow-health-check/SKILL.md` — skill template
  - `commands/fusebase-health.md` — slash command template
- **`.claude/commands/fusebase-health.md`** — `/fusebase-health` slash command (Claude Code).

#### Skill behavior — diagnose then offer

The skill is **read-only during diagnosis**. When drift is detected and recoverable, the skill **offers** recovery in chat with a yes/no confirmation:

```
Run recovery now? It will:
  • Restore AGENTS.md overlay block
  • Merge .claude/settings.json lifecycle events
  • Re-apply Windows shell:true patch
  • Re-mirror Fusebase Flow skills + sub-agents

Reply `yes` / `run it` / `fix it` / `proceed` to execute.
Reply anything else to halt and decide later.
```

On affirmative reply → recovery executes + re-check + report new verdict. On any non-affirmative reply (silence, `no`, a question) → halt. Operator authority preserved (PO.5 from `role-discipline` skill); friction reduced — no terminal context-switch needed for most cases. **EXCEPTION_IN_EFFECT** (drift attributable to active approval artifacts in `state/approvals/`) and **BROKEN** verdicts do NOT trigger the recovery offer (recovery wouldn't fix them).

#### Auto-discovery for upstream upgrades

The engine and the merger auto-discover canonical sets at runtime from `.fusebase-flow-source/`:

- **Skill names** from `skills/*/`
- **Agent names** from `agents/*/`
- **Lifecycle event names** from `.claude/settings.json.example`
- **Hook handler commands + matchers** from the same example file

Patch / minor upstream releases (new skill / agent / event) require **zero maintenance** to this system. Only major-version semantic changes (heading marker rename) require manual edits.

#### Heading marker convention

This release standardizes on `## Fusebase Flow — workflow lifecycle overlay` (AGENTS.md) and `## Fusebase Flow — additional rules (overlay)` (CLAUDE.md). The previous internal "V2" qualifier was dropped per the standard "Fusebase Flow" naming.

### Changed

- **`VERSION`** `2.1.1` → `2.2.0`.
- **`README.md`** — added "Health check & recovery (v2.2+)" section with quick reference, verdicts table, recovery flow, auto-discovery posture, and file inventory.
- **`docs/install-fusebase-cli-project.md`** — heading marker text updated to `## Fusebase Flow — workflow lifecycle overlay` (was `# Fusebase Flow Local — workflow discipline overlay`); recovery section added.
- **`docs/install-existing-project.md`** — health check + recovery section added.

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files (10 × 2 mirrors), 0 drift (after regen)
- agent mirror: 4 files, 0 drift (after regen)
- hook tests: 14/14 PASS
- Health check end-to-end test: HEALTHY → fusebase update → FUSEBASE_UPDATE_AFTERMATH → recovery offer → affirmative → recovery executed → HEALTHY (exit 0)
- Idempotency: 2nd recovery run reports "already in place" for all restorable items, byte-identical no-op on settings.json merge

### Notes for upgraders (v2.1.x → v2.2.0)

- **Heading marker change:** if you have an existing v2.1.x project with `## Fusebase Flow V2 — workflow lifecycle overlay` in your AGENTS.md, edit it to drop the "V2 ": `## Fusebase Flow — workflow lifecycle overlay`. Same for CLAUDE.md (`## Fusebase Flow V2 — additional rules (overlay)` → `## Fusebase Flow — additional rules (overlay)`). The recovery script and engine grep for the new heading; without this edit they'll think the marker is missing and append a duplicate block.
- **`stop.py` statusMessage:** the merger now writes `"Fusebase Flow stop hook…"` (was `"Fusebase Flow V2 stop hook…"`). Existing settings.json entries with the old text continue to work but will not match the merger's substring check on the next merge — re-run `bash hooks/local/post-fusebase-update.sh` to pick up the updated text.
- **No skill / agent rename:** existing skills and sub-agents keep their names. The new `fusebase-flow-health-check` skill is additive.
- **Fresh installs:** `bash install.sh` works as before; new health check files are picked up automatically by the existing mirror-skills step.

---

## [2.1.1] — 2026-05-09

### Added — defense-in-depth refinements to the v2.1.0 sub-agent design

Two post-release hardening changes from independent v2.1.0 evaluation feedback. Both move guarantees from prompt-level (LLM judgment) to structural (tool / control flow).

- **`hooks/local/po-investigate.sh` (new)** — allowlisted, read-only investigation wrapper for the Product Owner sub-agent. Allowed subcommands: `status`, `diff`, `log`, `show`, `blame`, `ls`, `cat`, `head`, `tail`, `find`. Anything else exits non-zero. The PO sub-agent's tool surface still includes Bash, but its system prompt now mandates **wrapper-only** Bash usage and explicitly denies direct calls to `git`, `npm`, `node`, `python`, `cat`, `bash -c`, etc. Mutating commands (`git stash`, `git commit`, `npm install`, `node -e "fs.writeFileSync(...)"`, etc.) are not reachable through the wrapper because they aren't allowlisted subcommands.

- **`DP.6` deploy-time operator confirm** — new Deploy phase don't-list rule. Before the deploy command runs, the agent must obtain the operator typing the literal phrase `APPROVE-DEPLOY-NOW`. Anything else (`yes`, `y`, `ok`, partial matches) aborts the deploy. Mirrors the existing `APPEND-ONLY` pattern in `install.sh`. Adds ~5 seconds of structural friction to keep a human at the keyboard for production cutover moments. Codified in `skills/role-discipline/SKILL.md` (Deploy phase section), `agents/ai-developer/AGENT.md` (Deploy phase ownership table + don't-list + stop conditions), and `workflows/greenlight-deploy.md` (procedure step 4).

### Changed

- **`agents/product-owner/AGENT.md`** — Bash row in tool-surface table now mandates the `po-investigate.sh` wrapper. Direct Bash calls added to the Denied table.
- **`agents/ai-developer/AGENT.md`** — Deploy phase ownership table includes the new DP.6 step between DP.2 (worker-undisturbed re-check) and the deploy command run; don't-list expanded from `DP.1..DP.5` to `DP.1..DP.6`; stop-conditions table includes the abort-on-non-matching-phrase row.
- **`skills/role-discipline/SKILL.md`** — Deploy phase don't-list adds DP.6 with refusal phrasing for the "just deploy, I'm watching" violation request, plus recovery note.
- **`workflows/greenlight-deploy.md`** — procedure list inserts step 4 (operator confirm); subsequent steps renumbered 5–10. Self-attestation phrase updated `DP.1..DP.5` → `DP.1..DP.6`.
- **`VERSION`** `2.1.0` → `2.1.1`.
- **Mirrors regenerated** by `mirror-skills.sh` and `mirror-agents.sh`.

### Why these changed

Both refinements address ergonomic-vs-structural tradeoffs identified during external evaluation of v2.1.0. The PO wrapper closes a fuzzy "read-only Bash" boundary that the prompt-level instruction couldn't fully police (`git stash` mutates; `node -e "..."` is one keystroke from a write). The DP.6 confirm closes the "operator distracted at moment of production cutover" failure mode that purely automated deploys can hit. Both are minimal-surface additions that preserve v2.1.0's architectural shape (two sub-agents, role-discipline-driven, handoff-on-disk).

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 18 files, 0 drift (after regen)
- agent mirror: 4 files, 0 drift (after regen)
- hook tests: 14/14 PASS
- `po-investigate.sh`: syntax OK; smoke-tested allowlisted (`status`, `log`) and rejected (`nonsense` → exit 2) paths

### Notes for upgraders

- **PO sub-agent users:** if you've started a session before this upgrade, restart it so the v2.1.1 prompt loads (the wrapper-only Bash rule is in the system prompt; cached prompts won't have it).
- **Deploy automation:** the DP.6 pause adds a single round-trip to every Deploy phase invocation. For automated CI/CD that needs no-pause deploys, that path is an Operator-attested action (the operator runs deploys directly), not a Deploy-phase sub-agent invocation. The DP.6 rule applies only to sub-agent / role-attested deploys.

---

## [2.1.0] — 2026-05-09

### Added — Sub-agents (major feature)

- **Two role-shaped sub-agents** that cover the full eight-phase ticket lifecycle:
  - **Product Owner** (`agents/product-owner/AGENT.md`) — drives Specify, Clarify, Plan, Decisions, Tasks, draft-verification-gate, post-implement code-review and security-permissions-review, deploy-handoff drafting, and the spec DRAFT→DONE flip. Absorbs Architect responsibilities inline when escalation triggers fire (>10 files, cross-cutting refactor, platform blocker, blocked migration). Never edits application code.
  - **AI Developer** (`agents/ai-developer/AGENT.md`) — executes Implementer or Deploy-phase handoffs. Self-attests by handoff filename: `*-implement.md` → Implementer (runs the T-chain, stops at the gate); `*-deploy.md` → Deploy phase (runs deploy command, captures hash, runs probes). Never drafts specs; STOPS and asks if no handoff is provided.
- **Provider parity** via canonical → mirror pattern (parallel to skills):
  - `agents/<name>/AGENT.md` (canonical)
  - `.claude/agents/<name>.md` (Claude Code — auto-discovered)
  - `.codex/agents/<name>.md` (Codex — operator-referenced in fresh session)
- **`hooks/local/mirror-agents.sh`** regenerates both provider mirrors from canonical; parallel to `mirror-skills.sh`.
- **`audit/agent-mirror-manifest.txt`** sha256 manifest for drift detection.
- **`hooks/local/preflight.sh`** new step 5b verifies agent mirror parity (warn-level on drift).
- **`install.sh`** new step 4 (4/4) offers to mirror agents alongside skills. Prompts renumbered 1/3..3/3 → 1/4..4/4.
- **`README.md`** — sub-agents row added to the enforcement table; tree shows `agents/`, `.claude/agents/`, `.codex/agents/`, `audit/agent-mirror-manifest.txt`; how-to-use section added under "Filing your first ticket".

### Changed

- **Self-attestation phrase** updated from `Fusebase Flow v0.1` to `Fusebase Flow v2.1` across all canonical files: `FLOW_RULES.md`, `CLAUDE.md`, `AGENTS.md` (where present), `GEMINI.md`, `.github/copilot-instructions.md`, `agents/*/AGENT.md`, `workflows/architect-escalation.md`, `workflows/greenlight-deploy.md`, `workflows/greenlight-implement.md`, `workflows/session-initiation.md`. Mirrors regenerated automatically.
- **Skill frontmatter** `fusebase_flow_version: 0.1` → `fusebase_flow_version: 2.1` across all 9 canonical skills + `templates/skill-template.md`. Mirrors regenerated.
- **`VERSION`** `0.1.2` → `2.1.0`.

### Coverage walkthrough (verified at release)

| Phase / cross-cut | Sub-agent | Verified |
|---|---|---|
| 1 Specify | Product Owner | ✓ |
| 2 Clarify | Product Owner | ✓ |
| 3 Plan | Product Owner | ✓ |
| 4 Decisions (recommend; operator locks) | Product Owner | ✓ |
| 5 Tasks | Product Owner | ✓ |
| 6a Draft verification gate | Product Owner | ✓ |
| 6b Run gate | AI Developer | ✓ |
| 6c Code review + security review | Product Owner | ✓ |
| 7 Implement | AI Developer (Implementer attestation) | ✓ |
| 8a Draft deploy handoff | Product Owner | ✓ |
| 8b Run deploy command | AI Developer (Deploy-phase attestation) | ✓ |
| 8c Spec DRAFT→DONE flip | Product Owner | ✓ |
| Architect escalation | Product Owner inline (AR.1..AR.6 additive) | ✓ |
| Live-user verification | AI Developer | ✓ |
| Knowledge curation | Product Owner | ✓ |
| Violation recovery | both (own role section) | ✓ |

### Validation at release

- preflight: 0 errors / 0 warnings (now includes step 5b agent-mirror check)
- skill mirror: 18 files, 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS

### Notes for upgraders

- Previous self-attestation phrases referencing `Fusebase Flow v0.1` are now `Fusebase Flow v2.1`. Sessions that run from cached prompts may need to be restarted to load the new phrasing.
- Sub-agents are **opt-in** — the framework remains fully usable via the existing skill-and-workflow flow without invoking sub-agents at all. Sub-agents are an additional entry point, not a replacement.
- Codex does not auto-discover `.codex/agents/` — operators reference the file in their first message of a fresh session (e.g., `Read .codex/agents/product-owner.md and operate as Product Owner`).

---

## [0.1.2] — 2026-05-09

### Added

- Sub-agents foundation (commit `937f658`) — superseded by the `2.1.0` release on the same day; effectively folded into v2.1.0.

## [0.1.1] — 2026-05-09

### Added

- `skills/role-discipline` (mandatory 8th canonical skill — actually 9th) with per-role don't-lists and exact refusal phrasing for Product Owner, Implementer, Architect (escalation), Deploy phase, and Operator.
- `workflows/live-user-verification.md` — 8-step procedure with verbatim consent flow, cookie sanity test, masked smoke output, end-of-work cleanup phrase that the stop hook checks for.
- `workflows/violation-recovery.md` — per-FR rule recovery procedures plus per-hook-event recovery.
- `docs/architecture-overview.md`, `docs/operator-discipline.md`, `docs/tradeoffs.md`, `docs/constitution.md`.
- `hooks/handlers/stop.py` — `cleanup_marker_present` and `live_user_verification_used` signals.
- `hooks/shared/secret_scanner.py` — `pattern_overrides` precedence (per-pattern escalation in tool context).
- `policies/secret-patterns.yml` — `cookie_session_value` pattern now blocks (not warns) in `pre_tool_use` and `git_pre_commit` contexts.
- 3 new deterministic hook test fixtures (12, 13, 14) covering cookie escalation and cleanup-marker gating.

### Changed

- Self-attestation phrase appended `I will apply the role-discipline skill section for {role}.`
- Implementer / Deploy / Architect role-specific self-attestation phrases now reference numbered sections (`IM.1..IM.10`, `DP.1..DP.5`, `AR.1..AR.6`).
- `skills/requirements-specification`: skip-clarify gate, Phase 1/2 split, abort-ticket failure case, scope-disagreement escalation.
- `skills/validation-and-qa`: 3-question empirical-coverage test for ACs; Sub-mode D test-data hygiene cleanup.
- `templates/smoke-test-playwright.md`: when-to-skip table, one-time setup block, CDP-vs-Playwright trade-offs.
- Various count updates triggered by adding the role-discipline skill (skills 8 → 9; mirrors 16 → 18; workflows 10 → 12; fixtures 11 → 14).

## [0.1.0] — Initial release

- Fusebase Flow Local v0.1 — repo-local workflow framework for AI coding agents and IDEs.
- 8 canonical skills, 10 workflows, 6 policies, 13 templates.
- Hook handlers for `session_start`, `user_prompt_submit`, `pre_tool_use`, `post_tool_use`, `stop`, `pre_compact`.
- Provider mirrors for Anthropic Claude Code (`.claude/skills/`, `.claude/settings.json.example`) and OpenAI / ChatGPT Codex (`.agents/skills/`, `.codex/{config.toml,hooks.json}.example`).
- Cursor rules (`.cursor/rules/*.mdc`).
- GitHub Copilot / VS Code instructions (`.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`).
- 11 deterministic hook test fixtures.
- CI workflow `.github/workflows/fusebase-flow-verify.yml`.
- Clean-room license attestation (`docs/clean-room.md`).
- MIT license.
