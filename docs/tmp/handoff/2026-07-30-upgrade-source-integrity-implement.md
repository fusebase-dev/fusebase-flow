# Implement handoff — upgrade-source-integrity-and-observability (T1..T7)

## Role bootstrap

You are the **AI Developer** under Fusebase Flow v4.7.0. Self-attest per `FLOW_RULES.md` § Self-attestation, naming the IM.1..IM.18 role section.

As a delegated sub-agent you inherit **no** auto-loaded skills and **not** the always-on write-time digest. Read yourself: `FLOW_RULES.md` (stop at `## Amendment log`), `flow-skills/role-discipline/SKILL.md`, `flow-skills/role-discipline/references/ai-developer.md`, `flow-skills/communication/SKILL.md`, `flow-skills/comment-policy/SKILL.md`, `flow-skills/module-size-discipline/SKILL.md`.

Load-bearing rules: FR-03 (one task = one commit), FR-05 (stop at gate), FR-07, FR-10 (reproduce before fix), FR-13, FR-27 (never launch bare), FR-24 digest.

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md`
2. `AGENTS.md` project section
3. `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md` — the consumer report this comes from
4. `docs/specs/upgrade-source-integrity-and-observability/decisions.md` — **M1..M10**; M1 and M6 are REVISED, M9/M10 are new
5. `docs/specs/upgrade-source-integrity-and-observability/tasks.md` — T1..T9
6. `docs/specs/upgrade-source-integrity-and-observability/verification-gate.md` — AC1..AC9, § Regression discriminators, § Review gate
7. `docs/specs/upgrade-source-integrity-and-observability/spec.md`
8. `policies/protected-paths.yml` — read it yourself; the FR-07 map in the gate was wrong once already
9. `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — five catalogued MSYS-vs-Linux pitfalls, one of which is this ticket's direct ancestor

---

## Ticket header

| Field | Value |
|---|---|
| Slug | `upgrade-source-integrity-and-observability` |
| Task range (this handoff) | **T1..T7** — stop at the gate |
| Do NOT run | T8 (reviews, PO-dispatched), T9 (release) |
| Decisions | M1..M10, all LOCKED |
| Branch | `fix/msys-v3307-hardening` — do not switch |
| Discriminator baseline | `85b97dd` |
| Current HEAD | `a44962c` |

---

## Pre-cached identifiers

| Identifier | Value |
|---|---|
| Full gate (unscoped) | `bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && python3 hooks/tests/run_hook_tests.py --compare-subprocess && bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh` |
| Managed manifest | `bash hooks/local/stamp-managed-content-manifest.sh && git diff --exit-code audit/managed-content-manifest.json && bash hooks/local/verify-managed-content-manifest.sh` |
| Baseline suite | 666/666 at `85b97dd` on Windows; Linux container 663/663 |
| Test tags | `FF_TAGS` array in `hooks/tests/run-tests.sh` (~line 44-49) — register any NEW test file or it never runs |
| Fixture count | `EXPECTED_HANDLER_FIXTURES` in `run_hook_tests.py` — bump only if you add handler fixtures (T1..T6 should not) |
| Module size | `bash hooks/local/check-module-size.sh --all` · ceiling 800 · **`upgrade.sh` is at 790** |
| Docker | v29.6.1 available for the mandatory Linux parity run |

---

## FR-07 posture — verified, use this

Protected (`policies/protected-paths.yml:84-93`): `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`.

**Not** protected: `hooks/local/**`, `hooks/tests/**`, `audit/**`.

So: **T5** needs the FR-07 bootstrap approval (`hooks/shared/policy_loader.py`, `policies/approval-policy.yml`) and **T6** needs it (`policies/command-policy.yml`). T1/T2/T3/T4 do **not** — they touch only hook-local, tests and manifests. Verify this yourself before assuming it; an earlier draft of this plan asserted the opposite and was wrong.

Cycle when required: `bash hooks/local/write-bootstrap-approval.sh` → commit → `--consume`. **Never `--no-verify`** (hard policy deny).

---

## Execution order — serialization matters

T1, T2, T5 may start independently. **T3 serializes after T1** (both edit `upgrade.sh`). **T4 serializes after T1** (both edit `hook-integrity-check.sh`). All *commits* serialize because T1..T6 each restamp the manifests. There is no "different files, no shared edits" safety here — that claim was removed from the plan as false.

Recommendation: run strictly T1 → T2 → T3 → T4 → T5 → T6. Parallelism buys little and manifest collisions cost more.

---

## The discipline that matters most

**Write the failing assertion first.** `verification-gate.md` § Regression discriminators names, for each of T1..T5, the assertion that must be observed **RED at `85b97dd`** before the fix, plus negative controls that must stay green. This is a contract, not advice: the previous release passed 649/649 and 665/666 while hiding a live gate bypass and a Linux failure respectively.

T1's discriminator specifically requires a **synthetic two-commit upstream** — do not depend on real repository history before `601574d`, it may not be reachable in a fixture.

