# WP 6: six skills and the optional pack (Flow 6.0.0 rebuild, wave 1)

Six core skills (plan, build, verify, ship, security-checklist, writing-card) replace 34: 20 fold into the six and the role cards, 12 go to the optional pack, 2 go upstream.

| Field | Value |
|---|---|
| Program record | `docs/changes/2026-10-16-v600-minimal-core.md` (T167; its T174 row tracks this commit) |
| This commit | WP6-a (T174): the six drafts `<skill>/SKILL.md` beside this file; `projection/` (kernel and role-card projections, measurement only, § 3); `hooks/tests/fixtures/skill_carry_anchors.py`; `hooks/tests/test-skill-carry.sh`; opt-in tag `skill-carry` (`hooks/tests/run-tests.sh`, `docs/maintainer-testing.md` § Diagnostic exclusions) |
| Installed | no. Nothing under `flow-skills/`, no mirror, nothing loads these files. This repository runs Flow 5.11 on itself until WP 5's boot switch |
| Manifests | the commit adds files under `hooks/`: restamp `audit/hook-layer-manifest.json`, then `audit/managed-content-manifest.json` |
| FR-07 | not protected |
| Ignored path | `.gitignore:51` `build/` ignores `build/SKILL.md` here; it is tracked by exact path (`git add -f`). The same pattern ignores `flow-skills/build/` and the `build` mirrors (§ 6, WP6-b) |
| Proof | `python -B hooks/tests/fixtures/skill_carry_anchors.py --root docs/changes/2026-10-16-v600-wp6-skills --repo .` → `[skill-carry] 0 FAIL`; hosted `fusebase-flow-maintainer.yml` `groups=skill-carry,ff-only`. The fixture checks the five verbatim blocks against `v5.11`, its substitution list against § 4 row for row, the anchors § 2 names, the § 5 interface names, brief hygiene and byte ceilings. Fold-map rows without an anchor are review-checked only |
| Review | rule-preservation review: round 1 returned FIX (findings 1-9), folded into this commit; at most 2 rounds |
| Citation keys | OD1, OD2, OD3, OD4 = owner decisions 2026-10-16, 2026-10-16b, 2026-10-16c, 2026-10-16d (program record); R = reply to the owner 2026-10-16; H = rebuild handoff rev 2; D = file 1 rev 3; LF = the 5.12 classification; C511 = the 5.11 carry list; DEC58, DEC911, WPM = team analyses. Only the program record is in this repository |

## 1. Fold map: all 34 skills

Today's 34 skill folders hold 500,755 B (measured 2026-10-16; LF's 481,574 B is the 5.10 figure). The 20 that fold hold 360,344 B; the 14 that leave hold 140,411 B. "Retired" means no line carries, with the reason. "Planner card" and "builder card" are the WP 5 role cards in `agents/planner/AGENT.md` and `agents/builder/AGENT.md`; WP 6 does not write them.

### 1a. The 20 that fold (section by section)

