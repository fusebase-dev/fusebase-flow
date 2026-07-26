# Decisions — token-floor-remediation

**Lock status:** LOCKED (delegated authority)
**Authority:** operator grant 2026-07-26 — "I'm the human operator, and I will step out. I expect you to accomplish all of the slices end to end in one run… You have my full authorization." Locks recorded under that grant per FR-11; scope is the escalation's F1–F6 plus the operator's explicit ops ask (A10). No decision extends beyond that scope.
See spec.md for problem statement.

## Decision matrix

| # | Decision | Chosen | Rejected | Driver |
|---|---|---|---|---|
| A1 | Amendment-log destination | root `FLOW_RULES_HISTORY.md` | `docs/flow-rules-history.md` | Escalation's primary ask; sibling discoverability; the two allowlist edits are 2 lines and are needed for `CONTENT_FILES` distribution either way |
| A2 | Boot-floor target | ≤42,200 bytes (~10.6k tok) role-aware, with per-artifact ceilings (amended at T7 on measurement; 2nd in the 2026-07-26 correction round — residency outranks the budget; 3rd at the T19 gate — headroom, not the measured minimum) | escalation's ≤5k tok | Arithmetically impossible as scoped — operative `FLOW_RULES.md` alone is 19,962 bytes (`wc -c`) |
| A3 | Lazy-load split rule | prohibitions resident, elaborations lazy | uniform "move the long sections" | A lazily-loaded prohibition reproduces the F3 trap exactly |
| A4 | Old `## Amendment log` heading | keep as compatibility stub | delete it | Preserves ~9 stop-at-heading consumers **and** the sweep-guard anchor by construction |
| A5 | Anti-reread wording | exact-body test + per-surface matrix | escalation's one-liner as written | Its premise is false on Gemini/Copilot; naked wording could suppress a mandatory load |
| A6 | Delegated-return cap | ≤80 lines **and** ≤6,000 chars; overflow → sanctioned durable artifact | ≤80 lines, "goes to a committed file" | One 32k-char line passes a line-only gate; read-only delegates must not be forced to commit |
| A7 | Supersede clarification | state both dimensions + fix TE-06 | add the line to FR-18 only | TE-06 currently asserts FR-18 rewrites are mandatory — the actual contradiction source |
| A8 | Audit auto-classification | conjunctive evidence; label-don't-delete for triples | auto-dismiss on size difference / exactly-3 | Size alone and count alone both admit real waste as false negatives |
| A9 | FR-07 protected-path approvals | one bootstrap approval per slice, minted after staging (edits → `git add` → mint → commit → consume) | one blanket approval for the ticket | Digest-bound approvals must name the specific edit; blanket approval is self-approval in disguise |
| A10 | Zero-trust delegation ops | codify as S7 | leave as run-local practice | Operator asked for it to persist ("update your project documentation for the future as well") |

## A1. Amendment-log destination — root `FLOW_RULES_HISTORY.md`

**Decision:** root-level sibling file.
**Reason:** the escalation named it; a root sibling is discoverable next to the rules it historicizes; `docs/` would still require the `CONTENT_FILES` distribution edit, so it saves only the two allowlist lines.
**Consequences (must ship in the same commit):** `.github/workflows/fusebase-flow-verify.yml:88` allowlist · `PUBLISHING.md:73-92` · `hooks/local/upgrade.sh` `CONTENT_FILES` · `policies/protected-paths.yml` · `agent-surface-ownership.json` · `hooks/tests/test-sync-allowlist.sh` dated-history classification.
**Alternatives:** `docs/flow-rules-history.md` (rejected — same distribution cost, worse discoverability).

## A2. Boot-floor target — ≤42,200 bytes, not ≤5k tokens

**Decision:** AC1 budget = per-artifact ceilings + total ≤42,200 bytes (~10.6k tok) role-aware. All sizes are bytes as reported by `wc -c`.

**Amended 2026-07-26 at T7** (delegated authority, same grant). The original split (role-discipline ≤9,000, total ≤36,000) was set without summing the components A3 and T7 declare non-negotiable — the same class of arithmetic gap this decision caught in the escalation's own ≤5k-token ask, one level down. Measured irreducible floor for `role-discipline/SKILL.md`, every element already maximally compressed: frontmatter 870 + anti-reread/surface matrix 911 + **FR-24 write-time digest 4,651** (all 7 rule rows verbatim; only non-normative prose trimmed, 5,061 → 4,651) + required-inputs 423 + scoped-loading 566 + 5 protocol prohibition stubs 2,270 + don't-collapse prohibition 352 + title/intro 552 = **10,595**. Closing the last 1,595 bytes would have required either lazy-loading the Operator Gate and Forward Momentum prohibitions (direct A3 violation, and it reproduces the F3 trap this ticket exists to close) or deleting FR-22/FR-26/FR-27 digest obligations locked by the `fr22-delivery-guarantee` and `liveness-discipline` specs. Both rejected. Ceiling raised to 10,600; total to 36,800 — both since superseded by the 2nd amendment below.

