# Spec — msys-test-fixture-rework

| Field | Value |
|---|---|
| Status | DRAFT |
| Scope lock | not locked — operator confirmation pending |
| Created | 2026-08-10 |
| Change tier | Full |
| Documentation tier | 3 — spec + tasks + Full-lane gate |
| Linked decisions | none — operator supplied the fixture, mutation, and scope boundaries; no `decisions.md` |
| Deploy hash | N/A — this repository is a framework/template, not a deployed app (`docs/constitution.md:35-37`) |

## Problem

The absent-interpreter assertions added by `bd47aed` and `800bf36` do not prove the missing-interpreter branch: deleting `hooks/git/pre-commit:96` leaves both rows green because the block message is emitted first, the empty interpreter command later fails, stderr and rc come from separate hook invocations, and the staged path is independently protected (`hooks/git/pre-commit:87-96,213`; `hooks/tests/test-bootstrap-exception.sh:292,299-300`; `policies/protected-paths.yml:84-101`).

The two consumers construct interpreter-less PATHs by mirroring host directories, duplicate the same host-dependent mechanism, and impose a 2000-entry host cap (`hooks/tests/test-bootstrap-exception.sh:255-290`; `hooks/tests/test-git-hooks-smoke.sh:78-114`). `test-git-hooks-smoke.sh` also merges oversized-directory, interpreter-leak, and missing-git failures into one boolean (`hooks/tests/test-git-hooks-smoke.sh:109-114`).

## Why now

The current branch labels the four rows fixed at `6ffd8da`, while the active handoff records only local green and says the hosted Windows runner has not been rerun (`docs/tmp/handoff.md:33-38`). A wrong-layer green cannot be used as hardening evidence until the missing-interpreter exit is mutation-sensitive (`bd47aed`; `800bf36`; `6ffd8da`).

## In scope

- Extract one shared minimal-PATH fixture to `hooks/tests/lib/minimal-path-fixture.sh`; resolve the real Git executable and shell before masking, expose only explicit absolute shims, and do not mirror or copy host PATH directories (`hooks/tests/test-bootstrap-exception.sh:255-290`; `hooks/tests/test-git-hooks-smoke.sh:78-108`).
- Move the direct missing-interpreter contract into `hooks/tests/test-pre-commit-interpreter-contract.sh`; retain named rows `8-interpreter-absent-blocks` and `8-interpreter-absent-block-message`, and remove the duplicated row-8 mask from the 799-line bootstrap file (`hooks/tests/test-bootstrap-exception.sh:255-300`; `FLOW_RULES.md:32`).
- Make one hook invocation supply both stderr and rc; use a benign staged path with a normal-PATH pass control so another gate cannot satisfy the assertion (`hooks/tests/test-bootstrap-exception.sh:292,299-300`; `policies/protected-paths.yml:23-101`).
- Refactor the git-smoke missing-interpreter row to consume the shared fixture and report each precondition independently (`hooks/tests/test-git-hooks-smoke.sh:74-130`).
- Add a registered mutation harness that proves an unmutated temporary hook copy is GREEN, deletes the one unique missing-interpreter `exit 1`, requires exactly `8-interpreter-absent-blocks` to FAIL while prerequisite/control results stay identical, and rejects an unmutated negative control (`hooks/git/pre-commit:93-96`).
- Register the fixture self-test, direct contract, and mutation tests in the full/scoped runner and refresh the hook-layer manifest, which covers tests and fixtures (`hooks/tests/run-tests.sh:68-110,456-543`; `audit/hook-layer-manifest.json:4-5`).

## Non-goals

- Production fail-open when Git is unavailable is a separate slice; this slice does not edit `hooks/git/pre-commit:20`.
- Production interpreter trust is a separate slice; this slice does not change discovery at `hooks/git/pre-commit:87` or add positive-verdict artifacts for Python controls at `hooks/git/pre-commit:213,316,503,678`.
- The preflight missing-Python residual is a separate slice; this slice does not edit `hooks/local/preflight.sh:42`.
- No workflow-trigger, CI-shim, timeout, release, UI, database, account, or app-deploy behavior changes (`.github/workflows/fusebase-flow-verify.yml:3-21,92-104`; `docs/constitution.md:35-37`).

## Acceptance criteria