| Source (file:lines) | Goes to | What carries |
|---|---|---|
| **smoke-testing** (18,984 B) | | |
| `smoke-testing/SKILL.md:26-28, 59-72, 76-88` | verify § Live evidence | outcome-first pass; supporting checks never pass; ground-truth diagnostic; real primary action; locators, data, auth, viewport; both surfaces; adversarial probe; traceback first; three candidate causes; `PENDING-OPERATOR-SMOKE`; `:80` run the named harness or say why |
| `:150` skipped harness → incomplete | verify § Live evidence, named-harness bullet | |
| `:64` (QP pointer), `:73` (live-user workflow), `:65, 79` (CLI edition map) | optional pack (QP, live-user); verify names the CLI log skills by name only | |
| `:93-112` flaky semantics | verify, **verbatim after substitution** (T142) | |
| `:114-121` live-run discipline, all six bullets | verify, **verbatim after substitution** (T147) | |
| `:127-129, 132` record-then-read, observability gap, screenshot diff | verify § Live evidence, two bullets | |
| `:89-91, 130-131, 134-149, 151-181` | retired | paths to removed documents (`docs/tmp/handoff/...-smoke/`, deploy report); duplicates of the above |
| **validation-and-qa** (21,396 B) | | |
| `validation-and-qa/SKILL.md:109-126` Sub-mode C | verify, **verbatim after substitution** (T142) | `:127` (attempts in chat) becomes Sub-mode C step 4: attempts in the run log (OD3) |
| `:61-66` three-question test | verify § Briefs, the skeptic brief (as questions, no rule text) | |
| `:69-75` UI and E2E plan | verify § Live evidence | |
| `:76` verdict never from the report's statuses; never by the implementer | verify (the reader returns, the planner records) | |
| `:103-107` Sub-mode B | verify § Live evidence | |
| `:129-152` Sub-mode D hygiene | verify, last bullet of § Live evidence | with the `:136-139` exceptions: shared fixtures kept; session-content captures redacted or deleted; retained external side effects recorded with their approval |
| `:57-59` gate rounds, `verify-gate.sh` | verify § Rounds (computed by `gate.py`) | |
| `:82` validator execution (FR-13) | rule 6 (WP 5); the effective-hook check becomes the reader's `git hooks: flow\|other\|none` (WP 7a, R:324) | |
| `:78-90` (except 82) release evidence, run tiers, CI scope | upstream: `docs/maintainer-testing.md` | maintainer process, not project text |
| `:92-101` Sub-mode E | retired | lanes are removed (WP 3) |
| `:22-49, 154-207` | retired | inputs and failure rows duplicate verify; `:188` rollback goes to ship |
| **code-review** (18,589 B) | | |
| `code-review/SKILL.md:91-104` defect hunt, `:105-114` tests | verify § Briefs, the review brief | hunt and test questions; `examined` paths (`:102-103`); BLOCKER criteria (`:103-104`, `:113-114`); name the missing case, never write it (`:114`) |
| `:53` scope against intent, `:51-55` | review brief rubric R(a) and R(b) (WP 8) | |
| `:82-86` split-quality check | review brief: one question and a BLOCKER criterion (a name that states no responsibility); a named but weak seam is graded | |
| `:120` per-blocker waiver | ship § Before the deploy | |
| `:140-150` round bound | verify § Rounds (decision 3: shared limit, own counter) | |
| `:124` severity grades | review brief severity criteria: a grade never replaces BLOCKER; ship § Before the deploy: a blocker stays open across rounds until fixed or waived | |
| `:60-76` comment-policy dimension | writing card line 3 (write time); review-time check retired (style, D:42) | |
| `:126-136` depth by risk, model routing | retired | `model-routing.yml` goes (D:41) |
| `:50, 115-119, 152-154, 156-208` | retired | the gate script computes the trusted fields; review record replaced by the ledger and the flags file |
| **task-delegation** (32,833 B) | | |
| `task-delegation/SKILL.md:33-46, 138-145` | build § Dispatch 2 | parallel only for disjoint, independent slices |
| `:73-75` critical path local | build § Dispatch 3 | |
| `:86` inputs need a tool (T152) | plan § Backlog items (inputs) and build § Dispatch 1 (`BLOCKED-AT-input`, computed by WP 9) | |
| `:213` question, never a fallback (T152) | plan § Backlog items | |
| `:93, 95, 97, 101, 105, 174` not alone, turn completion, facts as they occur, blocked return, return budget, ground truth | build § Builder push block | |
| `:99` delegate liveness | build § Delegate liveness | |
| `:107` no inherited auto-load | build header | |
| `:109` comment-policy push | the writing card, inlined by build § Dispatch 5 | |
| `:157-170` return shape and budget | push block items 8-9 (`state/returns/<slice>.json`) | |
| `:215-222` correction ownership | build § Corrections and successors | |
| `:224-231` pending answers (T149) | build § End the turn after dispatch | |
| `:233-242` unattended scheduling (T145) | build § Unattended runs and § Corrections (`:240` cross-slice, `:241` own brief) | |
| `:287` grant is not an approval, DP.1 sentence (T145) | ship § Approval (DP.1 sentence verbatim after one substitution) | |
| `:194-211` agent tool reach | plan (inputs), build § Dispatch 1 and 4; the mechanism is WP 4 and WP 11 | |
| `:31` `/step-out` routing | build § Unattended runs (R:50: `/step-out` dropped) | |
| `:62-71` role table | role cards (WP 5) and tool profiles (WP 4) | |
| `:111-136` frontend and test-only brief fields | verify § Live evidence (test fields); the slicer prints inputs and the reference project (WP 9) | |
| `:178-192` model routing | retired | D:41 |
| `:48-58, 147-155, 172, 176, 244-286, 288-294` | retired | gate and deploy report templates go (WP 2); integration is the DONE check and review |
| **liveness-discipline** (20,263 B) | | |
| `liveness-discipline/SKILL.md:22-45` failure, guardrail, protocol | rule 8 (WP 5) | |
| `:47-78` bounded-run example, heartbeat file, honest scope | push block item 4; build watcher bullet; the heartbeat is WP 7a's input | |
| `:80-93` diagnose, recover | build § Delegate liveness | |
| `:95-106` zero-trust | build § Delegate liveness, § At each boundary | |
| `:108-122` wake interval (T146) | build § End the turn after dispatch | |
| `:124-129` host wake paths (T159) | build wake table: Claude Code row **verbatim**; Codex row replaced by decision 9 (R:31) | |
| `:131-145` retry envelope | build § Delegate liveness (3 attempts, 5 minutes) | |
| `:147-170` | retired | cross-links and anti-patterns repeat the above |
| **implementation-planning** (11,390 B) | | |
| `implementation-planning/SKILL.md:67-68, 73-75` alternatives, lock | plan § Questions | |
| `:70` tasks name target files, module size | plan § Phases | |
| `:72` inputs and tools | plan § Backlog items | |
| `:106` over 12 tasks, split | plan § When planning goes wrong | |
| `:26-51, 55-66, 69, 71, 76-125` | retired | `decisions.md`, `tasks.md`, the gate file and the implement handoff are gone (WP 2); the slice replaces the handoff (WP 9) |
| **requirements-specification** (12,432 B) | | |
| `requirements-specification/SKILL.md:82-89` intent, questions | plan § Backlog items and § Questions | |
| `:61-69` diagnostic split | plan § Backlog items, "the cause unknown" bullet | |
| `:109-113` failure cases | plan § When planning goes wrong | |
| `:45-59` skip-clarify gate | trivial tier (WP 10) supersedes it | |
| `:37-43, 90` lane and doc tiers; QP and audience ACs | retired (WP 3); QP and audience go to the optional pack | |
| **handoff** (11,611 B) | | |
| `handoff/SKILL.md:22-36, 56-64, 75-77` | ship § Ledger entries (handoff entry, facts as they happen, `Unknown` not a guess) | |
| `:66-73` reader contract | ship § Resuming | |
| archive rules and the 16-section template | retired | git keeps history; the ledger replaces `docs/tmp/handoff.md` |
| **release-deploy-reporting** (14,140 B) | | |
| `release-deploy-reporting/SKILL.md:38` blocker waivers | ship § Before the deploy | |
| `:63` protected-path re-check | ship § Before the deploy | |
| `:85-103` rollback surface | ship table | |
| `:74` single docs commit (FR-14) | ship § The ship commit (`ship:`, decision 6) | |
| `:77-83` after the deploy | ship § After the deploy | |
| `:56` DP.6 authoring | ship § Approval | |
| `:30-32` Lightweight mode | retired (WP 3) | |
| **security-permissions-review** (12,517 B) | | |
| `security-permissions-review/SKILL.md:57-61, 68-69, 97-106` | security-checklist table rows 1-7 | |
| `:62-67` FuseBase app surfaces | security-checklist § FuseBase app surfaces | |
| `:70-78` approval verdicts | security-checklist § Approval list | |
| `:46-53` required inputs | `:48` no diff (ask), `:51` no approval policy (stop), `:53` grants unknown (ask; never org-only) → security-checklist § Before you start | `:49-50` retired (both policy files ship in the core); `:52` retired (the checklist names the CLI skills directly) |
| `:110` live exploit, `:111` compliance signoff, `:112` vendor advisory | security-checklist § Output | the `:110` incident file is not carried (no problem catalog in the four documents) |
| `:27-35` when to invoke | the description (risk tag trigger) | |
| `:120` `permission_request` hook | retired with the handler (WP 11) | |
| **role-discipline** (67,074 B with 5 references) | | |
| `role-discipline/SKILL.md:57-63` operator gate | ship § Approval ("never hand the operator a command"; no self-approval) | |
| `:65-69` forward momentum (FR-17) | build "dispatch every already-authorized independent slice" (R:45) | |
| `:71-87` write-time digest | writing card lines 2, 3, 5, 6, 7; rules 7 and 8 (WP 5) | |
| `:89-97` supersede | writing card line 2; ship § Ledger entries | |
| `:51-55` chat-text questions (FR-19) | plan § Questions keeps "in chat text"; the rule itself is dropped (R:44); the tool profile refuses `AskUserQuestion` (`agent_tool_profile.py:29`) | |
| `:47-49` operator relay (FR-16) | dropped (R:44) | |
| `references/deploy.md:9-11, 13-14, 19` DP.1, DP.2, DP.5, DP.6, DP.11 | ship | |
| `references/deploy.md:20` DP.12 | retired (WP 3) | |
| `references/ai-developer.md:9-28` IM.1-IM.18 | builder card (WP 5) for IM.2 and the stop-and-ask line (R:33); IM.3, IM.4, IM.6 are rules 2, 3, 6; the rest retired (attestation, gate report, lanes, timing records) | |
| `references/product-owner.md:9-24` PO.1-PO.16 | planner card (WP 5) for PO.1 and PO.5; PO.7 becomes plan "a related concern becomes a new item"; the rest retired | |
| `references/architect.md` | retired | the Architect role is removed (R:138) |
| `references/shared-protocols.md:14-46, 47-79, 102-190, 261-278` | retired | FR-16, FR-17, FR-19 bodies and the operator section; `:80-101` operator gate goes to ship; `:191-260` supersede to the writing card |
| `role-discipline/SKILL.md:16-41, 99-143` | retired | self-attestation and the footer are removed (decision 10a); OD-1..7 go |
| **product-owner** (5,405 B) | retired | the planner is the main session; `/product-owner` is dropped (R:52). The PO boot block (`agents/product-owner/AGENT.md:15-27`) is WP 5's |
| **north-star** (5,687 B) | `north-star/SKILL.md:47-50` → plan § Read first, one bullet (R:29) | the alignment verdict block retires; `/onboard` and `project-onboarding` are in the optional pack |
| **communication** (26,311 B with 2 references) | `communication/SKILL.md:24-25, 71-82` → writing card line 1 | file classification, visual patterns and Mode B detail retire (D:42) |
| **comment-policy** (12,519 B with 1 reference) | `comment-policy/SKILL.md:52-80, 105-108` → writing card line 3 | the push block, carve-out and audit prompt retire with `comment-policy.yml` (WP 11) |
| **documentation-budget** (13,366 B) | retired | the four-document rule is the budget (D:42); "no fifth document" is computed by flag 1 |
| **token-economy** (24,160 B) | TE-02 `:30` → writing card 5; TE-05 `:33` → line 6 with its not-a-strike list; TE-17 `:52` → line 7; TE-13 `:48` → line 4 (T158 guard); TE-06 `:34` → line 2; TE-19 `:63` → plan slice sizing (about 50 tool calls, never truncation, never below one verifiable task) and flag 3; TE-20 `:64` → build watcher | TE-20's model rates and the "Measure it" section `:81-108` go to the optional pack with `/token-waste-audit`; the rest retires (D:46) |
| **zoom-out** (9,886 B with the Karpathy reference) | rubric R(a) and R(b) in the review brief (WP 8); plan "failing test as the criterion" | **No line of `references/karpathy-guidelines.md` is copied.** It is MIT text with a required attribution block (`:5`); the core carries none of it and needs no attribution |
| **lightweight-lane** (13,944 B) | retired | lanes go (WP 3); the trivial tier (WP 10) is the small-change path; the safety floor is rules 3 to 7 |
| **module-size-discipline** (7,837 B) | `:51-53` plan-time rule → plan § Phases; `:57` named seam → review brief question | the ratchet itself is rule 7 and `check-module-size.sh` (WP 5, WP 11) |

