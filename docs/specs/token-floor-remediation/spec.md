# Spec — token-floor-remediation

**Status:** DONE — built, gated, and released locally as **v4.6.0**. Release commit `ef7793e`; docs/closeout commit is this one. Gate `a2214b3`: **28/28 AC PASS**, `run-tests.sh` **619/619** (0 FAIL, 0 INCONCLUSIVE), preflight 0/0, hook manifest 121/121 MATCH `flow_version=4.6.0`, health check HEALTHY. Delivered boot floor **78,148 → 41,321 bytes = 47.1%** against the 42,200 budget (879 B headroom).
**Deploy hash:** **`abd66c9`, tag `v4.6.1`** — published 2026-07-26 on operator go-ahead. CI green (`fusebase-flow-verify` + `fusebase-flow-release`).

**Publication history — v4.6.0 shipped red, v4.6.1 fixed it.** `9b62819` / tag `v4.6.0` was pushed first and turned both CI workflows red. Root cause was **not** platform divergence: the v4.6.0 closeout commit added a backlog note quoting the self-attestation string verbatim, which tripped `test-sync-allowlist.sh` through two latent defects (an enumerated record-tree prune naming a consumer path this repo never had, plus `producer | grep -q` returning SIGPIPE 141 under `pipefail`). The 619/619 green was real but was measured **before** the last two commits. Full post-mortem and the durable guardrail: `docs/problem-catalog/docs-only-commit-broke-content-derived-gate/problem.md`.

**Post-deploy verification at `abd66c9`:** suite **620/620** at the exact pushed tree · preflight 0/0 · `test-sync-allowlist.sh` 8/8 · P1 health HEALTHY (VERSION 4.6.1, hook layer 121 files match 4.6.1) · P2 both workflows green · P3 consumer `upgrade.sh --dry-run` lists `FLOW_RULES_HISTORY.md` · S1 boot floor 41,321 B on a clean clone of the tag · S2 inventory diff empty with the deliberate-removal control detecting · S3 history 32,634 B distributed, zero dated entries left in `FLOW_RULES.md` · S4 classify 49/49 with the size-differs-only fixture retained LIVE.
**Created:** 2026-07-26
**Lane:** Full (FR-21). Trigger: FR-07 protected paths (`FLOW_RULES.md`, `hooks/**`, `.github/workflows/**`), CI public-surface allowlist, cross-provider bootstrap contract, parser behavior change.
**Linked decisions:** A1–A10 (decisions.md, LOCKED; A2 twice-amended, A3/A5/A8 extended in the 2026-07-26 correction round)
**Sources:** consumer escalation `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-07-26-token-floor-and-report-back-budget.md` (F1–F6) · adversarial intel pass (Codex 5.6-Sol High, 2026-07-26, verdicts + `[NEW]` couplings) · correction round: Codex 5.6-Sol High implementation review 2026-07-26, 15/15 findings accepted → T13–T18

## Problem

Every Fusebase Flow session pays a fixed boot floor before any work starts. Measured on this repo at HEAD `18f2ffa`. All sizes in this ticket are **bytes as reported by `wc -c`**:

| Artifact | Bytes | Note |
|---|---:|---|
| `flow-skills/communication/SKILL.md` | 19,936 | auto-injected, mandatory |
| `flow-skills/role-discipline/SKILL.md` | 29,089 | auto-injected, mandatory |
| `FLOW_RULES.md` operative (`:1-134`) | 19,962 | history is `:135-611` (~62% of file) |
| **Three-artifact floor** | **68,987** | ≈17.2k tok |
| Role reference (`references/<role>.md`) | +2,815 … +9,161 | required by `role-discipline/SKILL.md:53-71` — **missed by the escalation** |
| **Actual role-aware floor** | **71,802–78,148** | ≈18.0–19.5k tok, before `AGENTS.md`/`CLAUDE.md` |

Five secondary defects compound it: mandatory skills are re-`Read` after auto-injection (F2); the "never load the Amendment log" rule sits *inside* the file it protects (F3); delegated report-backs have no size budget and reached 32,164 chars × 11 ≈ 88k tok (F4); the handoff procedure's "write fresh" wording nudges whole-file rewrites where a targeted edit would do (F5); and `token-waste-audit.py` emits candidate classes it already holds the data to auto-classify (F6).

## Why now

The framework's own `/token-waste-audit` produced the evidence (5 sessions, 7,175 requests, ~9.0M output tokens). FR-26 obligates the framework to cut redundant consumption; the floor is the largest single redundant cost and every consumer pays it on every session. Short sessions pay the worst ratio — the smallest audited session spent more on floor reads than on its task.

## In scope

