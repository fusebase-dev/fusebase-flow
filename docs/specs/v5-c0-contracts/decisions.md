# Decisions — v5-c0-contracts (C0: lock the executable contracts)

**Letter prefix:** A
**Approval status:** PENDING all locks
**Linked roadmap:** `docs/tmp/handoff/2026-08-05-v5-roadmap.md` seq 0
**Scope rule:** roadmap seq 0 names SIX contracts (A1–A8 below cover them). **A9 is an addition beyond that list** and can be dropped without affecting any other decision.
**Blocking:** no roadmap implementation begins until A1–A8 are LOCKED or REDIRECTED.

## Why this exists

2026-08-05: three backlog fixes were implemented before this packet existed. Independent adversarial review returned `STOP-AND-ZOOM-OUT`; all three were reverted (`5f8004f`). Two failures trace directly to contracts that are undecided here:

| Failure | The decision that was missing |
|---|---|
| All three self-classified "Lightweight"; FR-21 and F05 make them Full | **A2** — observable triggers instead of agent judgement |
| A malformed authorization object was made warning-only, by guess | **A7** — warn vs fail-closed is policy, not an implementer's call |

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| A1 | Classifier outcomes; Lightweight is default | Adopt roadmap §2.1 verbatim — 3 outcomes, no `UNCERTAIN` | PENDING |
| A2 | Full triggers F01–F11 + thresholds | Adopt §2.3; F09 at 8 files / 400 lines / 2 components | PENDING |
| A3 | Override contract | Adopt §2.6 — F01–F07 + protected F08 non-waivable | PENDING |
| A4 | Final-candidate SHA + what counts as release proof | Adopt §S1 receipt, **plus** scope recorded in the receipt | PENDING |
| A5 | One-file Full-lane `ticket.md` | Adopt; dual-read legacy for one major release | PENDING |
| A6 | Approval backends | Adopt `host` / `chat_record` / `artifact_v2` | PENDING |
| A7 | Enforcement vocabulary + malformed-control severity | Adopt H\*/G\*/C/P, **and** reject-whole + `BROKEN` for malformed control objects | PENDING |
| A8 | Compatibility window | One major release, deprecation-warned | PENDING |
| A9 | *(optional, beyond seq 0)* Bound policy: stall deadline + ceiling | Adopt; replaces single-scalar walls | PENDING |

---

## A1. Classifier outcomes; Lightweight is the default

**Recommendation:** Adopt roadmap §2.1 unchanged. Exactly three outcomes — `0 LIGHTWEIGHT` (default), `10 FULL`, `2 INPUT_INVALID`. No `UNCERTAIN`, and no "in doubt → Full" branch. Invalid input blocks with a repair message; it is never silently converted to Full.

