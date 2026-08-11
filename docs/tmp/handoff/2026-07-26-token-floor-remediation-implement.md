# Implement handoff — token-floor-remediation (T1–T10)

**Role:** AI Developer · **Ticket:** `token-floor-remediation` · **Lane:** Full (FR-21)
**Branch:** `fix/msys-v3307-hardening` · **Base HEAD at handoff:** `18f2ffa` · **Repo:** `c:\Users\Pavel\projects\fusebase-flow-publish\fusebase-flow-FuseBase CLI edition`

## Attestation (first response)

> "Operating as AI Developer under Fusebase Flow v4.5.0. I will follow FR-01 through FR-27. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for AI Developer."

## Canonical artifacts — read these, do not re-derive

| Artifact | Path |
|---|---|
| Spec + acceptance criteria AC1–AC23 | `docs/specs/token-floor-remediation/spec.md` |
| Locked decisions A1–A10 | `docs/specs/token-floor-remediation/decisions.md` |
| **Task chain T1–T12 with per-task file lists** | `docs/specs/token-floor-remediation/tasks.md` |
| Verification gate (T11) | `docs/specs/token-floor-remediation/verification-gate.md` |

`tasks.md` is authoritative for scope. Do not invent tasks, do not reorder, do not merge tasks.

## Rails

| Rail | Requirement |
|---|---|
| FR-03 | One task = one commit. Commit message cites `T<n>`. Never bundle two tasks. |
| FR-07 | T1, T2, T4, T5, T8, T9 stage protected paths. Order (A9): **edits → `git add` → mint `bash hooks/local/write-bootstrap-approval.sh` (digest binds the staged set) → commit → consume**. The 15-min TTL is why minting is the last step before committing, never the first. The approval artifact is gitignored — this stays one commit per task. |
| FR-06 | Never `--no-verify`, `git add -A`, `git add .`, `rm -rf`, `git reset --hard`, force push. |
| FR-13 | `bash hooks/local/preflight.sh` clean before every commit. |
| FR-05 | **STOP at T11.** Produce the gate report and halt. Do not run T12. Do not deploy. |
| FR-25 | Module-size ceiling 800. `hooks/local/token-waste-audit.py` is 479 — keep it under 800. |
| Mirrors | Any `flow-skills/` edit → `bash hooks/local/mirror-skills.sh` in the same commit; `audit/skill-mirror-manifest.txt` drift must be zero. Any `.claude/commands/<n>.md` edit → byte-identical `hooks/local/fusebase-flow-overlays/commands/<n>.md` twin. |
| Manifest | New/changed shell tests → `bash hooks/local/stamp-hook-manifest.sh`. `hooks/local/*.py` is NOT manifest-collected (`hooks/local/lib/hook_manifest.py:88-99`). |

## Write-time discipline digest (FR-24 — inlined; sub-agents do not inherit it)

| Rule | Apply |
|---|---|
| FR-23 | Tier-classify before creating any AI-consumed doc; pointers over restatement; don't create a doc because a template implies one |
| FR-09 | AI-consumed artifacts are Mode B: dense, tabular, front-loaded; no narrative padding or human-onboarding preamble |
| FR-18 | Revising an artifact → REPLACE stale content in place; git history is the audit trail. **Use a targeted `Edit` when most sections are unchanged; a full `Write` is for structure changes** (this is the very rule T2 ships — practice it) |
| FR-22 | Comments: only (1) a tripwire for a non-obvious constraint an editor could break, (2) a ≤1-line retrieval pointer to the external WHY-home. Remove WHAT-restating / changelog / rationale-recorded-elsewhere comments. Never match surrounding density upward. After each code diff emit `comment-policy review: applied (FR-22)` (or `… N/A (FR-22; no code diff)`) |
| FR-25 | A gated file stays ≤800 lines; extraction along a responsibility seam is in-scope, never scope creep; never bypass with `--no-verify` |
| FR-26 | Scoped reads; no re-reads of unchanged in-context files; targeted edits over whole-file rewrites; two-strike retry rule. Quality outranks tokens — never skip a needed first read or thin verification |
| FR-27 | Never launch long/silent work bare — bound it with a timeout/watchdog, complete it in-turn, or return `BLOCKED-AT-<gate>`. On Windows/MSYS the full test suite is slow: use `FF_ONLY=<tag> bash hooks/tests/run-tests.sh` while developing |

## Validation per task

```bash
bash hooks/local/mirror-skills.sh          # if flow-skills/ changed
bash hooks/local/preflight.sh              # must be 0 errors
FF_ONLY=<tag> bash hooks/tests/run-tests.sh   # targeted while developing
bash hooks/local/check-module-size.sh --all
git status --short                         # clean after the commit
```

## Known tripwires (verified — do not rediscover)

- `## Amendment log` is the sweep anchor in `hooks/local/sync-version-strings.sh:174-181`. T4 keeps the heading as a stub precisely so this keeps working.
- `hooks/local/preflight.sh:47-51` requires `---` at byte 1 of every SKILL.md. The T3 anti-reread line goes **below** the frontmatter.
- New top-level tracked files fail the CI public-surface allowlist (`.github/workflows/fusebase-flow-verify.yml:88`) — T4 must add `FLOW_RULES_HISTORY.md` there **and** in `PUBLISHING.md` **and** in `hooks/local/upgrade.sh:235` `CONTENT_FILES`.
- `preflight.sh:104-106` mirrors whatever `references/*` exist — a **missing** required reference is not detected. That is why T8 adds the check.
- `flow-skills/token-economy/SKILL.md:34` (TE-06) currently asserts FR-18 rewrites are mandatory. That is the contradiction T2 fixes.
- Inline `AGENTS.md` / `CLAUDE.md` overlay blocks must stay byte-identical to `hooks/local/fusebase-flow-overlays/*` templates — edit the canonical overlay, then re-splice.

