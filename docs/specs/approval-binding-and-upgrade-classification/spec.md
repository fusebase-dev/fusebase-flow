# Spec — approval-binding-and-upgrade-classification

**Status:** DRAFT
**Scope lock:** locked 2026-07-28 — decisions frozen; see `decisions.md`
**Created:** 2026-07-28
**Linked decisions:** K1..K17
**Promoted from:** consumer proposal `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-07-28-approval-artifact-binding-and-upgrade-conflict-classification.md`
**Deploy hash:** <captured at DRAFT → DONE flip>
**Lane:** Full (FR-21) — security-enforcement surface, multi-file, behaviour-tightening for existing consumers
**Doc tier:** 4 (FR-23) — spec + decisions + tasks + verification-gate

## Problem

The v3.30.5 fail-closed sweep (`docs/problem-catalog/security-check-fail-open-class/problem.md`) hardened `path_policy.py`, the pre-commit hook and the secret scanner — and **skipped `command_policy.py`**. The same defect class survived in the missed carrier. `hooks/shared/command_policy.py:34-51` binds a FR-12 approval artifact to nothing but the `<action>` prefix of its filename. It never reads the JSON body's `action`, ticket, command, author, repo, or nonce; a missing or empty-string `expires_at` is treated as valid forever; the artifact is never consumed, so it replays indefinitely. A consumer measured **98** `production_deploy` artifacts on one project, **22** with no expiry. `policies/approval-policy.yml:103-106` simultaneously documents `approval_authors` as hook-enforced operator-only authorship — a control the validator never implements, contradicted in the same file at `:44-46`. Separately, `hooks/local/upgrade.sh:246-257,366-388` detects that a managed directory differs but cannot distinguish *upstream changed it* from *the consumer changed it*, so it silently overwrote a consumer's locally hardened validator during a 4.5.0 → 4.6.1 upgrade.

## Why now

A consumer who wired `PreToolUse` — i.e. exactly the consumer relying on enforcement — had their security hardening reverted by an upgrade and reported the underlying gate is replayable. Flow already ships the correct binding design one file away (`hooks/shared/path_policy.py:197-280`: digest-bound, operation-bound, single-use for protected-path edits). The command gate is the outlier, not the norm.

## In scope

- Approval-artifact **schema v2** for command approvals: parseable UTC `expires_at` (mandatory on new artifacts), body/filename `action` agreement, `schema_version`, type-safe parsing, fail-closed on malformed.
- Approval **binding to enforceable ambient facts**: exact command digest + repository identity, enforced **when present** (additive; fail-closed on mismatch).
- **Truthful trust model**: `approved_by` and `ticket` documented as audit metadata, never authenticated authority; the contradictory `approval_authors` comment corrected.
- **Safe approval writer**: `hooks/local/approve-local.sh` serializes JSON in one language from argument data; validates `<action>` against policy and `<slug>` against a safe charset; atomic temp-file + replace; honours merged local policy.
- **Compound-command + SQL hardening**: all matching `require_approval` rules reported (not just the first); case-insensitive destructive SQL; `ALTER TABLE` gated.
- **Lightweight-lane gate parity** (FR-21): `lightweight_deploy` becomes an accepted action for the deploy command rule, with the process-authoritative trust boundary documented.
- **Cross-validator expiry fix**: the "missing `expires_at` = valid forever" hole in `hooks/shared/path_policy.py:237-239` and `hooks/local/lib/active-approvals.sh:27-38` — same defect, other carriers.
- **Legacy inventory + strict mode**: `--strict-approvals` / policy flag, default OFF this release; legacy artifacts accepted with a logged warning and surfaced by an inventory command.
- **Managed-content base manifest + three-way upgrade classification**: shipped-content checksums captured at install, classified at upgrade as unchanged-by-consumer / consumer-only / changed-by-both / upstream-deleted, with a bootstrap adoption path for consumers on ≤4.6.1.
- Release integration: VERSION, plugin manifests, CHANGELOG, release notes, mirrors, hook-layer manifest restamp, rule-inventory baseline.