| Slice | Finding | What ships |
|---|---|---|
| S1 | F4 | Chat-return budget (lines **and** chars) in the task-delegation successor contract + the two handoff-template push blocks |
| S2 | F5 | Supersede-vs-write-primitive clarification in FR-18, `role-discipline`, `handoff`, `token-economy` TE-06, `templates/handoff.md`, `/handoff` command |
| S3 | F2 | Exact-body anti-reread rule in both mandatory skills + correction of the per-surface auto-load matrix across all 5 provider surfaces |
| S4 | F3 | Amendment log extracted to `FLOW_RULES_HISTORY.md`; compatibility stub heading retained in `FLOW_RULES.md`; distribution/publication/allowlist/sync-guard updates |
| S5 | F1 | Boot-core compression of both mandatory skills + `FLOW_RULES.md` operative section; detail moved to `references/`; boot-size regression test |
| S6 | F6 | `token-waste-audit.py` labeled auto-classification of growing-source-tails and possible-FR-10 triples + synthetic parser fixtures |
| S7 | ops | Zero-trust delegated-session liveness recipe (rate-limit re-dispatch) into `liveness-discipline` + `task-delegation` |
| S8 | release | VERSION/CHANGELOG/release note/plugin+marketplace parity (`README.md:659-660` "25 baseline rules" → 27 drift fix moved to T18 / MINOR 15; T20 verifies) |

## Out of scope

- Compressing the per-role `references/<role>.md` don't-lists below their current size (S5 keeps every don't-list row; `role-discipline/SKILL.md:358-361` forbids collapsing them into generic FR pointers).
- Removing any FR rule, any role don't-list row, or any behavioral obligation. **No rule may be lost** — S5 relocates elaboration only.
- Changing FR-18 supersede *semantics* (S2 clarifies the write primitive, not the rule).
- Retrofitting existing dated-history artifacts (`docs/tmp/handoff/archive/`, `docs/release-notes/`).
- A hard boot-token gate (semantic-adjacent; S5 ships a regression *check*, not a blocking ceiling on prose quality).

## Acceptance criteria

**Boot floor (S5)**

- AC1 — Post-change role-aware boot floor: per-artifact ceilings **and** the total, in bytes (`wc -c`). Rationale for the ~40.7k budget (twice-amended; correctness outranks the byte budget) rather than the escalation's ≤5k tok: A2.

| Artifact | Ceiling (bytes) |
|---|---:|
| `flow-skills/communication/SKILL.md` | 7,000 (A2 2nd amendment) |
| `flow-skills/role-discipline/SKILL.md` | 14,500 (A2 3rd amendment) |
| `FLOW_RULES.md` operative (byte 1 → end of the `## Amendment log` stub) | 11,500 (A2 3rd amendment) |
| largest `flow-skills/role-discipline/references/<role>.md` | 9,200 (not compressed this ticket; actual `ai-developer.md` = 9,161) |
| **Total worst case** | **42,200 budget (A2 3rd amendment; a ~47% cut of the 78,148-byte measured *boot floor* — lazy `references/` content is re-tiered, not deleted)** |

- AC2 — Zero rule loss: every FR-01..FR-27 statement, every role don't-list row, and the FR-24 write-time digest remain **always-on** (not moved to a lazy reference). Verified by `bash hooks/local/rule-inventory.sh` (T5): the post-compression inventory diffed against `docs/specs/token-floor-remediation/rule-inventory-baseline.txt` must be **empty**. The tool drops the Enforcement column, so rewording enforcement never registers as rule loss. **Amended (correction round, T14):** each inventory row carries `ID + normalized text + canonical source path + resident|lazy`, so a rule moved resident→lazy — or a don't-list row moved between roles — is a **FAIL**, not a clean diff; coverage extends to the FR-24 digest rows, the 5 protocol stubs, role authority, attestation/footer, question shapes, file classifications, refusal rules, failure/escalation obligations, and the Mode-A/Mode-B normative clauses. Re-baselined in the same commit as the schema change, old row count (94) recorded in the commit message.
- AC3 — Every shared protocol retains a ≤2-line always-on stub carrying its **prohibition** plus a pointer; only elaboration/examples/recovery move to `references/`. Prohibitions never lazy-load (A3).
- AC4 — Existing section anchors (`§ Operator Relay Protocol`, `§ Supersede Convention`, `§ Forward Momentum Protocol`, `§ Chat-Text Questions Protocol`, `§ Operator Gate Protocol`, `§ Write-time discipline digest`) still resolve in the canonical files — as stubs if the body moved.
- AC5 — A boot-size regression test asserts AC1's per-artifact ceilings **and** the total (not the total alone) and fails if any required lazy `references/*.md` is **missing** (preflight currently mirrors only what exists — `preflight.sh:104-106`, `[NEW]`).

**History extraction (S4)**

