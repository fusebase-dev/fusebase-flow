# AI Developer implement handoff — msys-test-fixture-rework

## Header

| Field | Value |
|---|---|
| Ticket slug | `msys-test-fixture-rework` |
| Branch | `fix/msys-v3307-hardening` |
| Base SHA | `50ea0b1` |
| Lane | Full |
| Role | AI Developer |
| Spec | `docs/specs/msys-test-fixture-rework/spec.md` |
| Tasks | `docs/specs/msys-test-fixture-rework/tasks.md` |
| Verification gate | `docs/specs/msys-test-fixture-rework/verification-gate.md` |
| Roadmap slice | `docs/specs/msys-hardening-roadmap/roadmap.md` — S1 |
| Contract state | Locked by the operator for this handoff; do not reopen DRAFT fields |
| Pre-existing unrelated status | `?? docs/wasted-code/` — preserve; do not edit or stage |

## Task chain

| Field | Value |
|---|---|
| Commit contract | one task = one commit (`FLOW_RULES.md:10`; `docs/constitution.md:43-46`) |

| T# | Commit scope | Target files | Depends on | Acceptance | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | Add the deterministic fixture and its positive/negative self-tests | `hooks/tests/lib/minimal-path-fixture.sh` (new); `hooks/tests/test-minimal-path-fixture.sh` (new); `hooks/tests/run-tests.sh`; `audit/hook-layer-manifest.json` | — | AC2, AC7, AC9-AC10 | pending | pending |
| T2 | Migrate both consumers and relocate the direct contract | `hooks/tests/test-pre-commit-interpreter-contract.sh` (new); `hooks/tests/test-bootstrap-exception.sh`; `hooks/tests/test-git-hooks-smoke.sh`; `hooks/tests/run-tests.sh`; `audit/hook-layer-manifest.json` | T1 | AC1, AC3-AC5, AC7, AC9-AC10 | pending | pending |
| T3 | Add and register the causally constrained mutation discriminator | `hooks/tests/test-pre-commit-interpreter-mutation.sh` (new); `hooks/tests/run-tests.sh`; `audit/hook-layer-manifest.json` | T2 | AC6, AC9-AC10 | pending | pending |

Execute T1→T2→T3 serially. Use the task-local scope, commit subject, and verification blocks verbatim from `tasks.md`; do not bundle tasks or defer a broken task to the next commit (FR-03).

## Stop condition

- Stop at the verification gate after T3. Produce the full gate report from `templates/gate-report.md` plus the ticket-specific fields in `verification-gate.md`; do not substitute a summary.
- Do **not** deploy, publish, push, or run any post-gate action.
- Local scoped/full runs are developer evidence only. Hosted `workflow_dispatch` verification on T3's exact SHA is release evidence and is **not this session's job**; leave `hosted_run`/AC8 pending and do not claim gate PASS without it.

## Hard constraints

- Test scope only: edit only the T1-T3 target files (tests/fixtures/runner plus the required generated manifest). No edit to `hooks/git/pre-commit`, `.github/**`, `policies/**`, workflows, or runtime code. Copy and mutate the hook only inside isolated temporary test state (AC10).
- `hooks/tests/test-bootstrap-exception.sh` must shrink from 799 lines; every new shell file must be ≤800 lines (FR-25). Extract on the named seam `hooks/tests/lib/minimal-path-fixture.sh`; that directory already holds four fixtures, so follow their conventions. No exemption or baseline increase.
- AC6 is causal, not name-only: require (a) the unmutated baseline GREEN; (b) exactly `8-interpreter-absent-blocks` changes to FAIL in the mutant; (c) every prerequisite/control row is identical between baseline and mutant; and (d) an unmutated copy presented as mutant makes the harness fail. A named RED alone is insufficient and recreates the defect this slice removes.
- Never use `--no-verify`.
- Keep `docs/wasted-code/` untouched and unstaged. If it remains, report it as pre-existing; do not falsely call the global worktree clean.

## Verification commands

Run from the repository root. Every `hooks/tests/run-tests.sh` invocation is long: launch it through the host's background execution with the bounded wrapper below (FR-27); do not shell-detach with `&` under `bounded_run`.

```bash
bash -n hooks/tests/lib/minimal-path-fixture.sh hooks/tests/test-minimal-path-fixture.sh hooks/tests/test-pre-commit-interpreter-contract.sh hooks/tests/test-pre-commit-interpreter-mutation.sh hooks/tests/test-bootstrap-exception.sh hooks/tests/test-git-hooks-smoke.sh hooks/tests/run-tests.sh
source "$(git rev-parse --show-toplevel)/hooks/local/lib/bounded-run.sh"
bounded_run 1800 "G2 fixture and contract" -- env FF_ONLY=minimal-path-fixture,git-smoke,bootstrap-exception,interpreter-contract bash hooks/tests/run-tests.sh
bounded_run 1800 "G3 mutation discriminator" -- env FF_ONLY=interpreter-mutation bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --all
bash hooks/local/preflight.sh
git diff --name-only 50ea0b1..HEAD
git diff --exit-code 50ea0b1..HEAD -- hooks/git/pre-commit .github policies
bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code -- audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh
bounded_run 3600 "full local developer gate" -- env FF_FULL=1 bash hooks/tests/run-tests.sh
git status --short
```

Required observations and evidence fields are G1-G7 plus **Full local developer gate** in `verification-gate.md`. Do not dispatch G8 here.

## Known traps

- Deleting `exit 1` at `hooks/git/pre-commit:96` still yields a nonzero rc later via the broken empty shim. This is exactly why the oracle requires the one-row delta and negative-control clauses.
- Row 8's old fixture staged a PROTECTED path, so `rc != 0` could come from FR-07 rather than the interpreter contract. The new contract test stages a BENIGN path and proves it passes on a normal PATH first.
- A git-less mask makes the hook exit 0 at its top `rev-parse` guard—an environment artifact that reads as a fail-open.

## Definition of done

- All 10 ACs are demonstrably met; AC8 is completed only by the later exact-SHA hosted dispatch.
- The full gate report is produced; the AI Developer report leaves hosted evidence pending rather than asserting PASS.
- The ticket worktree is clean after T1-T3 and the gate report; the pre-existing `docs/wasted-code/` status is preserved and disclosed until the operator resolves it.
- T1, T2, and T3 are exactly three commits, one commit per task, with task-citing commit messages.
