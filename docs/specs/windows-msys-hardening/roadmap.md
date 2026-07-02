# Roadmap — Windows/MSYS hardening + adoption-path + process (v3.30.3 / v3.30.4)

**Status:** COMPLETE — all 9 workstreams SHIPPED across v3.30.3 (WS1-WS9) + v3.30.4 (WS2-hard + WS5). See § Post-deploy closeout — v3.30.3 and § Post-deploy closeout — v3.30.4. LOCKED body below is the historical execution source-of-truth for the 9 field-validated slices captured 2026-06-30.

## Post-deploy closeout — v3.30.4 (2026-07-02) — roadmap COMPLETE

**Released:** commit `37da04f0f551420feab24b74990b3c6100be2d2f` · tag `v3.30.4` · https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.30.4
**DP.1 approval:** `state/approvals/production_deploy-v3304-20260702.json` (operator standing authorization; DP.6 equivalent = standing GO).
**Reviews:** three passes on the corrected diff (Codex full BLOCK→fixed, FuseBase workflow BLOCK→fixed, Codex re-review SHIP); all findings folded (T19/T20 + T21/T22 corrections).

| Workstream | v3.30.4 status |
|---|---|
| WS2-hard — Windows Job Object outer fence (opt-in `FFHC_USE_JOB_OBJECT=1`, default OFF) + Cummings-class ac3d/deadline reliability | **DONE** |
| WS5 — Upgrade engine Windows-safe bounded exit (busy-loop root fix + critical/optional bounding + timestamp-safe prune glob) | **DONE** |

**PROVEN-here vs CONSUMER-GATED split (v3.30.4):**

