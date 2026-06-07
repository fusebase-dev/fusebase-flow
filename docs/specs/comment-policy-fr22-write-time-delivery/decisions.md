# Decisions — FR-22 write-time delivery

**Letter prefix:** W
**Approval status:** Locked by Pavel on 2026-06-06
**Linked spec:** `docs/specs/comment-policy-fr22-write-time-delivery/spec.md`

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| W1 | Write-time delivery mechanism | New description-matched skill `flow-skills/comment-policy/` (not always-loaded); optional `session_start.py` secondary reminder INCLUDED (T6) | LOCKED |
| W2 | Fix the false "already loaded" claim | Correct `role-discipline:50` + add AI-Developer load directive | LOCKED |
| W3 | Audit-prompt reachability in consumers | Bundle prompt with the delivered skill; re-point FR-22 + yml | LOCKED |
| W4 | Sub-agent push (delegated code-writers) | Inline the policy block into code-writing sub-agent prompts (push, not pull) | LOCKED |

---

## W1. Write-time delivery mechanism

**Recommendation:** A **new dedicated skill `flow-skills/comment-policy/SKILL.md`**, **description-matched** to fire on code-writing / implementation / comment-adding tasks (NOT always-loaded), carrying (a) FR-22's tripwire+pointer write-time body and (b) a bundled `references/audit-prompt.md`.

**Reasoning:**
- **Reaches the code-writing role and its sub-agents** via the same skill-loading mechanism every other behavioral FR already uses (`communication`, `zoom-out`, `lightweight-lane`). The WorkHub failure was a *sub-agent* writing code — skills load for sub-agents; the `SessionStart` hook does not fire for them (`hooks/handlers/session_start.py` runs at session bootstrap only) and is opt-in (off until `settings.json` is copied).
- **Description-matched, not always-loaded** → zero context cost on Product Owner / Architect / Deploy sessions that never write code. Honors FR-22's own token-economy ethos (a 3rd always-loaded skill would tax every session, including non-writing roles — self-contradictory for a rule about saving context).
- **A skill is mirrored** into `.claude/` + `.agents/` (the two skill-mirror surfaces; `.codex/` holds agents, not skills) *and* delivered to consumers, so bundling the audit prompt inside it (W3) makes the prompt reachable downstream automatically.
- **De-risk the match** (R1) with the W2 role-discipline directive as an explicit always-loaded trigger — belt-and-suspenders.

**Alternatives considered:**

- **Option B — embed the rule in `role-discipline`'s AI-Developer section (already always-loaded).** Rejected as *primary*: role-discipline always-loads for *every* role, taxing non-writing sessions; and it does not naturally carry the audit prompt (W3). We still add a one-line *pointer* there (that is W2), but the rule *body* lives in the dedicated skill.
- **Option C — inject FR-22 into `session_start.py` `context_summary`.** Rejected as sole/primary mechanism: SessionStart hooks are **opt-in** (do nothing until `settings.json.example`→`settings.json`) and **do not fire for Task sub-agents** — precisely the WorkHub failure mode. **Operator elected to INCLUDE it as a secondary reminder (T6)** alongside the primary skill — a belt for hook-on full-session starts, explicitly NOT relied on for sub-agent reach.
- **Option D — new *always-loaded* mandatory skill (3rd alongside communication + role-discipline).** Rejected: bloats every session including non-code roles; contradicts FR-22's context-economy goal.

**Lock status:** LOCKED (Pavel, 2026-06-06)

---

## W2. Fix the false "already loaded" claim

**Recommendation:** Replace the misleading reference row at `flow-skills/role-discipline/SKILL.md:50`. State accurately that `FLOW_RULES.md` is **existence-checked at bootstrap, not injected into context**, and add an explicit **AI-Developer directive**: *when writing code, load `flow-skills/comment-policy` (FR-22 is not auto-injected) before adding comments.*

**Reasoning:**
- The current claim (`"already loaded as part of session bootstrap"`) is false against the shipped hook (`session_start.py` existence-checks; it never reads or emits FLOW_RULES.md content). An agent that trusts the claim never opens the file — the claim actively **suppresses** the only available workaround.
- Correcting it inside the **always-loaded** role skill gives a guaranteed in-context trigger to the W1 carrier even if description-matching misses (R1 mitigation).
- Same-file fix: the false claim and its correction live together; one edit closes the gap and arms the trigger.

**Alternatives considered:**

- **Option B — make the claim literally true via `session_start.py` injection.** Rejected: opt-in + no sub-agent reach (see W1-C); does not make it true for the failure mode, and bloats the hook context for every session.
- **Option C — delete the row entirely.** Rejected: loses the (now-corrected) signal about where rules live and where to load the comment policy; correction is more useful than deletion.

**Lock status:** LOCKED (Pavel, 2026-06-06)