### 1b. The 14 that leave the core (LF:92-103)

| Skill | Bytes | Goes to | Reason |
|---|--:|---|---|
| `find-wasted-code` (+2 refs) | 16,362 | optional pack | audit tool (LF:96) |
| `find-wasted-effort` (+2 refs) | 19,758 | optional pack | audit tool; T161 stays useful for 5.x history (R:311) |
| `git-history-diagnostic` | 6,340 | optional pack | diagnostic (LF:100) |
| `phase-audit` | 4,276 | optional pack | audit (LF:101) |
| `project-onboarding` | 4,838 | optional pack | first-day task; goes with `/onboard` (R:53) |
| `repo-onboarding-context-map` | 5,406 | optional pack | first-day task |
| `product-docs-first` | 3,809 | optional pack | first-day task |
| `product-apps-decomposition` | 6,503 | optional pack | app-domain guidance (LF:103) |
| `design-discovery-ideation` | 10,101 | optional pack | app-domain guidance |
| `business-logic-guardian` | 6,864 | optional pack | app-domain guidance |
| `client-vs-internal` | 7,822 | optional pack | app-domain guidance |
| `app-quality-patterns` (+3 refs) | 12,238 | optional pack | app-domain guidance |
| `fusebase-flow-health-check` | 16,808 | **upstream** (maintainer) | becomes `flow health` (R:54; LF:98, LF:229 item 6) |
| `skill-authoring` | 19,286 | **upstream** (maintainer) | "maintainer only" (LF:99); owner question 2 |

