| Area | Verdict | Evidence | Consumer cost |
|---|---|---|---|
| Overall product | **Simplify aggressively** | The valuable kernel is deterministic checks, independent review, exact-SHA CI, smoke, rollback, and upgrade preservation. The rest is mostly prompt governance. | Normal changes inherit a safety-critical release process even when the hooks are off. |
| Full lane | **Cut as the default** | Full lane requires eight phases, separate implementation/deploy sessions, and up to seven markdown artifacts before reports and smoke evidence ([eight-phase-flow.md:14](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/workflows/eight-phase-flow.md:14>)). | Two sessions, 7+ artifacts, approval bookkeeping, repeated gates, closeout commit. |
| Lightweight lane | **Keep, make it the default** | Since its introduction, Git history contains 31 new Full specs versus 20 change notes; after June 11, 17 Full versus 3 Lightweight. The ledger records only 11 entries and no actual promotion ([index.md:15](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/changes/index.md:15>)). | It saves documents, but still mandates lint, typecheck, build, live verification, commit, FR-07, approval, and deploy ([lightweight-lane.md:11](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/workflows/lightweight-lane.md:11>)). |
| 27 rules / 34 skills | **Cut to a small core plus optional packs** | Twelve rules, FR-16–FR-27, were added in 38 days, often from one incident: FR-17 from agents suggesting rest, FR-18 from one bloated handoff, FR-24 because FR-22 did not load, FR-27 from one hung probe ([history:22](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/FLOW_RULES_HISTORY.md:22>), [history:34](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/FLOW_RULES_HISTORY.md:34>), [history:174](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/FLOW_RULES_HISTORY.md:174>), [history:435](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/FLOW_RULES_HISTORY.md:435>)). | Canonical skills occupy 49 files/441 KB and are mirrored twice; every provider needs discovery, synchronization, and drift checks. |
| Enforcement layer | **Keep only mechanically honest controls** | Flow hooks are opt-in/off by default; default recovery deliberately does not wire them. Several rules are explicitly judgment-only or policy declarations rather than tool-time checks ([rail-mapping.md:9](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/rail-mapping.md:9>), [approval-policy.yml:65](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/approval-policy.yml:65>)). | Consumers pay for 182 tracked hook files and ten policy files while receiving mostly prompt discipline unless they complete extra setup. |
| Approval system | **Delete production-deploy approval artifacts; retain only scoped technical exceptions** | Flow cannot authenticate the operator. `approved_by`, `ticket`, `scope`, and `reason` are unauthenticated metadata ([approval-policy.yml:112](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/approval-policy.yml:112>)). v4.7.1 still defaults `strict_approvals: false` ([approval-policy.yml:139](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/approval-policy.yml:139>)). | JSON minting, TTLs, inventory, compatibility modes, binding, stale warnings, and a parked single-use subsystem—without proving human consent. |
| Upgrade system | **Keep classifier/integrity; replace the two-engine entry path** | Two sophisticated consumers ran the wrong installed engine; one needed seven interventions, the other rolled back. The correct 4.7 engine would have refused safely, but users must already know to bootstrap it ([WorkHub report:5](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-30-workhub-upstream-report.md:5>), [Paperclip report:23](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-08-04-paperclip-escalation.md:23>)). | Upgrade knowledge is itself a safety prerequisite. That is a product failure, not user error. |
| Ceremony-audit subsystem | **Cut entirely** | Its own five-round report observed zero control firings, but `prevents:` annotations were enough to dismiss controls as governed; the result was 0 confirmed, 1 dismissed, 5 inconclusive ([audit:12](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-06-13-ceremony-efficiency-middle-lane-smoke/S1-find-wasted-effort-report.md:12>), [audit:49](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-06-13-ceremony-efficiency-middle-lane-smoke/S1-find-wasted-effort-report.md:49>)). | A policy, skill, analyzer, proposals schema, taxonomy, and reports whose design makes subtraction nearly impossible. |
| Independent review and release gates | **Keep; these buy the safety** | A 649/649 gate still missed seven blockers and six majors; independent review found them. FR-10 then prevented an incorrect reviewer instruction from becoming a regression ([review:3](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md:3>), [review:73](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md:73>), [review:81](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md:81>)). | Expensive, but demonstrably finds production defects. Apply only to risky changes. |