## Out of scope

- **Two-phase single-use approval consumption** (reserve → execute → consume). Requires a stable host call ID across `PermissionRequest` and `PreToolUse` (`hooks/handlers/pre_tool_use.py:62-76`, `hooks/handlers/permission_request.py:40-57`), failure finalization, orphan recovery, and network-filesystem atomicity that Flow cannot currently guarantee. Filed to backlog — see K11.
- **Authenticated operator authorship.** The agent and operator write as the same OS principal; `$USER`, self-attested role strings and locally stored non-secret metadata are all forgeable. Flow will state this limitation rather than pretend to enforce it.
- **Ticket binding as a security control.** Comparing a filename ticket to a JSON ticket compares two agent-writable strings. Retained as audit metadata only.
- **An executable customization seam for `command_policy.py`.** Arbitrary override code weakens the hook-integrity boundary; declarative policy extension plus conflict-aware upgrade covers the need.
- Changing `path_policy.py`'s non-bootstrap path/TTL approval semantics beyond the expiry fix.
- Any change to protected-path bootstrap artifacts' digest/operation/`--consume` semantics (FR-07 boundary).

## Audience classification

Internal / developer-facing only. `docs/audience.md` and `docs/north-star.md` are absent, so `client-vs-internal` and `north-star` are silent no-ops. No client UI, no SPA, no web surface. The two operator-visible surfaces are **CLI text**, and are treated as UX deliverables with explicit design criteria in AC14–AC15: the FR-12 denial message and the upgrade conflict report.

## Acceptance criteria