**Amended (2nd) 2026-07-26 — correction round** (delegated authority, same grant; PO adjudication of the Codex 5.6-Sol High implementation review). BLOCKERs 1–2 require pulling normative clauses back into the resident files (T13), which grows them. **Correctness outranks the byte budget:** a prohibition parked in a lazy file is not a rule, so residency wins over the budget. New ceilings:

| Artifact | 1st-amendment ceiling | 2nd-amendment ceiling |
|---|---:|---:|
| `flow-skills/communication/SKILL.md` | 6,000 | **7,000** |
| `flow-skills/role-discipline/SKILL.md` | 10,600 | **13,500** |
| `FLOW_RULES.md` operative | 11,000 | 11,000 (unchanged) |
| largest `references/<role>.md` | 9,200 | 9,200 (unchanged) |
| **Total** | 36,800 | **40,700** |

40,700 is still a **~48% cut** from the measured 78,148-byte role-aware floor, and the honest number is what we report. An implementer must never trade a prohibition for bytes — that is the exact failure the correction round exists to fix.

**Amended (3rd) 2026-07-26 — T19 gate FAIL** (delegated authority, same grant). The 2nd amendment left 5 bytes of headroom on `role-discipline/SKILL.md` and 6 on `FLOW_RULES.md`, so the AC14 and AC28 repairs the gate demanded could not land without breaching a ceiling. Twice now a ceiling has been set to the measured minimum and immediately blocked the next correct change. Ceilings are therefore set with **deliberate headroom**, not to the current measurement:

| Artifact | 2nd | 3rd | Headroom purpose |
|---|---:|---:|---|
| `flow-skills/communication/SKILL.md` | 7,000 | 7,000 | 133 B spare, sufficient |
| `flow-skills/role-discipline/SKILL.md` | 13,500 | **14,500** | AC14 `### Write primitive` section + AC28 envelope qualifier + ~600 B spare |
| `FLOW_RULES.md` operative | 11,000 | **11,500** | AC28 qualifier on the FR-27 row + ~400 B spare |
| largest `references/<role>.md` | 9,200 | 9,200 | unchanged |
| **Total** | 40,700 | **42,200** | |

Still a **~47% cut** from 78,148. **Reporting precision (gate finding F2):** the claim is that the *boot floor* fell ~47%, not that total content shrank — `references/shared-protocols.md` (21,233 B) and `references/mode-b-detail.md` are lazy, loaded only on demand. The release note must say re-tiered, not deleted.
**Reason:** operative `FLOW_RULES.md` is 19,962 bytes ≈ 5k tok on its own; the escalation's ≤5k-token target would require deleting rule statements, which AC2 forbids. Realistic split (2nd amendment): communication ≤7,000 · role-discipline ≤13,500 · FLOW_RULES operative ≤11,000 · largest role reference 9,161 untouched (ceiling 9,200) — worst-case total 40,700.
**Consequence:** the reduction is ~47% of the measured 78,148-byte role-aware floor (78,148 → ≤42,200), not the ~70% the escalation implied. Report the honest number back to the consumer in the release note.
**Alternatives:** hit ≤5k tok by moving the FR-24 write-time digest or role don't-lists to lazy files (rejected — FR-24's entire thesis is that those rules only work in-context at write time; `role-discipline/SKILL.md:358-361` forbids the don't-list collapse).

## A3. Lazy-load split rule — prohibitions resident, elaborations lazy

**Decision:** a rule that tells the agent **not** to do something keeps a ≤2-line always-on stub. Only its examples, rationale, recovery steps, and failure catalogs move to `references/`.
**Reason:** a lazily-loaded prohibition is only loaded by an agent who already remembered it — the identical structural trap as F3. Resident prohibitions: FR-16 relay trigger, FR-17 no-retreat, FR-18 supersede, FR-19 no-popups, Operator Gate "never hand the operator a command", plus the whole FR-24 digest.
**Alternatives:** move whole protocol sections (rejected — silently converts mandatory behavior into opt-in).
**Enforcement (added 2026-07-26, correction round — T13):** `hooks/tests/test-prohibition-residency.sh` FAILS when any `flow-skills/*/references/*.md` file contains a normative marker (`MUST`, `never`, `do not`, `don't`, `forbidden`, `STOP`, `refuse`, exact-refusal-phrasing block) with no resident counterpart in its `SKILL.md`; the red arm is proven by planting one. The T6/T7 implementation violated this decision (BLOCKERs 1–2: shared-protocol prohibitions and six B-principle normative clauses went lazy); T13 restores them resident under the A2 2nd-amendment ceilings.