The 12 optional skills name retired core skills about 48 times (grep, 2026-10-16: `design-discovery-ideation` 8, `phase-audit` 6, `find-wasted-effort` 8, `git-history-diagnostic` 5, `app-quality-patterns` 4, `client-vs-internal` 4, `business-logic-guardian` 3, the rest 1 to 2). Those pointers are swept when they move (wave 3, WP6-d).

Commands (R:50-54; hooks-wp11:178-180, which gives WP 6 the call): `/step-out` → build § Unattended runs; `/handoff` → ship § Ledger entries; `/product-owner` → dropped. `/onboard`, `/token-waste-audit`, `/find-wasted-effort`, `/find-wasted-code` → optional pack. `/fusebase-health` → upstream.

## 2. Carried 5.11 content: where each item lands

| Item | 5.11 source (commit) | Lands in | How checked |
|---|---|---|---|
| T145 cross-slice order | `task-delegation/SKILL.md:240` (`4b707520`) | build § Corrections and successors; computed by the DONE check (WP 7b) | anchor `T145-cross-slice-order` |
| T145 own-brief re-dispatch | `:241` | build § Corrections and successors | anchor `T145-own-brief-redispatch` |
| T145 grant is not an approval; worker never mints | `:287` first sentences | ship § Approval | anchors `T145-grant-is-not-approval`, `T145-worker-never-mints` |
| **DP.1 presentation sentence** | `:287` last sentence | ship § Approval, **verbatim** except `(DP.1: …)` → `(…)` | verbatim case `T145-DP1-presentation-sentence` |
| T147 **six live-run bullets** | `smoke-testing/SKILL.md:116-121` (`dbfc5154`) | verify § Live-run discipline, **verbatim after substitution**; the FLAKY clause of `:121` is also computed by WP 7c | verbatim case `T147-six-live-run-bullets` |
| T142 flaky semantics | `smoke-testing/SKILL.md:93-112` (`548f3ee5`) | verify, verbatim after substitution | verbatim case `T142-flaky-semantics` |
| **Sub-mode C verdict table** | `validation-and-qa/SKILL.md:109-126` (table `:120-123`) | verify § Sub-mode C, verbatim after substitution | verbatim case `T142-sub-mode-c-verdict-table` |
| T149 keep working while an answer waits | `task-delegation/SKILL.md:224-231` (`f5693925`) | build § End the turn after dispatch; both guards kept: "opens no gate" (`:226`) and the parked action with its dependents (`:228`) | anchors `T149-*` |
| T152 tasks declare inputs | `task-delegation/SKILL.md:86, :213` (`9875f885`) | plan § Backlog items; build § Dispatch 1; computed by WP 9 | anchors `T152-*` |
| T158 read by slice | `agents/ai-developer/AGENT.md:14` (`904a05ad`) | writing card line 4, with the TE-13 guard | anchor `T158-read-before-edit` |
| T159 wake paths per provider | `liveness-discipline/SKILL.md:124-129` (`f77edc54`) | build wake table: Claude Code row verbatim; "never the only wake" kept | verbatim case `T159-claude-code-wake-row`; anchor `T159-never-the-only-wake` |
| Codex polled boundary | R:31 (decision 9) | build wake table, Codex row | anchors `codex-polled-boundary`, `codex-reader-held-turn`, `codex-unproven` |
| "End the turn after dispatch" | D:47, D:66; T146 `liveness-discipline/SKILL.md:120` (`cb04186e`) | build § End the turn after dispatch | anchor `end-the-turn-after-dispatch` |
| `gate_rounds` (a)-(e) | R:25 | verify § Rounds | anchors `gate-rounds-a` … `-e`, `gate-budget-carry-over` |
| Smoke template's tool-neutral lines | `templates/smoke-test-playwright.md:23, 29-41, 151, 160` | verify § Live evidence (primary action, test-plan fields, shared-state rule, either-surface FAIL, "never commit screenshots or raw run output") | anchor `no-commit-raw-output` |
| Pre-minted dev deploy (decisions 1 and I) | R:316 | ship § Approval; build § Unattended runs | anchor `pre-minted-dev-deploy` |
| North-star line | R:29 (decision 7) | plan § Read first | anchor `north-star-line` |
| Evidence rows and run log | OD3 | verify § Evidence rows; flaky block and live-run bullets through § 4 rows 3-4; Sub-mode C step 4 | anchors `evidence-row-schema`, `evidence-test-id-row`, `evidence-hash-in-place`, `runs-index-only`, `run-log-is-the-tools`, `sub-mode-c-step-4-run-log` |
| Deploy record line | OD3 | ship § After the deploy | anchor `deploy-jsonl-fields` |
| Review blockers | `code-review/SKILL.md:82-86, :102-114, :124` | verify review brief (severity); ship § Before the deploy | anchors `review-blocker-criteria`, `grade-never-replaces-blocker`, `ship-blocker-whatever-grade` |
| Security prerequisites and escalation | `security-permissions-review/SKILL.md:51, :53, :111, :112` | security-checklist § Before you start, § Output | anchors `security-policy-missing-stop`, `security-never-org-only`, `security-compliance-signoff`, `security-vendor-advisory` |
| Approval verdicts | `security-permissions-review/SKILL.md:72-78` | security-checklist § Approval list | anchors `approval-verdict-valid`, `approval-verdict-missing-expiry`, `approval-verdict-rejected` |
| Cleanup exceptions | `validation-and-qa/SKILL.md:136-139` | verify § Live evidence, last bullet | anchors `cleanup-exceptions`, `cleanup-retained-side-effects` |
| Named harness | `smoke-testing/SKILL.md:80, :150` | verify § Live evidence | anchor `named-harness` |
| Two-strike exceptions | `token-economy/SKILL.md:33` | writing card line 6 | anchor `two-strike-exceptions` |
| Slice size | `token-economy/SKILL.md:63` | plan § Phases, slices, tasks | anchors `slice-about-50-calls`, `slice-never-truncation` |