Verdict: **Fusebase Flow does not buy its current cost for an ordinary consumer.** It contains a strong safety toolkit inside a workflow bureaucracy. The toolkit is worth keeping; the bureaucracy is not.

## Cuts

### 1. Collapse the Full lane

A Full change currently creates or updates:

- spec
- clarify conversation
- decisions
- tasks
- verification gate
- implementation handoff
- deploy handoff
- gate report
- approval artifact
- optional smoke directory
- post-deploy status/docs commit

The approval-binding ticket is the extreme but revealing example: 22 directly related files and roughly 4,819 lines across its core artifacts, handoffs, review, and smoke evidence. Yet the first implementation gate reported 649/649 and independent review still found seven blockers and six majors, including replayable approvals, fail-open classifier fallback, shell evasion, and non-discriminating tests ([review:3–16](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md:3>)).

That means the artifact pack did not provide the decisive safety. The review did.

Replace the pack with one `ticket.md` containing:

- problem and scope
- acceptance criteria
- only material decisions
- implementation checklist
- verification and rollback

Create a handoff only when a real context/session boundary occurs. Create smoke evidence only when smoke is required. This preserves the information and eliminates duplication.

FR-01, FR-02, FR-04, FR-05, FR-11, FR-18, FR-20, FR-21, and FR-23 are currently different facets of “understand the change, record what matters, and verify it.” They do not need nine always-on rules.

### 2. Delete the role theatre and mandatory chat scaffolding

Cut as always-on requirements:

- self-attestation
- the footer on every output
- Product Owner/Architect/AI Developer/Deploy role switching
- “forward momentum, never retreat”
- chat-format mandates
- forced separate deploy session

The role separation is not an authority boundary. The backlog admits PO path restrictions are prompt-only: a PO can still edit application code and only the operator noticing the diff catches it ([role-path backlog:5](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/backlog/role-path-hook-enforcement/README.md:5>)).

FR-17 is particularly bad product design. “Never suggest stopping or postponing” conflicts in spirit with FR-05’s stop-at-gate discipline and incentivizes endless forward motion. It exists because of a single observed conversational annoyance, not because it prevented a product defect ([history:22–31](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/FLOW_RULES_HISTORY.md:22>)).

Keep role labels as optional prompts for fresh-context review. Do not pretend they are separation of duties.

### 3. Reduce 34 skills to a core set

No skill “fires” mechanically. Skills are prompt documents selected by model matching or explicit invocation. Even the Codex configuration says only descriptions/metadata are injected; bodies are not ([config.toml.example:28](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/.codex/config.toml.example:28>)).

The repository also has no skill-load telemetry, so it cannot substantiate actual consumer usage. The best artifact proxy shows:

- `repo-onboarding-context-map`: zero references in specs, handoffs, or change notes.
- `app-quality-patterns`: referenced only by its own spec.
- `design-discovery-ideation` and `git-history-diagnostic`: only generic skill-design/spec references.
- `phase-audit`: only generic/module-size planning references.
- `north-star`, `client-vs-internal`, `product-docs-first`, and `business-logic-guardian`: dormant unless optional onboarding artifacts exist.
- `find-wasted-code`: intentionally manual and inert until invoked.

Split the distribution:

- **Core:** diagnose/reproduce, concise specification, implementation, validation, independent review, deploy/smoke, handoff, security.
- **Optional app-product pack:** North Star, audience, business logic, product docs, app decomposition, quality patterns.
- **Optional framework-maintenance pack:** skill authoring, phase audit, wasted-code, wasted-effort, token audit, repo context mapping.

Consumers should not install Flow’s self-maintenance machinery as part of every app workflow.

### 4. Delete `find-wasted-effort` and `ratchet-governance`

This whole subsystem is not worth it.

The audit’s circularity is visible in its own output:

- No control firings were observed.
- No gate deviation was blocked.
- No approvals appeared.
- Controls were still dismissed from waste consideration because they carried a `prevents:` annotation.
- Catastrophic controls are definitionally inconclusive on a clean window.

See the zero-firing evidence and final 0/1/5 verdict ([audit:43–66](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-06-13-ceremony-efficiency-middle-lane-smoke/S1-find-wasted-effort-report.md:43>)).