**Reasoning:** North Star locks Lightweight as the default lane ([north-star.md:16](docs/north-star.md#L16)) and names "in doubt → Full" as the mechanism that turned uncertainty into ceremony. The current rule still sends doubt to Full ([lightweight-lane/SKILL.md:46](flow-skills/lightweight-lane/SKILL.md#L46)). Keeping a doubt branch would preserve today's behaviour under a new name.

**Alternatives:**
- **Keep an `UNCERTAIN` outcome** — rejected: it is the doubt branch with a new label, and an agent will reach for it exactly when the diff is inconvenient.
- **Default to Full, opt into Lightweight** — rejected: contradicts the locked North Star.

**Lock status:** PENDING

---

## A2. Full triggers F01–F11 and their thresholds

**Recommendation:** Adopt §2.3 as written. F01–F08 non-waivable (F08's binary arm operator-waivable); F09 blast radius at **more than 8 non-generated production files / 400 added+deleted production lines / 2 components**; F10 dependency-platform; F11 explicit force.

**Reasoning:** This is the decision that would have caught 2026-08-05. All three reverted changes touched `hooks/**` enforcement surfaces and manifests — **F05 RELEASE_SECURITY_UPGRADE**, non-waivable Full. I classified them Lightweight by judgement and skipped the review that would have found the defects before they were written, not after.

Thresholds are locked policy values, not agent judgement, changeable only by a reviewed policy commit with measurement evidence (§2.3 closing note). Configured-but-unmapped paths stay Lightweight and are *counted*, so coverage improves from data rather than from doubt.

**Alternatives:**
- **Fewer triggers, broader wording** — rejected: unenforceable wording is what FR-21 already is.
- **Tighter F09 (e.g. 5 files)** — rejected: no measurement supports a number yet; M1 supplies it. Start permissive and ratchet on evidence.

**Verification this decision must pass before lock:** a fixture corpus in which (a) a one-file copy fix classifies LIGHTWEIGHT, (b) a self-declared Lightweight edit to approval/secret enforcement classifies FULL, and (c) **the three reverted 2026-08-05 changes classify FULL**. If (c) fails, this decision is wrong.

**Lock status:** PENDING

---

## A3. Override contract

**Recommendation:** Adopt §2.6. Upward (`force_full: true`) free and recorded. Downward only by the operator, only for F09 / F08-binary / F10, bound to base SHA + diff digest + expiry + trigger list. **F01–F07 and protected-path F08 are not waivable.** No global `ignore_risk_classifier`; changing the policy is itself F05.

**Reasoning:** An agent that can author its own downward override converts a mechanism back into prose — the failure class this repo keeps shipping (`approval_authors` documented as enforced, never implemented). Binding the override to a diff digest means it dies when the diff changes, which is what makes it a mechanism rather than a note.

**Alternatives:**
- **Let agents waive F09 with a recorded reason** — rejected: F09 is the trigger an agent is most tempted by, which is exactly why it needs a human.
- **Allow a global disable for emergencies** — rejected: the escape route is a reviewed policy change, which is itself Full and auditable.

**Lock status:** PENDING

---

## A4. Final-candidate SHA contract, and what counts as release proof

**Recommendation:** Adopt roadmap S1 — content-derived checks run **after** closeout; emit a verification receipt carrying `candidate_sha`, tree hash, check set, timestamp; refuse release preparation when `HEAD != candidate_sha`. Keep the existing tag-SHA GitHub gate.

**Addition from 2026-08-05 evidence:** the receipt must also record **check scope and platform set**, and a receipt whose scope is not "full unscoped, both platforms" is structurally not release proof.

**Reasoning:** The scoped-run trap fired twice in one day. `FF_ONLY=...` runs were reported as green while the full suite was red ([test-health-check-timeout.sh:412](hooks/tests/test-health-check-timeout.sh#L412) was failing throughout). The harness already writes scoped results to a separate file and deliberately breaks the strict summary shape ([run-tests.sh:5-15](hooks/tests/run-tests.sh#L5-L15)) — that guard exists and I still misread my own runs. Putting scope **inside the receipt** makes the claim carry its own limits instead of relying on the reader.

Two-platform gating is already mandatory before a release claim (a green MSYS run alone has been wrong twice); the receipt is where that becomes checkable rather than remembered.

**Alternatives:**
- **Receipt records SHA only** — rejected: a full-scope and a one-tag run would produce indistinguishable receipts.
- **Ban scoped runs** — rejected: they are the implement-loop's speed and cost nothing when they cannot be mistaken for proof.

**Lock status:** PENDING

---

## A5. One-file Full-lane `ticket.md`

**Recommendation:** Adopt roadmap S5's shape — one structured `ticket.md` replaces mandatory `spec.md` + `decisions.md` + `tasks.md` + `verification-gate.md`. Linked detail files only when a hard trigger needs them. Handoffs persist only at real context/session boundaries. Dual-read legacy directories for one major release; **never bulk-rewrite historical specs**.

**Reasoning:** Serves "one human decision per ordinary change" ([north-star.md:15](docs/north-star.md#L15)). PO latency dominated the last cycle (89h06m of 117h12m) and was driven by decision gaps, not by review execution.

**Note against my own recommendation:** this packet is itself a `decisions.md`, i.e. the legacy shape. That is deliberate — C0 must land before the artifact model changes, or it would be the first thing rewritten under a contract it is supposed to define.

**Alternatives:**
- **Keep four files, shorten each** — rejected: the count is the friction, not the length.
- **Migrate existing specs to `ticket.md`** — rejected: destroys evidence for no reader benefit; dual-read is cheaper.

**Lock status:** PENDING

---

## A6. Approval backends

**Recommendation:** Adopt roadmap S6 — three backends: `host` (an interactive confirmation), `chat_record` (an explicit operator go-ahead in chat), `artifact_v2` (signed/scoped/expiring file). Ordinary changes need **one** confirmation through any available backend. Long-lived, delegated or technical exceptions require `artifact_v2`. FR-07 exception artifacts keep exact path/scope binding and are not replaced by an ordinary go-ahead.

**Reasoning:** Current policy already admits authorship is not authenticated and `approval_authors` is unenforced ([approval-policy.yml:112](policies/approval-policy.yml#L112)). Naming the backends stops one honest chat approval from being followed by a demand for a hand-authored JSON file — measured friction, in the catalog as `deploy-approval-terminal-friction`.

**Explicitly not in scope:** authenticating operator identity. Decision K3 rules it unenforceable under the same-principal host model, and nothing has changed that.

**Alternatives:**
- **Artifact-only (status quo)** — rejected: imposes governance ceremony on every solo user.
- **Chat-only** — rejected: strands Paperclip, which needs `artifact_v2`.

**Lock status:** PENDING

---

## A7. Enforcement vocabulary, and the severity of a malformed control object

**Recommendation, part 1 — vocabulary:** adopt the roadmap §3 legend as the only sanctioned words: **H\*** conditional host (only after the example config is installed and trusted), **G\*** local git hook (bypassable), **C** CI, **P** prose/agent behaviour. Every enforcement claim in docs, policies and skills must carry one of these. A claim without a qualifier is a defect.

**Recommendation, part 2 — severity (the question that bit us):** a **malformed authorization or control object is rejected whole and classified `BROKEN` / `UNVERIFIED`**, not warned-about while its well-formed siblings stay effective.

**Reasoning:** On 2026-08-05 I made a malformed `deferred_checks` entry warning-only while valid entries from the same artifact kept working. The review's objection is correct and generalises: partially accepting an authorization object is the fail-open class already in the catalog (`approval-gate-unbound-and-fail-open`, `security-check-fail-open-class`). Warning-only also cannot make automation fail, so nothing downstream can act on it.

Rejecting the whole object does **not** grant anything — it withholds a deferral the artifact failed to express validly, which is the safe direction.

**Alternatives:**
- **Warn and keep valid siblings** — rejected above; this is what was tried and reviewed down.
- **Silently drop malformed entries** — rejected: invisible, and the operator cannot repair what they cannot see.
- **Hard-fail the whole health run** — rejected: a malformed *deferral* should not take down an unrelated verdict; `BROKEN`/`UNVERIFIED` for that artifact's effect is proportionate.

**Consequence to implement later:** `deferred_checks` must be required to be a **list**; a JSON object currently passes element-level validation via its keys (verified 2026-08-05: `{"deferred_checks":{"claude_md_overlay":true}}` → accepted).

**Lock status:** PENDING

---

## A8. Compatibility window

**Recommendation:** One major release. Within it: dual-read legacy artifact directories (A5), `approval_backend: artifact_v2` reproduces today's governance (A6), `default_lane: full` reproduces today's lane behaviour (A1) — **but hard triggers are never suppressible by that setting** — and removed machine-shaped fields emit a deprecation warning before deletion. Compatibility mirrors keep old paths as pointers, never duplicate bodies.

**Reasoning:** WorkHub and Paperclip are regression consumers, not the audience setting defaults. A window keeps them whole without letting them dictate the default; a permanent window would mean maintaining two safety engines, which the roadmap names as a falsifier.

**Alternatives:**
- **No window** — rejected: strands both known consumers.
- **Two releases** — rejected: doubles the dual-read surface with no named consumer needing it.

**Lock status:** PENDING

---

## A9. *(Optional — beyond roadmap seq 0)* Bound policy: stall deadline plus absolute ceiling

**Recommendation:** A bounded phase gets **two** limits — a short **no-progress (stall) deadline** and a large **absolute ceiling** — replacing today's single scalar wall. A phase that emits progress is not killed for being slow; a phase that emits nothing for the stall window is killed promptly.

**Reasoning:** Today's evidence. `cli-flow-recovery` has crossed its single wall five times (240 → 480 → 900s, then 1813s measured). Raising it to 5400s was reviewed down: with a ~30-minute healthy path, no single number is both generous headroom and prompt hang detection. Two limits give both. This also removes the incentive to keep raising a number instead of fixing cost — the actual driver is `test-cli-flow-recovery.sh` copying `$PROJECT` seven times among 24 `cp -R` calls, not skill-tree growth as the ticket claimed.

**Why it is marked optional:** roadmap seq 0 lists six contracts and this is not one of them. "Build only what was asked" is rule 6 of `docs/maintainer-execution.md`, and I violated it today. Drop A9 without consequence if you want C0 kept to its stated scope; it can be its own ticket.

**Alternatives:**
- **Keep single scalar, raise it** — rejected by review; that is the reverted change.
- **Lower the wall to force the performance fix** — rejected: manufactures false failures on loaded hosts, which is the original defect.

**Lock status:** PENDING

---

## What this packet deliberately does NOT decide

| Left open | Why |
|---|---|
| `approval-binding-omits-head` — whether a later push of a different HEAD needs re-approval | A per-action property needing its own contract; not required by any seq-0 item |
| `command-gate-shell-evasion` | Needs a semantic corpus and a false-positive policy first; roadmap forbids a partial regex parser |
| `approval-single-use-consumption` | Blocked on a stable host call ID and atomic consumption, absent today |
| `compat-approval-surfacing` | Needs its carrier census before any further implementation |
| Making `cli-flow-recovery` cheap | A performance ticket. Not blocked on any decision here — it needs profiling |

## How to lock

Reply per decision: `lock A1`, `redirect A4 to <alternative>`, or `lock all as recommended`. Anything not locked stays PENDING and blocks the implementation it gates. A9 may simply be dropped.

**Recommended before locking:** send this packet through the same adversarial review that caught 2026-08-05. It cost roughly one run and prevented a day of rework; the same reviewer explicitly asked for C0 to be the next commit.
