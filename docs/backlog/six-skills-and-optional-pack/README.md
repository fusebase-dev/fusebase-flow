# six-skills-and-optional-pack

**Status:** open — 6.0.0 rebuild, **wave 1 (drafts)**, final text in **wave 3**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 6 (R §2). **Surface:** `flow-skills/` (34 skill folders today, none of them one of the six, R §5b row 16), the mirrors `.claude/skills/` and `.agents/skills/`, `.claude/commands/` and `hooks/local/fusebase-flow-overlays/commands/`. **FR-07:** no (`flow-skills/**` and the mirrors are outside `policies/protected-paths.yml:84-101`).

## Delivers

- **Six skills** (D §2 row 5): plan, build, verify, ship, security checklist (loaded by risk tag only), writing card (text authored in `eight-rule-kernel-and-cards`). Under 40 KB together (H recommendation).
- **Disposition of all 34 folders:** the 14 that LF assigns go to the optional pack or upstream (LF:92-103); the other 20 fold into the six skills and the cards, and their folders retire (R §5b row 16). Sources: plan ← implementation-planning, requirements-specification; build ← task-delegation, liveness-discipline; verify ← smoke-testing, validation-and-qa, code-review; ship ← release-deploy-reporting, handoff; security checklist ← security-permissions-review; writing card ← communication, comment-policy, documentation-budget, token-economy.
- **Text that must survive the compression** (R §6 and the decisions):
  - verify: all six live-run bullets of `flow-skills/smoke-testing/SKILL.md:116-121` (not four) and the Sub-mode C verdict table; about 10 tool-neutral lines from the dropped smoke template, including "do not commit screenshots or raw run output"; the review brief, the gate rows and the skeptic brief (two skeptics per phase gate, never per slice); no brief carries Flow rule text or a default verdict.
  - verify, gate rounds (decision 3): a round is one verdict dispatch after the gate script passes, so a script failure costs no round (3c); review rounds share the limit with their own counter (3d); at the limit the planner drafts the numbered carry-over list, security, privacy, data-loss and owner-answer contradictions first, and the operator closes unless an unattended close was authorized beforehand (3e).
  - build: delegation; the typed return written to `state/returns/<slice>.json` before the turn ends, with task ids and SHAs; budgets; liveness; "end the turn after dispatch" with the wake path per provider. Claude Code: the watcher is the primary wake; report-back and scheduled tasks are "never the only wake" (`flow-skills/liveness-discipline/SKILL.md:128`; R §5b row 15). Codex: none is documented (`:129`), so the orchestrator polls `state/returns/` at each task boundary and the next operator message starts that boundary; the `codex exec` reader runs synchronously under `bounded-run` (decision 9). "Continue independent slices while a question waits" with T149's two guards; the `state/pause` check at task boundaries; the pre-minted approval lines (the content of `/step-out`).
  - ship: the deploy step with its approval; ledger entries for handoff and deploy; the DP.1 presentation sentence from `flow-skills/task-delegation/SKILL.md:287`.
  - plan: backlog to phases to slices; estimates in minutes and files; globs per task; the reference project; one line "read `docs/north-star.md` when present" (decision 7).
  - the two holds of decision 6 (a rubric "yes" on a risk-tagged item; the DONE send-back), each released by one planner ruling written with `checks --rule`, one flag id at a time.
- **Commands** (R §1 confirmed drops): `/step-out`, `/handoff` and `/product-owner` are dropped; `/onboard` and the three audit commands go to the optional pack with their skills; `/fusebase-health` becomes upstream `flow health`.
- `policies/ratchet-governance.yml` travels with the find-wasted-effort audit into the optional pack (R §1 confirmed drops).

## Decisions and asks carried

Decisions 3 (c)(d)(e), 6, 7 (north-star line, smoke template lines, command drops), 9 (wake path, `codex exec` exception), 10b (the card line is not repeated in build); R §6 rows T142, T145, T147, T149, T158, T159.

## Estimate

R §2: 11 to 16 agent-h (mid 13.5), a parallel long pole from wave 1 (R §2). Review: 2 rounds, one an independent rule-preservation audit.

## Depends

The decision table (answered). Final text after `slice-gate`, `reader-agent-and-dispatch-check`, `overbuilding-flags` and `task-slicer` fix their interfaces, and after `eight-rule-kernel-and-cards` fixes the writing card. Blocks: `one-lifecycle-page` (skill names), `flow-install-declared-providers` (inventory).

## Acceptance

1. 6 skills, under 40 KB together (H WP 6).
2. A reviewer or skeptic brief contains no Flow rule text and no default verdict (H WP 6; fixture).
3. Every kept rule is present by anchor text: the smoke and flaky rules, the six live-run bullets, gate rows, `gate_rounds` with `BLOCKED-AT-gate-budget` and the carry-over order, the typed return path, the `state/pause` check, the wake path per provider (fixture).
4. Every one of the 34 folders has a recorded fate (optional pack, upstream, or folded and retired); mirrors and the skill manifest are regenerated.
5. No skill names a design tool, ticket system or model (H non-negotiable 6).

## Wave split

- **Wave 1:** the six drafts and the 34-folder disposition table, written in their own worktree and audited for rule preservation. The design pass's WP 6 plan decides whether the drafts commit in wave 1 or with the final text.
- **Wave 3:** final text, the folder retirements, the command drops, mirror regeneration.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; LF = `flow-handoff-2026-10-15-lighter-flow.md`; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
