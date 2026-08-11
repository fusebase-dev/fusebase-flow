# Tasks — msys-test-fixture-rework

| Field | Value |
|---|---|
| Status | DRAFT |
| T-counter going in | T0 |
| Task range | T1..T3 |
| Commit contract | one task = one commit (`FLOW_RULES.md:10`; `docs/constitution.md:43-46`) |
| Gate | `docs/specs/msys-test-fixture-rework/verification-gate.md` — no task/commit |
| Linked spec | `docs/specs/msys-test-fixture-rework/spec.md` |
| Linked decisions | none — `spec.md` Clarify summary |

## Task chain

| T# | Commit scope | Target files | Depends on | Acceptance | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | Add the deterministic fixture and its positive/negative self-tests | `hooks/tests/lib/minimal-path-fixture.sh` (new); `hooks/tests/test-minimal-path-fixture.sh` (new); `hooks/tests/run-tests.sh`; `audit/hook-layer-manifest.json` | — | AC2, AC7, AC9-AC10 | pending | pending |
| T2 | Migrate both consumers and relocate the direct contract | `hooks/tests/test-pre-commit-interpreter-contract.sh` (new); `hooks/tests/test-bootstrap-exception.sh`; `hooks/tests/test-git-hooks-smoke.sh`; `hooks/tests/run-tests.sh`; `audit/hook-layer-manifest.json` | T1 | AC1, AC3-AC5, AC7, AC9-AC10 | pending | pending |
| T3 | Add and register the causally constrained mutation discriminator | `hooks/tests/test-pre-commit-interpreter-mutation.sh` (new); `hooks/tests/run-tests.sh`; `audit/hook-layer-manifest.json` | T2 | AC6, AC9-AC10 | pending | pending |

## Per-task detail

### T1. Shared minimal-PATH fixture and self-tests

| Field | Value |
|---|---|
| Commit | `test(flow): T1 add deterministic interpreter fixture` |
| Files | `hooks/tests/lib/minimal-path-fixture.sh`, `hooks/tests/test-minimal-path-fixture.sh`, `hooks/tests/run-tests.sh`, `audit/hook-layer-manifest.json` |
| Module-size (FR-25) | No target is over 800 lines; each new responsibility-specific file remains below 800, and this task does not grow the 799-line bootstrap file (`hooks/tests/test-bootstrap-exception.sh:1-799`; `FLOW_RULES.md:32`). |
| Depends on | — |
| Acceptance | AC2, AC7, AC9-AC10 |
| Worker-undisturbed | empty configured set (`policies/protected-paths.yml:46-48`) |

**Scope:**

- Resolve absolute Git and invoking-shell paths before masking; build a minimal bin from explicit absolute shims only; never enumerate, mirror, symlink, or copy host PATH directories.
- Expose cause-specific prerequisite results for interpreter absence, Git availability, shell availability, and fixture construction.
- Add positive fixture construction coverage plus the four `spec.md` Diagnostic injection matrix cases. Each uniquely named outer assertion row captures one mapped inner failure row/reason, rejects extra failures, and emits PASS only after the expected inner rejection is proved.
- Register `minimal-path-fixture` in `FF_TAGS` and `run_shell_phase` (`hooks/tests/run-tests.sh:68-110,456-543`); leave it outside `FF_FAST_TAGS` until runtime is measured (`hooks/tests/run-tests.sh:125-127`).
- Regenerate `audit/hook-layer-manifest.json` in the same commit because its declared membership covers tests and fixtures (`audit/hook-layer-manifest.json:4-5`).

**Task-local verification:**

```bash
bash -n hooks/tests/lib/minimal-path-fixture.sh hooks/tests/test-minimal-path-fixture.sh hooks/tests/run-tests.sh
FF_ONLY=minimal-path-fixture bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --all
bash hooks/local/stamp-hook-manifest.sh
bash hooks/local/verify-hook-manifest.sh
```

### T2. Consumer migration and direct contract

| Field | Value |
|---|---|
| Commit | `test(flow): T2 migrate minimal-path fixture consumers` |
| Files | `hooks/tests/test-pre-commit-interpreter-contract.sh`, `hooks/tests/test-bootstrap-exception.sh`, `hooks/tests/test-git-hooks-smoke.sh`, `hooks/tests/run-tests.sh`, `audit/hook-layer-manifest.json` |
| Module-size (FR-25) | Remove the missing-interpreter PATH responsibility from the 799-line `test-bootstrap-exception.sh`; that file must shrink, and every target remains at or below 800 lines (`hooks/tests/test-bootstrap-exception.sh:1-799`; `FLOW_RULES.md:32`). |
| Depends on | T1 |
| Acceptance | AC1, AC3-AC5, AC7, AC9-AC10 |
| Worker-undisturbed | empty configured set (`policies/protected-paths.yml:46-48`) |