## A4. Compatibility stub for `## Amendment log`

**Decision:** `FLOW_RULES.md` keeps the heading with a ≤2-line pointer body.
**Reason:** ~9 surfaces instruct "read down to `## Amendment log`" (`AGENTS.md:27,150`, `CLAUDE.md:3,15`, `GEMINI.md:3`, Copilot `:6`, Cursor `:9`, `role-discipline/SKILL.md:50`, `product-owner/SKILL.md:44`, `handoff-implement.md:25`, `session-initiation.md:11`), and `sync-version-strings.sh:174-181` uses the literal heading as its sweep anchor. The stub removes the payload while every inbound reference and the guard keep resolving.
**Alternatives:** delete the heading and update all consumers (rejected — larger blast radius, and any un-updated downstream consumer silently reads to EOF).

## A5. Anti-reread wording — exact-body test, per-surface matrix

**Decision:** ship, below the frontmatter:
> If this exact SKILL.md body is already present in your context (surfaces that auto-load `.claude/skills/` or `.agents/skills/`), do not Read this file again — seeing the name/description in a skill index does **not** count. If it is not present, read it once. Delegated sub-agent sessions do not inherit an auto-load: they read it.

Plus per-surface truth-up: Claude Code auto-loads (`CLAUDE.md:69-76`); Codex auto-loads via `.agents/skills/` — **both claims superseded for the Claude Code/Codex rows by the Amended paragraph below**; Gemini does **not** (`GEMINI.md:41`); Copilot reads canonical on invocation (`.github/copilot-instructions.md:68-69`); Cursor per `.cursor/rules/fusebase-flow-always.mdc:9,47`. `AGENTS.md:150` currently over-claims and is corrected.
**Reason:** the escalation's bare line is false on 3 of 5 surfaces and would suppress a mandatory load there.
**Constraint:** the line goes **after** the YAML frontmatter — `preflight.sh:47-51` requires `---` at byte 1.
**Amended 2026-07-26 — correction round (T15, BLOCKERs 3–4).** Verified first-hand: on Claude Code with `.claude/skills/` populated, only skill *descriptions* reach the session context; bodies are **not** injected (`hooks/handlers/session_start.py:35-38,75-102` existence-checks and emits reminders — it never injects a body). No active `.codex/config.toml` ships; `.codex/config.toml.example:28-36` makes Codex loading conditional on an optional `skills_dir`. The Claude Code and Codex surface rows must therefore state: *descriptions/metadata are injected; bodies are not — check whether the exact body is present, read once if not.* Any "do not re-Read" instruction is conditioned on a body-presence check, never on a surface name. The in-file blockquote rule above stays unchanged — it is already conditional on the exact body being present and rejects metadata as proof. Gemini/Copilot/Cursor/delegated-sub-agent rows were already correct. **This narrows F2's premise:** the measured "double-pay" was largely sessions reading bodies that were never auto-injected; the anti-reread rule still pays off on genuine within-session re-reads. Say so plainly in the release note.

## A6. Delegated-return cap — lines and chars

**Decision:** ≤80 lines **and** ≤6,000 chars on the delegated session's chat return. Overflow goes to a sanctioned durable artifact; commit only when the owning workflow requires it. Canonical gate reports (`handoff-implement.md:179-183`) and deploy reports (`handoff-deploy.md:159-170`) are exempt.
**Reason:** a line-only cap is trivially evaded by one long line; "commit it" is wrong for read-only PO/Architect delegates and for concurrent investigations that would collide on the index.
**Alternatives:** cap gate reports too (rejected — evidence completeness outranks token cost at the gate; `policies/ratchet-governance.yml:100-127` protects that evidence).

## A7. Supersede clarification — both dimensions, TE-06 fixed

**Decision:** every carrier states: *replace stale semantics; patch unchanged structure.* Default to targeted `Edit` when most sections are unchanged; full `Write` for structure/mode/ticket changes or when most sections changed. `token-economy` TE-06 (`:34`) is amended — it currently says FR-18 rewrites are mandatory, which is the contradiction FR-26 trips over.
**Reason:** FR-18 governs authoritative *content*, never the write primitive. Nothing about supersede requires a full rewrite.
**Alternatives:** amend FR-18 alone (rejected — leaves TE-06 asserting the opposite).

## A8. Audit auto-classification — conjunctive, label-don't-delete

