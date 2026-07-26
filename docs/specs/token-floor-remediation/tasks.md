# Tasks — token-floor-remediation

**Spec:** spec.md · **Decisions:** decisions.md (A1–A10 LOCKED; A2 twice-amended, A3/A5/A8 extended in the 2026-07-26 correction round → T13–T18)
**Rule:** one task = one commit (FR-03); commit message cites `T<n>`. Stop at T19 (gate). Do not proceed to T20 without the gate verdict.
**Protected-path rule:** T1, T2, T4, T5, T8, T9, and T13–T18 stage FR-07 paths. Order per A9: **make the edits → `git add` the paths → mint (`write-bootstrap-approval.sh`, digest binds the staged set) → commit → consume**. T20 is gated by deploy approval.

## Completion — ALL TASKS COMPLETE (T20 publication step withheld)

Branch `fix/msys-v3307-hardening`. One task = one commit (FR-03), each message citing its `T<n>`.

| T# | Status | Commit |
|---|---|---|
| T1 | done | `1198168` |
| T2 | done | `8ce1901` |
| T3 | done | `aeb66cf` |
| T4 | done | `cfac6c0` |
| T5 | done | `de06ec0` (+ instrument fix `0a3ead2`, range-heading phantom row) |
| T6 | done | `9830092` |
| T7 | done | `e43090b` |
| T8 | done | `5a78a52` |
| T9 | done | `13f2486` |
| T10 | done | `9b6c152` |
| T15 | done | `bae92bc` (correction round ran first) |
| T13 | done | `d814539` |
| T14 | done | `9fde710` |
| T16 | done | `4027f1b` |
| T17 | done | `65003ed` |
| T18 | done | `be4c511` |
| T21 | done | `7c5f78a` |
| T22 | done | `2e8d6aa` |
| T23 | done | `3cd06e7` |
| T24 | done | `a2214b3` |
| T19 | done — **PASS 28/28 AC** | no commit; `gate-report.md` (HEAD at gate `a2214b3`) |
| T25 | done | `43c052d` — rule-inventory re-baselined at `a2214b3` per PO ruling D5 |
| T20 | **done except publication** | release bookkeeping `ef7793e`; FR-14 docs commit = this one |

**T25 delta characterization (PO ruling D5).** Exactly 2 rows changed (`85c85` FR-27 in `FLOW_RULES.md`; `170c170` WT.FR-27 in `role-discipline/SKILL.md`), both `c`, **zero `d`**, zero `a`; row count unchanged 170 → 170; ID+source+residency triple sets byte-identical → **zero residency flips, zero rule loss**. Cause: T23 was mandated to reword the FR-27 liveness statement (unbounded "retry until it starts" → bounded delegate-retry envelope). Post-re-baseline the inventory diff is EMPTY.

**T20 step 5 (publication) NOT executed.** No push, no `v4.6.0` tag, no `gh release create`, no remote contact — withheld pending an explicit operator go-ahead. Probe P1 (health check) ran locally and is HEALTHY at 4.6.0; probes P2 (tag workflows) and P3 (consumer `upgrade.sh --dry-run`) and smoke S1–S4 are publication-dependent and remain **outstanding**.

## Task chain

