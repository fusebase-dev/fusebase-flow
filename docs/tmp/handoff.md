# Active handoff — Flow v5 simplification, ready to execute

**Updated:** 2026-08-05 · **Branch:** `fix/msys-v3307-hardening` · **`origin/main`:** `3608271` · **VERSION:** 4.7.1
**Shipped and live:** v4.7.0 (`bad4d92`) and v4.7.1 — both published, both untouched by anything below.

## Start here

1. `docs/north-star.md` — **locked 2026-08-05**. Flow is for **solo builders and small teams who want low friction**. This is the anchor; without it the roadmap below is unfalsifiable, and that is not hypothetical — a simplification proposal was drafted and could not be validated because this file did not exist.
2. `docs/tmp/handoff/2026-08-05-v5-roadmap.md` — the 11-slice roadmap, ordered by `(evidence × consumer pain) / migration risk`. Sections: slice list · risk-classification contract · enforcement-honesty table · per-rule FR-01..FR-27 disposition · do-not list · measurement plan.
3. `docs/maintainer-execution.md` — **how to run work here**. Maintainer-side, not Flow product. Read it before starting; it is the fix for the 76% of elapsed time that was decision latency.

## Execution order

| Seq | Slice | Note |
|---:|---|---|
| 0 | **C0** — lock the executable contracts | One decision packet *before* any code. Includes the classifier spec, the final-candidate SHA contract, the one-file Full-lane shape. **Do this first.** |
| 1 | S1 — bind release readiness to the exact candidate SHA | Narrowest, best-evidenced. Closes the closeout-commit gap hit on 2026-08-03 |
| 2 | S2 — local gate matches CI freshness checks | |
| 3 | **S3 — deterministic risk classifier; Lightweight becomes default** | The keystone. Ships `policies/risk-classification.yml` — a file, not a principle |
| 4 | S4 — close the approval-expiry fail-open | The live open deploy gate a consumer measured |
| 5 | **M1 — instrument the ordinary-consumer baseline** | **Runs BEFORE the big cuts on purpose.** It can falsify the roadmap while changing course is still cheap |
| 6-10 | S5..S9 — one-file tickets · approval backends · enforcement honesty · rules → 8 invariants · core/optional packaging | The simplification proper |

## Non-negotiables

- **The safety kernel is KEEP**, per the North Star: adversarial review on security/upgrade/data/release surfaces, release publication gated on the exact verified SHA, FR-06, FR-07, fail-closed secret scanning, per-file three-way upgrade classification, the problem catalog. Low friction means less ceremony per unit of safety — not less safety.
- **Corrected numbers are binding.** 46 days (not 38), 19 spec files (not "17 Full"), ceremony audit `0 confirmed / 1 dismissed / 5 inconclusive` (not "zero firings"). The refuted versions must not reappear.
- **Do not re-litigate the audience.** It is locked. Work that only pays off for regulated-team auditability or maintainer tooling is out of scope.

## The two failure modes this repo actually has

1. **Undecided contracts.** `docs/problem-catalog/undecided-contract-drives-repeat-defects/` — a review round whose findings sit inside the *previous round's fix* means the contract is undecided. Stop implementing and decide it. This fired three times before it was honoured; overriding it on a "the list is converging" argument was wrong both times it was tried.
2. **Claims wider than the thing they describe.** `approval_authors` documented as enforced and never implemented; release notes ahead of code; test names ahead of predicates; a surfacing tool that could not see the artifact it existed to surface. Assume it is present and grep for it — three green gates produced three NO-SHIPs on one feature.

## Open, filed, unstarted

`docs/backlog/`: `gate-bounds-lack-headroom` (schedule before the next release — a bound has been crossed four times) · `compat-approval-surfacing` (parked, needs the carrier table) · `self-granting-health-deferral` · `command-gate-shell-evasion` · `approval-single-use-consumption` · `approval-binding-omits-head` · `rm-rule-pattern-single-space-gap` · `provenance-and-single-seam-guarantees`.

Not a Flow ticket: the Paperclip host report (`paperclip+hermes-v1`, different product) — three transferable lessons already extracted into `provenance-and-single-seam-guarantees`.

## Operational

Two-platform gating (Windows unscoped + Linux `ubuntu:24.04` container) before any release claim — a green MSYS run alone has been wrong twice. Before diagnosing a timing FAIL, check for a competing suite via Win32 `CommandLine` (`ps -W` alone misses it). Write long-running agent output to `c:/tmp/`, not the session scratchpad. Never `--no-verify`. FR-07 protected: `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` only.