## 3. Byte counts and loading

All counts are LF bytes, measured by the fixture (`[skill-carry] bytes total` and the two `projected … boot` lines) on 2026-10-16. The boot lists themselves are WP 5's; the numbers here are what WP 5 must budget.

| Skill | Bytes | Description | Ceiling (fixture) | Loaded by | When |
|---|--:|--:|--:|---|---|
| `plan` | 3,691 | 139 | 6,000 | planner | at plan |
| `build` | 7,363 | 164 | 10,000 | planner | at dispatch |
| `verify` | 14,798 | 157 | 15,000 | planner | at verify (6,479 B of it, § Flaky-result to the end of Sub-mode C, is the 5.11 carry) |
| `ship` | 5,268 | 166 | 7,000 | planner | at deploy or handoff |
| `security-checklist` | 3,554 | 147 | 5,000 | planner at verify; inlined into the slice when the item is risk-tagged | risk tag present |
| `writing-card` | 1,378 | 122 | 1,500 | everyone who writes; inlined into every builder slice | first write |
| **Total** | **36,052** | **895** | 40,000 | | |

**Projections (measurement only).** `projection/` holds the three bodies the boot lists need and WP 5 has not written: `kernel-FLOW_RULES.md` (5.11 `FLOW_RULES.md` with removals; wording changed only in rules 1, 5, 6, 8 and the role table, H:134; rule 6 is the owner's decision-2 text, the first three sentences of 5.11 `workflows/git-discipline.md:91`), `builder-AGENT.md` and `planner-AGENT.md` (the decision-10b stop-and-ask line and one ceremony line on both; IM.2 on the builder; PO.1 and PO.5 on the planner; the tools line is WP 4's), and `planner-state.md` (ledger line 1 from the frozen grammar § 6 and an estimated `state/status.line` with WP 7a's fields and one alert). Each file's first line says "projection for measurement; WP 5 owns the final text" and is not measured.

**Builder bootstrap read list (the 6 KB target).**

| Read | Bytes |
|---|--:|
| `FLOW_RULES.md` (kernel projection, whole file) | 3,522 |
| `agents/builder/AGENT.md` (card projection) | 680 |
| slice: the push block body, as `slice.py` prints it (`build` § Builder push block) | 1,127 |
| slice: the writing card, whole file (its frontmatter is 163 B) | 1,378 |
| **Flow text in an ordinary slice** | **6,707** |
| risk-tagged slice: + the security checklist, whole file | 10,261 |

- Not counted: the slice's project text (item, criterion, cited answers, globs, `state/status.line`), which has its own budget (H:85). The host-injected overlay (`AGENTS.md`/`CLAUDE.md` Flow section; Claude Code injects it into sub-agents too) is WP 5's and unmeasured: it adds to both lists.
- Risk-specific text: counted only on a risk-tagged slice, as its own total. WP 5 and WP 9 decide whether the measured boot excludes it (phase text, H:57) or the slicer prints only the rows the risk tag needs.
- **Result: over.** 6,707 B is 563 B over 6,144 (707 over 6,000) before the overlay. Removals that close most of it, all WP 5's call: the writing card's frontmatter when inlined (163), the kernel's text after `## Amendment log`, if the read stops at that heading (246), FR-27's "A hung process …" sentence (95), FR-25's "Line count is objective …", "no committed baseline → warn-only" and "Not retroactive" (102). Together 606 B: 6,101 B, under 6,144 by 43 and still 101 over 6,000, with no room left for an overlay. Meeting 6 KB with an overlay needs a shorter kernel than removal-only or a shorter push block or writing card.
- Sensitivity: rule 6 with the whole of `git-discipline.md:91` (its `pre-commit` and `validator-free-paths.yml` sentences, which OD1's policy fold changes) adds 515 B.

**Planner bootstrap read list (the 8 KB target).**

| Read | Bytes |
|---|--:|
| `FLOW_RULES.md` (kernel projection) | 3,522 |
| `agents/planner/AGENT.md` (card projection) | 848 |
| ledger line 1 and `state/status.line` (estimate) | 230 |
| **Boot** | **4,600** |
| + the writing card at the first write | 5,978 |

Under 8,192 by 3,592 (8,000 by 3,400) before the overlay; 2,214 left after the writing card. Skills add at their phase and are not boot: plan 3,691 at planning; the largest step is verify (14,798 B), loaded only at verification.

**Readers** get only a brief: review 1,801 B, skeptic 394 B, verdict 293 B, plus the slice's data. No Flow rule text (fixture case `briefs-no-rule-text-no-default-verdict`).

**Skill index (always on through the host, in neither list).** 895 B for six descriptions, against 15,576 B for today's 34.

## 4. Substitution table (open owner question)

The flaky block, the six bullets, Sub-mode C and the DP.1 sentence carry 5.11 text word for word, except these path and name phrases. Each one points at a document, folder or skill the rebuild removes (WP 2, WP 3, this WP, OD3). The fixture applies exactly this table to `git show v5.11:<path>` and requires the result, whitespace-collapsed, inside the draft. Its own substitution list must equal this table row for row (case `substitutions-match-readme`), and case `negative-undocumented-substitution-caught` proves that an added or swapped pair (round 1's "product timeouts and retries may be lengthened") fails that comparison.

| # | 5.11 text | Becomes | Why |
|---|---|---|---|
| 1 | `` `flow-skills/validation-and-qa/SKILL.md` Sub-mode C `` | `Sub-mode C (below)` | Sub-mode C now lives in verify |
| 2 | `` `validation-and-qa` Sub-mode C `` | `Sub-mode C (below)` | same |
| 3 | `` under `docs/tmp/handoff/<date>-<slug>-smoke/` `` | `in the tool's native output, cited by an evidence row with path, sha256 and size` | OD3: Flow defines no capture folder; diagnostics stay where the test tool wrote them |
| 4 | `in the evidence dir` | `in the run log` | OD3: attempts and contract commits go in the tool's run log (the live runner's run-directory `README.md`); `state/runs/<phase>/` is an index only |
| 5 | `docs/specs/<slug>/verification-gate.md` | `backlog.md` | the criteria are the contract now (WP 2) |
| 6 | `(spec or S<n> pass criterion)` | `(the item's criterion or S<n> pass criterion)` | no spec document |
| 7 | ``Systemic → `requirements-specification` fix spec`` | `Systemic → a new backlog item` | no spec skill |
| 8 | `Systemic → fix spec (prompt/tooling/guard)` | `Systemic → a new backlog item (prompt/tooling/guard)` | same |
| 9 | ` (the classic FR-10 close)` | removed | FR-10 leaves the rules (R:43) |
| 10 | ``For the reproducing test/probe required by `flow-skills/zoom-out/references/karpathy-guidelines.md` §4, reproduce`` | `For the reproducing test or probe, reproduce` | no Karpathy text in the core |
| 11 | ``(mirrors `smoke-testing` § Flaky-result "Explained")`` | `(mirrors § Flaky-result "Explained" above)` | same skill now |
| 12 | `(DP.1: an action not presented is not covered)` | `(an action not presented is not covered)` | the DP ids retire |

`S<n>` is kept and defined once in verify ("one live row of `evidence.md`"), and "the run log" once in verify § Evidence rows, so no bullet needs rewording. Sub-mode C step 4 (5.11 `validation-and-qa/SKILL.md:127`, not a verbatim carry) also records attempts in the run log.

## 5. Interfaces the drafts name before they exist

Every name below is in the drafts and in the fixture's `interface-tokens` case, so a rename in another WP fails the fixture until WP 6 final follows it.

| Name in the drafts | Owner | Status on 2026-10-16 |
|---|---|---|
| `backlog.md` (`B<n>`, source slice, criterion or test id, inputs, risk, status), `phases.md` (`T<n>`, globs, minutes and files, reference project), `evidence.md` rows (status, capture path, sha256 and size, run log path; test-id rows `<file path>::<test name>` with a TAP log, OD3), `ledger.md` first line, risk tags `auth`, `data`, `production` | WP 2 (grammar review, wave 1) | proposed (H:78); evidence-row fields decided (OD3) |
| `state/deploys/<env>.jsonl`, one JSON line per deploy written by the ship step and committed with the `ship:` commit | WP 2 (state files), WP 6 ship | decided (OD3) |
| `planner`, `builder`, `builder-project`, `reader`; the reader's typed return; the dispatch check; `codex exec -s read-only … -o state/returns/<slice>-<role>.json` | WP 4 | decided (R:31, R:61); code wave 3 |
| `reader.py --once/--watch`, `state/status.line` fields (`reader last seen`, hooks per provider, `git hooks: flow\|other\|none`), whether `--watch` exits on an alert | WP 7a | wave 2; the watcher bullet uses the 5.11 `bounded_run` loop until then |
| `state/returns/<slice>.json` fields | WP 7b and WP 9 | the push block proposes: slice, verdict, tasks {id, sha}, tool_calls, compacted, residual_risk |
| validator, FLAKY reproduction note, `state/runs/<phase>/` (one index line per run: run id, phase, directory, started, exit code), the run log (the live runner's run-directory `README.md` with the `Time (UTC)`, `Row`, `Record` header; a TAP log for test ids) | WP 7c | wave 2; runner conventions received (OD3) |
| `python hooks/local/lib/gate.py <slice>`, `state/gate/<slice>.txt`, round count | WP 7d | wave 2 |
| `python hooks/local/lib/checks.py --rule <flag-id> upheld\|rejected --reason`, `state/flags/<slice>.tsv` | WP 8 | wave 2 |
| `python hooks/local/lib/slice.py <slice>`, `--brief review\|skeptic\|verdict`, `BLOCKED-AT-input`, printing the push block | WP 9 | wave 2 |
| trivial tier, `plan:` and `ship:` prefixes, the housekeeping task | WP 10 | wave 2 |
| `gate_rounds` in `approval-policy.yml`; `evidence-classes.yml`; the input-kind key in `agent-tools.yml`; `approve-local.sh --inventory` | WP 11 | wave 1 |
| the canonical location of the six in the Flow repository and the provider generator | WP 1a, WP 1b | wave 1 and wave 4 |

## 6. Deferred, by wave

| Wave | Item | Owner | Notes |
|---|---|---|---|
| 3 | **WP6-b** Finalize the six against the shipped interfaces (§ 5) and land them at `flow-skills/<six>/SKILL.md`, adding the ten frontmatter keys preflight requires unless WP 1a has re-based preflight; mirrors regenerated by `mirror-skills.sh` only; manifests restamped by their stamp scripts (hook-layer before managed-content). Fixture `--root` moves to `flow-skills`, with `--readme` pointing at this file. One commit, not protected. | WP 6 | Second review round (2 of 2). `build/` is ignored by `.gitignore:51` and by many project ignore files: the canonical folder and the `build` mirrors need an exact-path add or a negation (WP 1b for projects). **WP6-b and WP6-c land as adjacent commits:** between them this repository's own `.claude/skills` would hold the six beside the 20 they replace, with overlapping descriptions |
| 3 | **WP6-c** Retire the 20 folded folders (`flow-skills/<name>/` and references), the 5.11-only tests of their prose (`test-return-budget.sh`, `test-supersede-primitive.sh`, and the `return-budget`, `supersede-primitive` tags), re-base `test-codex-plugin-surface.sh` (`:6, :51, :88-89` read retired skills), delete `hooks/local/fusebase-flow-overlays/commands/{step-out,handoff,product-owner}.md`; mirrors regenerated. Not protected. | WP 6 | **After** WP 5's boot switch: this repository's `CLAUDE.md` and the agents still require `communication` and `role-discipline` until then |
| 3 | **WP6-d** Move the 12 optional skills to the optional-pack location and the 2 upstream skills under `maintainer/` (WP 1a's layout), with the ~48-pointer sweep (§ 1b) and the four optional commands. Not protected. | WP 6 | |
| 3 | WP6-b also follows the frozen grammar (`docs/backlog/four-document-model/grammar.md`, T177): the four documents live in `docs/flow/`, and the deploy record is the `state/deploys/<env>.jsonl` line, not a ledger entry (grammar § 6); ship § Ledger entries and § The ship commit still name a ledger deploy record | WP 6 | the drafts predate T177 |
| 3 | Kernel and the two role cards: `projection/` is measurement only (§ 3); WP 5 writes the final text and owns the boot-size test (builder ≤ 6,144 B, planner ≤ 8,192 B). The builder projection is over (§ 3) | WP 5 | |
| 3 | Promote `skill-carry` from opt-in to the release profile, or keep it opt-in | WP 6, owner | static, seconds |
| 3 | Tests and scripts that name retired skills by path (grep 2026-10-16: 67 files outside `flow-skills/`, `docs/`, mirrors): `test-boot-size.sh`, `test-startup-context.sh`, `test-prohibition-residency.sh`, `test-rule-inventory.sh`, `rule-inventory.sh`, `test-po-verifiable-boot.sh`, `test-sync-allowlist.sh`, `AGENTS.md`, `CLAUDE.md`, the overlays | WP 5 | |
| 3 | `workflows/*.md`, `test-lane-router.sh`, `test-lane-workflow.sh` | WP 3 | |
| 3 | `agents/*/AGENT.md`, `.codex/agents/*.md` | WP 4, WP 5 | |
| per WP 2's plan | `templates/*.md` (the 21 removed templates name retired skills) | WP 2 | |
| 1 | `hooks/handlers/session_start.py:*` (removed); `policies/comment-policy.yml`, `policies/model-routing.yml` (removed) | WP 11 | |
| 1 | `.github/instructions/*`, `.github/copilot-instructions.md`, `.cursor/rules/*`, `GEMINI.md` (decision 5c); `upgrade.sh`, `post-fusebase-update.sh`, `check-cli-flow-conflicts.sh`, `fusebase-flow-health-check.sh`, `partial-upgrade-check.sh`, `recovery-preflight.py`, `agent-surface-ownership.json`, the `cli-flow-recovery-*` and `test-recovery-*` suites (move to `maintainer/`) | WP 1a | |
| 2 | `hooks/local/lib/bounded-run.sh:3` comment, with heartbeat line 2 | WP 7a | |
| 3 | `policies/approval-policy.yml:72` comment naming `role-discipline` DP.1 and `workflows/greenlight-deploy.md` (protected; point it at ship) | WP 3 | in WP 3's protected commit that removes `lightweight_deploy` (`:73`) |
| 4 | Canonical home of the six in the Flow repository, the provider-declared generator, `.codex-plugin/plugin.json`'s skill list (publisher-only, R:27 5b), reserved-name list for the new skill names | WP 1b | |
| 4 | `flow migrate` removes the 34 old mirror folders and writes the six | WP 12 | |
| 5 | Release note: the six byte counts, the description total, the builder push-block bytes | close | |
| later | T148 relabel of `token-waste-audit` strings that cite `FR-26 TE-xx` (C511:52) | optional pack | not 6.0.0 |

**Wave 3 estimate for WP 6:** finalize 2 to 3, retire and move with sweeps 3 to 4, review round 2 about 1.5 → **6.5 to 8.5 agent-h.** With wave 1, WP 6 totals about 13 to 15.5, inside R:89 (11 to 16).