**Linux parity is mandatory before you report the gate.** Docker is available; the container recipe is in the problem-catalog entry. The last release tagged on a green MSYS suite and went red on Linux CI within minutes. A green Windows run alone does not satisfy T7.

---

## Comment policy (FR-22)

```
COMMENT POLICY (FR-22) — applies to all code you write:
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision M1)".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```

**Tripwires this ticket requires** — each is a constraint whose violation is silent and expensive:

| Location | Content |
|---|---|
| materialization archive call | incoming `U` is forced `core.autocrlf=false`; inheriting consumer EOL recreates F2 (decision M1) |
| K13 base synthesis archive call | `B` keeps the **consumer's** EOL deliberately; forcing LF here misclassifies untouched CRLF files (decision M1) |
| `SOURCE_REPO` declaration | metadata/ref-resolution only — every content read uses `SOURCE_TREE` (decision M1) |
| heartbeat helper | tempfile capture is retained on purpose; `tee`/pipe reintroduces the MSYS inherited-pipe hang (decision M3) |
| cleanup authority list | exact stem membership, never string-prefix matching (decision M5) |
| integrity hashing functions | byte-exact by design; normalizing would hide transport corruption (decision M2) |

Emit `comment-policy review: applied (FR-22)` when your code passes.

---

## Stop at gate

Produce the T7 gate report from `templates/gate-report.md` (fields per `policies/gate-contracts.yml: gate_report`), **unscoped** run only, citing `state/audit/hook-test-results.md` — never the scoped file. Include the Linux container result. Then **halt**. Do not run T8 or T9, do not touch `VERSION`, do not touch the `v4.7.0` tag.

---

## Per-commit pre-attestation

```
T<n> pre-commit check:
☐ Discriminator written FIRST and observed RED at 85b97dd
☐ Negative controls pass
☐ Preflight / bash -n / python ast clean
☐ Relevant test phase green
☐ Both manifests restamped and staged (if a covered path changed)
☐ Mirrors regenerated (only if flow-skills/agents/overlay changed)
☐ One task scope
☐ No TODO/FIXME/WIP
☐ Comments: tripwire + pointer only (FR-22)
☐ Module size clean — upgrade.sh at 790/800, logic goes in the new lib
☐ FR-07 approval minted IF this task touches a protected path (T5, T6 only)
☐ Commit message cites T<n>
```

---

## State announcement (every reply)

```
---
📍 Phase: Implement
🎯 Ticket: upgrade-source-integrity-and-observability
✅ Completed: T1..T<n-1> (<SHAs>)
📍 Current: T<n>
⏭️ Next: <next task OR "gate T7">
```

---

## Notes / context (PO-authored)

**Where this came from.** A consumer upgraded 4.5.0 → 4.7.0 on Windows and needed seven manual interventions. Their report had 8 findings; an adversarial scope review cut it to 4 real ones and **corrected the root cause of the most important**. Then an adversarial review of my plan found 4 BLOCKERs in it. You are executing the third pass. The file:line citations have been verified twice — but if one is wrong, say so rather than working around it.

**Three findings need no code, deliberately.** F1 and F3 were the last run of the **4.5** engine, not 4.7.0 behaviour — `upgrade.sh:237-249` already drives the managed set through `list-managed` and the K9 classifier already preserves consumer-modified policy files. F4 is refuted: `merge-module-size-baseline.sh:95-103` dedupes by path. Do **not** write code for these; a test that passes at HEAD is the tautology the contract forbids. If you find evidence any of them IS live at HEAD, stop and report — that would change the scope.

**F7 is deliberately deferred** (M8). Do not attempt to narrow command-policy matching. Every proposed narrowing is unsafe: `git commit -m "$(rm -rf /)"` executes the substitution before git runs, and argv-splitting worsens the K21 quote-fragmentation evasion. T6 only documents the limitation and points at `git commit -F`.

**The one thing most likely to go wrong.** T1's byte model has two *opposite* requirements that look like one: incoming `U` must be forced LF, K13's base `B` must keep the consumer's EOL. My first draft collapsed them and would have recreated the exact bug being fixed. Read M1's table before writing the archive calls, and put a tripwire on each.

**Second most likely.** T1 is not a one-line change. `upgrade.sh` reads source content in ~10 places (enumerated in T1's scope). Missing one leaves a path still reading the mutable worktree, and the discriminator may still pass because the *fixture's* path happens to be converted. Convert them all, then grep for any remaining `SOURCE_CLONE` content read.

**Scope stays closed.** No hasher normalization (M2), no `tee` (M3), no `.gitattributes` edits (the pins are already correct), no secret-scan exclusion (M4 — the reporter's premise there is false and a bypass would create a hole), no FR-06 exception for `rm -rf` (M5 — narrow the tool, not the guard).

**If a finding turns out wrong, say so with evidence** rather than implementing a fix for a non-defect. Two reviews have already overturned claims in this chain, including two of mine.
