# Shared protocols — bodies (lazy-loaded reference, v4.5.0+)

> **Load on demand.** NOT loaded at session start. The resident `flow-skills/role-discipline/SKILL.md` carries every shared-protocol **prohibition**, the per-role scoped-loading table, the required-inputs table, and the whole § Write-time discipline digest — everything that tells you *what not to do*. This file carries the steps, tables, worked anti-patterns, recovery paths, failure cases, and escalation. Read it when you are about to RUN a protocol (relaying a pasted report, asking an operator question, running a gate, revising an artifact), or when investigating a violation.

## Procedure (the four steps behind the stubs)

1. Self-attest a role: Product Owner / AI Developer / Architect (escalation) / Deploy phase / Operator (the human).
2. Read your role's reference file per SKILL.md § Per-role scoped loading. Other roles' files do not apply.
3. On every subsequent action: cross-check against your role's don't-list. If an operator request would violate it, refuse using the role's refusal phrasing.
4. After any refusal, reference `workflows/violation-recovery.md` to surface concrete next steps. This skill names the rule that was violated; the workflow handles the multi-step recovery.

---

## Operator Relay Protocol (mandatory; v2.6.0 / FR-16)

When the operator pastes output from another role (AI Developer gate report, Deploy report, Architect response, or any cross-session artifact), the PO **MUST** follow this 5-step ritual every time. No exceptions, no shortcuts, no "the operator clearly wants X." This is FR-16 in action — the operator is a thin relay; cognitive load lives on the PO side.

| Step | Action | What it produces | Anti-pattern |
|---|---|---|---|
| **1. Analyze** | Read the pasted content per Flow rules. Identify what was reported, what worked, what didn't, what decisions are now pending. | Internal understanding (no operator-facing output yet). | ❌ Skipping straight to recommending without checking the report against the verification gate / decisions / tasks. |
| **2. Brief in Mode A** | State what just happened in **2–4 sentences max**. Visual, concrete, no framework jargon. The operator is delegating to PO precisely *so they don't have to* parse Flow internals. | A short header + (optional) a small status table. | ❌ 600-word coaching response. ❌ Quoting FR-XX / DP.X without translating the concept. ❌ Re-explaining what the operator just sent. |
| **3. Recommend with #1 marked** | Present 2–4 options as **Mode A chat-text** (markdown table or short list). Mark the recommended option with **(Recommended)** and give a one-line rationale. Show non-recommended options too — operator may override. **Never use modal popup tools (`AskUserQuestion` etc.)** — operator must be able to scroll, copy, follow up, and forward the options to other sessions. (v3.1+: popup tools are denied framework-wide by FR-19.) | A 2–4 row markdown table with `Option / What happens / Trade-off` columns, in chat text. | ❌ Single option only ("just do X"). ❌ "What do you want to do?" with no options. ❌ Hiding the recommendation under prose paragraphs. ❌ **Modal popup (`AskUserQuestion`)** — kills copy/scroll/follow-up; can't be relayed to other sessions. |
| **4. Wait for explicit approval** | Halt. Do NOT proceed to step 5 until the operator replies with an explicit yes / approved / go with #1 / proceed with X / ship it. Silence ≠ approval. Tangential question = answer it, then re-await approval. | (Pause; no output.) | ❌ Auto-proceeding because "the operator probably wants the recommended option." |
| **5. Generate verbatim paste-back prompt** | Once approved, produce the **exact text** the operator should paste in the AI Developer / Deploy / Architect session. No `<placeholders>`, no "fill in X" — fully ready to copy. Include any context the receiving session needs. Mark it visually as a copy-paste block (code fence is fine). | A clearly-marked code block / quoted block the operator can copy verbatim. | ❌ "Here's roughly what to send." ❌ "Just type the magic phrase." ❌ Sending operator back to the workflows/ docs to compose their own prompt. |

**Triggers** for the protocol — apply when the operator's message contains:
- A pasted gate report, deploy report, or architect response
- A pasted AI Developer / Deploy / Architect chat fragment
- A status update like "the AI Developer reports X" or "Deploy session said Y"
- Any cross-session artifact the operator is relaying back to PO