A control’s author writing “prevents unauthorized deploy” is not evidence that it did so. The subsystem adds a policy taxonomy, annotations, a skill, an analyzer, proposal JSON, and a prune protocol to answer a question the design makes almost impossible to answer.

Replace it with a quarterly table:

| Control | Observed block | Incident avoided | False-positive cost | Keep/remove |
|---|---|---|---|---|

No annotation counts as evidence.

### 5. Remove production approval artifacts

K3 is correct: Flow cannot authenticate identity because agent and operator share an OS principal. An approval artifact therefore proves only:

> A process capable of writing the repository created a JSON file satisfying the local validator.

It does **not** prove:

- a human approved;
- who approved;
- the approval corresponded to the current chat;
- the artifact was used once;
- the approved state is still current.

The remaining value is accidental-action prevention: a literal deploy command is blocked until an artifact exists. But that value is weak:

- hooks are off by default;
- an agent can mint the artifact;
- production TTL is 90 days;
- artifacts are not single-use;
- strict mode remains off;
- raw-command regex is both evasive and obstructive.

WorkHub found stale artifacts that left a protected-path gate effectively open for three months ([WorkHub:274–301](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-30-workhub-upstream-report.md:274>)). Paperclip measured v4.7 allowing deploy and push from missing-expiry artifacts that its 4.6.1 overlay correctly denied ([Paperclip:28–46](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-08-04-paperclip-escalation.md:28>)). Single-use remains parked because the host lifecycle cannot support it reliably ([single-use backlog:24](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/backlog/approval-single-use-consumption/README.md:24>)).

Replace production approval artifacts with:

- a host-native approval event where available;
- CI environment approval/branch protection for releases;
- otherwise an explicit chat confirmation, honestly described as process discipline.

Keep digest-bound, single-use artifacts only for technical exceptions such as a specific protected-path staged set. There, identity is irrelevant: the useful property is exact scope binding.

The honest K3 framing is documented in the policy, hook coverage, and decisions. But the rest of the product still uses phrases such as “machine-checkable human-in-the-loop record” and “authorization on file.” Those imply evidence of human authorization that the machine cannot establish.

### 6. Demote FR-22, FR-23, FR-25, FR-26, and FR-27

These are mostly maintainability/economy preferences, not universal safety rules.

- **FR-22 comments:** make it a concise style guide. Its hook can only check that an agent emitted a marker, never comment quality ([required-artifacts.yml:127](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/required-artifacts.yml:127>)).
- **FR-23 documentation budget:** keep the principle, delete tier bureaucracy.
- **FR-25 module size:** optional warn-by-default lint. Its rollout froze consumer monolith work and collided with FR-07 before another subsystem repaired the adoption path ([FR25 incident:9–23](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/problem-catalog/fr25-upgrade-adoption-collision/problem.md:9>)).
- **FR-26 token economy:** one paragraph in agent guidance, not an always-on rule plus skill and audit.
- **FR-27 liveness:** keep bounded-run tooling and make shipped long-running scripts observable by construction. Delete the sprawling zero-trust sub-agent protocol from the always-on floor.

WorkHub’s 25-minute buffered test run proves the right fix is in the runner, not in reminding every consumer agent about liveness ([WorkHub:212–234](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-30-workhub-upstream-report.md:212>)).

FR-24 should disappear entirely. It is a meta-rule created because other rules failed to reach agents at write time. Fixing prompt delivery by adding another permanent rule is textbook accretion.

### 7. Stop claiming that policy files equal enforcement

Concrete gaps remain:

- `before_implementation` declares required spec/tasks/gate artifacts but is warn-only ([required-artifacts.yml:8–29](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/required-artifacts.yml:8>)).
- `stop.py` only evaluates `signal` entries and ignores path requirements; signals are keyword regexes such as “rollback,” “gate report,” or “worker-undisturbed” ([stop.py:74–103](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/handlers/stop.py:74>), [stop.py:237–257](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/handlers/stop.py:237>)).
- FR-03’s hook requires a `T<number>` in the subject; it cannot show one task equals one commit ([commit-msg:40](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/git/commit-msg:40>)).
- FR-13 silently does nothing unless commands are configured or Node scripts happen to exist ([pre-commit:649](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/git/pre-commit:649>)).
- `gate-contracts.yml` is consumed only by an explicitly run validation script.
- `comment-policy.yml` has no runtime hook consumer.
- `ratchet-governance.yml` is consumed only by the manual audit.
- FR-21 lane classification is openly process-authoritative; an agent may self-declare Lightweight and take the cheaper gate ([lightweight skill:74–81](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/flow-skills/lightweight-lane/SKILL.md:74>)).