| T# | Slice | Scope | Depends-on | FR-07 approval |
|---|---|---|---|---|
| T1 | S1 (F4) | delegated chat-return budget | — | yes (`hooks/tests/**` new contract-presence test, `hooks/tests/run-tests.sh`) |
| T2 | S2 (F5) | supersede vs write-primitive | T1 | yes (`FLOW_RULES.md`, `hooks/local/token-waste-audit.py`, `hooks/tests/**`) |
| T3 | S3 (F2) | anti-reread + per-surface auto-load matrix | T2 | no (boot-contract assertion lands in `hooks/tests/test-boot-size.sh` at T8 — T3 does not edit `hooks/local/preflight.sh`) |
| T4 | S4 (F3) | Amendment-log extraction + stub | T3 | yes (`FLOW_RULES.md`, `hooks/local/upgrade.sh`, `hooks/local/preflight.sh`, `hooks/handlers/session_start.py`, `policies/protected-paths.yml`, `.github/workflows/fusebase-flow-verify.yml`, `hooks/tests/**`) |
| T5 | S5-pre (AC2) | rule-inventory instrument + baseline | T4 | yes (`hooks/local/rule-inventory.sh`, `hooks/tests/**`) |
| T6 | S5a (F1) | `communication` boot-core compression | T5 | no (canonical skills + mirrors + `audit/` manifests only — none are FR-07 categories) |
| T7 | S5b (F1) | `role-discipline` boot-core compression | T6 | no (same as T6) |
| T8 | S5c (F1) | `FLOW_RULES.md` operative compression + boot-size test | T7 | yes (`FLOW_RULES.md`, `hooks/tests/**`) |
| T9 | S6 (F6) | audit-tool labeled auto-classification + fixtures | T2 | yes (`hooks/local/token-waste-audit.py`, `hooks/tests/**`) |
| T10 | S7 | zero-trust delegated-session liveness recipe | T1 | no |
| T13 | correction (B1+B2) | resident prohibitions restored + residency test | T15 | yes (`hooks/tests/**`) |
| T14 | correction (M7) | rule-inventory residency schema + coverage + red controls | T13 | yes (`hooks/local/rule-inventory.sh`, `hooks/tests/**`) |
| T15 | correction (B3+B4) | truthful auto-load matrix — **runs first in the correction round** | T1–T10 complete | yes (`hooks/tests/**`) |
| T16 | correction (B5+B6) | classifier verb-anchored probe match + path canonicalization | T14 | yes (`hooks/local/token-waste-audit.py`, `hooks/tests/**`) |
| T17 | correction (M8,M11,M12) | non-vacuous test arms + bounded-retry contract | T16 | yes (`hooks/tests/**`) |
| T18 | correction (M9,M10,M13–M15) | documentation truth-up + budget-literal consistency assertion | T17 | yes (`hooks/tests/**`) |
| T19 | gate | verification gate | T1–T18 | no |
| T20 | S8 | release bookkeeping + deploy + FR-14 docs commit | T19 verdict PASS | deploy approval |

**Correction-round order (Codex 5.6-Sol High review 2026-07-26, all 15 findings accepted):** T15 → T13 → T14 → T16 → T17 → T18. T15 first — it is the only finding that can cause a mandatory skill to silently not load.

If a task's staged set turns out to include an FR-07 path not listed here, mint for the actual staged set — the digest binds what is staged, not what was planned.

**Every task ends with:** `bash hooks/local/mirror-skills.sh` (if `flow-skills/` changed) → `bash hooks/local/preflight.sh` → targeted tests → `git status --short` clean → one commit citing `T<n>`.

## Per-task detail

### T1. Delegated chat-return budget (S1 / F4 / AC12–AC13)

| Field | Value |
|---|---|
| Edit | `flow-skills/task-delegation/SKILL.md` (successor contract, `:87,98-100,150-161`) |
| Edit | `templates/handoff-implement.md:105` push block · `templates/handoff-deploy.md:27` push block |
| Edit | `templates/handoff.md:6` successor pointer (clarify only) |
| Add | contract-presence test in `hooks/tests/`; register in `hooks/tests/run-tests.sh` |
| Mirror | `.claude/skills/task-delegation/`, `.agents/skills/task-delegation/`, `audit/skill-mirror-manifest.txt` |
| Stamp | `audit/hook-layer-manifest.json` (new shell test) |
| Text | "≤80 lines **and** ≤6,000 characters. Longer → write a sanctioned durable artifact and return its path; commit only when the owning workflow requires it." |
| Must NOT | apply the cap at `handoff-implement.md:179-183` or `handoff-deploy.md:159-170` (AC13 exemption — state the exemption explicitly) |

### T2. Supersede vs write-primitive (S2 / F5 / AC14)

| Field | Value |
|---|---|
| Approval | stage `FLOW_RULES.md` + `hooks/local/token-waste-audit.py` + `hooks/tests/**`, then mint (digest binds the staged set), commit, consume (A9) |
| Edit | `FLOW_RULES.md:27` (FR-18 row) — add the primitive clause |
| Edit | `flow-skills/role-discipline/SKILL.md:266,278-327` (§ Supersede Convention + digest FR-18 row) |
| Edit | `flow-skills/handoff/SKILL.md:59-71,92` — "write fresh" → primitive guidance |
| Edit | `flow-skills/token-economy/SKILL.md:34,83` — **TE-06 currently asserts FR-18 rewrites are mandatory; that is the contradiction** |
| Edit | `templates/handoff.md:3` · `.claude/commands/handoff.md:11` · overlay twin `hooks/local/fusebase-flow-overlays/commands/handoff.md` |
| Edit | `hooks/local/token-waste-audit.py:38-49` FP header wording · `.claude/commands/token-waste-audit.md:11` + overlay twin |
| Add | contract regression test; register in `run-tests.sh`; stamp hook manifest |
| Text | "Supersede replaces stale *semantics*, not the file: use a targeted `Edit` when most sections are unchanged; a full `Write` is for structure/mode/ticket changes or when most sections changed." |