- AC6 — `FLOW_RULES.md` contains no dated log entries; `FLOW_RULES_HISTORY.md` contains all of them, **content-equivalent except a normalized final newline** (amended, correction round MINOR 14 — the extraction added one final LF, so literal "byte-preserved" was false; the gate tests this exact contract, T18).
- AC7 — `FLOW_RULES.md` retains a compatibility stub `## Amendment log` heading whose body is a ≤2-line pointer, so every stop-at-heading consumer and the `sync-version-strings.sh:174-181` sweep anchor keep working unchanged.
- AC8 — CI public-surface allowlist (`.github/workflows/fusebase-flow-verify.yml:88`) and `PUBLISHING.md:73-92` admit the new root file; `hooks/local/upgrade.sh` `CONTENT_FILES` ships it to consumers; `policies/protected-paths.yml` and `agent-surface-ownership.json` classify it.
- AC9 — `hooks/tests/test-sync-allowlist.sh` classifies `FLOW_RULES_HISTORY.md` as dated history and proves it is never version-synced (it contains live-looking FR/version strings — `[NEW]`).

**Anti-reread (S3)**

- AC10 — Both mandatory skills carry the exact-body rule **below** the YAML frontmatter (preflight requires `---` at byte 1 — `preflight.sh:47-51`, `[NEW]`), worded so that description/metadata discovery does **not** count as "already loaded" and delegated sub-agent sessions are excluded (they do not inherit — `task-delegation/SKILL.md:98-102`).
- AC11 — The auto-load matrix is correct per surface **(amended, correction round T15 / A5 amended — verified first-hand)**: Claude Code + Codex inject skill *descriptions/metadata* only — bodies are **not** auto-loaded (`session_start.py:35-38,75-102` never injects a body; `.codex/config.toml.example:28-36` is conditional on an optional `skills_dir`); Gemini does not auto-load (`GEMINI.md:41`); Copilot reads canonical on invocation (`.github/copilot-instructions.md:68-69`); Cursor per `.cursor/rules/fusebase-flow-always.mdc`. No surface row may claim eager **body** loading unless a fresh-session test proves it; every "do not re-Read" instruction is conditioned on a body-presence check, never on a surface name.

**Report budget (S1)**

- AC12 — Delegated **chat return** capped at ≤80 lines **and** ≤6,000 chars (a single 32k-char line passes a line-only gate — `[NEW]`). Overflow goes to a sanctioned durable artifact; commit only when the owning workflow requires it (read-only PO/Architect delegates must not be forced to commit).
- AC13 — Canonical gate reports (`handoff-implement.md:179-183`) and deploy reports (`handoff-deploy.md:159-170`) are **exempt** — evidence completeness outranks the cap there.

**Supersede primitive (S2)**

- AC14 — FR-18, `role-discipline § Supersede Convention`, `handoff/SKILL.md`, and `token-economy` TE-06 state both dimensions without contradiction: *replace stale semantics; patch unchanged structure*. Targeted `Edit` is the default when most sections are unchanged; full `Write` is for structure/mode/ticket changes.

**Audit tool (S6)** — surface posture: **internal** (`client-vs-internal`; the only human reader is the maintaining operator; no client surface exists in this repo)

- AC15 — Growing-source-tail auto-classification requires **all** of: same full read key, monotonic growth or differing digests, and no contradictory event (predicate defined in decisions.md A8). Size difference alone is insufficient (it can be repeated waste against changing output). Read→result association must preserve the full read key and event order (`token-waste-audit.py:153,201-203` vs `:158,200,230-233`, `[NEW]`).
- AC16 — Exactly-3 command runs are **labeled** `possible-FR-10-triple`, and auto-dismissed only when the command is test/probe-shaped (predicate defined in decisions.md A8); otherwise the candidate is retained. Three failed retries and three polls are indistinguishable from a repro triple by count alone. Note `bash_runs` counts runs since the last write, not truly consecutive (`:208-214`, `[NEW]`).
- AC17 — Every auto-classification renders as a visible labeled line stating the rule that fired **and** the evidence that triggered it (`client-vs-internal` I2 audit visibility, I4 full error detail). Silent dismissal is forbidden.
- AC18 — Dismissals are counted and reported in a section separate from live findings, so they neither bury nor inflate the finding count (I3 density).
- AC19 — The report distinguishes three terminal states in words: *candidates found*, *candidates found but all auto-classified*, and *no transcripts / parse failure* (QP-21 empty-vs-error states; silence is auditable, not proof of cleanliness).

**Cross-cutting**

- AC20 — Every canonical `flow-skills/` or `agents/` edit is mirrored and `audit/skill-mirror-manifest.txt` / `audit/agent-mirror-manifest.txt` show zero drift (`preflight.sh:96-145`).
- AC21 — Every `.claude/commands/<name>.md` change has a byte-identical `hooks/local/fusebase-flow-overlays/commands/<name>.md` twin (`preflight.sh:211-229`).
- AC22 — `bash hooks/local/preflight.sh` clean (0 errors) and `bash hooks/tests/run-tests.sh` green at each slice boundary.
- AC23 — New/changed shell tests are stamped into `audit/hook-layer-manifest.json`. Note `hooks/local/*.py` tools are **not** manifest-collected (`hooks/local/lib/hook_manifest.py:88-99`, `[NEW]`) — `token-waste-audit.py` alone needs no restamp; its new shell test does.