The `live-enforcement-inertness` class is not fully closed. Native-shaped fixtures now exist, but the suite remains an in-process synthetic runner, not a host integration test ([hook-coverage.md:63](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/hook-coverage.md:63>)). The deploy handoff still delegated confirmation of real live-hook firing to a consumer machine ([v3.30.7 deploy:48](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-03-v3307-deploy.md:48>)).

`session_start`, `post_tool_use`, and `pre_compact` also lack the fixture coverage present for PreToolUse/Stop/UserPromptSubmit. Codex support is represented by opt-in example configuration, not shipped active configuration. Cursor, Copilot, Gemini, and generic workflows have only partial git-hook fallback ([hook-coverage.md:52–57](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/hook-coverage.md:52>)).

### 8. Replace the upgrade UX, not just the upgrade engine

WorkHub’s seven interventions included:

- missing managed file;
- permanent Windows hash drift;
- consumer policy loss;
- backup/test collision;
- silent 13-minute periods;
- raw-string command false positives.

It eventually reached healthy state, but the protection-to-friction ratio was poor ([WorkHub:5–8](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-30-workhub-upstream-report.md:5>), [WorkHub:315–324](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-30-workhub-upstream-report.md:315>)).

Paperclip correctly stayed on 4.6.1. Adopting 4.7 required either:

- a Full-lane port across the most security-critical files;
- losing `call_id`/`shadow_allow`;
- accepting the live missing-expiry deploy gate.

Their stated routes are explicit ([Paperclip:147–156](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-08-04-paperclip-escalation.md:147>)). Declining the upgrade was rational. A governance product has failed its value proposition when adopting its safety update requires weakening a consumer’s stricter safety posture.

The classifier and immutable-source work are worth keeping. The two-engine route is not. Ship one command that:

1. detects the installed version;
2. fetches/materializes the target engine;
3. classifies before writing;
4. refuses safely on unresolved conflicts;
5. runs the final consumer gate;
6. reports exactly what remains.

Old `upgrade.sh` should hard-stop and redirect automatically when it is incapable of the safe hop.

### 9. Stop creating post-gate documentation commits

FR-14’s separate closeout commit actively created a release gap. v4.6.0 had 619/619 and two adversarial reviews, then two documentation commits landed after the gate and the pushed tree was red ([docs-only incident:9–26](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/problem-catalog/docs-only-commit-broke-content-derived-gate/problem.md:9>), [docs-only incident:44–52](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/problem-catalog/docs-only-commit-broke-content-derived-gate/problem.md:44>)).

Delete FR-14’s “single docs commit on deploy.” Update status before the final gate or after release in a non-release-affecting system. The only meaningful invariant is:

> The exact SHA published passed the required checks.

## What to keep

- **FR-10’s reproduce/measure discipline.** It stopped a confident but empirically false review instruction from shipping ([review:81–89](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md:81>)).
- **Independent adversarial review for security, upgrade, data, and release infrastructure.** This repeatedly found defects green suites missed.
- **Release publication structurally dependent on verification.** Before this, Flow published roughly three releases while CI was red; `publish needs verify` finally made a red tag unable to create a release ([CI incident:11–32](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/problem-catalog/ci-red-invisible-no-release-gate/problem.md:11>)).
- **Exact-release-SHA verification.** More valuable than every status artifact combined.
- **FR-06 destructive-operation protections.**
- **FR-07 protected-path diffing and tightly scoped, digest-bound exceptions.**
- **Fail-closed secret scanning.**
- **Live smoke against operator-visible behavior plus rollback.**
- **Per-file three-way upgrade classification and verified source materialization.** Paperclip acknowledges the correct 4.7 engine would have refused and written nothing ([Paperclip:23–26](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/tmp/handoff/2026-08-04-paperclip-escalation.md:23>)).
- **The Lightweight one-pass concept.** The implementation is directionally right; its eligibility posture is too conservative.
- **The problem catalog itself.** It is the clearest and most valuable product artifact in the repository. Its census exposes recurring failure classes far better than the rule inventory does.
- **Atomic/revertible commits**, but expressed as that—not “one T-numbered task equals one commit.”

