# tool-time-protected-path-intent

**Status:** filed, NOT built — E4 ask (b) shipped instead as the documented sanctioned path; (a) is the optional upgrade
**Filed:** 2026-08-25
**Source:** paperclip+hermes-v1 escalation E4 (`2026-08-20-E4-first-edit-deadlock.md`), asks (a) + 3
**One-liner:** a first-class TOOL-TIME intent artifact — one exact path, one tool set, ≤10 min TTL, consumed on use — so the FIRST `Edit`/`Write` of a protected path can be authorized at tool time instead of routed through `Bash`.

## The deadlock is real, and its cheap half already shipped

The deadlock is confirmed, not assumed: `has_active_exception` requires a `tree_digest` over CURRENT STAGED content for a digest-bound category, `pre_tool_use` evaluates the `Edit` before that content exists, and `write-bootstrap-approval.sh` exits when no category path is staged. The first `Edit` of a protected path cannot mint the approval that would permit it.

**E4 ask (b) SHIPPED** — `workflows/violation-recovery.md` § "The FIRST edit of a protected path is not a violation" now states that the tool-time arm is defense-in-depth for already-staged content, that the commit gate is the boundary, and that the sanctioned path is stage → mint → commit → `--consume`, disclosed in the commit body. That was the one-paragraph half of their either/or, and it describes what this repository actually does.

Ask (a) is the better answer to the same problem: authorize the first `Edit` at tool time so a protected-path edit never has to leave the `Edit`/`Write` surface. They ran it for three weeks without incident on their 4.6.1 overlay (`write-bootstrap-approval.sh --intent <path>`, consumed by `pre_tool_use.py`), then moved it OUT of their 4.12.0 port on their own plan review — as an upstream defect, not a consumer patch.

## Their constraint worth keeping (ask 3)

The verifier and the writer MUST import the SAME `path_policy` constants (allowed tools, TTL cap) so they cannot drift. This is not style: it is the property the existing digest-bound artifact already has — `write-bootstrap-approval.sh` calls `path_policy.compute_staged_tree_digest` and reads `path_policy._DIGEST_BOUND_OPERATIONS`, so writer and verifier read ONE definition, and `approval-binding-omits-head` names the same pattern as the one to mirror. An intent artifact inherits the requirement or it is not worth building.

## Why it is NOT being built now

1. **A tool-time intent is a NEW CARRIER on a gate whose carrier model is the open question.** `carrier-aware-approval-binding` and `compat-approval-surfacing` BOTH conclude that the carrier table must be designed before further artifact or predicate work — the carriers structurally supply different facts, and three implementation rounds of the surfacing feature failed three adversarial reviews for exactly that reason. Adding a fourth artifact kind first repeats it.
2. **"Consumed on use" is not free here, and neither filing names why.** `hooks/handlers/post_tool_use.py:41-50` runs `evaluate_path` over every changed path AFTER an Edit-like tool and records `has_exception` in both its warning text and the audit row. An intent consumed at `pre_tool_use` makes that second evaluation report `exception=False` for the very edit it just authorized — a false FR-07 warning and a misleading audit trail. The consumption point has to be decided against this, not left to fall out.
   - Verified good news, worth recording so nobody re-derives it: `hooks/handlers/permission_request.py:48` handles **command tools only** and never evaluates an `Edit` path. So the double-evaluation defect that killed claim-at-evaluation for COMMANDS (`approval-single-use-consumption` § "Why it is not in …") does **not** apply to a path intent. The `post_tool_use` collision is the milder cousin — a warn, not a burned claim.
3. **The residual exposure is bounded and disclosed.** With ask (b) documented, what is left is ergonomics: a first protected-path edit is authored through `Bash` and says so in the commit body. The commit gate is unchanged and is still the boundary.

## Shape if commissioned

- New artifact kind `protected_path_intent`: exactly one path, an explicit allowed-tool set, TTL capped ≤10 min, single-use.
- Minted by the AGENT on the operator's chat approval (§ Operator Gate Protocol). Minting without that approval is self-approval and forbidden.
- Writer and verifier import the same `path_policy` constants (ask 3).
- Consumption point decided EXPLICITLY against `post_tool_use`'s re-evaluation.
- The commit gate is untouched: an intent authorizes the `Edit`, never the commit. The digest-bound artifact is still required at commit time.

## Acceptance sketch (to be refined at spec)

1. AC1 — a minted intent authorizes exactly one `Edit`/`Write` of exactly one path with a listed tool; a second `Edit` of the same path is denied.
2. AC2 — an intent for path A never authorizes path B, and any glob metacharacter in the path field invalidates the artifact (parity with the digest-bound category's existing `_has_glob_meta` rule).
3. AC3 — an intent never authorizes a COMMIT; the pre-commit still requires the digest-bound artifact.
4. AC4 — after a consumed intent, `post_tool_use` does not emit a false FR-07 warning for that edit and the audit row is not misleading.
5. AC5 — writer and verifier share one constants source, asserted by a test that fails if they drift.

## Out of scope

- Any weakening of the commit gate.
- Single-use for COMMAND approvals — that is `approval-single-use-consumption` / `host-call-identity-feature-request`, and it needs a host call identity Flow does not have.

## Risks / unknowns

- A second artifact kind doubles the surface `compat-approval-surfacing` already cannot report coherently.
- Same-principal threat model (K3): an agent that can mint an intent can mint one for a path the operator never approved. The real gate is the operator's chat go-ahead, not the artifact — any doc must say so.
- Ordinary-consumer demand is **UNVERIFIED** (`docs/north-star.md`); both consumers in this chain run their own overlays.

## Related

- `workflows/violation-recovery.md` § FR-07 — ask (b), SHIPPED; the sanctioned path
- `docs/backlog/carrier-aware-approval-binding/README.md` · `docs/backlog/compat-approval-surfacing/README.md` — the carrier-table prerequisite
- `docs/backlog/approval-single-use-consumption/README.md` — the command-side sibling; different failure mode, same missing-host-call-identity root
- `docs/backlog/approval-binding-omits-head/README.md` — the writer/verifier single-definition pattern to mirror
- `hooks/shared/path_policy.py` · `hooks/handlers/pre_tool_use.py` §2 · `hooks/handlers/post_tool_use.py:41-50` · `hooks/handlers/permission_request.py:48` · `hooks/local/write-bootstrap-approval.sh`