---

## W3. Audit-prompt reachability in consumers

**Recommendation:** Bundle the independent-audit prompt as **`flow-skills/comment-policy/references/audit-prompt.md`** (rides the skill into every consumer mirror), and update the pointers in **FR-22 (`FLOW_RULES.md:68`)** and **`policies/comment-policy.yml:19`** to name that reachable location. Keep `docs/comment-policy.md` as the framework-dev rationale home (its audience is the maintainer, not the consumer).

**Reasoning:**
- `upgrade.sh:114-118` deliberately does **not** copy framework `docs/` into consumers (U4 — they collide with consumer doc layouts; `--with-framework-docs` only stages them namespaced under `docs/_fusebase-flow/`). So today's instruction "run the audit prompt in `docs/comment-policy.md`" is **unreachable in every consumer** — including WorkHub, which correctly reported the file absent.
- **Skills are delivered**; a `references/` file inside the carrier skill is the natural delivery vehicle. The prompt is already generalized (no plugin-specific clauses) per the parent ticket.
- Re-pointing FR-22 + the yml keeps the in-context instruction honest: it names a path the consuming agent can actually open.

**Alternatives considered:**

- **Option B — special-case `upgrade.sh` to carry this one doc into consumer `docs/`.** Rejected: violates U4's namespacing rule; special-casing one file is fragile and re-introduces the doc-collision the U4 policy exists to prevent.
- **Option C — inline the full prompt into `comment-policy.yml` comments.** Rejected: the prompt is ~30 lines; bloats a declarative config that is loaded as a carve-out source by `code-review`.

**Lock status:** LOCKED (Pavel, 2026-06-06)

---

## W4. Sub-agent push (explicit delivery to delegated code-writers)

**Added 2026-06-06 after the V7 behavioral probe.** An unprimed delegated sub-agent, given a code task, wrote default JSDoc-heavy output (~90% removable per FR-22) **even with CLAUDE.md context present** — the `comment-policy` skill never auto-loaded/applied. The W1 carrier relies on **pull** (agent auto-loads the skill); delegated Task sub-agents do not reliably pull. The original WorkHub failure was a sub-agent. So the carrier alone does not close the headline gap for the delegation path.

**Recommendation:** Deliver FR-22 to delegated code-writers by **push** — inline the policy text into the sub-agent's prompt, do not rely on the sub-agent loading a skill.

- **`flow-skills/comment-policy/SKILL.md`** gains a **"Delegation push block"** — a compact (~5-line) verbatim-inline tripwire+pointer summary a delegating agent pastes into ANY code-writing sub-agent prompt. Inlines the *rule text* (not "load the skill"), so it is in-context regardless of whether the sub-agent loads skills.
- **`flow-skills/task-delegation/SKILL.md`** gains a **mandatory clause**: when delegating a code-writing / implementation slice, the delegating prompt MUST carry the Delegation push block (push, not pull). Read-only/triage delegation is exempt (no code written).
- **`templates/handoff-implement.md`** gains a one-line reminder in the Tracks/delegation area.

**Reasoning:** V7 empirically showed pull does not reach an unprimed sub-agent. Push (inline in prompt) is the only reliable in-context delivery for an agent that may not run skill-matching. Inlining the literal rule guarantees presence; a secondary "+ load `comment-policy` for detail" is allowed but never the sole mechanism.

**Alternatives considered:**

- **Option B — instruct the sub-agent to "load `comment-policy`" (pull-via-instruction).** Rejected as sole mechanism: still depends on the sub-agent successfully loading the skill, which V7 shows is unreliable. Allowed only as a secondary line after the inlined block.
- **Option C — do nothing; rely on the main-session role-discipline directive (W2).** Rejected: W2 protects the main session, not delegated sub-agents — the exact failure mode. Shipping without W4 leaves the headline gap open (FR-20: fix the root failure mode).

**Lock status:** LOCKED (Pavel, 2026-06-06)

---

## Lock confirmation

When operator says `lock`, all PENDING decisions flip to LOCKED with date stamp. When operator says `redirect W<n>`, that decision returns to discussion (recommendation re-drafted; lock re-attempted).

| ID | Final option | Locked by | Date |
|---|---|---|---|
| W1 | New description-matched `flow-skills/comment-policy/` skill + T6 secondary `session_start.py` reminder INCLUDED | Pavel | 2026-06-06 |
| W2 | Correct `role-discipline:50` + add AI-Developer load directive | Pavel | 2026-06-06 |
| W3 | Bundle audit prompt with the delivered skill; re-point FR-22 + `comment-policy.yml` | Pavel | 2026-06-06 |
| W4 | Inline the policy block into code-writing sub-agent prompts (push, not pull) | Pavel | 2026-06-06 |

All decisions LOCKED — implementation may proceed via the implement handoff.