**Scope:**

- Move row 8 into `test-pre-commit-interpreter-contract.sh`; preserve `8-interpreter-absent-blocks` and `8-interpreter-absent-block-message`.
- Capture stderr and rc from one hook invocation; stage a benign non-protected file; add the same-state normal-PATH PASS control.
- Delete the bootstrap and git-smoke host-directory mirror loops and 2000-entry caps; both consumers source `minimal-path-fixture.sh`.
- Replace `nopy_precondition` with cause-specific git-smoke diagnostics and run the `spec.md` Diagnostic injection matrix; each uniquely named outer assertion row captures one mapped inner failure row/reason, rejects extra failures, and emits PASS only after the expected inner rejection is proved (`hooks/tests/test-git-hooks-smoke.sh:109-130`).
- Register `interpreter-contract` in `FF_TAGS` and `run_shell_phase` (`hooks/tests/run-tests.sh:68-110,456-543`); leave it outside `FF_FAST_TAGS` until runtime is measured (`hooks/tests/run-tests.sh:125-127`).
- Regenerate `audit/hook-layer-manifest.json` in the same commit (`audit/hook-layer-manifest.json:4-5`).

**Task-local verification:**

```bash
bash -n hooks/tests/lib/minimal-path-fixture.sh hooks/tests/test-minimal-path-fixture.sh hooks/tests/test-pre-commit-interpreter-contract.sh hooks/tests/test-bootstrap-exception.sh hooks/tests/test-git-hooks-smoke.sh hooks/tests/run-tests.sh
FF_ONLY=minimal-path-fixture,git-smoke,bootstrap-exception,interpreter-contract bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --all
bash hooks/local/stamp-hook-manifest.sh
bash hooks/local/verify-hook-manifest.sh
```

### T3. Missing-interpreter exit mutation discriminator

| Field | Value |
|---|---|
| Commit | `test(flow): T3 mutation-test missing-interpreter block` |
| Files | `hooks/tests/test-pre-commit-interpreter-mutation.sh`, `hooks/tests/run-tests.sh`, `audit/hook-layer-manifest.json` |
| Module-size (FR-25) | New responsibility-specific test file; no growth to `test-bootstrap-exception.sh`; every target remains at or below 800 lines (`FLOW_RULES.md:32`). |
| Depends on | T2 |
| Acceptance | AC6, AC9-AC10 |
| Worker-undisturbed | empty configured set (`policies/protected-paths.yml:46-48`) |

**Scope:**

- Copy `hooks/git/pre-commit` into isolated baseline and mutant states; match the diagnostic-adjacent `exit 1` exactly once and fail on zero or multiple matches (`hooks/git/pre-commit:93-96`).
- Require the unmutated baseline copy to run GREEN before mutation.
- Require the mutant to make exactly `8-interpreter-absent-blocks` FAIL while every prerequisite/control row remains identical to baseline.
- Present a separate unmutated copy to the mutation harness as a negative control and require the harness itself to fail; an undetected mutant cannot be accepted.
- Keep production `hooks/git/pre-commit` byte-unchanged; register `interpreter-mutation` last in `FF_TAGS` and `run_shell_phase` (`hooks/tests/run-tests.sh:68-110,456-543`), outside `FF_FAST_TAGS` pending runtime measurement (`hooks/tests/run-tests.sh:125-127`).
- Regenerate `audit/hook-layer-manifest.json` in the same commit (`audit/hook-layer-manifest.json:4-5`).

**Task-local verification:**

```bash
bash -n hooks/tests/test-pre-commit-interpreter-mutation.sh hooks/tests/run-tests.sh
FF_ONLY=interpreter-contract,interpreter-mutation bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --all
bash hooks/local/stamp-hook-manifest.sh
bash hooks/local/verify-hook-manifest.sh
```

## Task chain audit

| Check | Mapping |
|---|---|
| Every AC mapped | AC2/AC7/AC9-AC10 → T1; AC1/AC3-AC5/AC7/AC9-AC10 → T2; AC6/AC9-AC10 → T3; AC8 → hosted gate |
| Every task is one commit | T1, T2, and T3 each define one commit subject |
| Every task names target files | T1-T3 `Files` fields |
| 799-line target shrinks | T2 removes the fixture and row-8 contract from `test-bootstrap-exception.sh`; T1/T3 do not touch it |
| No production fail-open edit | No task targets `hooks/git/pre-commit` |
| Serial mutation registration | T3 depends on T2 and owns the final runner/manifest registration |
| Manifest freshness per commit | `audit/hook-layer-manifest.json` belongs to T1-T3 |
