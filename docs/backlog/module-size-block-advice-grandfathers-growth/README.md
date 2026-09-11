# FR-25 growth-block advice offers adoption, which grandfathers the growth (module-size-block-advice-grandfathers-growth)

**Status:** parked — wording defect in a gate message; no ratchet logic change implied
**Filed:** 2026-09-11
**One-liner:** The per-violation text for a GROWN pre-existing over-ceiling file (`hooks/shared/module_size.py:337`) says "extract the addition, or adopt+freeze it (--write-baseline)", but a full `--write-baseline` measures working-tree files (`_line_count(..., staged=False)`, `:117-120`), so following that advice mid-change records the growth as the new limit.

## Operator pain (in their words)

fusebase-troubleshooter v4.15.3 escalation § 3: the block "consumed a full triage cycle before we confirmed the design intent"; they then ran `--write-baseline` and committed the feature (`ef1fd51` then `7632cfa` in their repo). Whether their adopted row froze the grown size is UNVERIFIED here.

## Why now

T91 corrected both install guides to say adoption is not permission to grow and must run from a clean tree; the gate's own message still says the opposite at the moment a reader is most likely to act on it.

## Architectural sketch (rough)

- `:337` (grown pre-existing file): name extraction as the remedy; drop "or adopt+freeze it", or qualify it to "adopt from a clean tree, never to clear this block".
- `:353-359` (shared remedy block): already frames adoption as the operator's decision; check it does not read as a way to clear a growth violation.
- Optional, separate decision: make `--write-baseline` refuse while a gated over-ceiling file is larger in the worktree than at `HEAD`. That is a ratchet behavior change and needs its own review.

## Acceptance criteria (rough)

1. AC1 — no FR-25 block message presents baseline regeneration as a remedy for growth.
2. AC2 — the extraction remedy text is unchanged in substance.
3. AC3 — any test pinning the message text is updated in the same commit.

## Out of scope

- Changing what the ratchet blocks.
- The shipped-dogfood-baseline observation (a consumer always has a baseline, so warn-only never applies); T91 documents it.

## Risks / unknowns

- Consumers may script against the message text; grep consumers before rewording.

## Related

- `docs/install-existing-project.md` § Activate the module-size ratchet (T91)
- `flow-skills/module-size-discipline/SKILL.md` § Baseline shipping
- `docs/backlog/cli-flag-resolution-project-local-only/` (filed from the same escalation)
