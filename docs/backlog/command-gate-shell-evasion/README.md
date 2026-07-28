# command-gate-shell-evasion

**Status:** parked
**Found:** 2026-07-28, adversarial implementation review of `approval-binding-and-upgrade-classification`
**Surface:** `policies/command-policy.yml` + `hooks/shared/command_rules.py` (`rule_matches`)
**Severity:** medium — pre-existing property of regex-on-raw-command, not a regression
**Decision of record:** K21 (`docs/specs/approval-binding-and-upgrade-classification/decisions.md`) — document, do not half-fix

## Defect

Rule matching is `re.search(pattern, command)` over the **raw** command string. Two classes execute a gated command while matching no rule:

| Class | Example | Executes | Matches a rule |
|---|---|---|---|
| Quote fragmentation | `fusebase de'pl'oy` | yes | no |
| Quote fragmentation | `npx prisma mi"grate" deploy` | yes | no |
| Dynamic construction | `CMD='fusebase deploy'; eval "$CMD"` | yes | no |
| Dynamic construction | `$(printf 'fusebase deploy')` | yes | no |

Verified in-process by the review; `hooks/tests/test-command-policy.sh` carries the first two as **documented-limitation** cases asserting today's `allow`, so the future fix flips them rather than being written against no baseline.

## Why it was not fixed in the corrections round

Locked by K21. Closing it properly means shell-aware parsing (or conservatively denying dynamically constructed gated commands), which is a design change with a large blast radius and a real false-positive risk against ordinary developer usage. A half-parser shipped under time pressure produces a gate that is **both** evadable and obstructive. The K3 principle governs the interim: a limitation that is written down is safer than one implied not to exist — an operator who knows the gate is regex-based will not treat it as a sandbox.

## Shape of the real fix (for whoever picks this up)

| Option | Sketch | Main risk |
|---|---|---|
| A — shell-aware tokenization | Parse with a real shell grammar, match rules against the *resolved* argv | Parser divergence from the executing shell; MSYS/PowerShell variance |
| B — conservative deny | Deny any command containing `eval`/command substitution/variable expansion that could reach a gated token | False positives on ordinary developer usage; pushes users toward workarounds |
| C — post-hoc | Gate at the process level (audit executed argv) instead of the command string | Not preventive; needs a host capability Flow does not have |

Prerequisite for any of them: a corpus of real developer command lines to measure the false-positive rate before shipping, and a decision on whether an evasion attempt should deny or merely warn.

## Related

- `docs/backlog/rm-rule-pattern-single-space-gap/` — a narrow pattern gap in the same file, **closed** in the corrections round (T28)
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` — the carrier-enumeration lesson
- `policies/command-policy.yml` header — the truthful statement of this limitation
- `docs/hook-coverage.md` — same statement on the coverage surface