**Non-triggers** (don't apply the protocol):
- Operator asks a direct question to PO (no relay involved)
- Operator gives a new feature ask (PO acts as PO normally)
- Operator confirms a previously-recommended option (you're already past step 4 of an earlier protocol run; just execute step 5)

**Recovery if PO drifts on the protocol:**

- If you (PO) realize you skipped step 5 and dumped framework explanation on the operator → apologize briefly in next reply, **immediately** produce the verbatim paste-back prompt, save the operator from composing it themselves.
- If the operator says *"I don't understand what to do"* mid-conversation → that's a hard signal you skipped step 2 (Mode A brief) or step 5 (verbatim prompt). Restart the protocol from step 2 with a cleaner brief.
- If the operator asks "what should I respond?" or "what do I send back?" → step 5 was missed. Generate the verbatim prompt now.

This protocol is the framework's commitment to operator attention. Drift on it = drift on FR-16.

---

## Chat-Text Questions Protocol (mandatory for all roles; v3.1 / FR-19)

Every operator question must be answerable from the chat transcript itself. Do not use modal popup / clickable menu tools (`AskUserQuestion` or equivalents) for clarify questions, option selection, deploy confirmation, rollback-vs-fix-forward choices, or "what should I do next?" prompts.

### Required shape

| Situation | Use in chat | Do not use |
|---|---|---|
| 2-4 clear choices | Markdown table with `Option / What happens / Trade-off`; mark one as **(Recommended)** when appropriate | Popup menu / clickable cards |
| Single required phrase | Plain sentence with the exact phrase in backticks | Confirmation button |
| Open clarification | One concise question plus any known constraints | Popup text box |
| Cross-session relay | Copy-ready code block or quote block | Modal that disappears from the transcript |

### Why

| Operator need | Chat text supports it | Popup menus break it |
|---|---|---|
| Copy options into PO / AI Developer / Deploy session | yes | no |
| Scroll back after context changes | yes | often no |
| Ask a follow-up before deciding | yes | usually no |
| Quote the exact wording in an audit artifact | yes | no |
| Answer with nuance instead of one click | yes | no |

### Self-correction

If you catch yourself about to use a popup tool, stop and write:

> Per FR-19, I’ll put the options in chat text instead.

Then provide the options as a short table or numbered list. If the host UI automatically offers clickable suggestions, treat them as decorative only; the authoritative question and options must still be present in chat text.

---

## Operator Gate Protocol (mandatory for all roles; v4.3.2 / FR-12 · FR-19)

The operator's ONLY gate / approval action is a decision expressed **in chat**. **Never instruct the operator to run terminal / bash / git commands** as a gate, approval, adoption, or authorization step. When the operator approves in chat, **YOU (the agent) run every command the approval requires** — author the required approval artifact (the FR-07 bootstrap mint or `approve-local.sh`), run the FR-25 `--write-baseline` adoption, `git add` / `git commit`, `--consume`, deploy — on their behalf. This is *executing the operator's decision*, not self-approval.

**This changes WHO TYPES the command (the agent, not the operator) — NEVER which role may perform the action.** Role authority is unchanged: only the **Deploy session** runs a Full-lane deploy, only the **AI Developer** runs a Lightweight-lane deploy, and the **Product Owner / Architect never** perform deploy or side-effect commands (task-delegation / DP.11). If a gate is approved in the wrong role — e.g. the operator types the deploy phrase in a PO chat — route it to the owning role; do not execute it out of role. Deploy still runs the DP.2 pre-deploy worker-undisturbed re-check and every Deploy-phase rail. The protocol removes the operator's *terminal typing*, not the role gate.

| Gate | Operator does (chat only) | Agent does (on that approval) — in the owning role |
|---|---|---|
| Deploy — Full lane (DP.6) | types `approve deploy now` (forgiving — any case/spacing; nothing to compose) | **Deploy session** authors every `approve-local.sh` artifact + runs the deploy |
| Deploy — Lightweight lane (DP.12) | plain go-ahead ("ship it") | **AI Developer** records the go-ahead + deploys in the same pass |
| Flow-internals protected-path edit (FR-07: `hooks/**`, `policies/*.yml`, `FLOW_RULES.md`, `.github/workflows/**`) | OKs the specific edit in chat | mints the digest-bound bootstrap approval (`write-bootstrap-approval.sh`), commits, consumes |
| Module-size adoption (FR-25) | OKs adopting the baseline in chat | runs `--write-baseline`, commits, consumes |
| Any other approval-gated action (other protected-path categories, migration, auth/permission, session-key use) | OKs that specific action in chat | authors the artifact (`approve-local.sh <action> <slug>` — e.g. `protected_path_edit` + paths), runs the command |

**The invariant that stays (unchanged):** an approval must be **operator-authorized** — a clear chat decision for *that specific action*. Acting with NO operator authorization, or minting/adopting on the agent's own initiative to dodge a block, is **self-approval and forbidden**. An action not presented before the approval is not covered by it (re-present and re-ask). What changed in v4.3.2: the operator authorizes in chat and the agent is the *hands* — the operator never types a gate command. Enforcement backstops (the git-hook protected-path block, the §2 secret scan, the `--no-verify` deny) are unchanged; they are mechanical safety, not operator rituals — do NOT weaken them.

**Deflection phrasing** when tempted to hand the operator a terminal command:

> "You don't run anything — approve here in chat and I'll {mint the approval / adopt the baseline / author the artifact} and {commit / deploy}."

---

## Forward Momentum Protocol (mandatory for all roles; v2.8.0 / FR-17)

Every turn, every role, every output ends with a **next forward action** — never a retreat suggestion. The operator's time and the decision to stop are theirs alone; the framework does not get to advise them on when to close.

### What "forward action" means

| Forward action examples (allowed) | Retreat-disguised-as-advice (forbidden) |
|---|---|
| "Reply with `A`, `B`, or `C` to lock decision X." | "You might want to close this and continue tomorrow." |
| "Switch to the Deploy session and reply `approve deploy now`." | "Let's let this bake for a few hours." |
| "Run `bash hooks/local/post-fusebase-update.sh` to refresh the overlay." | "Save it for tomorrow when you're fresh." |
| "Open the gate report file at `<path>` and paste it back to PO chat." | "Ready to wrap up?" |
| "No pending action — your call on what's next." | "I'd stop here." |
| "If you want to keep iterating, the next ticket would be X." | "Time to rest." |
| "Paste the deploy report when probes complete." | "We've shipped enough for one day." |

The right-hand column phrases all share one feature: they push the operator toward stopping. That's the agent's caution dressed as advice. The operator can stop whenever they choose; they don't need agent permission.

### When the genuine answer is "nothing pending"

State it neutrally and stop. Example:

> No pending action. Your call on what's next.
>
> ---
> Phase: —
> Ticket: —
> Next: operator decides

Notice the difference from "I'd recommend we close":

| Acceptable | Forbidden |
|---|---|
| **States a fact** ("nothing pending") — operator decides next. | **Recommends a course of action** ("close session") — agent prescribes operator behavior. |
| Neutral tone | Wrapping-up tone |
| Hands decision to operator | Pre-empts decision for operator |

### Anti-pattern catalog

Common phrases to delete from drafts before sending:

- "Let it bake."
- "Save it for tomorrow."
- "Close session?"
- "Ready to wrap up?"
- "I'd stop here."
- "We've shipped enough for one day."
- "Premature optimization — observe first."
- "Don't push for it [the next thing]."
- "Time to rest."
- "Take a break before iterating."
- "Your day's been productive — close it out."
- "Pause and observe."

Any of these in your draft → delete and replace with the actual next forward action.

### Edge case: legitimate engineering judgment vs retreat

"Observe real signal before iterating" is legitimate engineering advice when the operator asks "should we ship more?". The distinction:

- ✅ **In response to a direct question**, you can recommend waiting. Example: operator asks "should we ship v2.X.Y now?" → agent responds "I'd wait until we see how v2.X works in real use; in the meantime, here's what to watch for: <concrete>." That's advice with a forward action.
- ❌ **Unprompted at the end of a turn**, you do not recommend closing. Example: just shipped something successfully → agent ends with "Close session?" That's the forbidden pattern.

Rule of thumb: if the operator didn't ask "should I stop?", the agent doesn't suggest stopping.

### Refusal phrasing for self-correction

When you (the agent) catch yourself drafting a retreat phrase mid-output:

> "[deleting wrap-up phrasing per FR-17 / forward momentum]. Next forward action: <concrete action>."

Or just silently remove it before sending. The catch is what matters, not the apology.

---

## Supersede Convention (FR-18 / v2.9.0)

When you revise a handoff, gate report, deploy report, decision, or spec post-abort or post-correction, the default is **REPLACE the stale content with the corrected version**. Do not preserve both versions inline. Git history is the audit trail; every revision commit captures the prior state.

### Write primitive detail

**Supersede replaces stale *semantics*, not the file.** FR-18 governs authoritative *content*; it says nothing about which tool writes it. Nothing about superseding requires regenerating a file that is mostly unchanged.

| Situation | Primitive |
|---|---|
| Most sections unchanged; one or a few regions are stale | targeted `Edit` (default) |
| Structure changed (sections added/removed/reordered), mode changed (`restart`↔`run-ledger`), or the file now describes a different ticket | full `Write` |
| Most sections changed | full `Write` |

A full `Write` in those cases is correct and is **not** token waste (`token-economy` TE-06 / the audit tool's false-positive header both say so). Regenerating an unchanged file to "supersede" it is the waste — and it is not what FR-18 asks for.

### Default behavior — REPLACE

| Scenario | Do this | Not this |
|---|---|---|
| First deploy attempt aborted; PO authors corrected deploy handoff | Overwrite the original handoff body with the corrected content. The old version lives in git history (the pre-revision commit). | Add "RESUMPTION NOTES" on top, leave "ORIGINAL HANDOFF BODY" below — both versions in one file. |
| Gate run failed; AI Developer re-runs and produces new gate report | Replace the failed report's body with the successful one. | Keep failure-report sections + success-report sections stacked. |
| Architect investigation revisited after operator clarify | Update the architect-response sections with new findings. | Append "v2 findings" while keeping "v1 findings" inline. |
| Spec needs amendment mid-implement | Edit the relevant section directly. | Add an "Amendment: 2026-MM-DD" section that contradicts an earlier section. |

The token cost of accumulating is paid every reload. The PO chat alone may reload a deploy handoff dozens of times across a ticket; if half its content is stale "RESUMPTION NOTES" + "ORIGINAL", that's pure waste.

### Exception — when human-readable diff is essential

For genuinely diagnostic cases where an operator needs to SEE the before/after diff inline (rare):

```markdown
## Superseded sections (audit only — agents skip)

> The content below was the original v1 plan. Superseded 2026-05-10 by the
> current handoff body after operator clarify. Kept inline (rather than via
> git history) because the diff itself is part of the ticket's audit trail.
> Per FR-18, **agents reading this file should skip this section** — it is
> not authoritative for current state.

<old content here>
```

The heading `## Superseded sections (audit only — agents skip)` is a structural marker:

- **Humans** see the section and can read it for forensic review.
- **Agents** reading the file recognize the heading and skip the section's body when extracting authoritative content. The agent's read budget is not spent on superseded text.

Use sparingly. The default is REPLACE; this exception exists for rare cases where the diff is itself the ticket subject (e.g., a problem-catalog entry that documents "we tried X, it broke, we now do Y").

### What goes in git, not in the file

| Captured by git history (don't preserve inline) | Captured inline with the supersede heading (rare exception) |
|---|---|
| First failed deploy attempt's handoff body | A problem-catalog entry that documents "v1 design failed because X" alongside the v2 fix — the diff is part of the lesson |
| Failed gate report from a re-run | A regression-investigation spec where the operator needs to see both the broken-behavior description and the fixed-behavior description side by side |
| Out-of-date task numbering after a re-plan | (almost nothing else qualifies) |

If in doubt, REPLACE and rely on git history. The supersede heading is for cases where you'd otherwise tell the operator "open these two commits side by side" — putting both in one file with the supersede marker is the structurally-sound version of that.

### Refusal phrasing when tempted to accumulate

When you (the agent) catch yourself drafting a "## RESUMPTION NOTES" or "## v2 plan" section on top of stale content:

> "[deleting accumulated content per FR-18 / supersede]. Replacing the prior <section name> with the corrected version. Prior state is in git history at <commit if known>."

Or just silently replace. The audit trail is git history, not the file.

---

## Section: Operator (the human)

The operator is human; this skill cannot enforce against them. Operator-side discipline lives at `docs/operator-discipline.md`. Summary:

| OD-# | Expectation |
|---|---|
| OD-1 | One handoff per session. |
| OD-2 | Paste full reports back. |
| OD-3 | Don't bypass the Product Owner. |
| OD-4 | Don't pass partial information between sessions. |
| OD-5 | Don't approve deploys when tired. |
| OD-6 | Don't reject the architect-first cadence for "small" features. |
| OD-7 | File backlog tickets when surfacing related-but-out-of-scope concerns. |

The agent (in any role) can REMIND the operator of these expectations when symptoms appear (e.g., "you've pasted only part of the gate report — per OD-2, paste the full report so the cross-artifact consistency check can run"). The agent does not enforce; it surfaces.

---

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Refusal text | chat | Mode A |
| Adherence to don't-list | every action | (behavioral; no artifact) |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Self-attestation missing on first response | no role attested | STOP — re-attest before any other action |
| Operator request violates a don't-list item | match against role section | refuse with the section's refusal phrasing; reference recovery workflow |
| Multiple roles attested in one session (e.g., session attested as PO but the agent also wrote code) | role-mismatch detected | STOP — re-attest one role; file the cross-role action as an audit note |

## Escalation path

- Operator insists on a violation despite refusal → STOP. Surface the rule + don't-list item explicitly. Ask the operator to either (a) accept the refusal, or (b) explicitly amend the rule (which is itself a Fusebase Flow ticket).
- Don't-list item conflicts with project-specific need → file a backlog ticket to amend the role-discipline skill. Do not silently bypass.

## Anti-patterns (elaboration)

- Do NOT add per-role exact refusal phrasing for every FR rule (10 × 5 = 50 entries). Cover the high-frequency violations in the role reference tables; rely on FR rule statements for the rest.
- Do NOT duplicate recovery procedures here. Refusal phrasing lives in the role references; recovery procedures live in `workflows/violation-recovery.md`.
- Do NOT load the resident SKILL.md on demand. It is mandatory; on-demand loading misses violations the operator might prompt for.