## Prioritized change list

1. **P0 — Close the live approval exposure.** Flip strict approval handling, surface/reject legacy missing-expiry artifacts, and stop describing local JSON as authenticated human approval. v4.7.1 leaves the consumer-observed exposure live; the attempted surfacing feature is parked after three failed review rounds ([compat backlog:17–39](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/backlog/compat-approval-surfacing/README.md:17>)).

2. **P0 — Replace the dual upgrade entry path with one version-aware command.** An old engine must never be capable of destructively “upgrading” to a release whose classifier it cannot run.

3. **P0 — Gate the exact published SHA.** Eliminate post-gate release-affecting commits, including FR-14 closeout commits. Align local full gate with CI; manifest freshness is still a known missing local assertion ([manifest backlog:8–28](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/backlog/local-gate-misses-manifest-freshness/README.md:8>)).

4. **P1 — Replace 27 rules with roughly eight core invariants:** understand scope, reproduce, atomic/reversible changes, deterministic checks, protect sensitive paths/secrets, explicit human confirmation for external effects, independent review for risky changes, live proof/rollback.

5. **P1 — Make Lightweight the normal lane.** Escalate only on explicit triggers: unknown root cause, auth/permissions, migration/data mutation, public-contract change, broad refactor, or high blast radius. Remove “in doubt → Full.”

6. **P1 — Collapse Full artifacts into one ticket file.** Handoffs become event-driven, not phase-mandatory. Delete separate clarify, decisions, tasks, and gate files unless their content is genuinely substantial.

7. **P1 — Remove production-deploy approval JSON.** Use host/CI approval where available; otherwise retain honest chat authorization. Preserve scoped artifacts only where their machine-enforced binding is itself useful.

8. **P1 — Split skills into core and optional packages.** Do not ship product/onboarding/meta-maintenance skills to every consumer by default.

9. **P1 — Add actual host-contract tests or narrow support claims.** Exercise real Claude/Codex hook invocation for every claimed event. A synthetic JSON fixture is not live-hook proof.

10. **P2 — Remove `find-wasted-effort`, `ratchet-governance`, mandatory state footers, mandatory self-attestation, FR-17, and FR-24.** These are governance about governance.

11. **P2 — Demote module size, comment style, token economy, and liveness prose to optional lint/guidance.** Keep the useful tools; stop loading the policy narrative into every session.

12. **P2 — Rename the raw-command regex layer honestly.** It is an accident guard, not a security boundary. It currently permits executable quote fragmentation and rejects inert prose ([shell-evasion backlog:10–25](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/backlog/command-gate-shell-evasion/README.md:10>)).

Decision churn is another warning sign: of the requested K1–K21/M1–M21 set, K6, M1, and M6 were revised after lock; M14 was refuted and superseded. That is 4/42 in the requested status categories, with zero `UNLOCKED`. M20 and M21 were also locked and later withdrawn with their parked feature, so broad post-lock churn is 6/42. On shipped `main`, only M1–M19 remain; the withdrawal is documented at [compat backlog:6–15](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/backlog/compat-approval-surfacing/README.md:6>). More importantly, both decision files admit the “locks” were PO recommendations under standing authorization, not individually confirmed operator decisions ([K decisions:4](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/approval-binding-and-upgrade-classification/decisions.md:4>), [M decisions:4](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/upgrade-source-integrity-and-observability/decisions.md:4>)). The lock label is stronger than the underlying consent.

Audit note: I reviewed the requested `3608271` Git object. The current worktree is a descendant branch at `53b025a` with pre-existing changes; I did not switch branches or edit any file. The original July 28 consumer proposal is not present as a standalone file in the shipped tree; the spec only records its external source and incorporates its findings ([spec:7–15](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/docs/specs/approval-binding-and-upgrade-classification/spec.md:7>)).

---
🧭 Phase: Verify  
🎫 Ticket: —  
⏭️ Next: Convert the P0/P1 cuts into a replacement product contract if the operator chooses to proceed.