### T3. Anti-reread + per-surface auto-load matrix (S3 / F2 / AC10–AC11)

| Field | Value |
|---|---|
| Edit | `flow-skills/communication/SKILL.md` + `flow-skills/role-discipline/SKILL.md` — A5 text, **placed after the closing `---` of the YAML frontmatter** (`preflight.sh:47-51` requires `---` at byte 1) |
| Edit | surface truth-up: `AGENTS.md:150` (over-claims), `CLAUDE.md:69-76`, `GEMINI.md:41`, `.github/copilot-instructions.md:68-69`, `.cursor/rules/fusebase-flow-always.mdc:9,47`, `.codex/config.toml.example:28-31` |
| Edit | overlay twins `hooks/local/fusebase-flow-overlays/agents-md-overlay.md` + `claude-md-overlay.md` — **must stay byte-identical to the inline blocks** |
| Add | assert the boot contract (frontmatter first + anti-reread rule present in both mandatory skills) inside `hooks/tests/test-boot-size.sh` (T8). T3 does not edit `hooks/local/preflight.sh` |
| Mirror | four skill mirrors + skill manifest |
| Must | exclude delegated sub-agent sessions from the exemption (`task-delegation/SKILL.md:98-102`, `handoff-implement.md:105`) |
| Must NOT | tell Gemini/Copilot they auto-load — they do not (AC11) |

### T4. Amendment-log extraction (S4 / F3 / AC6–AC9)

| Field | Value |
|---|---|
| Approval | stage `FLOW_RULES.md`, `hooks/local/upgrade.sh`, `hooks/local/preflight.sh`, `hooks/handlers/session_start.py`, `policies/protected-paths.yml`, `.github/workflows/fusebase-flow-verify.yml`, `hooks/tests/**`, then mint (digest binds the staged set), commit, consume (A9) |
| Move | `FLOW_RULES.md:135-611` → new root `FLOW_RULES_HISTORY.md`, **byte-preserved** (contract since amended to *content-equivalent except a normalized final newline* — AC6 amended, MINOR 14; the gate test lands at T18) |
| Keep | stub in `FLOW_RULES.md`: `## Amendment log` + ≤2-line pointer (A4 — preserves ~9 consumers and the `sync-version-strings.sh:174-181` anchor) |
| Edit | `.github/workflows/fusebase-flow-verify.yml:88` ALLOWED array · `PUBLISHING.md:73-92` |
| Edit | `hooks/local/upgrade.sh:235` `CONTENT_FILES` (else consumers never receive the file) |
| Edit | `hooks/local/preflight.sh:25-28` · `hooks/handlers/session_start.py:27-36` (history is **not** a required boot file — do not add it to `REQUIRED_TOP_FILES_BASE`; only ensure nothing breaks) |
| Edit | `policies/protected-paths.yml:84-91` · `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json:243-249` |
| Edit | `hooks/tests/test-sync-allowlist.sh:60-82` — classify as dated history; prove it is never version-synced (it contains live-looking FR/version strings) |
| Edit | install docs: `README.md:473,749,760-770` · `docs/install-existing-project.md:54,129,172,329,385` · `docs/install-fusebase-cli-project.md:109,126,144,235,257` |
| Verify | `bash hooks/tests/run-tests.sh` green; `sync-version-strings.sh` sweep still stops at the stub |
| Stamp | hook manifest |

### T5. Rule-inventory instrument (S5-pre / AC2)

