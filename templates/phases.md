# Phases
- reference: none

<!--
reference: the reference project for every phase (a cookbook blueprint, a project, a path) or none.
One block per phase, one table per slice. Task ids are unique across this file. Example:

## P1 Sign-in hardening
- base: pending

### P1-S1 Link expiry
| Task | Item | Does | Globs | Estimate |
|---|---|---|---|---|
| T1 | B1 | Reject magic links older than 15 minutes | `packages/core/src/auth/**` | 45m 2f |

base: the phase's base commit (7-40 hex), or pending before the phase starts.
Estimate: <minutes>m <files>f; test paths are estimated separately.
-->