1. **AC1** — `_approval_artifact_present()` rejects an artifact whose JSON body `action` differs from the filename action. Test: artifact `production_deploy-x-20260728.json` with body `{"action":"database_migration",...}` → `evaluate("fusebase deploy")` returns `decision == "deny"`.
2. **AC2** — A missing, empty, non-string, or unparseable `expires_at` makes an artifact INVALID (not valid-forever) in strict mode, and produces a logged legacy warning in compat mode. Expiry is compared as a parsed UTC timestamp, never lexicographically.
3. **AC3** — Malformed approval JSON of any shape (array, number, null, wrong types) is rejected without raising outside the guarded block; `evaluate()` never propagates an exception for any artifact content.
4. **AC4** — `evaluate()` threads the resolved repository `root` into `get_policy()` for both `command-policy` and `approval-policy`; policy no longer resolves from process CWD. Test: evaluate from a foreign CWD and assert the same decision as from repo root.
5. **AC5** — An invalid regex in a `deny` or `require_approval` rule fails **closed** (the command is denied with a policy-error reason), not skipped. A missing or empty command policy fails closed rather than falling through to `default: allow`.
6. **AC6** — All matching `require_approval` rules for one command are evaluated; the denial reason lists **every** required action in a single message. Test: `fusebase deploy && npx prisma migrate deploy` with only a `production_deploy` artifact → deny naming `database_migration`.
7. **AC7** — Destructive-SQL matching is case-insensitive and `ALTER TABLE` is gated. Test: `psql -c "drop table users"` and `psql -c "ALTER TABLE users ..."` both require `database_migration`.
8. **AC8** — A `lightweight_deploy` artifact satisfies the `fusebase deploy` command rule; a `production_deploy` artifact also still satisfies it. Both are proven through `pre_tool_use` **and** `permission_request`.
9. **AC9** — When an artifact carries `command_digest` and/or `repo_id`, a mismatch **denies**. When absent (legacy), the artifact is action-scoped as before plus AC1–AC3. New artifacts written by `approve-local.sh` always carry them.
10. **AC10** — `approve-local.sh` produces valid JSON for adversarial inputs: slug/reason containing `"`, `\`, newline, `$(...)`, and unicode. It rejects an action absent from the merged approval policy (exit 2, no file written) and a slug outside `[A-Za-z0-9._-]{1,64}` (exit 2). Writes via temp file + atomic replace, and re-parses the artifact before reporting success.
11. **AC11** — `path_policy.has_active_exception()` and `active-approvals.sh` treat missing/empty expiry identically to `command_policy` (invalid in strict, warned in compat). Bootstrap artifacts (`operation == flow-internals-bootstrap`, digest-bound) continue to pass unchanged — proven by `test-bootstrap-exception.sh` staying green.
12. **AC12** — `bash hooks/local/approve-local.sh --inventory` lists every artifact under `state/approvals/` with columns `file · action · schema · expiry-state · binding-state · verdict(strict)`, so a consumer can see exactly which artifacts a strict cutover will reject.
13. **AC13** — `audit/managed-content-manifest.json` records a sha256 per managed path, is stamped byte-stably by `hooks/local/stamp-managed-content-manifest.sh` (no timestamps), is CI-freshness-gated, and `upgrade.sh` classifies every managed path into exactly one of the ten states in the K9 truth table: `current`, `upstream-only`, `consumer-only`, `changed-by-both`, `upstream-deleted` (clean/dirty), `consumer-added`, `upstream-added`, `consumer-deleted`, `unknown-base`. `--auto-yes` **never** overwrites `consumer-only`, `changed-by-both`, dirty `upstream-deleted`, or `unknown-base`, and aborts on `changed-by-both`.
    - **AC13b** — Base lifecycle per K13: with no local base manifest, adoption synthesizes one from the upstream tag equal to the consumer's installed `VERSION`; `unknown-base` occurs only when that tag cannot be resolved. After a successful apply, the source tree's manifest is installed as the new base **last**. Test: two consecutive upgrades (4.6.1→4.7.0→4.7.1) leave zero paths misclassified as `consumer-only` in the second run.
    - **AC13c** — Apply is per-file per K15: a directory containing one `consumer-only` file among many `upstream-only` files refreshes the others and preserves that one. The existing directory-level `.pre-upgrade-<TS>` backup and its retention pruning are unchanged.
14. **AC14** — *(UX, internal CLI)* The FR-12 denial message states, in this order: what was blocked, every action required, why the present artifact failed (missing / expired / action-mismatch / digest-mismatch — the specific reason, not a generic "no artifact"), and the single exact command that resolves it. ≤ 8 lines, no framework jargon uncued by a path.
15. **AC15** — *(UX, internal CLI)* The upgrade conflict report groups paths by classification with a count per group, lists `consumer-only` and `changed-by-both` paths explicitly (never elided behind "N files"), names the backup directory, and ends with the exact resume command. Safe groups are summarized as counts; only groups needing a decision are enumerated.
16. **AC16** — A consumer on 4.6.1 with a locally patched `hooks/shared/command_policy.py` runs the documented bootstrap path; their patch is **preserved and explicitly named in the report**, never silently overwritten. Because 4.7.0 also rewrites that file, its correct classification is **`changed-by-both`** (K9 row 4), so an unattended `--auto-yes` run **aborts** on it rather than proceeding. Proven by an end-to-end fixture test. This is the direct regression for the incident that produced this ticket.
**AC20..AC27 (corrections round)** — canonical text lives in `verification-gate.md` § New acceptance criteria, added after an adversarial implementation review of `1eb53a1..808db35` found 7 BLOCKERs and 6 MAJORs. They cover per-rule non-dedup (K18a), denial completeness (K18b), mandatory `--command` (K19), fail-closed classifier (K20a), no self-restamp (K20b), bootstrap no-write-before-classification, the `rm` gap + documented regex-evasion limitation (K21), and truthful inventory. AC3, AC9 and AC11 are revised in the same table. Pointer, not restatement (FR-23).

19. **AC19** — `policies/approval-policy.yml` no longer claims hooks enforce `approval_authors` against a self-attested role, and `approved_by` / `ticket` are labelled audit metadata at every canonical mention. Grep-testable: no occurrence of an authorship-enforcement claim remains in `policies/approval-policy.yml`, `flow-skills/role-discipline/references/deploy.md`, or `workflows/greenlight-deploy.md`.
17. **AC17** — Full gate green: `bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && python3 hooks/tests/run_hook_tests.py --compare-subprocess && bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh` — unscoped, no `FF_ONLY`.
18. **AC18** — Zero mirror drift after implementation: `bash hooks/local/mirror-skills.sh` and `bash hooks/local/mirror-agents.sh` produce an empty `git diff`.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths (`policies/protected-paths.yml`) | `hooks/**`, `policies/**`, `audit/**` are `fusebase_flow_internals` — every commit needs the FR-07 bootstrap approval path (`hooks/local/write-bootstrap-approval.sh`), never `--no-verify` |
| Mixed-fleet considerations | Consumers on ≤4.6.1 have no managed-content base → adoption **synthesizes** one from the upstream tag matching their installed `VERSION` (K13/AC13b), so classification is real on the first run; `unknown-base` (preserve + report) is the fallback only when that tag cannot be resolved. `bootstrap-upgrade.sh` is the documented transition (K10) |
| Migration approach | Two-stage, no data migration: this release ships strict-capable validator with strict **OFF** + inventory (AC12); a later release flips the default. Expiry is never synthesized onto legacy artifacts |
| Auth model | Unchanged and now truthfully documented: Flow enforces schema, expiry, action agreement, command/repo binding — **not** operator identity (K3) |
| Quality bar (lint/typecheck/tests) | New `hooks/tests/test-approval-binding.sh`, `test-command-policy.sh`, `test-upgrade-conflict-classification.sh` + fixtures; all registered in `hooks/tests/run-tests.sh` `FF_TAGS` |

## Wire format

Approval artifact, schema v2 (command approvals):

```jsonc
{
  "schema_version": 2,
  "action": "production_deploy",       // MUST equal the filename action (AC1)
  "scope": "<slug>",
  "expires_at": "2026-07-28T18:00:00Z",// mandatory, parseable UTC (AC2)
  "approved_by": "pavel",              // AUDIT METADATA ONLY — not authenticated (K3)
  "ticket": "<slug>",                  // AUDIT METADATA ONLY — not a security binding (K3)
  "reason": "approve deploy now",
  "repo_id": "<sha256 of git-root realpath>",  // enforced when present (AC9)
  "command_digest": "<sha256 of canonical command>" // enforced when present (AC9)
}
```

Managed-content base manifest:

```jsonc
{
  "schema_version": 1,
  "flow_version": "4.7.0",
  "asset_count": 1,
  "assets": [{ "path": "hooks/shared/command_policy.py", "sha256": "…" }],
  "manifest_self_sha256": "…"
}
```

Upgrade classification verdicts (full set — see the K9 truth table): `current` · `upstream-only` · `consumer-only` · `changed-by-both` · `upstream-deleted` · `consumer-added` · `upstream-added` · `consumer-deleted` · `unknown-base`.

Approval verdicts are **state only** (K17): `VALID` · `EXPIRED` · `MISSING_EXPIRY` · `MALFORMED` · `ACTION_MISMATCH` · `BINDING_MISMATCH`. Mode resolution is the separate predicate `is_acceptable(verdict, *, strict)`.

## Backend changes

- `hooks/shared/command_policy.py` — schema-v2 validation, body/filename action agreement, parsed expiry, type-safe load, root threading, fail-closed regex/empty-policy, all-matching-rules, binding checks, compat/strict mode, structured denial reason. **Watch FR-25**: currently 165 lines; extract artifact validation to `hooks/shared/approval_artifact.py` on the responsibility seam rather than growing one file.
- `hooks/shared/approval_artifact.py` *(new)* — single canonical artifact loader/validator shared by `command_policy` and `path_policy`; owns expiry parsing, schema detection, verdict enum.
- `hooks/shared/path_policy.py` — delegate expiry/schema handling to `approval_artifact`; bootstrap semantics untouched.
- `hooks/shared/policy_loader.py` — accept and thread `root`.
- `hooks/handlers/pre_tool_use.py`, `hooks/handlers/permission_request.py` — pass root; render the AC14 denial message.
- `hooks/local/approve-local.sh` — single-language JSON serialization, action/slug validation, atomic write, re-parse verify, merged local policy, `--inventory`.
- `hooks/local/lib/active-approvals.sh` — shared expiry semantics, schema/status-aware reporting.
- `hooks/local/lib/managed_content_manifest.py` *(new)*, `hooks/local/stamp-managed-content-manifest.sh` *(new)*, `hooks/local/verify-managed-content-manifest.sh` *(new)*.
- `hooks/local/upgrade.sh` — three-way classification + AC15 report + `--auto-yes` containment.
- `hooks/local/bootstrap-upgrade.sh`, `install.sh`, `hooks/local/preflight.sh` — base capture + adoption path.
- `policies/command-policy.yml`, `policies/approval-policy.yml`, `policies/required-artifacts.yml`.
- `audit/managed-content-manifest.json` *(new)*, `audit/hook-layer-manifest.json` *(restamp)*.

## Client / extension / SPA changes

None — internal developer tooling only (see § Audience classification).

## Risks

- **Over-tightening breaks the DP.6 flow.** Mitigation: the typed phrase stays the authority event; the writer captures command/repo automatically; no nonce, no ticket ceremony, no operator-typed command (K3, K5).
- **FR-07 bootstrap approvals rejected by the new schema.** Mitigation: schema strictness is scoped to *command* approvals; `protected_path_edit` artifacts keep `path_policy` semantics; `test-bootstrap-exception.sh` is a required green (AC11).
- **Compound-command all-match floods the operator with serial denials.** Mitigation: one denial names the complete required-action set (AC6, AC14).
- **Command-digest canonicalization drifts between mint and execution.** Mitigation: hash the exact command string the hook receives, with only whitespace-collapse normalization documented; never normalize semantics-changing shell syntax (K6).
- **Upgrade classifier makes first adoption unusable by stopping on every unknown path.** Mitigation: `unknown-base` is *preserve + report*, not *abort*; abort is reserved for `changed-by-both` (K9).
- **The classifier release cannot install itself through the old engine** — the old `upgrade.sh` would overwrite the new validator first. Mitigation: `bootstrap-upgrade.sh` staged-engine hop is the documented and tested transition (K10, AC16).
- **FR-25 module-size ceiling** on `command_policy.py` and `upgrade.sh`. Mitigation: extraction along the seams named above is in-scope, not scope creep.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | Single-use consumption in this release? | No — deferred to backlog; host lifecycle contract absent (K11) | 2026-07-28 |
| Q-B | Enforce operator authorship? | Not enforceable; document as audit metadata and fix the contradictory comment (K3) | 2026-07-28 |
| Q-C | Strict schema default this release? | No — compat + inventory now, strict default next release (K7) | 2026-07-28 |
| Q-D | Lightweight-lane gate: accept `lightweight_deploy`? | Yes, with the process-authoritative trust boundary documented (K5) | 2026-07-28 |

Operator authorized end-to-end autonomous execution for this run; decisions are PO recommendations locked under that authorization and are flagged as assumptions in `decisions.md`.

## Related

- `docs/specs/approval-binding-and-upgrade-classification/decisions.md`
- `docs/specs/approval-binding-and-upgrade-classification/tasks.md`
- `docs/specs/approval-binding-and-upgrade-classification/verification-gate.md`
- Consumer proposal: `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-07-28-approval-artifact-binding-and-upgrade-conflict-classification.md`