## Scope for THIS dispatch

**CORRECTION ROUND.** T1–T10 landed and the T11 gate passed 537/537 with 23/23 ACs evidenced — but an independent Codex 5.6-Sol High adversarial review then found **6 BLOCKERs**. All 15 findings were accepted by the PO and are now planned as **T13–T18**; the gate is renumbered **T19** and release **T20**.

Execute **T22, T23, T24** (the three T19 gate FAILs), then **re-run T19** and halt. Do not run T20. Do not deploy.

**The T19 gate returned FAIL: 25/28 AC PASS, 3 FAIL.** Task specs are in `tasks.md` §§ T22, T23, T24. Summary: AC14 — `### Write primitive` subsection is missing from canonical `role-discipline/SKILL.md` (T7 moved it, T13 restored only the digest clause); AC28 — unqualified "retry until it starts" survives in 5 live locations including two of the three envelope carriers; AC22 — `cli-flow-recovery` exceeds its 240s bound (241s, reproduced 2/2; was 199s at T11 — growth drift, not a regression).

**A2 has been amended a THIRD time, deliberately with headroom** (the previous two ceilings were set to the measured minimum and each immediately blocked the next correct change): communication ≤7,000 · **role-discipline ≤14,500** · **FLOW_RULES ≤11,500** · largest role reference ≤9,200 · **total ≤42,200**. Update `hooks/tests/test-boot-size.sh` literals as part of T22 or T23 so the suite and `test-budget-literals.sh` stay green.

**Landed:** T15 `bae92bc` · T13 `d814539` · T14 `9fde710` · T16 `4027f1b` · T17 `65003ed` · T18 `be4c511` · T21 `7c5f78a`.

**On T21 — a lesson to carry:** the "known non-defect, don't chase it" note in this handoff was wrong twice over. There were two independent defects, and the standalone run was 10/11, not the 11/11 the note claimed. Verify a dismissal before inheriting it.

**Landed:** T1 `1198168` · T2 `8ce1901` · T3 `aeb66cf` · T4 `cfac6c0` · T5 `de06ec0` (+ `0a3ead2`) · T6 `9830092` · T7 `e43090b` · T8 `5a78a52` · T9 `13f2486` · T10 `9b6c152`.

**A2 has been amended a second time — ceilings are now communication ≤7,000 · role-discipline ≤13,500 · FLOW_RULES ≤11,000 · largest role reference ≤9,200 · total ≤40,700.** The standing ruling is: **correctness outranks the byte budget.** A prohibition parked in a lazy file is not a rule. Never trade a prohibition for bytes — that is the exact failure this round exists to fix. `hooks/tests/test-boot-size.sh` still carries the OLD literals; T13/T18 update them.

**Known non-defect:** `ff-only scoped-skip-count` fails only when `test-ff-only.sh` runs *inside* an `FF_ONLY`-scoped harness (it inherits the outer `FF_ONLY` into its own `FF_LIST` child). Standalone it is 11/11. Pre-existing harness nesting quirk — do not chase it.

**Compression phase is closed and gated.** Live boot floor: communication 5,949 · role-discipline 10,595 · FLOW_RULES 10,994 · largest role reference 9,161 = **36,699 ≤ 36,800**. Headroom is ~6 bytes on `FLOW_RULES.md` and ~5 on role-discipline — `hooks/tests/test-boot-size.sh` will block any growth at commit time. If T9/T10 need to add to a gated file, they cannot; put the content in a `references/` file or the skill being edited (`liveness-discipline` / `task-delegation` are **not** gated).

**Landed already (do not redo):** T1 `1198168` · T2 `8ce1901` · T3 `aeb66cf` · T4 `cfac6c0` · T5 `de06ec0` (+ instrument fix `0a3ead2`) · T6 `9830092`.

**The AC2 safety net is live.** `bash hooks/local/rule-inventory.sh` emits 94 normalized rows (27 FR + 55 don't-list + 12 Mode-B principles) and is fail-closed (a category extracting zero rows exits 1 with no stdout). Baseline: `docs/specs/token-floor-remediation/rule-inventory-baseline.txt`, taken at `cfac6c0`. After every compression commit the diff against that baseline must be **EMPTY**. If it is not, you dropped a rule — restore it. **Never edit the baseline to make a diff pass.**

**Field-verified corrections to `tasks.md`'s approval predictions** (trust the tool's verdict over the plan):
- `hooks/tests/**` is **not** in `fusebase_flow_internals` — `policies/protected-paths.yml:84-99` lists only `FLOW_RULES.md`, `policies/*.yml`, `hooks/{handlers,shared,git}/**`. A new test alone needs no approval.
- The bootstrap approval covers `fusebase_flow_internals` **only**. A `.github/workflows/**` edit needs its own `ci_cd_config`-scoped approval (`approve-local.sh`), as T4 discovered.
- `hooks/local/*` is not manifest-collected; only `hooks/{handlers,shared,git}/**` and `hooks/tests/*` move `audit/hook-layer-manifest.json`.

**Post-T4 baseline:** `FLOW_RULES.md` is now 20,546 bytes / 138 lines (history extracted; stub heading retained). T8's ≤11,000-byte target is measured against that.

## Report back (binding — this is the budget the ticket ships)

**≤80 lines AND ≤6,000 characters.** Include: per task — `T<n>`, commit SHA, files touched, approval artifact id (if FR-07), preflight result, targeted test result, and `comment-policy review:` line. Anything longer goes into the commit messages and the artifacts, not the chat return. No narrative recap.