| Field | Value |
|---|---|
| Approval | yes (`hooks/**`) — stage, then mint (digest binds the staged set), commit, consume (A9) |
| Add | `hooks/local/rule-inventory.sh` — extracts a normalized inventory: (a) every `FR-\d+` id + its rule-name + its rule-statement cell from the `FLOW_RULES.md` FR table; (b) every don't-list row id (`PO.n`/`IM.n`/`AR.n`/`DP.n`) + its rule text from each `flow-skills/role-discipline/references/<role>.md`; (c) the 12 Mode-B principle ids (`B1..B12`) from `flow-skills/communication/` |
| Output | one normalized line per rule: `<id>\t<normalized-text>`; normalization strips markdown emphasis, collapses whitespace, drops the Enforcement column entirely so a reword of enforcement never registers as rule loss |
| Add | `hooks/tests/test-rule-inventory.sh` — RED/GREEN: deleting a rule row makes the pre/post diff non-empty; rewording the Enforcement column keeps it empty |
| Register | `hooks/tests/run-tests.sh`; stamp `audit/hook-layer-manifest.json` |
| Baseline | run it on HEAD before T6 and commit the baseline to `docs/specs/token-floor-remediation/rule-inventory-baseline.txt` |
| Depends-on | T4 |

### T6. `communication` boot-core compression (S5a / F1 / AC1–AC5)

| Field | Value |
|---|---|
| Target | `flow-skills/communication/SKILL.md` 19,936 → **≤6,000 bytes** (`wc -c`; ceiling since raised to 7,000 by A2 2nd amendment — T13 restores the normative clauses and updates the test) |
| Keep resident | Mode A/B definitions · file classification lists · when-to-use-a-visual triggers · FR-19 chat-text shape table · the 12 Mode-B principle names as one-liners · the A5 anti-reread line from T3 (must remain directly below the YAML frontmatter — `preflight.sh:47-51` anchors `---` at byte 1) |
| Move to `references/mode-b-detail.md` | B1–B12 worked ❌/✅ examples (`:207-288`) · anti-pattern catalog · common pitfalls · failure cases · escalation |
| Move to existing `references/patterns.md` | character/width discipline table |
| Must NOT | drop any principle **name** or the "visuals never in Mode-B files" prohibition (A3) |
| Mirror | two mirrors + skill manifest (preflight mirrors `references/*` too — `preflight.sh:104-106`) |

### T7. `role-discipline` boot-core compression (S5b / F1 / AC1–AC5)

