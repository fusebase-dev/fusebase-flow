# Implement handoff — v3.30.3 Group 2: WS4 (verdict+timeouts) · WS6 (dual-marker migration + install hygiene) · WS9 (slash-command naming)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.2. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03, FR-05, FR-07, FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated); no runaways; stop at gate; do NOT bump VERSION/push/tag.** Builds on G1 (`0a95f36`): the bounded-run engine now returns a true 124/137 on an MSYS kill (T3 relies on this).

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `docs/specs/windows-msys-hardening/roadmap.md` — the **"Codex doc-review — FOLDED"** block is AUTHORITATIVE (esp. the BLOCKER marker-migration + F-b: do NOT reclassify rc0). WS4/WS6/WS9 sections.
2. `hooks/local/fusebase-flow-health-check.sh` (hook-test classify ~`:400-427`, the `rc0+no-FAIL+no-PASS⇒BROKEN` guard `:417`, signal-only inconclusive `:407`, `FFHC_PREFLIGHT_TIMEOUT`/`FFHC_TESTS_TIMEOUT` defaults `:80-83`, `ffhc_is_msys` via `run-with-timeout.sh:71`, verdict-recommendations `:716-719`, the overlay markers `:196/:215`).
3. `hooks/local/preflight.sh` (overlay content-token checks `:196-202`), `hooks/local/post-fusebase-update.sh` (`:195-233` marker-guarded append), `hooks/local/fusebase-flow-overlays/{agents,claude}-md-overlay.md` (the markers).
4. `hooks/local/fusebase-flow-overlays/commands/*.md` (command descriptions — SINGLE SOURCE), `hooks/local/install-codex-prompts.sh` (transform), the AGENTS.md command-equivalents table.
5. Marker consumers to keep consistent (per Codex): health-check `:196/:215`, preflight, post-fusebase-update `:195/:219`, overlay templates, `test-cli-flow-recovery.sh :196/:198/:614/:645`, `test-health-check-timeout.sh :63`, `docs/install-*.md`, README `:516/:517`.

## Scope — one task = one commit.

- **T3 (WS4) — verdict robustness + MSYS timeout defaults. Do NOT regress fail-closed.**
  - The real Ovation `rc0-on-kill` fix already shipped in G1 (engine returns true 124) → confirm the existing `124⇒PARTIAL_UNVERIFIED` path now handles it. **KEEP the `rc0 + no PASS + no FAIL ⇒ BROKEN` guard (`:417`) unchanged** (HT8/HT9/HT10/HT11 must stay green); the signal/timeout-only inconclusive branch (`:407`) stays as-is. Do NOT blindly reclassify rc0.
  - `ffhc_is_msys`-gate higher defaults: `FFHC_PREFLIGHT_TIMEOUT` 60 / `FFHC_TESTS_TIMEOUT` 120 on MINGW*/MSYS*/CYGWIN; 30/60 on POSIX (env-override still wins). In the PARTIAL_UNVERIFIED recommendation (`:716-719`), print the exact knob **names + current effective values**. Document the MSYS-under-load case in the health-check `SKILL.md` (+ mirrors).
  - Test: MSYS defaults applied on MINGW; POSIX defaults on non-MSYS; a killed hook-test (engine rc124) → PARTIAL_UNVERIFIED; an injected genuine `FAIL:`/rc0-no-run still → BROKEN (fail-closed intact).
- **T4 (WS6) — BACKWARD-COMPATIBLE dual-marker migration + install hygiene.** (Per the BLOCKER: a bare rename breaks every installed base.)
  - **Dual-marker acceptance:** make BOTH `fusebase-flow-health-check.sh` (`:196/:215`) AND `preflight.sh` accept the OLD marker (`## Fusebase Flow — workflow lifecycle overlay` / `## Fusebase Flow — additional rules (overlay)`) **and** the NEW capitalized marker (`## FuseBase Flow — …`). preflight ADDS exact-marker asserts (dual-accept) to match health-check (so preflight ⟷ health-check agree). Keep the baseline-title fallback.
  - **Templates emit NEW:** `{agents,claude}-md-overlay.md` markers → `FuseBase Flow`. **Migrate in place:** `post-fusebase-update.sh` (upgrade path) rewrites an existing OLD marker → NEW in `AGENTS.md`/`CLAUDE.md` (idempotent; only if present).
  - **install.sh appends canonical overlay blocks:** reuse `post-fusebase-update.sh:195-233`'s `grep -qF MARKER` guard + `cat overlay.md >> file`, behind the existing APPEND-ONLY confirm (so a fresh install passes BOTH preflight and health-check).
  - **Install hygiene:** move the mirror step ABOVE preflight in `install.sh` (or `FF_FIRST_INSTALL` guard) so first-install doesn't emit ~86 stale mirror-missing warnings; offer `pip install -r hooks/requirements.txt` (honor `--auto-yes`, fall back to WARN if pip absent).
  - Update the other marker consumers (tests `test-cli-flow-recovery.sh`, `test-health-check-timeout.sh`; docs `install-existing-project.md`, README) to accept/emit consistently (dual-accept in tests; docs name the exact new marker + the append commands).
  - **Tests:** an OLD-marker `AGENTS.md`/`CLAUDE.md` still validates HEALTHY (both preflight + health-check); a NEW-marker one validates; the upgrade path migrates OLD→NEW in place (idempotent, no double); install.sh append is idempotent (no double-append).
- **T5 (WS9) — slash-command display naming + capitalization (descriptions only, NOT the markers).**
  - In `hooks/local/fusebase-flow-overlays/commands/*.md` (single source) reorder each `description:` to **command/purpose first, trailing `(FuseBase Flow)` tag** (not a `Fusebase Flow:` prefix); fix `Fusebase`→`FuseBase`. Propagate via the `install-codex-prompts.sh` transform + re-mirror to `.claude/commands/*` if mirrored; update the AGENTS.md command-equivalents table wording consistently. First `git grep` where the pictured `Product Docs/Apps/Client Workflows` descriptions are generated so the rename hits the right fields. (These descriptions are picker-facing, NOT the WS6 section markers.)
  - Test/assert: a command description reads `<purpose> … (FuseBase Flow)` and no `Fusebase Flow:` prefix remains in the command set; capitalization correct.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet. **Do NOT reclassify rc0** (keep the fail-closed guard). Marker change is dual-accept + migrate (never break the installed base). Preserve verdict ENUM + exit codes (0/2/3/4). Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ rc0-no-run⇒BROKEN guard intact (HT8-11)  ☐ dual-marker accepts OLD+NEW  ☐ verdict enum/exit intact
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n` changed shells + `py_compile` if touched · run-tests PASS incl. new tests + the health-check-timeout HT8-11 (fail-closed) + old-marker-validates + upgrade-migrates (bounded; per-phase 0-FAIL) · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** (now a real read-only mode from G1) · FR-07 clean. Emit the FR-22 marker; produce the gate report; HALT.

## Return
Gate report: per-task SHAs (T3/T4/T5), AC evidence (T3 MSYS-defaults + killed→PARTIAL + genuine-crash→BROKEN; T4 old-marker-validates + upgrade-migrates + install-append-idempotent + hygiene; T5 naming+capitalization), no-regression (HT8-11 fail-closed, verdict enum/exit), gate numbers, FR-07. Do NOT push/tag.
