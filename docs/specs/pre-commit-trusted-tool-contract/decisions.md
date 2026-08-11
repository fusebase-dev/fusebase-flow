# Trusted-tool contract decisions

**Status:** `A2 LOCKED; B1 CLOSED - NOT BUILT`. Both operator-decided on 2026-08-11: A2 locked for implementation, B1 closed as path (a) after the DO-NOT-BUILD review. T1/S2d and T2/S2b may proceed; S2c does not exist as work.

| Decision | Status | Implementation effect |
|---|---|---|
| A2 - independent repository-context evidence | `LOCKED` | T2 authorized subject to `spec.md` compatibility/termination contract. |
| B1 - per-control positive verdict | `CLOSED - NOT BUILT` (operator, 2026-08-11) | No S2c task, gate row, helper, verdict artifact, nonce or control ID exists or may be created. The per-control `rc == 0` contract stands unchanged. |

**Reviving B1 requires a changed threat model, not a new implementation idea.** It was closed because a PATH-controlling same-principal attacker can read the nonce and fabricate the verdict, so the mechanism cannot deliver the guarantee its name implies — not because the design was rough. A smaller or cleverer protocol under the same model is the same decision and must be refused on this record.

North-star result: retain A2's concrete fail-closed mechanism; withhold B1 because its mechanism cost exceeds its modeled same-principal benefit (`docs/north-star.md:18,31-34`).

## D-A - Git resolution versus genuine non-repository execution

### Statement

`hooks/git/pre-commit:20-24` maps both unusable Git in repository context and genuine outside-repository execution to `exit 0`, preventing later controls from running.

### Locked threat model

| Dimension | Locked input |
|---|---|
| Adversary | Same-principal caller can shape `PATH` and workspace-controlled inputs. |
| Boundary | Repository discovery runs before Python sanitization; empty `ROOT` exits 0. |
| Limit | Workspace-local evidence detects context/faults but cannot authenticate Git against that principal. |

### Options retained at lock

| Option | Outcome | Rejection / limit |
|---|---|---|
| A1 - fail closed on every query failure | Blocks every empty/nonzero root query. | Breaks genuine outside-repository execution. |
| **A2 - independent repository-context evidence** | Repository evidence + unusable Git BLOCKS; proven no-context execution skips. | Locked choice; still forgeable by the same principal. |
| A3 - explicit outside-repo opt-out | Default BLOCK with caller opt-out. | Adds an unauthenticated bypass contract. |
| A4 - accept/document | Keeps current behavior. | Leaves ordinary missing/broken-Git fail-open behavior. |

### Locked decision

**A2 remains LOCKED.** T2 must implement `spec.md`'s complete compatibility matrix and search-termination rule. A2 is repository-context/Git fault detection only; it is not Git authentication, binary verification, or a trust root.

## D-B - Python positive-verdict protocol

### Reopened finding

**B1 is REOPENED - operator decision required.** Under the locked same-principal threat model, B1 catches only a naive zero-exit stub. The modeled PATH-controlling attacker can read the nonce and artifact path and fabricate the expected verdict. That limited benefit would cost four producer/consumer seams, temp-artifact lifecycle, concurrency handling, and possibly trusted-helper bootstrap inside a 731-line consumer hook.

### Implementation-fatal lifecycle conflict

`hooks/git/pre-commit` deletes `SEC_TMP` and `FR07_TMP` immediately after each Python call and before acting on rc (`hooks/git/pre-commit:316-320,678-682`). A verdict placed in either natural per-control directory would therefore be deleted before validation; every commit with staged changes would BLOCK. This is a reason not to build B1 as specified, not an implementation detail to improvise around.

### Decision — path (a), closed 2026-08-11

| Path | Scope | Security claim | Outcome |
|---|---|---|---|
| **(a) Drop B1 entirely** | Keep the existing per-control `rc == 0` contract and the existing mitigations unchanged. | None; same-principal interpreter integrity stays outside the model and is documented as such. | **CHOSEN by the operator.** |
| (b) Narrow accidental completion-fault detection | A materially smaller protocol for accidental/non-cooperating completion faults only. | Explicitly not a security control. | Rejected with (a): a control that exits 0 without doing its work is a defect in that control, caught by its own tests — not worth a permanent runtime protocol in a consumer-shipped hook. |

No S2c task, gate row, helper, verdict artifact, nonce or control ID exists. What remains in force from this analysis is the **prohibition**, not a deferred plan: nothing in this repository may describe `rc == 0` from a Python control, or any future local artifact, as proof that the control ran or that the interpreter is genuine.

## S2d implementation contract - no operator decision open

| Item | Required resolution |
|---|---|
| Probe | Attempt bounded `python3 -S -c` first. |
| Backward compatibility | A wrapper that supports existing `-S <file>` but rejects/mishandles `-c` must remain usable through bounded trusted file-script fallback. |
| Consumer requirement | `python3 -S -c` support is NOT required; Python >=3.10 and existing `-S <file>` behavior remain required. |
| Failure evidence | Preserve bounded stderr and rc/timeout attribution; do not discard diagnostic output. |
| Budget | <=10 seconds per attempt; <=20 seconds total. |

## What must NOT be done

- Do not implement S2c/B1 under the former lock or describe its rejected nonce/artifact protocol as security.
- Do not call A2/S2d a genuine-interpreter check, verified-binary check, identity assurance, unforgeable proof, authentication, tamper-proofing, or a trust root.
- Do not place a helper in the same commit that first requires committed-HEAD materialization; T1/T2 remain inline and <=800 or planning stops for a prior helper task.
- Do not weaken environment sanitization, `-S`, controlled `PYTHONPATH`, file-script wrappers, shell sentinels, or trusted-HEAD extraction.

Next decision: operator chooses B1 path (a) or (b) separately; that choice does not block authorized T1/T2 implementation.