| Field | Value |
|---|---|
| Target | `flow-skills/role-discipline/SKILL.md` 31,052 → **≤10,600 bytes** (`wc -c`; ceiling amended at T7 — see A2 § Amended. Measured irreducible floor with every A3 element resident = 10,595. Ceiling since raised to 13,500 by A2 2nd amendment — T13 restores the resident prohibitions and updates the test) |
| Keep resident (non-negotiable) | the **entire** § Write-time discipline digest (`:258-275` — FR-24's whole thesis) · per-role scoped-loading table · required-inputs table · a ≤2-line prohibition stub for each of the 5 shared protocols (A3) · the A5 anti-reread line from T3 (must remain directly below the YAML frontmatter — `preflight.sh:47-51` anchors `---` at byte 1) |
| Move to `references/shared-protocols.md` | Operator Relay Protocol body · Chat-Text Questions body · Operator Gate Protocol body · Forward Momentum catalog · Supersede Convention body · Operator OD-1..7 section · failure cases · escalation |
| Note | T2 already rewrote § Supersede Convention — move the corrected body, do not restore the pre-T2 text |
| Must keep as anchors | `§ Operator Relay Protocol`, `§ Supersede Convention`, `§ Forward Momentum Protocol`, `§ Chat-Text Questions Protocol`, `§ Operator Gate Protocol`, `§ Write-time discipline digest` — inbound refs at `agents/product-owner/AGENT.md:160`, `templates/gate-report.md:193`, `workflows/architect-escalation.md:130`, `workflows/greenlight-{implement,deploy}.md`, `references/product-owner.md:18-20`, `references/ai-developer.md:5,22` |
| Must NOT | collapse role don't-lists into generic FR pointers (`:358-361` forbids it) |
| Mirror | two mirrors + skill manifest |

### T8. `FLOW_RULES.md` operative compression + boot-size test (S5c / F1 / AC1–AC5)

| Field | Value |
|---|---|
| Approval | stage `FLOW_RULES.md` + `hooks/tests/**`, then mint (digest binds the staged set), commit, consume (A9) |
| Target | operative section 19,962 → **≤11,000 bytes** (`wc -c`) |
| Method | move the long **Enforcement** column detail to a lazy maintainer-facing file; compress the `FR-XX implication` restatements (`:61-81`) to a pointer table — they duplicate the FR rows and the FR-24 digest |
| Must NOT | remove or reword any FR **rule statement** (AC2) |
| Add | `hooks/tests/test-boot-size.sh` — asserts AC1's per-artifact ceilings **and** the byte total (not the total alone); ceilings are now A2 2nd-amendment values (communication ≤7,000 · role-discipline ≤13,500 · FLOW_RULES ≤11,000 · largest role reference ≤9,200 · total ≤40,700 — since raised by the A2 3rd amendment at T22) — T13 updates the test literals · asserts the boot contract (frontmatter first + anti-reread rule present in both mandatory skills, per T3) · fails when any required lazy `references/*.md` is missing (`[NEW]`: `preflight.sh:104-106` mirrors only what exists, so deletion looks clean today) |
| Edit | `docs/rail-mapping.md` — it maps FR→enforcement rails that this task relocates, and it is in the version-sync `SYNC_FILES` set — update it in this task |
| Register | `hooks/tests/run-tests.sh`; stamp hook manifest |
| Verify | `diff <(bash hooks/local/rule-inventory.sh) docs/specs/token-floor-remediation/rule-inventory-baseline.txt` → empty (AC2; T5 instrument) |

### T9. Audit-tool labeled auto-classification (S6 / F6 / AC15–AC19)

| Field | Value |
|---|---|
| Approval | stage `hooks/local/token-waste-audit.py` + `hooks/tests/**`, then mint (digest binds the staged set), commit, consume (A9) |
| Edit | `hooks/local/token-waste-audit.py` — preserve full read key + event order into result association (`:153,201-203` vs `:158,200,230-233`) before classifying |
| Rule 1 | `auto-classified: growing-source-tail` only when same full read key **and** monotonic growth or differing digests **and** no contradictory event |
| Rule 2 | exactly-3 runs → `possible-FR-10-triple` **label**; auto-dismiss only when the command is probe-shaped per the A8 predicate. Account for `bash_runs` counting since-last-write (`:208-214`) |
| Output (internal posture) | each auto-classification prints the rule that fired + the evidence (I2/I4); dismissals counted in a **separate** section from live findings (I3); report names three terminal states in words — candidates found / all auto-classified / no transcripts-or-parse-failure (QP-21) |
| Edit | `flow-skills/token-economy/SKILL.md:72-84` · `.claude/commands/token-waste-audit.md` + overlay twin |
| Add | synthetic parser fixtures covering candidate **and** dismissal cases; fixtures must exercise each branch of both A8 predicates — contradictory event and probe-shaped command — matching and non-matching; new shell test; register in `run-tests.sh`; stamp hook manifest |
| Note | `hooks/local/*.py` is not manifest-collected (`hooks/local/lib/hook_manifest.py:88-99`) — the parser needs no restamp; its shell test does. Keep the file < 800 lines (FR-25; currently 479) |

### T10. Zero-trust delegated-session liveness recipe (S7 / A10)

| Field | Value |
|---|---|
| Edit | `flow-skills/liveness-discipline/SKILL.md` — add the transient-provider-limit recipe: a delegate that dies on a rate-limit is **re-dispatched** ("try again"); if it reports the limit again, wait ~60s and retry until it starts (bounded at T17: max 3 attempts / 5 min); never treat the death as a task verdict |
| Edit | `flow-skills/task-delegation/SKILL.md` — delegation-side twin: poll progress (git/process/file growth) on a fixed cadence; a missing completion ping is not evidence of completion **or** of death |
| Mirror | four mirrors + skill manifest |
| Must NOT | add a blocking gate or a "watchdog applied" attestation hook (FR-27 forbids both — a hang is undetectable by construction) |

### T13. Restore resident prohibitions (correction / BLOCKER 1+2 / AC24, AC1 amended)

| Field | Value |
|---|---|
| Approval | stage `hooks/tests/**`, then mint (digest binds the staged set), commit, consume (A9) |
| Edit | `flow-skills/role-discipline/SKILL.md` — restore resident the normative clauses now parked in `references/shared-protocols.md:3,16-24,49-76,82-98,167-173,237-243,253-289`: MUST/no-exceptions clauses, wait/refusal requirements, role-authority prohibitions, uncovered-approval prohibition, operator OD-1..7 don't-list, STOP responses, exact refusal phrasing. Only rationale, worked examples, recovery narrative stay lazy (A3) |
| Edit | `flow-skills/communication/SKILL.md` — restore the B3–B8/B11–B12 normative clauses (name-only since T6) from `references/mode-b-detail.md:30,34,38,42,60,79,83,152`; restore the over-decoration + 80-character width/alignment obligation from `references/patterns.md:22` |
| Edit | `hooks/tests/test-boot-size.sh` — raise ceilings to A2 2nd-amendment values: communication ≤7,000 · role-discipline ≤13,500 · total ≤40,700 (since raised again by the A2 3rd amendment at T22) |
| Add | `hooks/tests/test-prohibition-residency.sh` — FAILS when a `flow-skills/*/references/*.md` file contains a normative marker (`MUST`, `never`, `do not`, `don't`, `forbidden`, `STOP`, `refuse`, exact-refusal-phrasing block) with no resident counterpart; prove the red arm by planting one. Register in `run-tests.sh`; stamp hook manifest |
| Must NOT | trade a prohibition for bytes (A2 2nd amendment: residency outranks the budget) · re-baseline `rule-inventory-baseline.txt` — only T14's schema change re-baselines, never a diff-pass convenience |
| Mirror | skill mirrors + `audit/skill-mirror-manifest.txt` |
| Depends-on | T15 |

### T14. Inventory residency + coverage (correction / MAJOR 7 / AC2 amended)

| Field | Value |
|---|---|
| Approval | stage `hooks/local/rule-inventory.sh` + `hooks/tests/**`, then mint, commit, consume (A9) |
| Edit | `hooks/local/rule-inventory.sh` — emit `ID + normalized text + canonical source path + resident\|lazy` per row; extend coverage to the FR-24 digest rows, the 5 protocol stubs, role authority, attestation/footer, question shapes, file classifications, refusal rules, failure/escalation obligations, and the Mode-A/Mode-B normative clauses |
| Add | red controls in `hooks/tests/test-rule-inventory.sh`: (a) a rule moved resident→lazy → must FAIL; (b) a don't-list row moved between roles → must FAIL |
| Baseline | re-baseline `docs/specs/token-floor-remediation/rule-inventory-baseline.txt` in the **same commit** as the schema change; record the old baseline's row count (94) in the commit message |
| Depends-on | T13 |

### T15. Truthful auto-load matrix (correction / BLOCKER 3+4 / AC11 amended) — runs first

| Field | Value |
|---|---|
| Approval | stage `hooks/tests/**`, then mint, commit, consume (A9) |
| Edit | `AGENTS.md:151-160` + twin `hooks/local/fusebase-flow-overlays/agents-md-overlay.md` · `CLAUDE.md:69-76` + twin `claude-md-overlay.md` — Claude Code and Codex rows must no longer assert the body is already in context. Correct statement: *descriptions/metadata are injected; bodies are not — check whether the exact body is present, read once if not* (verified first-hand; `session_start.py:35-38,75-102` never injects a body; `.codex/config.toml.example:28-36` is conditional on an optional `skills_dir`) |
| Add | assertion in `hooks/tests/test-boot-size.sh` (or the T13 residency test): no surface row may claim eager **body** loading unless a fresh-session test proves it |
| Must | keep the in-file blockquote rule in both mandatory skills unchanged (conditional on body presence — already correct) · keep Gemini/Copilot/Cursor/delegated-sub-agent rows as-is · condition every "do not re-Read" instruction on a body-presence check, never on a surface name |
| Must NOT | weaken the anti-reread rule itself — F2's premise narrows (the measured double-pay was largely bodies never auto-injected), it does not vanish; record the narrowing for the T20 release note (A5 amended) |
| Verify | preflight overlay/inline parity green; boot-size test green |
| Depends-on | T1–T10 complete (correction-round entry point) |

### T16. Classifier false negatives (correction / BLOCKER 5+6 / AC25–AC26)

| Field | Value |
|---|---|
| Approval | stage `hooks/local/token-waste-audit.py` + `hooks/tests/**`, then mint, commit, consume (A9) |
| Edit | `token-waste-audit.py:60-71,373-381` — probe-shape match on the parsed command **verb** / known exact forms (never `\bstatus\b`-anywhere); `--probe-command` requires normalized equality (or an explicitly validated wrapper), never substring containment |
| Edit | `token-waste-audit.py:267-274,328-345` — canonicalize both sides (absolute resolution, separator normalization, Windows case-folding) before keying and before contradiction checks |
| Add | both Codex PoCs (`echo status` ×3 / `deploy --message status` ×3; documented probe + extra mutating commands) plus path-alias fixtures (`C:/Repo/a.txt` vs `c:\repo\a.txt`) as **retained-live** cases; register + stamp |
| Must | keep the file < 800 lines (FR-25; currently 696); if it would exceed, extract along a responsibility seam — in-scope, not scope creep |
| Depends-on | T14 |

### T17. Non-vacuous test arms + bounded-retry contract (correction / MAJOR 8,11,12 / AC27–AC28)

| Field | Value |
|---|---|
| Approval | stage `hooks/tests/**`, then mint, commit, consume (A9) |
| Edit | `hooks/tests/test-token-waste-classify.sh:66-83` — assert the **exact live row and evidence string** for fixtures 02–05, 07, 08; add one mutation control per fixture proving it FAILS under the corresponding unsafe classifier |
| Edit | `hooks/tests/test-sync-allowlist.sh:86-96` — replace the vacuous omission self-test (it filters `FLOW_RULES.md` out, then searches the filtered stream): run the **production** missing-set calculation against a mutated reachable set and assert `FLOW_RULES.md` is reported missing |
| Edit | `flow-skills/task-delegation/SKILL.md:97` + `flow-skills/liveness-discipline/SKILL.md:93-106` + `flow-skills/token-economy/SKILL.md:33,36` — define **one bounded exception** to don't-poll-while-running / record-then-read / two-strike: max attempts + max wall-time, labeled backoff, the exact transition to successor-or-blocked when exhausted, and when delegate-progress polling overrides record-then-read |
| Mirror | skill mirrors + skill manifest |
| Depends-on | T16 |

### T18. Documentation truth-up (correction / MAJOR 9,10 + MINOR 13–15 / AC1, AC6 amended)

| Field | Value |
|---|---|
| Approval | stage `hooks/tests/**` (consistency assertion), then mint, commit, consume (A9) |
| Edit | budget literals (MAJOR 9): replace every remaining live pre-2nd-amendment total in repo docs/tests with 40,700 per A2 2nd amendment (the four planning artifacts were corrected in the correction-round planning pass) |
| Add | cross-artifact literal-budget consistency assertion — a test that greps the budget literal across all carriers and fails on divergence, so the next amendment cannot half-land |
| Edit | `.github/copilot-instructions.md:6,32` + `.github/instructions/fusebase-flow.instructions.md:12` — enforcement map lives in `docs/rail-mapping.md` (moved at T8), not `FLOW_RULES.md` (MAJOR 10) |
| Edit | `agents/product-owner/AGENT.md:160`, `workflows/greenlight-implement.md:76`, `workflows/greenlight-deploy.md:100` — full Operator Relay body references → `references/shared-protocols.md`; keep the resident-anchor citation separate (MINOR 13) |
| Edit | gate contract for AC6: history file is content-equivalent except a normalized final newline; make the gate test that exact contract (MINOR 14) |
| Edit | `README.md:660`, `AGENTS.md:27`, `workflows/session-initiation.md:11` — "25 baseline rules" → 27; amendment-log description → compatibility stub pointing at external history (MINOR 15) |
| Depends-on | T17 |

### T19. Verification gate

Run `verification-gate.md` in full. Produce the gate report from `templates/gate-report.md`. **Halt.** Do not deploy.

### T20. Release + deploy + single docs commit (FR-14)

| Field | Value |
|---|---|
| Pre | gate verdict PASS; deploy approval artifact on file |
| Edit | `VERSION` → 4.6.0 · `CHANGELOG.md` · `docs/release-notes/v4.6.0.md` · `.claude-plugin/plugin.json` + `marketplace.json` · `.codex-plugin/plugin.json` · README version badge |
| Fix | verify only — `README.md:659-660` "25 baseline rules" → 27 landed at T18 (MINOR 15 moved it there; the version synchronizer does not match that wording) |
| Note | release note must state the honest figure — 42,200-byte budget, a ~47% cut from the measured 78,148-byte role-aware floor (A2 3rd amendment) — and the narrowed F2 premise: descriptions are injected, bodies are not; the anti-reread rule still pays on genuine within-session re-reads (A5 amended, T15) |
| Run | `bash hooks/local/sync-version-strings.sh` |
| Docs commit | spec DRAFT→DONE, tasks marked, backlog index — **one commit** (FR-14) |
| Docs refresh | `docs/specs/repo-context.md` (its own freshness gate says "stale after major repo restructuring"; a new root file + a restructured `FLOW_RULES.md` qualifies) · supersede `docs/tmp/handoff.md` (currently 2026-06-10 / v3.17.0) |
| Release | annotated `v4.6.0` tag + `git push origin HEAD:main --follow-tags`; the tag push triggers the gated release workflow (never `gh release create` manually) |

### T22. Restore `### Write primitive` resident (AC14 gate FAIL)

| Field | Value |
|---|---|
| Cause | T7 moved `### Write primitive` to `references/shared-protocols.md:181`; T13 restored the clause into the FR-24 digest row (`:83`) but not the named section. `test-supersede-primitive.sh` asserts the named subsection exists in the canonical file — 20/21, exit 1 |
| Edit | `flow-skills/role-discipline/SKILL.md:93-97` § Supersede Convention — restore a `### Write primitive` subsection carrying the Edit-vs-Write rule (T2's text; do not restore pre-T2 wording) |
| Ceiling | ≤14,500 bytes (A2 3rd amendment) |
| Verify | `FF_ONLY=supersede-primitive` 21/21; mirrors 0 drift; inventory diff EMPTY |

### T23. Bound every "retry until it starts" (AC28 gate FAIL)

| Field | Value |
|---|---|
| Cause | The 3-attempt / 5-minute envelope is stated correctly, but unbounded `retry until it starts` survives in 5 live canonical locations — including inside two of the three carriers |
| Edit | `flow-skills/task-delegation/SKILL.md:198,219` · `flow-skills/liveness-discipline/SKILL.md:132` · `flow-skills/role-discipline/SKILL.md:87` · `FLOW_RULES.md:34` (FR-27 row) |
| Rule | Every occurrence carries the envelope or a pointer to it. No unqualified "until it starts" may remain anywhere |
| Approval | stage `FLOW_RULES.md` → mint after staging (A9) |
| Ceilings | role-discipline ≤14,500 · `FLOW_RULES.md` ≤11,500 (A2 3rd amendment) |
| Verify | grep proves zero unqualified occurrences; `FF_ONLY=liveness,boot-size,budget-literals` green |

### T24. Re-bound `cli-flow-recovery` (AC22 gate FAIL)

| Field | Value |
|---|---|
| Cause | Bounded-run timeout rc 124 at 240s, reproduced 2/2 on a quiet host (241s). Took 199s at the T11 gate — +21% drift from the tests/skills/fixtures this ticket added. The test does not fail; it exceeds a deadline that no longer fits the grown repo |
| Edit | raise that phase's bound in `hooks/tests/test-cli-flow-recovery.sh` (or its bounded-run invocation) with headroom, not to the measured edge |
| Must | prove it PASSES at the new bound — a timeout raise that still times out is not a fix. Record the actual runtime |
| Must NOT | mask a genuine hang: confirm the phase completes and asserts, rather than merely running longer |
| Verify | `FF_ONLY=cli-flow-recovery` green with runtime recorded; full suite exit 0 |

## Task chain audit

| Check | Status |
|---|---|
| Every AC maps to ≥1 task | AC1→T6–T8,T13,T18 · AC2→T5–T8,T14 · AC3/AC4→T6–T8 · AC5→T5/T8 · AC6→T4,T18 · AC7–AC9→T4 · AC10→T3 · AC11→T3,T15 · AC12–AC13→T1 · AC14→T2 · AC15–AC19→T9 · AC20–AC23→every task · AC24→T13 · AC25/AC26→T16 · AC27/AC28→T17 |
| Every task cites target files | yes |
| Over-ceiling files targeted (FR-25) | none; `token-waste-audit.py` 696/800 after T9 — T16 must stay < 800 or extract along a responsibility seam |
| Dependency order acyclic | T1→T2→{T3,T9} · T3→T4→T5→T6→T7→T8 · T1→T10 · correction round: T15→T13→T14→T16→T17→T18 · all→T19→T20 |