**Correction round (Codex 5.6-Sol High implementation review 2026-07-26; 15/15 findings accepted; T13–T18)**

- AC24 — Prohibition residency: no `flow-skills/*/references/*.md` file carries a normative marker (`MUST`, `never`, `do not`, `don't`, `forbidden`, `STOP`, `refuse`, exact-refusal-phrasing block) without a resident counterpart in its `SKILL.md`; resident B1–B12 lines carry each principle's **normative clause**, not the name alone; the Mode-A over-decoration + 80-character width/alignment obligation is resident. Enforced by `hooks/tests/test-prohibition-residency.sh` with a proven red arm (planted marker → FAIL). (A3 § Enforcement; T13.)
- AC25 — Verb-anchored probe matching: FR-10-triple auto-dismissal matches the parsed command **verb** / known exact forms — never `\bstatus\b`-anywhere; `--probe-command` comparison is normalized equality (or an explicitly validated wrapper), never substring containment. Both Codex PoCs (`echo status` ×3; documented probe + extra mutating commands) ship as retained-live fixtures. (A8 amended; T16.)
- AC26 — Path canonicalization: read-key and intervening-write contradiction checks canonicalize both sides (absolute resolution, separator normalization, Windows case-folding) before keying; the `C:/Repo/a.txt` vs `c:\repo\a.txt` alias fixture is a retained-live case. (A8 amended; T16.)
- AC27 — Non-vacuous test arms: `test-token-waste-classify.sh` asserts the **exact live row and evidence string** for fixtures 02–05, 07, 08, with one mutation control per fixture proving FAIL under the corresponding unsafe classifier; `test-sync-allowlist.sh`'s omission self-test runs the **production** missing-set calculation against a mutated reachable set and asserts `FLOW_RULES.md` is reported missing. (T17.)
- AC28 — Bounded retry exception: the delegate-retry recipe (T10) is stated as **one bounded exception** to don't-poll-while-running / record-then-read / two-strike (`token-economy:33,36`): max attempts + max wall-time, labeled backoff, the exact transition to successor-or-blocked on exhaustion, and when delegate-progress polling overrides record-then-read. All three carriers (`task-delegation:97`, `liveness-discipline:93-106`, `token-economy`) agree without contradiction. (T17.)

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths | none configured — N/A |
| FR-07 protected paths touched | `FLOW_RULES.md`, `hooks/**`, `policies/*.yml`, `.github/workflows/**` — require per-edit bootstrap approval (A9) |
| Module-size ceiling (800) | `token-waste-audit.py` 696 lines after T9; T16 must stay < 800 — extract along a responsibility seam if needed. Markdown is outside the gate (`policies/module-size.yml:40-65`) |
| Clean-room | no third-party text imported; all changes original |
| Secret scan | no credentials in scope |

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | S5 compression silently drops a behavioral obligation | AC2 rule-inventory diff + AC3 prohibition-stays-resident rule + Fable/Codex adversarial review gates |
| R2 | S4 breaks consumer upgrades (new root file not distributed) | AC8 `CONTENT_FILES` + both allowlists in the same commit |
| R3 | S4 breaks the version sweep guard | AC7 compatibility stub keeps the `## Amendment log` anchor by construction |
| R4 | S3 tells a non-auto-loading surface it auto-loads → mandatory skill never loads | AC11 per-surface matrix verified against each surface file |
| R5 | S6 auto-dismisses real waste (false negatives) | AC15/AC16 conjunctive conditions + label-don't-delete default + AC17 visible evidence |
| R6 | S1 cap suppresses gate evidence | AC13 explicit exemption for canonical gate/deploy reports |
| R7 | Slice interdependence causes rework | Dependency order fixed in tasks.md: S1 → S2 → S3 → S4 → S5 → S6 → S7 → S8 |

## Clarify summary

Operator granted blanket authorization for this run ("You have my full authorization", "accomplish all of the slices end to end in one run", migration + production deploy pre-approved) and stepped out. Decisions A1–A10 are locked under that delegated authority and recorded in decisions.md with the grant cited; no decision was invented beyond the escalation's scope.

## Related

- `docs/specs/repo-context.md` — repo topology, commands, protected paths
- `flow-skills/token-economy/SKILL.md` — FR-26 rules the floor violates
- Intel report — Codex 5.6-Sol High verdicts, blast radii, `[NEW]` couplings (scratchpad `codex-intel-report.md`; findings inlined above)