1. **AC1 — one fixture seam.** `hooks/tests/lib/minimal-path-fixture.sh` is the only missing-interpreter PATH constructor used by the contract and git-smoke tests; the host-directory mirror loops and 2000-entry caps are absent from `hooks/tests/test-bootstrap-exception.sh` and `hooks/tests/test-git-hooks-smoke.sh` (`hooks/tests/test-bootstrap-exception.sh:255-290`; `hooks/tests/test-git-hooks-smoke.sh:78-108`).
2. **AC2 — deterministic prerequisites.** The shared fixture resolves Git and the invoking shell before masking, creates explicit absolute shims, proves `python3`, `python`, and `py` are absent, and proves Git plus the shell remain executable. Its self-test injects every Diagnostic injection matrix cause; each outer assertion row passes only after capturing exactly its one cause-specific inner failure row/reason.
3. **AC3 — one-invocation attribution.** `8-interpreter-absent-blocks` and `8-interpreter-absent-block-message` derive rc and stderr from the same hook invocation; PASS requires nonzero rc and `no supported Python 3.10+ interpreter found` in that invocation's stderr (`hooks/git/pre-commit:93-96`; `hooks/tests/test-bootstrap-exception.sh:299-300`).
4. **AC4 — wrong-reason guard.** The direct contract stages only a benign, non-protected path, proves that same staged state passes with the normal PATH, then proves it blocks under the fixture PATH; a protected-path denial cannot satisfy either absent-interpreter row (`policies/protected-paths.yml:23-101`; `hooks/tests/test-bootstrap-exception.sh:292`).
5. **AC5 — independent git-smoke diagnosis.** The git-smoke adapter exercises every Diagnostic injection matrix cause; each outer assertion row passes only after capturing exactly its one cause-specific inner failure row/reason, and no merged precondition boolean can convert one cause into another (`hooks/tests/test-git-hooks-smoke.sh:109-130`).
6. **AC6 — causally constrained mutation sensitivity.** The mutation target is the one unique `exit 1` following the missing-interpreter diagnostic; zero or multiple matches fail. The harness requires: (a) the unmutated baseline copy is GREEN; (b) the mutant copy makes exactly `8-interpreter-absent-blocks` FAIL; (c) every prerequisite/control row is identical between baseline and mutant; and (d) presenting an unmutated copy as the mutant makes the harness itself fail (`hooks/git/pre-commit:93-96`).
7. **AC7 — hosted-path independence.** The fixture does not enumerate, mirror, symlink, or copy entries from PATH directories; the Windows `python3` provisioning directory therefore needs no special exclusion (`.github/workflows/fusebase-flow-verify.yml:92-104`).
8. **AC8 — required-platform proof.** A `workflow_dispatch` run on the exact implementation SHA reports GREEN for `verify-linux`, `verify-windows-msys`, and `verify-gate`; a push/PR is not accepted as evidence because the workflow has only `workflow_dispatch` and `workflow_call` triggers (`.github/workflows/fusebase-flow-verify.yml:3-21,35-58,209-230`).
9. **AC9 — module-size ratchet.** `test-bootstrap-exception.sh` shrinks from its current 799 lines, every new shell file remains at or below the 800-line ceiling, and `bash hooks/local/check-module-size.sh --all` is GREEN (`hooks/tests/test-bootstrap-exception.sh:1-799`; `FLOW_RULES.md:32`).
10. **AC10 — test-only production scope.** The implementation diff contains no change to `hooks/git/pre-commit`, `.github/**`, `policies/**`, or workflow/runtime code; the hook is copied and mutated only inside temporary test state.

### Diagnostic injection matrix

| Injected cause | Fixture self-test assertion row | Git-smoke assertion row | Required captured inner reason |
|---|---|---|---|
| Interpreter leakage | `fixture-negative-interpreter-leakage` | `git-smoke-negative-interpreter-leakage` | `interpreter leakage` |
| Missing Git | `fixture-negative-missing-git` | `git-smoke-negative-missing-git` | `Git unavailable` |
| Missing shell | `fixture-negative-missing-shell` | `git-smoke-negative-missing-shell` | `shell unavailable` |
| Fixture-construction failure | `fixture-negative-construction-failure` | `git-smoke-negative-construction-failure` | `fixture construction failed` |

Each outer row is PASS only when the injected inner call is non-GREEN with exactly the mapped row/reason and no other failure; uncaptured top-level `FAIL:` output fails G2.

## Constraints

| Constraint | Required posture | Evidence |
|---|---|---|
| Role boundary | Product Owner writes planning artifacts only; AI Developer owns T1-T3 | `FLOW_RULES.md:40-45` |
| Commit boundary | T1, T2, and T3 are separate commits | `FLOW_RULES.md:10`; `docs/constitution.md:43-46` |
| Module size | Extract the fixture on a named responsibility seam; no exemption or baseline increase | `FLOW_RULES.md:32`; `hooks/tests/test-bootstrap-exception.sh:1-799` |
| Worker-undisturbed | No configured worker-undisturbed paths; implementation still reports the check | `policies/protected-paths.yml:46-48` |
| Protected paths | Planned edits do not touch the protected `hooks/handlers/**`, `hooks/shared/**`, or `hooks/git/**` paths | `policies/protected-paths.yml:84-101` |
| Release evidence | Local scoped/full runs are developer evidence only; hosted exact-SHA verification is required | `hooks/tests/run-tests.sh:4-8`; `.github/workflows/fusebase-flow-verify.yml:3-21` |

## Risks

| Risk | Mitigation | Acceptance |
|---|---|---|
| A retained interpreter makes the test exercise discovery | Independent absence checks fail the row before hook invocation | AC2, AC5 |
| A missing utility or Git produces the asserted nonzero rc | Absolute Git/shell shims, normal-PATH control, and message attribution | AC2-AC4 |
| The mutation harness accepts unrelated RED or cannot detect an undetected mutant | Unique target, GREEN baseline, exact one-row delta, identical controls, and unmutated negative control | AC6 |
| Fixture extraction is replaced by another monolith | Named new seam plus full module-size scan | AC1, AC9 |
| Linux-only green hides Windows PATH behavior | Required exact-SHA two-platform dispatch | AC8 |

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Remedy layer | One shared minimal-PATH fixture plus mutation sensitivity; operator-supplied | 2026-08-10 |
| Production fail-opens | Separate slice; explicitly out of scope | 2026-08-10 |
| Release evidence | Hosted `workflow_dispatch`; push/PR triggers nothing | 2026-08-10 |

No real decisions: the operator supplied the implementation boundary and required proof; no `decisions.md` is created.

## Related

- `docs/specs/msys-test-fixture-rework/tasks.md`
- `docs/specs/msys-test-fixture-rework/verification-gate.md`
- `docs/specs/msys-hardening-roadmap/roadmap.md`
