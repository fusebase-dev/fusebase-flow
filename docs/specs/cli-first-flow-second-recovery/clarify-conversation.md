# Clarify conversation - cli-first-flow-second-recovery

**Status:** in progress
**Linked spec:** `docs/specs/cli-first-flow-second-recovery/spec.md`

## Locked answers

| ID | Question | Locked answer | Date |
|---|---|---|---|
| Q-A | Should Flow ever restore CLI instructions from Flow's bundled provider copy? | No. Current FuseBase CLI remains source of truth for CLI-owned instructions/assets. | 2026-05-29 |
| Q-B | What is the recovery order when both CLI and Flow surfaces are damaged? | Run current FuseBase CLI refresh/update first, then Flow recovery. | 2026-05-29 |
| Q-C | What does Flow recovery restore? | Flow-owned overlay pieces only: Flow skills, Flow agents, Flow lifecycle hooks, Flow overlay blocks, Flow health skill/command, and Flow framework files. | 2026-05-29 |

## Active questions

### Q-D - CLI drift detection depth

**Question:** How deep should Flow health check go when checking CLI-owned assets?

**Options:**
- **Option 1:** Shape-only detection - verify current CLI-owned files exist and contain expected structural markers; do not compare hashes. Lower maintenance; cannot prove latest wording.
- **Option 2:** CLI-version-aware detection - ask current `fusebase` binary for version/template manifest when available, then compare generated assets against that manifest. Stronger; requires CLI support or a stable manifest contract.
- **Option 3:** Archive-fixture detection only - test against known archives during Flow development, but runtime health check only reports Flow health. Lowest runtime risk; weaker operator diagnostics.

**PO recommendation:** Option 1 now, with Option 2 as a follow-up if the CLI exposes a stable manifest. This avoids Flow freezing CLI text while still catching missing or obviously damaged CLI layer files.

**Operator answer:** pending

### Q-E - Installer scope

**Question:** Should this ticket implement the existing-project installer script, or only the health-check/recovery model?

**Options:**
- **Option 1:** Health/recovery first - add ownership map, health-check layer verdicts, recovery guardrails, and simulation tests; leave full installer script for the existing backlog ticket.
- **Option 2:** Bundle installer script now - implement dry-run conflict detector and write-capable existing-project installer in the same ticket. More complete; larger blast radius.
- **Option 3:** Spec only - produce decisions/tasks but defer implementation. Lowest risk; does not solve the immediate validation gap.

**PO recommendation:** Option 1. It establishes the invariant and tests before adding a write-capable installer.

**Operator answer:** pending

### Q-F - CLI refresh command in recovery guidance

**Question:** What exact CLI command should health check recommend when CLI-owned assets appear damaged?

**Options:**
- **Option 1:** Recommend `fusebase update --skip-cli-update --skip-mcp --skip-deps --skip-install --skip-commit` for agent-asset refresh only. Minimizes side effects if current CLI supports these flags.
- **Option 2:** Recommend full `fusebase update`, then Flow recovery. Most aligned with CLI behavior; more side effects.
- **Option 3:** Do not recommend an exact command; say "run the current FuseBase CLI refresh/update for this project", then Flow recovery. Safest wording across CLI versions; less actionable.

**PO recommendation:** Option 1 if verified against current CLI behavior during planning; otherwise Option 3.

**Operator answer:** pending