| Item | Status | Evidence / gate |
|---|---|---|
| WS2-hard fence mechanism (launch → assign → strictly-scoped atomic kill of the assigned tree) | **PROVEN here** | MSYS + PowerShell publish host; opt-in gated, default OFF |
| WS2-hard default behavior byte-unchanged (fence OFF) | **PROVEN here** | full run-tests green + POSIX byte-equivalence; fence is opt-in |
| WS2-hard Cummings-class `ac3d → rc137` reliability | **CONSUMER-GATED** | requires a real Cummings-class MINGW64 host (can't repro on publish host) |
| WS2-hard Job-Object-vs-`timeout -k` kill discriminator | **CONSUMER-GATED** | same host dependency; best-effort launch→assign race documented honestly |
| WS5 `prune_pre_backups` busy-loop root fix (single-pass O(M)) + critical/optional bounding + `set -e` fix (tested under `set -e`) | **PROVEN here** | code-verified + tested; adversarial-review corrections folded |
| WS5 full `upgrade.sh --auto-yes` end-to-end on MSYS | **CONSUMER-GATED** | host-dependent; operator distributes the apply/validate prompt |

**Consumer-verify (operator distributes):** full `run-tests.sh` on a quiet MINGW64 box · opt-in `FFHC_USE_JOB_OBJECT=1` on a real Cummings-class host · full `upgrade.sh --auto-yes` end-to-end.

**Adversarial-review corrections folded (T19-T22):** fence NO-RERUN fallback cleans both temp files (no leak); opt-in fence command-substitution HANG/leak fix + knob-first gate + honest race claim; `set -e` optional-step abort fix tested under `set -e` (the "tests ran without `set -e`" blind spot closed — see `docs/problem-catalog/tests-ran-without-set-e/`); prune glob tightened to the timestamp shape.

## Post-deploy closeout — v3.30.3 (2026-07-01)

**Released:** commit `989604e386b055a0a33639ff420f50a7eb0ae55d` · tag `v3.30.3` · https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.30.3
**DP.1 approval:** `state/approvals/production_deploy-v3303-20260701.json` (operator standing authorization).

| Workstream | v3.30.3 status |
|---|---|
| WS1 — Adoption path: install/upgrade commit succeeds (secret-scan runtime tokens + single-use digest-bound protected-path exception + safe git-hook (re)install) | **DONE** |
| WS2-core — Bounded-run engine strict recorded-winpid scoping + true-124/137-on-kill + no-hang | **DONE** |
| WS3 — Test harness reuses engine reap + bounds heavy phases + fixture-phase stdin fix (T17/T18) + real `mirror-skills --check` | **DONE** |
| WS4 — Health-check verdict robustness (rc0-no-run⇒BROKEN guard preserved) + MSYS timeout defaults | **DONE** |
| WS6 — preflight ↔ health-check overlay-marker consistency (backward-compatible dual-marker migration) + install hygiene | **DONE** |
| WS7 — Internal problem catalog (`docs/problem-catalog/`) | **DONE** |
| WS8 — Mandatory zero-trust subagent-liveness rule (FR-27 extension) | **DONE** |
| WS9 — Slash-command naming + capitalization | **DONE** |
| WS2-hard — Windows Job Object + Cummings-class ac3d/deadline reliability | **DONE (v3.30.4 · `37da04f` · tag v3.30.4)** |
| WS5 — Upgrade engine Windows-safe bounded exit (busy-loop / 255-at-tail) | **DONE (v3.30.4 · `37da04f` · tag v3.30.4)** |

**Adversarial-review corrections folded (T10-T18):** glob-bypass close, unique hook marker, trap re-verify, secret-scan runtime tokens, single-use digest-bound protected-path exception, MSYS bounded-run strict winpid scoping + harness reap + fixture-phase stdin fix, health-check verdict robustness + MSYS timeouts, dual-marker migration, test fidelity. Two independent adversarial reviews (Codex + FuseBase workflow) returned SHIP.

---

**Status (original):** LOCKED — Codex doc-review folded (RESCOPE). Execution source-of-truth for the 9 field-validated slices captured 2026-06-30.

## Codex doc-review — FOLDED (authoritative deltas; override the workstream bodies where they differ)
Codex 2026-06-30 → **RESCOPE**. Confirmed: **F-a** WS2-core strict recorded-winpid scoping is sufficient for WS3 (Job Object NOT a prerequisite; WS3 waits on WS2-core only) · **F-b** do NOT reclassify `rc0`; the real Ovation fix is WS2 "true-124-on-kill" then the existing `124⇒PARTIAL` path; keep `rc0+no-PASS+no-FAIL⇒BROKEN` (health-check `:417`; signal-only inconclusive `:407`; HT8-HT11 lock it) · **F-e** version split right (but do NOT market v3.30.3 as "complete Windows robustness" while WS5 is deferred). Load-bearing corrections:
- **[BLOCKER] WS6/WS9 markers — backward-compatible migration, NOT a rename.** The `## Fusebase Flow — …overlay` markers have MANY consumers that must move together AND accept the installed base: health-check `:196/:215`, preflight, post-fusebase-update `:195/:219`, overlay templates, `test-cli-flow-recovery.sh :196/:198/:614/:645`, `test-health-check-timeout.sh :63`, install docs `:224/:231/:248/:253`, health-check deferral docs, README `:516/:517`, plus installed consumers' `AGENTS.md`/`CLAUDE.md`. **Fix:** implement **dual-marker acceptance** (validators accept old `Fusebase Flow` **and** new `FuseBase Flow`), templates emit the new marker, `post-fusebase-update` **migrates old→new in place** on upgrade. **WS9's capitalization is the command DESCRIPTIONS only** (`hooks/local/fusebase-flow-overlays/commands/*.md` — single-sourced, picker-facing) — those are NOT the section markers → safe to reorder+recapitalize independently. Marker capitalization is done ONLY via the dual-accept migration, never a bare rename. **New ACs:** an old-marker install still validates HEALTHY; an upgrade migrates old→new; both validators accept both.
- **[HIGH] WS1(a) — keep secret excludes NARROW + runtime-construct tokens.** Do NOT `:(exclude)hooks/tests/` (blinds the scanner to a real secret in non-designed test code). Instead: **construct the designed tokens at runtime** in `test-secret-scan-staged.sh:22,54` (no literal PAT on a committed `+` line → nothing to exclude), and if any exclude is still needed keep it to the exact designed-token file. **New AC:** a real secret hard-coded in *other* `hooks/tests/*.sh` still BLOCKS.
- **[HIGH] WS1(b) — the exception must be genuinely SINGLE-USE.** `path_policy.has_active_exception` (`:62`) is path+TTL only today → a plain artifact is a reusable FR-07 bypass. **Fix:** the bootstrap/upgrade approval artifact must be **bound to the staged tree/path digest**, short-TTL, exact-operation, and **consumed/cleaned after the setup commit passes**. **New AC:** after the setup commit, a *second, unrelated* protected-path edit still DENIES (no standing bypass).
- **[MED] WS1(c) — don't clobber custom `.git/hooks`.** Hook (re)install must detect a Flow-managed marker/hash, **back up or warn** on a custom hook, and require explicit opt-in to overwrite. **New AC:** a pre-existing custom `.git/hooks/pre-commit` is preserved (or backed up), not silently overwritten.
- **[LOW] WS1 AC / release self-test — no `git add -A`.** Use a temp clone or an explicit path-staging list (command-policy compat).
- **Security review (F-f):** WS1 touches security guardrails (secret scanner + FR-07 protected-paths + approvals) → its adversarial review MUST include a **security-permissions dimension** (not functional-only).
- **Sequencing (corrected):** v3.30.3 = **WS2-core FIRST → WS3**; **WS4 after WS2** true-timeout-rc; WS1 (hardened exception + narrow excludes + custom-hook safe); **WS6+WS9 as ONE backward-compatible migration**; WS7/WS8 docs. v3.30.4 = WS2 Job-Object + WS5. **Add ACs:** old-marker downstream upgrade migrates/validates · custom git-hook preserved · exact staged-index-bound exception reuse-denial · real-secret-in-non-designed-test-code still blocks · a **30+ concurrent `bash.exe` sibling-survival** test for WS2/WS3 (a bounded kill reaps ONLY its recorded child tree).
**Baseline:** FuseBase Flow v3.30.2 (`origin/main` at author time).
**Authorization (operator, 2026-06-30):** full — migrations permitted (no real data/users on prod), **production deploy permitted**, execute all slices **end-to-end in one run** while the operator is away. Deploy discipline gates (verify-before-push, adversarial reviews) still apply; the operator's standing go-ahead replaces the per-release DP.6 prompt.
**Execution protocol:** per-workstream loop = spec/handoff → implement (ai-developer subagent) → gate → adversarial review → fold → ship. **Subagent liveness = zero-trust:** poll git/process progress every ~60–90s; on transient rate-limit/stall, re-dispatch or SendMessage-resume (wait ~60s and retry until it starts); verify final git state (clean linear history, 0 mirror drift) before trusting any agent. See [[retry-failed-subagents-and-poll-liveness]].

---

## 0. Scope classification — INTERNAL vs CLIENT (required UX gate)

**Every workstream here is INTERNAL developer/AI-agent tooling.** None touch the FuseBase Apps **client/end-user product**, and none touch **auth/sign-in/registration/session-tokens/user-role-group permissions** (so the "update the problem catalog for infrastructure/auth bugs" clause does not trigger from these fixes — the catalog is still *built* as WS7, populated with these dev-tooling issues + lessons).

The "UI/UX" surfaces in scope are all **operator/developer-facing CLI + IDE experiences**, and each gets deliberate DX design (not just a code change):
- **CLI verdict/message UX** (health-check output, block messages, progress) — WS3, WS4, WS1.
- **IDE slash-command picker UX** (non-truncated names) — WS9.
- **Install/upgrade flow UX** (no documented dead-ends; honest, actionable errors) — WS1, WS6.

**DX design principles applied throughout:** honest + actionable messages (name the exact knob + current value, not a generic hint); never a documented flow that dead-ends; discoverable escapes; non-truncated/scannable names; progress that is visibly *progressing* (flushed), never mistakable for a freeze; no false verdicts (never BROKEN/blocked on a healthy/legitimate state).

---

## 1. Source slices → deduped workstreams (traceability)

9 consumer field reports (Cummings, WorkHub, Ovation, Start-page, troubleshooter; all Windows MINGW64) validated v3.30.2 and surfaced the items below. Cross-consumer Bug-B matrix (drives priority):

| Box | bounded-run tests | health-check false-BROKEN | full `run-tests`→exit 0 |
|---|---|---|---|
| Cummings | **FAIL** (ac3d rc124≠137; msys-tree 5/6) | — | never |
| WorkHub | PASS (isolation) | fixed | never (255 collateral) |
| Ovation | slow (>40s bisect) | **still BROKEN** (rc0-on-kill) | never |
| Start-page | PASS 10/0 · 6/6 | fixed | never (25 min) |
| troubleshooter | PASS | fixed | never (F3) |

**Reading:** the v3.30.2 bounded-run *engine* fix works on 3/5 boxes (host-specific residual on Cummings); health-check false-BROKEN is fixed on most but **still fires on Ovation** via the `rc0-on-kill` path; **full `run-tests`→exit 0 fails on *every* box** — the universal, highest-leverage defect (harness doesn't reuse the engine reap).

---

## 2. Workstreams (deduped) — problem · root cause · fix · ACs · UX class · risk · version

### WS1 — Adoption path: install/upgrade commit must succeed out-of-the-box  · **HIGH** · v3.30.3
**Problem.** A fresh install AND a self-upgrade **cannot make the documented setup/upgrade commit** through Flow's own just-installed pre-commit — two gates fire, and the docs forbid `--no-verify`.
**Root causes (source-verified).**
- (a) **Secret scan self-trip, relocated:** `hooks/shared/staged_secret_scan.py._EXCLUDE_PATHSPECS` excludes `hooks/tests/fixtures/` but NOT `hooks/tests/test-secret-scan-staged.sh` (lives one level up), which ships literal PATs at `:22` and `:54` → block. (Slices 1·F1, 2·I3, 5·F1, 8·F1, 9·F1a.)
- (b) **FR-07 protected-paths blocks the changeset:** every Flow internal is a newly-*added* file; `path_policy.evaluate` is glob-only (no added-vs-modified distinction); no `state/approvals/` exception on a fresh/upgrade tree → `on_unapproved_edit: deny`. (Slices 8·F2, 9·F1b.)
- (c) **Hooks not (re)installed by upgrade:** `upgrade.sh`/`post-fusebase-update.sh` do NOT run `install-git-hooks.sh`, so the *fixed* pre-commit is inert on upgrade until a manual reinstall; and my earlier consumer prompt wrongly claimed "the upgrade installs the fixed pre-commit." (Slices 2·I2, 8·F2, 9·F1.)
- (d) `install.sh` never appends the canonical marker-guarded overlay blocks (see WS6). (Slice 9·F2.)
**Fixes.**
- **(a1)** Broaden the *commit-time* exclude to `:(exclude)hooks/tests/` (all designed-token test code) — PreToolUse/UserPromptSubmit scanning unchanged. **(a2)** Also construct the tokens at runtime in `test-secret-scan-staged.sh:22,54` (`ghp_$(printf 'x%.0s' $(seq 1 36))`) so no literal PAT is a committed `+` line (defense-in-depth). **(a3)** Add a **release-gate self-test**: stage the entire release tree through the fixed pre-commit and assert exit 0 — catches any future in-tree token before tagging.
- **(b)** Give install/upgrade a **scoped, short-TTL, audited** exception: `install.sh`/`upgrade.sh --wire-hooks` writes `state/approvals/protected_path_edit-flow-bootstrap-<date>.json` (exact Flow-internal globs, short TTL) so `path_policy.has_active_exception` matches ONLY the setup/upgrade commit — reuses the audited exception path, NOT a `--no-verify` bypass. **Tight-scope is load-bearing** (a broad exception = reusable FR-07 hole).
- **(c)** `upgrade.sh`/`post-fusebase-update.sh` (re)install the git hooks (or detect+warn a stale `.git/hooks/pre-commit`). Correct my inaccurate consumer prompt + the release-note wording.
- **(d)** see WS6.
**ACs.** Fresh install + upgrade: `install.sh --auto-yes` then `git add -A && git commit` **succeeds** through the wired hook with **no `--no-verify`**; a real secret in a normal file still blocks; the bootstrap exception is single-use/expiring (a *second* unrelated protected-path edit still denies); release-gate self-test asserts the release tree commits clean.
**UX class:** internal (install/upgrade CLI flow). **Risk:** med — the bootstrap exception must be tightly scoped; adversarial-review it hard.

### WS2 — Bounded-run engine: strict winpid scoping (fix over-broad taskkill) · **HIGH** · v3.30.3 (core) + v3.30.4 (hard)
**Problem.** The MSYS `taskkill` is unreliable in BOTH directions: **over-kills** (255-reaps the caller shell, the `run-tests` harness, and unrelated `bash.exe` in *other sessions* — Slice 5·F2.1) AND **under-kills** on some hosts (Cummings: ac3d SIGKILL grace doesn't fire → rc124≠137; native descendant blocks past deadline — Slice 2·I4). Also returns **rc0 on an MSYS kill** (masks the timeout → routes health-check to BROKEN — Slice 7·D1) and **hangs with a large budget** (Slice 7·D3).
**Root cause (hypothesis, to confirm).** `taskkill /T /PID <winpid>` root resolves to an **ancestor** and/or **Windows PID reuse** under churn; MSYS pid↔winpid mis-resolution; the `-k` SIGKILL escalation and deadline capture don't fire when a native descendant is alive.
**Fixes.**
- **v3.30.3 (core, prerequisite for WS3):** scope the kill **strictly to the spawned child's own recorded winpid subtree** — assert the taskkill root IS the child (never an ancestor), guard pid↔winpid mis-resolution + PID reuse (verify the winpid still maps to the expected child before killing). Ensure `run_with_timeout`/`ffhc_run_bounded` return a **true 124/137 on an MSYS kill (never 0)** and never hang on a large budget. Preserve the `ffhc_*` API + POSIX byte-equivalence.
- **v3.30.4 (hard):** wrap each bounded sub-run in a **Windows Job Object** so a kill can never reach the harness/caller/other session, and make the SIGKILL-grace/deadline reliable on Cummings-class hosts (ac3d → rc137).
**ACs.** A bounded run's kill affects ONLY the spawned child tree (a concurrent sibling `bash.exe`/the caller survives — reproduce with a 2nd concurrent `run-tests`); rc is 124/137 on kill (never 0); no hang with a large `FFHC_*_TIMEOUT`; 26 timeout tests + POSIX byte-equivalence intact; ac3d → rc137 (v3.30.4).
**UX class:** internal (engine). **Risk:** HIGH — FR-07-sensitive `ffhc_*` core; host-dependent (can't fully repro here) → consumer re-test gates the hard pass.

### WS3 — Test harness reuses the engine reap + bounds heavy phases (universal `run-tests` fix) · **HIGH** · v3.30.3
**Problem.** `run-tests.sh` never reaches `Total:`/exit 0 on ANY consumer box (the universal defect).
**Root cause (source-verified, Slice 9·F3).** The harness does NOT reuse the v3.30.2 engine reap: raw `$(...)` captures (`:100/:129/:158`, fixture loop `:32/:55/:59`) block until every write-end closes (an MSYS native grandchild survives POSIX `timeout`); **no `trap … EXIT` reaper**; `run_exitcode_phase test-cli-flow-recovery.sh` (`:204→:194`) is **unbounded**; phase output only echoes after `$(...)` completes (a multi-min phase looks like a freeze).
**Fixes.** Source the bounded core in `run-tests.sh`; replace `$(...)` captures with `ffhc_run_bounded` (tempfile capture + reap; read `FFHC_LAST_OUT`/`FFHC_LAST_RC`); add an MSYS **EXIT-trap that taskkills ONLY the harness's own recorded child winpids** (never a broad taskkill — depends on WS2 strict scoping); bound `test-cli-flow-recovery` (`ffhc_run_bounded "${FF_CLI_RECOVERY_TIMEOUT:-240}"` + `FF_SKIP_CLI_RECOVERY=1` opt-out; report its rc124 as INCONCLUSIVE, not silent-green); **flush per-phase progress** (`printf '[run-tests] starting %s\n' >&2` before each phase). Also: real `mirror-skills.sh --check` mode (currently no argv handling — WS3 also fixes the non-existent flag I relied on) + **batch Phase-3 per-file `dirname`/hash into the fork-free pass Phase-2 already uses** (Slice 8·F3, reduces 255-fork-fail).
**ACs.** `timeout 900 bash run-tests.sh` reaches `Total: N/N`/exit 0 on a quiet MSYS box; the EXIT-trap reaps only recorded children (a concurrent sibling survives); `test-cli-flow-recovery` bounded + opt-out; per-phase progress flushed; `mirror-skills.sh --check` is a real read-only drift check (exit nonzero on drift, no mkdir/cp).
**UX class:** internal (test-runner CLI progress). **Risk:** med — depends on WS2 strict scoping.

### WS4 — Health-check verdict robustness + MSYS timeout defaults · **HIGH/MED** · v3.30.3
**Problem.** (a) On Ovation, a healthy install reads **BROKEN** because the wrapper returns **rc0 on a kill** → the `rc0 + no FAIL: + no PASS ⇒ BROKEN` branch fires (Slice 7·D1). (b) Flat 30s/60s timeouts → healthy MSYS installs routinely `PARTIAL_UNVERIFIED` under load (Slices 1·F3, 7·F5, 9·F4).
**Fix.** **(a) — F2-gated, must NOT regress fail-closed:** the *root* fix is WS2 (wrapper returns true 124 on kill), after which the existing `124⇒PARTIAL` path handles it. As **defense**, treat a killed/unparseable hook-test run as INCONCLUSIVE only when the rc is genuinely signal/timeout-induced — **preserve `rc0 + no PASS + no FAIL ⇒ BROKEN` for a genuine no-run crash** (the Codex-validated guard; tests HT8/HT9/HT10/HT11). Do NOT blindly reclassify all rc0. **(b)** `ffhc_is_msys`-gate higher defaults (`FFHC_PREFLIGHT_TIMEOUT` 60 / `FFHC_TESTS_TIMEOUT` 120 on MINGW/MSYS/CYGWIN; 30/60 POSIX); in the PARTIAL_UNVERIFIED recommendation, print the exact knob **names + current effective values**; document the MSYS case in the health-check `SKILL.md`.
**ACs.** After WS2, a killed hook-test run on Ovation-class hosts → PARTIAL_UNVERIFIED (never BROKEN); an injected genuine `FAIL:`/rc0-no-run still → BROKEN (no fail-closed regression); MSYS defaults raised + knob names/values surfaced.
**UX class:** internal (verdict CLI messages). **Risk:** med — the reclassification tension (see the FLAG below).

### WS5 — Upgrade engine: Windows-safe bounded exit (busy-loop / 255-at-tail) · **HIGH** · v3.30.4
**Problem.** `upgrade.sh --auto-yes` busy-loops after the merge-baseline step on some hosts (Slice 2·I1) and/or exits 255 at its tail (Slice 8) under load.
**Fix.** Give `upgrade.sh` + the merge-baseline/content-copy loop a Windows-safe bounded exit (reuse the WS2 winpid/taskkill path); ensure it terminates and returns 0; make long steps killable + observable. Bound + progress-echo the silenced re-mirror.
**ACs.** `upgrade.sh --auto-yes` terminates + returns 0 on MSYS (bounded), no runaway, observable progress.
**UX class:** internal. **Risk:** med — host-dependent (partly the same MSYS kill path as WS2).

### WS6 — preflight ↔ health-check overlay-marker consistency + install hygiene · **HIGH/LOW** · v3.30.3
**Problem.** preflight checks only content tokens; health-check requires exact heading markers → a hand-merge passing preflight fails health-check with `FLOW_LAYER_DRIFT`; `install.sh` never appends the canonical overlay blocks (Slice 9·F2). Plus: install runs preflight *before* mirror (~86 stale warnings); PyYAML only warned not installed (Slice 9·F5).
**Fix.** Align both validators on the canonical heading marker (add exact-marker asserts to preflight, accept marker OR baseline fallback); have `install.sh` idempotently append the canonical overlay blocks (reuse `post-fusebase-update.sh:195-233`'s `grep -qF MARKER` guard, behind the APPEND-ONLY confirm); move mirror before preflight (or `FF_FIRST_INSTALL` guard); offer `pip install -r hooks/requirements.txt` (honor `--auto-yes`); fix `install-existing-project.md` to name the exact markers.
**ACs.** A canonical-block merge passes BOTH preflight and health-check; install.sh appends idempotently (no double-append); no stale mirror warnings on first install; PyYAML install offered.
**UX class:** internal (install flow). **Risk:** low (additive, marker-guarded). **COUPLING:** atomic with WS9 (see FLAG).

### WS7 — Internal problem catalog · v3.30.3
**Deliverable.** `docs/problem-catalog/` — one entry per issue: **problem → root cause → resolution → guardrail/lesson**, reviewed at ticket/session start. Populate with: this batch's issues + the two **self-inflicted mistakes** (see §4). Wire a pointer into the session/ticket-start routine (FR-24 digest / role-discipline) so it's actually read.
**UX class:** internal (docs). **Risk:** low.

### WS8 — Mandatory zero-trust subagent-liveness rule · v3.30.3
**Deliverable.** Extend FR-27 / the `liveness-discipline` skill with a mandatory clause: *never trust or passively wait on a subagent/Codex completion ping; proactively poll its liveness often (git-progress/process, not the 0-byte transcript); on transient rate-limit/stall, re-dispatch or SendMessage-resume (wait ~60s, retry until it starts); verify final git state before trusting it.* Deliver via the FR-24 write-time digest so it's present-by-construction. (Improves the operator's example wording.)
**UX class:** internal (rule/skill). **Risk:** low (no gate; safe-default guidance).

### WS9 — Slash-command naming + capitalization · v3.30.3
**Problem.** `Fusebase Flow:` prefix truncates the command name in the Codex/IDE picker; also mis-capitalized ("Fusebase" → must be "FuseBase").
**Fix.** Reorder descriptions to **command/purpose first, `(FuseBase Flow)` trailing tag**; fix capitalization; apply to Codex prompts, `.claude/commands/*`, the AGENTS.md command-equivalents table, and the `install-codex-prompts.sh` transform. First locate exactly where the pictured `Product Docs/Apps/Client Workflows` descriptions are generated.
**UX class:** internal (IDE picker DX). **Risk:** low. **COUPLING:** the capitalization change touches the SAME `## Fusebase Flow — …overlay` heading markers WS6 asserts on — changing them requires updating the health-check (`:196/:215`) + preflight asserts + templates **atomically**, or it breaks marker-matching → `FLOW_LAYER_DRIFT` for everyone.

---

## 3. Version map + sequencing + dependencies

- **v3.30.3 — "Windows/MSYS adoption + harness + verdict + process"** (deterministic/high-value; the universal + adoption wins):
  WS1 (adoption) · **WS2-core (strict winpid scoping — prerequisite for WS3)** · WS3 (harness reap + bound recovery + real `--check` + Phase-3 batch) · WS4 (verdict rc0-guard + MSYS timeout defaults) · WS6 (marker consistency + install hygiene) · **WS9 (naming — ATOMIC with WS6 markers)** · WS7 (problem catalog) · WS8 (zero-trust FR rule).
- **v3.30.4 — "Windows/MSYS bounded-run robustness"** (harder, host-dependent, higher-risk):
  WS2-hard (Windows Job Object + Cummings-class ac3d/deadline reliability) · WS5 (upgrade engine bounded exit).
- **Dependency edges:** WS2-core → WS3 (harness reuses strict-scoped reap). WS6 markers ⟷ WS9 capitalization (atomic). WS4·(a) → WS2 (true-124-on-kill is the real fix; WS4 is the defensive guard).
- **Implementation grouping (one ai-developer task per commit; group by file-locality):** G1 = WS1(a) secret-scan + WS9 naming (both touch scanner/prompts/descriptions). G2 = WS2-core + WS3 harness (bounded-run + run-tests). G3 = WS4 + WS6 (health-check + preflight + install.sh). G4 = WS1(b/c) protected-path exception + hook (re)install. G5 = WS7 catalog + WS8 FR rule (docs/FLOW_RULES). Then v3.30.4: G6 = WS2-hard + WS5.

## 4. Self-inflicted mistakes to log in the catalog (WS7)
1. **Truncated manifest in a release commit** — `sync-version-strings.sh` bound-hit mid-write + my repeated `mirror-skills.sh --check` calls (a flag that DOESN'T EXIST → they ran a *full mirror*) racing concurrently → duplicated/truncated `audit/skill-mirror-manifest.txt` in `bbaf53a`; corrected post-deploy in `12a543f`. **Guardrail:** never stage a bound-terminated generated file; verify manifest raw==unique==expected + 0 drift before committing; there is no `mirror-skills --check` (use re-run + `git diff --exit-code`) — WS3 adds a real one.
2. **Inaccurate consumer prompt** — my "apply+validate" prompt claimed "the upgrade installs the fixed pre-commit"; false (upgrade doesn't wire `.git/hooks/`). **Guardrail:** verify tool behavior against source before asserting it in operator-facing guidance.

## 5. Validation strategy (host-dependent items)
Bug-B/MSYS items (WS2/WS5) can't be fully reproduced on the publish host (tests pass here). Validate by: strict-scoping/Job-Object correctness by code + the 26 timeout tests + POSIX byte-equivalence + a concurrent-sibling-survives test; then **consumer re-test on a real MINGW64 box** post-release (the operator distributes the apply+validate prompt). Deterministic items (WS1 secret-scan/protected-path, WS6 markers, WS9 naming, WS7/WS8 docs) are fully verifiable here (RED-then-GREEN).

## 6. FLAGS for the Codex doc-review (validate these before implementation)
- **F-a:** Is the WS2-core→WS3 dependency correct, and is shipping WS2-core (strict scoping) in v3.30.3 without the full Job Object safe/sufficient to make WS3's EXIT-trap non-collateral?
- **F-b:** WS4 reclassification tension — confirm the plan does NOT regress the Codex-validated `rc0-no-run⇒BROKEN` guard while fixing Ovation's `rc0-on-kill⇒BROKEN` false negative (the real fix is WS2 true-124-on-kill; WS4 is defensive). Is that framing right?
- **F-c:** WS1(b) protected-path bootstrap exception — is a scoped short-TTL `state/approvals/` artifact the right mechanism, and can it be made single-use so it isn't a reusable FR-07 hole? Any safer alternative (e.g. tool-authored setup commit)?
- **F-d:** WS9⟷WS6 marker atomicity — confirm the capitalization change must update markers + both validators + templates together; any hidden marker consumers.
- **F-e:** Version split (v3.30.3 deterministic vs v3.30.4 hard) — right call, or ship all at once?
- **F-f:** Anything missing, mis-scoped, or over-engineered across the 9 workstreams; any UX surface not given design treatment.