**Decision:**
- **Growing-source-tail:** auto-classify only when *all* hold — same full read key, monotonic growth or differing digests, no contradictory event. Render a labeled `auto-classified: growing-source-tail` line with the evidence.
- **FR-10 triples:** exactly-3 runs are **labeled** `possible-FR-10-triple`; auto-dismissed only when the command is test/probe-shaped. Otherwise the candidate is retained.

**Definitions (normative — spec AC15/AC16 point here):**

- **Contradictory event** (any one disqualifies a growing-source-tail auto-classification): an intervening `Write`/`Edit`/`NotebookEdit` whose **canonicalized** target equals the **canonicalized** read path (both sides absolute-resolved, separator-normalized, Windows case-folded — amended, see below); a context-compaction marker between the reads; an error-shaped tool_result for either read; or a non-monotonic size sequence (a later read smaller than an earlier one) with identical digests.
- **Probe-shaped command** (required for an FR-10-triple auto-dismissal; matched against the parsed command **verb** or a known exact form — never substring/anywhere matching; amended, see below): a test runner (`pytest`, `npm test`, `run-tests`, `bash hooks/tests/`), an explicit `--dry-run`, a health/status/version verb in verb position (`git status`, `health-check`, `preflight`, `--version`), or a documented probe command from the ticket's own gate under **normalized equality** (or an explicitly validated wrapper). Anything else keeps the candidate.

**Reason:** differing size can mean repeated waste against changing output; three failed retries and three polls are count-identical to a repro triple. The instrument's job is to make adjudication cheaper, never to decide silently.
**Prerequisite:** preserve the full read key and event order through the result-association path (`:153,201-203` vs `:158,200,230-233`), and account for `bash_runs` counting since-last-write rather than truly consecutive (`:208-214`).
**Alternatives:** dismiss on size difference / exactly-3 alone as the escalation proposed (rejected — both admit real waste as silent false negatives).
**Amended 2026-07-26 — correction round (T16, BLOCKERs 5–6).** The T9 implementation admitted false negatives both definitions now exclude: (a) `\bstatus\b` matched anywhere in the command string, so `echo status` ×3 or `deploy --message status` ×3 auto-dismissed, and `--probe-command` used substring containment, so a documented probe plus extra mutating commands also dismissed (`token-waste-audit.py:60-71,373-381`) — fixed by verb-anchored / known-exact-form matching and normalized-equality probe comparison; (b) intervening-write detection used raw string equality, so `C:/Repo/a.txt` vs `c:\repo\a.txt` were treated as unrelated paths (`:267-274,328-345`) — fixed by canonicalizing both sides before keying and contradiction checks. Both Codex PoCs plus path-alias fixtures ship as retained-live cases.

## A9. FR-07 approvals — one bootstrap approval per slice

**Decision:** Each slice that edits `FLOW_RULES.md`, `hooks/**`, `policies/*.yml`, or `.github/workflows/**` mints its own digest-bound bootstrap approval in this order: **make the edits → `git add` the paths → mint (`write-bootstrap-approval.sh`, digest binds the staged set) → commit → consume**. The approval artifact is gitignored, so this remains one commit per task (FR-03). The agent mints — the operator types nothing (Operator Gate Protocol).
The 15-minute TTL is why minting is the last step before the commit, not the first step of the slice.
**Reason:** an approval must name the specific edit; one blanket ticket-wide approval is indistinguishable from self-approval.
**Alternatives:** one ticket-scoped approval (rejected — defeats the digest binding).

## A10. Zero-trust delegation ops — codify as S7

**Decision:** the run's operational protocol becomes framework content: a delegated session that dies on a transient provider rate-limit is **re-dispatched** ("try again"), and if it reports the limit again, wait ~60s and retry until it starts — **bounded at T17** to max 3 attempts / 5 min, then successor-or-`BLOCKED-AT-delegate-no-start` (`flow-skills/liveness-discipline` § Bounded delegate-retry envelope); liveness is verified by polling progress (git/process/file growth), never by waiting for a completion ping.
**Reason:** operator asked for it to persist. FR-27 already carries zero-trust sub-agent liveness in principle; the concrete rate-limit recipe is missing.
**Carriers:** `flow-skills/liveness-discipline/SKILL.md` (protocol) + `flow-skills/task-delegation/SKILL.md` (delegation-side).

## Lock confirmation

| Decision | Locked | By |
|---|---|---|
| A1–A10 | 2026-07-26 | delegated operator authority (grant cited above) |
| A2 2nd amendment · A3 enforcement · A5 amendment · A8 amendment | 2026-07-26 (correction round) | delegated operator authority — PO adjudication of the Codex 5.6-Sol High implementation review (15/15 findings accepted) |
