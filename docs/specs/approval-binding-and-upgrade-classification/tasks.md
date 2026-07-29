# Tasks — approval-binding-and-upgrade-classification

**T-counter going in:** T0 (next task is T1)
**Task range:** T1..T14 (original) + T17..T29 (corrections round, 2026-07-28 adversarial review)
**Gate task:** T15 (T-gate — runs after T29)
**Deploy task:** T16 (T-deploy — runs after T15)
**Linked spec:** `docs/specs/approval-binding-and-upgrade-classification/spec.md`
**Linked decisions:** `docs/specs/approval-binding-and-upgrade-classification/decisions.md`

## Task chain

| T# | Track | Scope | Cites decision | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | docs/policy | Truthful trust model: correct `approval_authors` comment; state audit-metadata semantics | K3 | — | — | pending |
<!-- Revision note (FR-18): T2/T4/T7/T9/T10/T11/T12/T13/T14 scopes and the parallelism diagram were superseded after adversarial review found the base-synthesis hole (K13), the dead `fallthrough` key (K16), and the verdict/mode conflation (K17). Prior state is in git history. -->

| T2 | hooks | New `hooks/shared/approval_artifact.py` — canonical loader, parsed expiry, verdict enum | K1, K2, K4 | T1 | — | pending |
| T3 | hooks | `command_policy.py` adopts `approval_artifact`: body/filename action agreement, type-safe load, root threading | K1, K2, K4 | T2 | — | pending |
| T4 | hooks | Fail-closed regex + empty/missing policy; all-matching-rules collection | K4, K8 | T3 | — | pending |
| T5 | hooks | Binding enforcement: `command_digest` + `repo_id` when present | K2, K6 | T3 | — | pending |
| T6 | hooks | Denial-message renderer (AC14) wired into both handlers | K12, K8 | T4, T5 | — | pending |
| T7 | policy | SQL case-insensitivity + `ALTER TABLE`; `any_of` deploy actions (Lightweight parity) | K5, K8 | T4 | — | pending |
| T8 | hooks | `approve-local.sh` rewrite: single-language JSON, action/slug validation, atomic write, merged local policy, binding fields | K2, K6 | T2, T7 | — | pending |
| T9 | hooks | `approve-local.sh --inventory` + `strict_approvals` flag (default OFF) | K7, K12 | T8 | — | pending |
| T10 | hooks | Cross-carrier expiry fix: `path_policy.py` + `active-approvals.sh` delegate to `approval_artifact` | K1 | T2 | — | pending |
| T11 | hooks | Managed-content base manifest: `managed_content_manifest.py` + stamp/verify scripts + `audit/managed-content-manifest.json` | K9 | T2 | — | pending |
| T12 | hooks | `upgrade.sh` three-way classification + `--auto-yes` containment + conflict report (AC15) | K9, K12 | T11 | — | pending |
| T13 | hooks/docs | Classifier adoption hop via `bootstrap-upgrade.sh`; `install.sh` base capture; preflight diagnosis | K10 | T12 | — | pending |
| T14 | docs | Backlog ticket for deferred single-use consumption; Flow docs + skills + mirrors + CHANGELOG | K11, K3, K5 | T1..T13 | — | pending |
| T17 | hooks | `parse_expiry` totality: extreme ISO offsets must not raise `OverflowError` | K1, K4 | T14 | — | pending |
| T18 | hooks | K6 revision: `compute_command_digest` = strip-only; no interior whitespace collapse | K6 (rev) | T17 | — | pending |
| T19 | hooks | K18(a): per-rule requirements — remove de-duplication by display action | K18 | T17 | — | pending |
| T20 | hooks | K18(b): denials name ALL required actions; fix the test that encoded unsatisfied-only | K18, K12 | T19 | — | pending |
| T21 | hooks | K4 totality: non-mapping `only_when` and malformed `match_order` → `FLOW-POLICY-ERROR` | K4 | T20 | — | pending |
| T22 | hooks | K19: `--command` mandatory for command-gated actions; denial emits bound resolving invocation | K19, K12 | T18, T20 | — | pending |
| T23 | hooks | Cross-carrier strict/compat unification: compat audit log + strict in `active-approvals.sh` | K1, K7, K17 | T17 | — | pending |
| T24 | hooks | Truthful inventory: check `repo_id` against current root; command binding = `UNCHECKED`, never `ACCEPT` | K7, K17 | T18 | — | pending |
| T25 | hooks | K20(a): classifier-unavailable → fail closed; legacy copy only behind explicit unsafe flag | K20 | T14 | — | pending |
| T26 | hooks | K20(b): preflight stops advising self-restamp of a diverged base | K20 | T25 | — | pending |
| T27 | hooks | Bootstrap writes nothing before classification authorizes; fix the `git archive`/autocrlf comment | K10, K20 | T26 | — | pending |
| T28 | policy/docs | K21: fix `rm` pattern gap; document regex quote-fragmentation limit; file shell-evasion backlog | K21, K3 | T21 | — | pending |
| T29 | tests | Regression discriminators: fixtures 22/23, AC16 incident `changed-by-both`, `core.autocrlf=true` | K18, K13 | T19, T20, T27 | — | pending |
| T15 | — | verification gate (no commit; gate report only) | — | T1..T14, T17..T29 | — | pending |
| T16 | — | deploy + post-deploy probes + single docs commit | — | T15 | — | pending |

## Per-task detail

### T1. Truthful trust model

**Track:** docs/policy
**Scope:** Correct the internally contradictory approval contract. `policies/approval-policy.yml:103-106` claims hooks check the self-attested role against `approval_authors`; the same file admits at `:44-46` that only filename + expiry are checked. Replace the comment with the enforceable/not-enforceable split, mark `approved_by` and `ticket` as audit metadata, and cross-reference K3. Mirror the same statement into the deploy role reference and greenlight workflow so an agent reading either does not re-assert authorship enforcement.
**Files:** `policies/approval-policy.yml`, `flow-skills/role-discipline/references/deploy.md`, `workflows/greenlight-deploy.md`, `docs/hook-coverage.md`
**Module-size (FR-25):** all targets under ceiling
**Cites:** decision K3
**Depends on:** —
**Acceptance:** AC19
**Tests:** `bash hooks/tests/test-prohibition-residency.sh`; `bash hooks/local/rule-inventory.sh`; grep assertion that no authorship-enforcement claim survives in the three canonical files (AC19)
**Worker-undisturbed:** `policies/**`, `flow-skills/**`, `workflows/**` are `fusebase_flow_internals` — mint the FR-07 bootstrap approval (`bash hooks/local/write-bootstrap-approval.sh`), commit, then `--consume`. Never `--no-verify`.
**Mirrors:** re-run `bash hooks/local/mirror-skills.sh`; stage the regenerated `.claude/skills/**`, `.agents/skills/**`, `audit/skill-mirror-manifest.txt` in the SAME commit.
**SHA:** `f618338`

---

### T2. `hooks/shared/approval_artifact.py` — canonical loader

**Track:** hooks
**Scope:** New module owning every artifact-reading concern currently duplicated across three carriers. Public surface per K17 — verdict is **state**, acceptability is a **separate predicate**:

- `load(path) -> Artifact | None` — never raises on any file content.
- `Verdict` enum, state only: `VALID`, `EXPIRED`, `MISSING_EXPIRY`, `MALFORMED`, `ACTION_MISMATCH`, `BINDING_MISMATCH`. **No `LEGACY_OK`** — that conflated state with mode.
- `parse_expiry(value) -> datetime | None` — parsed UTC, **never** lexicographic string compare (the `command_policy.py:30-31,47-48` defect).
- `evaluate_artifact(data, *, expected_action, command_digest=None, repo_id=None) -> Verdict` — mode-independent.
- `is_acceptable(verdict, *, strict) -> bool` — the only place `strict` is consulted. Pass-sets per carrier are in K17's table; implement exactly that table.

All type coercion happens inside the guard: a JSON array, a numeric `expires_at`, `null`, or any non-dict top level yields `MALFORMED`, never an exception (the `command_policy.py:43-48` defect where parsing is guarded but field access is not).
**Files:** `hooks/shared/approval_artifact.py` (new), `hooks/tests/test-approval-binding.sh` (new), register the `approval-binding` tag in `hooks/tests/run-tests.sh` `FF_TAGS`
**Module-size (FR-25):** new module, target ≤250 lines — this IS the K1 extraction seam
**Cites:** decisions K1, K2, K4, K17
**Depends on:** T1
**Acceptance:** AC2, AC3
**Tests:** table-driven cases for every `Verdict`: missing key, empty string, `null`, integer, non-UTC string, malformed ISO, valid-future, valid-past, top-level array, top-level string, non-dict, unicode. Assert `load()` raises on nothing. Separately assert `is_acceptable` matches K17's per-carrier pass-set for both `strict` values.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval as T1.
**SHA:** `bf2d0ca`

---

### T3. `command_policy.py` adopts the canonical loader

**Track:** hooks
**Scope:** Replace `_approval_artifact_present()` (`hooks/shared/command_policy.py:34-51`) with a call into `approval_artifact`. Enforce body/filename `action` agreement (AC1). Thread the resolved `root` into `get_policy("command-policy")` and `get_policy("approval-policy")` at `:136-140` — today they resolve from process CWD while artifact lookup uses the passed root (AC4). Return the failing `Verdict` on the `CommandDecision` so T6 can render a specific reason. Keep `approval_artifact_present` on the dataclass for compatibility; add `approval_verdict` and `required_actions`.
**Files:** `hooks/shared/command_policy.py`, `hooks/shared/policy_loader.py` (accept + thread `root`), `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** `command_policy.py` is 165 lines; validation logic moves OUT to T2's module, so it must not exceed ~220
**Cites:** decisions K1, K2, K4
**Depends on:** T2
**Acceptance:** AC1, AC3, AC4
**Tests:** AC1 mismatch case; AC4 foreign-CWD evaluation asserting decision parity with repo-root evaluation
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `42bfdaf`

---

### T4. Fail-closed policy defects + all-matching-rules

**Track:** hooks
**Scope:** Three changes, all closing "gate fails open" paths.

(a) `re.error` in `_evaluate_deny` (`:64-67`), `_evaluate_require_approval` (`:83-87`) and `_evaluate_allow` (`:127-131`) currently `continue`, silently disabling the rule; make each **deny** with a policy-error reason. A missing or empty command policy must deny rather than reach `default: allow` at `:136-158`.

(b) `_evaluate_require_approval` returns on first match at `:79-99`; collect **every** matching rule and require an artifact for each, returning the complete unsatisfied set on `required_actions`. Stage order is unchanged: `deny` still short-circuits, so a denied command never reaches `require_approval`.

(c) Per K16, delete the dead `fallthrough: true` key at `policies/command-policy.yml:88` and state the all-match semantics in that file's header. Accepted consequence: `fusebase deploy && rm build.log` now requires `destructive_file_delete` as well — correct, and AC14's single message keeps it to one round-trip.

**Recovery note for the implementer:** with (a) live, a mid-edit invalid `policies/command-policy.yml` denies every Bash command in a hooks-wired tree (`policy_loader.py` raises on load). The escape hatch is the **Edit tool**, which routes through the separate path-policy gate — never `--no-verify`.
**Files:** `hooks/shared/command_policy.py`, `policies/command-policy.yml`, `hooks/tests/test-command-policy.sh` (new; register `command-policy` in `FF_TAGS`)
**Module-size (FR-25):** if `command_policy.py` approaches 250, extract rule-matching into `hooks/shared/command_rules.py` on that seam — in-scope, not scope creep
**Cites:** decisions K4, K8, K16
**Depends on:** T3
**Acceptance:** AC5, AC6
**Tests:** deliberately broken regex in each of the three stages → deny; empty policy file → deny; `fusebase deploy && npx prisma migrate deploy` with only a deploy artifact → deny naming `database_migration`; `fusebase deploy && rm build.log` → deny naming `destructive_file_delete` (the K16 consequence, asserted deliberately rather than discovered); a `rm -rf` command still hits the `deny` stage and never reaches all-match
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `5745d08`

---

### T5. Binding enforcement

**Track:** hooks
**Scope:** When an artifact carries `command_digest`, it authorizes only a command whose digest matches; when it carries `repo_id`, only that repository. Absent fields → action-scoped as before (K2 additive rule). `repo_id = sha256(realpath(git_root))`. `command_digest = sha256(command.strip())` per K6 **as REVISED 2026-07-28** — trim leading/trailing whitespace ONLY, never collapse interior whitespace (the original collapse rule produced the `--app "safe  prod"` == `--app "safe prod"` collision; T18 implements the revision), normalize nothing else, and document the rule in a ≤1-line FR-22 tripwire beside the function since a future editor "improving" normalization would silently widen what an artifact authorizes.
**Files:** `hooks/shared/approval_artifact.py`, `hooks/shared/command_policy.py`, `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K2, K6
**Depends on:** T3
**Acceptance:** AC9
**Tests:** matching digest → allow; one-character-different command → deny; same command different repo → deny; artifact with neither field → legacy allow (compat) and reject (strict); leading/trailing-whitespace-only difference → allow; **interior**-whitespace difference inside a quoted argument → deny (K6 revised; asserted in T18)
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `4c1f8d1`

---

### T6. Denial-message renderer (internal CLI UX)

**Track:** hooks
**Scope:** One shared formatter consumed by both entry points — `hooks/handlers/pre_tool_use.py:62-76` and `hooks/handlers/permission_request.py:40-57` — replacing the current five-line generic reason at `command_policy.py:104-111` that says "no artifact found" whether the artifact was absent, expired, action-mismatched or digest-mismatched. Required order and content per AC14: (1) what was blocked, (2) **every** required action (K8), (3) the specific per-artifact failure reason drawn from the `Verdict`, (4) one exact resolving command. ≤8 lines. No framework jargon that is not immediately cued by a path the operator can open. Pass `root` from both handlers so policy resolution is root-anchored (AC4).
**Files:** `hooks/shared/command_policy.py` or a small `hooks/shared/denial_message.py` if the formatter pushes `command_policy.py` toward ceiling, `hooks/handlers/pre_tool_use.py`, `hooks/handlers/permission_request.py`, `hooks/tests/fixtures/*.json` (new approval-denial fixtures), `hooks/tests/run_hook_tests.py` (`EXPECTED_HANDLER_FIXTURES` count)
**Module-size (FR-25):** extract to `denial_message.py` if needed — named seam
**Audit emission:** both handlers must include the resolved `approval_verdict` token in the `audit_logger` `extra` payload — smoke S1/S2 assert on that token as ground truth, not on stdout.
**Cites:** decisions K12, K8, K17
**Depends on:** T4, T5
**File-conflict note:** T6 and T7 both edit `hooks/shared/command_policy.py`. They must be run **serially**, never delegated in parallel.
**Acceptance:** AC14, and AC6's "single message" half
**Tests:** fixture per verdict asserting the specific reason token appears and that a stale-vs-absent artifact produce **different** messages; assert ≤8 lines; `python3 hooks/tests/run_hook_tests.py --compare-subprocess` stays 100%
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `69813cc`

---

### T7. SQL hardening + Lightweight-lane gate parity

**Track:** policy
**Scope:** (a) `policies/command-policy.yml:79-82` — make destructive-SQL matching case-insensitive (per-rule `flags: [i]` read by `command_policy.py`, not a global flag change) and add `ALTER\s+TABLE`. (b) K5: the `fusebase deploy` rule at `:43-46` gains `any_of: [production_deploy, lightweight_deploy]`; the validator satisfies the rule when **any** listed action has a valid artifact. Document in `flow-skills/lightweight-lane/SKILL.md` and `workflows/lightweight-lane.md` that lane classification is process-authoritative — the hook cannot verify LL-eligibility.

**Rule shape (locked here so the implementer invents nothing):** a `require_approval` rule is `{pattern, action | any_of, flags?, reason, rule_id, only_when?}`. `action` and `any_of` are mutually exclusive; exactly one is required. When `any_of` is used, the **first** listed action is the rule's display name for the T6 denial renderer and the T9 inventory, so `production_deploy` leads. `flags` accepts `[i]` only for now. Bump `policies/command-policy.yml` `schema_version: 1 → 2` and add the shape to the file header. `policies/required-artifacts.yml:73-78` already uses an `any_of` shape for the same Full-vs-Lightweight choice — match its spelling rather than inventing a second one.
**Files:** `policies/command-policy.yml`, `hooks/shared/command_policy.py` (per-rule flags + `any_of`), `flow-skills/lightweight-lane/SKILL.md`, `workflows/lightweight-lane.md`, `flow-skills/role-discipline/references/deploy.md`, `hooks/tests/test-command-policy.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K5, K8
**Depends on:** T4
**Acceptance:** AC7, AC8
**Tests:** `psql -c "drop table users"`, `psql -c "DROP TABLE users"`, `psql -c "ALTER TABLE users ADD COLUMN x int"` all require `database_migration`; `fusebase deploy` allowed with a `lightweight_deploy` artifact and separately with a `production_deploy` artifact, **through both handlers**
**Worker-undisturbed:** `policies/**`, `flow-skills/**`, `workflows/**` — FR-07 bootstrap approval.
**Mirrors:** re-run `mirror-skills.sh`; stage regenerated mirrors + `audit/skill-mirror-manifest.txt` in the same commit.
**SHA:** `30ca6e3`

---

### T8. Safe approval writer

**Track:** hooks
**Scope:** Rewrite artifact authoring in `hooks/local/approve-local.sh:44-91`. Today `$USER`, `$SLUG`, `$REASON` and `$ACTION` are interpolated unescaped into a JSON heredoc at `:75-83`, and `$ACTION` is additionally interpolated into **Python source** at `:56-67`. Filename construction at `:69-71` has **no** validation of either component today — that guard is being added, not fixed. Replace with: values passed as `argv` to one Python process that reads the merged policy via `policy_loader`, validates, and `json.dumps` the whole object; validate `<action>` against the merged policy's `require_approval` keys (unknown → exit 2, no file written) and `<slug>` against `^[A-Za-z0-9._-]{1,64}$` (traversal + same-day-overwrite guard); write to a same-directory temp file and atomically replace; re-read and parse the artifact before printing success. Emit schema v2 with `schema_version`, `repo_id`, `command_digest` (from an optional `--command` argument), and a mandatory parseable `expires_at`.

**Do not touch `hooks/local/write-bootstrap-approval.sh`.** It authors `protected_path_edit` artifacts through `path_policy` on an independent code path; it already serializes with `json.dumps` (`:70-96`) and is correct. T8 is scoped to command approvals.
**Files:** `hooks/local/approve-local.sh`, `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K2, K6
**Depends on:** T2, T7
**Acceptance:** AC10
**Tests:** slug/reason containing `"`, `\`, literal newline, `$(id)`, and unicode → artifact parses and values round-trip exactly; unknown action → exit 2 and **no file created**; `../escape` slug → exit 2; interrupted write leaves no partial artifact
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `fd4db2b`

---

### T9. Inventory + strict flag

**Track:** hooks
**Scope:** `bash hooks/local/approve-local.sh --inventory` prints one row per artifact under `state/approvals/`: `file · action · schema · expiry-state · binding-state · verdict(strict)`, plus a trailing count of how many would be rejected under strict. Add `strict_approvals: false` to `policies/approval-policy.yml` with a comment naming the K7 flip release; `approval_artifact.is_acceptable` honours it (per K17 it is the **only** consumer of `strict`). Register `strict_approvals` in `policy_loader.py`'s tighten-only rule set at `:130-144` so that once the default flips, an `approval-policy.local.yml` cannot set it back to `false` — `local_override_may_relax: false` must actually cover it. In compat mode a legacy artifact is accepted **and** logged once via `hooks/shared/audit_logger.py` so the acceptance is auditable rather than silent.
**Files:** `hooks/local/approve-local.sh`, `policies/approval-policy.yml`, `hooks/shared/approval_artifact.py`, `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K7, K12
**Depends on:** T8
**Acceptance:** AC12
**Tests:** fixture dir containing one valid v2, one expiry-less legacy, one expired, one malformed → inventory reports four distinct verdicts and a reject-count of 3 under strict; strict=true denies the legacy artifact that compat allows
**Worker-undisturbed:** `hooks/**`, `policies/**` — FR-07 bootstrap approval.
**SHA:** `635cb34`

---

### T10. Cross-carrier expiry fix

**Track:** hooks
**Scope:** The `if expires and expires < now` hole is not unique to the reported file — it is verbatim at `hooks/shared/path_policy.py:237-239` and `hooks/local/lib/active-approvals.sh:35-38`. Route both through `approval_artifact`'s parsed-expiry semantics and K17's per-carrier pass-sets. `path_policy.py` bootstrap handling (`:241-275`: exact path membership, no-glob, `operation == flow-internals-bootstrap`, `tree_digest`) is **unchanged** — only expiry/schema handling is delegated. `active-approvals.sh` becomes status-aware, reporting `active | expired | legacy-no-expiry | malformed` instead of treating missing expiry as active forever.

**Blast-radius constraint:** `hooks/local/fusebase-flow-health-check.sh:162` is the sole consumer of `ffhc_collect_active_approvals` and reads its arrays (`ACTIVE_ARTIFACTS`, `ARTIFACT_NOTES`, `DEFERRED_CHECKS`, `DEFERRED_BY_ARTIFACT`). **Keep the array contract identical** — the new status belongs in the `ARTIFACT_NOTES` text only. Changing the array shape would silently break `EXCEPTION_IN_EFFECT` classification in the health engine.
**Files:** `hooks/shared/path_policy.py`, `hooks/local/lib/active-approvals.sh`, `hooks/local/fusebase-flow-health-check.sh` (verify only — expect no edit), `hooks/tests/test-bootstrap-exception.sh` (extend, do not weaken)
**Module-size (FR-25):** `path_policy.py` is 316 lines; delegation should reduce it — must not grow
**Cites:** decisions K1, K17
**Depends on:** T2
**Acceptance:** AC11
**Tests:** `bash hooks/tests/test-bootstrap-exception.sh` stays green unmodified in intent; new case — a `protected_path_edit` artifact with no `expires_at` no longer authorizes indefinitely; health-deferral artifacts still surface in `active-approvals`; `bash hooks/local/fusebase-flow-health-check.sh` still reports `EXCEPTION_IN_EFFECT` for a deferral artifact (array-contract regression)
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `4d23f30`

---

### T11. Managed-content base manifest

**Track:** hooks
**Scope:** Record what upstream actually shipped, so an upgrade can tell consumer edits from upstream edits. New `hooks/local/lib/managed_content_manifest.py` with subcommands `stamp` / `verify` / `classify` / `list-managed`, mirroring the byte-stable, timestamp-free design of `hooks/local/lib/hook_manifest.py:75-112`, plus thin wrappers `hooks/local/stamp-managed-content-manifest.sh` and `hooks/local/verify-managed-content-manifest.sh`, producing `audit/managed-content-manifest.json`.

**Canonical list home (K14):** the managed-path list moves **into this Python module** and is exposed by `list-managed` (one path per line). `hooks/local/upgrade.sh` stops declaring `CONTENT_DIRS` / `CONTENT_FILES` inline at `:232-235` and populates them from that output instead. The list must live in exactly one place or the manifest and the engine will eventually disagree about what "managed" means — a silent correctness hole in the classifier. `audit/managed-content-manifest.json` itself joins the managed file set (K13b) and is applied last.
**Files:** `hooks/local/lib/managed_content_manifest.py` (new), `hooks/local/stamp-managed-content-manifest.sh` (new), `hooks/local/verify-managed-content-manifest.sh` (new), `audit/managed-content-manifest.json` (new), `audit/README.md`, `hooks/local/lib/hook_manifest.py` (enroll the new local-lib Python; its local-lib coverage at `:96-98` is currently narrow), `.github/workflows/fusebase-flow-verify.yml` (freshness gate), `hooks/tests/test-upgrade-conflict-classification.sh` (new; register `upgrade-classify` in `FF_TAGS`)
**Module-size (FR-25):** new module target ≤400 lines
**Cites:** decisions K9, K14
**Depends on:** T2
**Acceptance:** AC13 (manifest half)
**Tests:** stamp twice → byte-identical output (no timestamps); mutate one covered file → verify fails naming that path; CI freshness gate fails on an unstamped change; new local-lib file is hook-manifest-covered; `list-managed` output and the set `upgrade.sh` actually iterates are asserted identical (the K14 single-home property)
**Worker-undisturbed:** `hooks/**`, `audit/**` — FR-07 bootstrap approval.
**SHA:** `22e1b89`

---

### T12. Three-way upgrade classification

**Track:** hooks
**Scope:** `hooks/local/upgrade.sh:246-257` currently only asks "does this directory differ" and `:366-388` copies upstream over it wholesale. Replace with per-**path** classification against the base manifest into exactly one of the **ten** K9 states, applying that table's action columns — notably `--auto-yes` must **never** overwrite `consumer-only`, `changed-by-both`, dirty `upstream-deleted`, or `unknown-base`, and **aborts** on `changed-by-both`.

**Apply granularity (K15) — this is the part that must be rewritten, not just extended.** Today's engine applies at directory granularity via a whole-tree `cp -R`. The new apply loop is driven per file by the classification list, so a directory holding one `consumer-only` file among a hundred `upstream-only` files refreshes the ninety-nine and preserves the one. The existing directory-level `.pre-upgrade-<TS>` backup at `:368-388` is **kept unchanged** — it already snapshots everything before any write, so no per-file backup scheme is introduced and the retention pruning at `:561-607` is untouched.

**Base lifecycle (K13b) — ordering is fixed:** classify against the OLD base → apply → install the SOURCE tree's manifest as the NEW base, last. Without this the classifier is single-shot and the next release misreads every 4.7.0 file as consumer-divergent.

Handle upstream deletion explicitly (`:366-378` currently leaves upstream-removed files behind) with recoverable backup. Emit the AC15 report: safe groups collapsed to counts, `consumer-only` / `changed-by-both` / dirty-deleted / `unknown-base` paths enumerated in full and never elided, backup directory named, exact resume command last.
**Files:** `hooks/local/upgrade.sh`, `hooks/local/lib/managed_content_manifest.py`, `hooks/tests/test-upgrade-conflict-classification.sh`
**Module-size (FR-25):** `upgrade.sh` is large — put classification logic in the T11 Python module and keep the shell as orchestration; extraction here is in-scope
**Cites:** decisions K9, K12, K13, K15
**Depends on:** T11
**Acceptance:** AC13, AC13b, AC13c, AC15
**Tests:** full ten-state matrix from K9, including `consumer-added`, `upstream-added` and `consumer-deleted`; a **mixed-class directory** proving partial apply (AC13c); `--auto-yes` proven non-destructive on all four protected classes and proven to abort on `changed-by-both`; two consecutive upgrades proving the base refresh (AC13b); report asserted to name every `consumer-only` path literally
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `af18431`

---

### T13. Classifier adoption hop

**Track:** hooks/docs
**Scope:** Two distinct problems, both required for the classifier to work on a real fleet.

**(a) The staged-engine hop.** The first classifier release cannot install itself through the old engine — the old `upgrade.sh` copies upstream over `hooks/**`, including the new engine, before any classification runs. Route adoption through the existing mechanism at `hooks/local/bootstrap-upgrade.sh:9-28,123-174`, which copies `hooks/local/lib/` and `exec`s the **fetched** engine rather than the installed one.

**(b) Base synthesis (K13a) — without this, (a) is useless.** A consumer arriving from ≤4.6.1 has no base manifest. If every path therefore classifies `unknown-base`, K9 preserves all of them and the 4.7.0 upgrade **installs nothing** — the classifier release cannot deliver its own content. So bootstrap adoption checks out the upstream tag equal to the consumer's installed `VERSION` (e.g. `v4.6.1`) from the clone it has **already fetched**, stamps a base manifest from that tree, and classifies against it. The tag is not a guess: it is byte-identical to what the consumer's last install/upgrade wrote. `unknown-base` remains only for an unresolvable tag (forked or unreleased `VERSION`).

Add base capture to `install.sh` (whose steps at `:12-37` capture no consumer-side base today) so fresh installs start with a real base. `hooks/local/preflight.sh` diagnoses a missing or stale base manifest. Document the transition in install/upgrade docs and release notes.
**Files:** `hooks/local/bootstrap-upgrade.sh`, `install.sh`, `hooks/local/preflight.sh`, `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`, `README.md`, `hooks/tests/test-upgrade-conflict-classification.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K10, K13
**Depends on:** T12
**Acceptance:** AC16, AC13b
**Tests:** end-to-end fixture — a 4.6.1 tree with a locally patched `hooks/shared/command_policy.py`; run the documented bootstrap path; assert the patch is **still present** afterwards and that the path is **named literally in the report**. Expected classification is **`changed-by-both`** (K9 row 4), because 4.7.0 also rewrites that file — not `consumer-only`, which the first draft of this plan wrongly assumed. Assert `--auto-yes` **aborts** on it. Second assertion: a 4.6.1 file the consumer never touched classifies `upstream-only` and **is** refreshed — this is what proves base synthesis worked and the upgrade is not a silent no-op. This test is the direct regression for the incident that produced this ticket.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `e64c5f2`

---

### T14. Docs, backlog, mirrors, changelog

**Track:** docs
**Scope:** (a) File `docs/backlog/approval-single-use-consumption/README.md` per K11 recording the prerequisites: stable host call ID across both hook entry points, consume-on-success / release-on-failure, orphan TTL + recovery, Windows and network-FS atomicity testing. (a2) File `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` from `templates/problem-catalog-entry.md`, and add its row to `docs/problem-catalog/README.md`. The lesson is **recurrence in a missed carrier**, not the defect itself: the v3.30.5 fail-closed sweep hardened `path_policy.py`, `hooks/git/pre-commit` and the secret scanner, and left `hooks/shared/command_policy.py` — a sibling enforcement carrier — untouched, so the same fail-open class survived a remediation that believed it was complete. Recurrence trigger to record: *when closing a defect class, enumerate every carrier of that class and assert each one, rather than fixing the carriers the report named.* Cross-link `docs/problem-catalog/security-check-fail-open-class/problem.md` and `docs/problem-catalog/live-enforcement-inertness/problem.md`; do **not** restate their content (FR-23). (b) Refresh `docs/hook-coverage.md`, `docs/framework.md`, `docs/architecture-overview.md`, `hooks/README.md` for the new schema, verdicts and classification. (c) `flow-skills/security-permissions-review/SKILL.md`: approval review moves from "artifact exists" to schema + binding validation. (d) CHANGELOG + release notes. (e) Re-run `mirror-skills.sh` / `mirror-agents.sh`, restamp `audit/hook-layer-manifest.json`, refresh the rule-inventory baseline, and stage all regenerated artifacts.
**Files:** `docs/backlog/approval-single-use-consumption/README.md` (new), `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` (new), `docs/problem-catalog/README.md`, `docs/backlog/index.md`, `docs/hook-coverage.md`, `docs/framework.md`, `docs/architecture-overview.md`, `hooks/README.md`, `flow-skills/security-permissions-review/SKILL.md`, `CHANGELOG.md`, `docs/release-notes/v4.7.0.md` (new), `.claude/skills/**`, `.agents/skills/**`, `audit/skill-mirror-manifest.txt`, `audit/agent-mirror-manifest.txt`, `audit/hook-layer-manifest.json`
**Module-size (FR-25):** N/A (docs)
**Cites:** decisions K11, K3, K5
**Depends on:** T1..T13
**Acceptance:** AC18
**Tests:** `bash hooks/local/mirror-skills.sh && bash hooks/local/mirror-agents.sh && git diff --exit-code`; `bash hooks/local/rule-inventory.sh`; `bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json`
**Worker-undisturbed:** `flow-skills/**`, `audit/**` — FR-07 bootstrap approval.
**SHA:** `f69fb41, 808db35`

---

## Corrections round (T17..T29)

**Input:** adversarial implementation review `docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md` (7 BLOCKER, 6 MAJOR, 1 MINOR). **Authority:** decisions K6 (REVISED) and K18..K21 — LOCKED; invent nothing beyond them. **Anti-tautology contract:** every task's primary test must go RED against the pre-correction code — the specific failing assertion is named per task and mirrored in `verification-gate.md` § Regression discriminators. Test files already exist and are FF_TAGS-registered; extend them, add no new test files except where named.

---

### T17. `parse_expiry` totality — OverflowError on extreme ISO offsets

**Track:** hooks
**Scope:** `hooks/shared/approval_artifact.py:74-94` — `parse_expiry()` parses via `datetime.fromisoformat` then converts at `:94` with `dt.astimezone(timezone.utc)`. For valid extreme aware stamps (`9999-12-31T23:59:59-14:00`, `0001-01-01T00:00:00+14:00`) the UTC conversion raises `OverflowError`, which is not caught (`:90-93` catches only `ValueError`/`TypeError` around `fromisoformat`, not the conversion). The exception escapes `evaluate_artifact()` (`:199`) and `evaluate()` — the handler emits no deny; AC3 ("never propagates an exception for any artifact content") is currently false. Fix: wrap the `replace`/`astimezone` conversion in the same try, catching `(ValueError, TypeError, OverflowError, OSError)` → return `None` (⇒ `MALFORMED` at `:200-201`). Extend the `:77-81` tripwire with one line: conversion errors are artifact content too.
**Files:** `hooks/shared/approval_artifact.py`, `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** `approval_artifact.py` is 265 lines — stays well under ceiling
**Cites:** decisions K1, K4; review BLOCKER #1
**Depends on:** T14
**Acceptance:** AC3 (restored to true)
**Tests:** RED without fix — `evaluate_artifact({"action": a, "expires_at": "9999-12-31T23:59:59-14:00"}, expected_action=a)` currently raises `OverflowError`; after fix it returns `MALFORMED` without raising. Same for the `-14:00`/`+14:00` lower bound. Boundary-but-convertible stamps (`9999-12-31T23:59:59+00:00`) still parse. Run through BOTH handlers via a fixture artifact (a hand-written far-boundary artifact + `run_hook_tests.py`) asserting a deny decision, not a traceback.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval (mint → commit → `--consume`); never `--no-verify`.
**SHA:** `7d60bdd`

---

### T18. K6 revision — strip-only command digest

**Track:** hooks
**Scope:** `hooks/shared/approval_artifact.py:101-111` — `compute_command_digest()` collapses interior whitespace (`_WS.sub(" ", command)` at `:110`, `_WS` at `:23`), so `fusebase deploy --app "safe  prod"` and `--app "safe prod"` hash identically: one approval authorizes a command targeting a different value. Per K6 **REVISED**: `canonical = (command or "").strip()` — trim ends only, collapse nothing. Delete `_WS` if unused elsewhere. Rewrite the `:104-108` tripwire to state the revised rule and cite the collision that forced it (interior whitespace inside quotes is data, not formatting). Update the stale "whitespace collapse" comments in `hooks/local/approve-local.sh:23-26` in the same commit (same semantic unit).
**Rollout note:** any v2 artifact minted with a collapse-era digest whose command contained interior whitespace runs will stop matching → re-approve via the T22 resolving invocation. Denial (one re-approval) is the safe direction; state this in CHANGELOG at T-deploy.
**Files:** `hooks/shared/approval_artifact.py`, `hooks/local/approve-local.sh` (comment only), `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decision K6 (REVISED 2026-07-28); review BLOCKER #3
**Depends on:** T17 (same file — serial)
**Acceptance:** AC9 (binding is one-command binding)
**Tests:** RED without fix — `compute_command_digest('fusebase deploy --app "safe  prod"') != compute_command_digest('fusebase deploy --app "safe prod"')` currently FAILS (digests are equal). Also: `"  cmd  "` and `"cmd"` still hash equal (strip retained); `"cmd  arg"` vs `"cmd arg"` hash differently; end-to-end — artifact minted with `--command 'x  y'` denies command `x y` with `BINDING_MISMATCH`.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `be0820f`

---

### T19. K18(a) — per-rule requirements, no display-name de-duplication

**Track:** hooks
**Scope:** `hooks/shared/command_policy.py:198-200` — `display = actions[0]; if display in verdicts: continue` skips any later matching rule whose display action was already recorded. The `fusebase deploy` `any_of` rule (display `production_deploy`, per `hooks/shared/command_rules.py:44-45`) therefore absorbs the separate `git push origin main` rule that genuinely requires `production_deploy`: with only a `lightweight_deploy` artifact, `fusebase deploy && git push origin main` is **allowed** — a live gate bypass. Fix per K18(a): evaluate **every** matching rule independently; a rule is satisfied only by its own `action`/`any_of` set; after satisfaction is known, de-duplicate only identical (requirement-set, satisfied) outcomes for rendering. `satisfied`/`unsatisfied`/`verdicts` become per-rule aggregates; an action name may appear as satisfied for one rule and unsatisfied for another only if the rules' accept-sets genuinely differ.
**Files:** `hooks/shared/command_policy.py`, `hooks/tests/test-command-policy.sh`
**Module-size (FR-25):** `command_policy.py` currently 308 lines; if the loop grows past ~350, extend the extraction seam in `hooks/shared/command_rules.py` — in-scope
**Cites:** decision K18; review BLOCKER #4
**Depends on:** T17 (branch base; different file — may run parallel to T18)
**Acceptance:** AC20
**Tests:** RED without fix — repo with only a `lightweight_deploy` artifact: `decide(repo, "fusebase deploy && git push origin main")` currently returns `allow`; must return `deny` with `production_deploy` in `required_actions`. Discriminator pair: same command with `lightweight_deploy` **and** `production_deploy` artifacts → allow (proves the fix is per-rule, not blanket-deny). Existing all-match cases stay green.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `e1c80be`

---

### T20. K18(b) — denials name ALL required actions

**Track:** hooks
**Scope:** `hooks/shared/command_policy.py:235-247` — the deny branch passes only `unsatisfied` into `render_approval_denial` (`:239`) and sets `required_actions=list(unsatisfied)` (`:245`), so with a deploy artifact present the compound deploy+migration denial names only `database_migration`. AC6/AC14/S5 require every required action in the one message. Fix: carry `all_required_actions` (every action any matched rule demands, satisfied or not) separately from `unsatisfied_actions` on `CommandDecision`; `hooks/shared/denial_message.py:40-67` renders the full set on line 2 with per-action status (`SATISFIED` vs the failing verdict token from `_REASON` at `:21-28`); the resolving invocation (`:63-66`) lists only unsatisfied actions. Audit `extra` payload carries both lists. Fix the test that encoded the wrong result: `hooks/tests/test-command-policy.sh:121-124` (`required=["database_migration"]`) — supersede in place per FR-18, expecting both actions.
**Files:** `hooks/shared/command_policy.py`, `hooks/shared/denial_message.py`, `hooks/handlers/pre_tool_use.py` + `hooks/handlers/permission_request.py` (audit payload passthrough only, if needed), `hooks/tests/test-command-policy.sh`, handler fixtures if their expected stdout changes (`hooks/tests/run_hook_tests.py` parity must stay 100%)
**Module-size (FR-25):** under ceiling; `denial_message.py` is 71 lines
**Cites:** decisions K18, K12; review MAJOR #1 (line 10 of the review table)
**Depends on:** T19 (same file — serial)
**Acceptance:** AC21, AC6, AC14
**Tests:** RED without fix — `fusebase deploy && npx prisma migrate deploy` with a valid `production_deploy` artifact: the denial message currently omits `production_deploy`; assert BOTH `production_deploy` and `database_migration` appear in the single message and `all_required_actions` has two entries while `unsatisfied_actions` has one. Message stays ≤8 lines (`MAX_LINES`, `denial_message.py:14`).
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `a16a4a6`

---

### T21. K4 totality — `only_when` and `match_order` schema validation

**Track:** hooks
**Scope:** Two fail-open/crash residues in `hooks/shared/command_policy.py`:
(a) `:185-186` — `only_when = rule.get("only_when") or {}` then `only_when.get(...)`: a non-mapping truthy `only_when` (string, list, int) raises `AttributeError` through `evaluate()`.
(b) `:284` — `order = policy.get("match_order", [...])` is used unvalidated at `:287-299`; a malformed `match_order` that omits `require_approval` (or is not a list of exactly the known stages) silently skips the approval stage and reaches `default: allow` at `:301-305` — every gated command ungated.
Fix per K4: validate the policy shape **before** evaluating any command — `only_when` must be a mapping (else `FLOW-POLICY-ERROR` deny via `_policy_error`); `match_order`, when present, must be a list whose elements are a permutation-subset of `{deny, require_approval, allow}` **containing all stages the policy declares rules for**; any defect denies with a policy-error reason. Extend the `:270-283` load-point validation block rather than scattering checks.
**Files:** `hooks/shared/command_policy.py`, `hooks/tests/test-command-policy.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decision K4; review MAJOR #2 (review table line 11)
**Depends on:** T20 (same file — serial)
**Acceptance:** AC5 (extended to full policy-schema totality)
**Tests:** RED without fix — (a) a `require_approval` rule with `only_when: "direct_to_main"` (string): `decide()` currently raises `AttributeError`; must return deny with `rule_id=POLICY_ERROR_RULE_ID`. (b) policy with `match_order: [deny, allow]` and a live `require_approval` rule: `decide(repo, "fusebase deploy")` currently returns `allow` (default); must deny as `FLOW-POLICY-ERROR`.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `5e77690`

---

### T22. K19 — `--command` mandatory; denial emits the bound resolving invocation

**Track:** hooks
**Scope:** Two ends of the same defect (review BLOCKER #2): the documented mint path produces unbound, replayable artifacts.
(a) `hooks/local/approve-local.sh:38,45,139-140` — `--command` is optional; without it `command_digest` is simply omitted (`:139-140`). Per K19: for any action reachable from a `command-policy.yml` `require_approval` rule (compute the set inside the existing Python block from the merged command policy, alongside the `:104-110` action validation), a missing/empty `--command` → message + **exit 2, no file written**. Actions not command-gated (e.g. `protected_path_edit`, `health_check_deferral`) keep `--command` optional. Update the usage header (`:17-29`).
(b) `hooks/shared/denial_message.py:63-66` — the resolving invocation omits `--command`, so the copy-paste path mints the weaker artifact (and after (a), would exit 2). Emit per unsatisfied action: `bash hooks/local/approve-local.sh <action> <slug> --command '<blocked command>'` with the blocked command **safely single-quoted** (`'` → `'\''`), truncation-free (the digest must be over the exact command; if the rendered line would exceed the message budget, the command still must not be elided — allow this one line to run long and document why beside `_MAX_COMMAND_CHARS`, which applies to the display line 1 only).
**Files:** `hooks/local/approve-local.sh`, `hooks/shared/denial_message.py`, `hooks/tests/test-approval-binding.sh`, `hooks/tests/test-command-policy.sh`, handler fixtures whose expected denial text changes
**Module-size (FR-25):** under ceiling
**Cites:** decisions K19, K12, K6 (rev); review BLOCKER #2
**Depends on:** T18 (digest semantics), T20 (renderer shape) — serial after both
**Acceptance:** AC22, AC9
**Tests:** RED without fix — (a) `bash hooks/local/approve-local.sh production_deploy s1 'r'` (no `--command`) currently exits 0 and writes an unbound artifact; must exit 2 and write nothing (assert the approvals dir is unchanged). (b) the rendered denial currently contains `approve-local.sh <action> <slug>` with no `--command`; assert the resolving line contains `--command` and the exact blocked command, including one with an embedded single quote round-tripping safely. (c) end-to-end: run the emitted invocation verbatim, re-run the blocked command → allow; run a one-character-different command → deny.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `91e4c10`

---

### T23. Cross-carrier strict/compat unification

**Track:** hooks
**Scope:** Strict/compat behavior diverges across carriers (review MAJOR #3, table line 12):
(a) `hooks/shared/path_policy.py:251-253` — non-bootstrap compat acceptance of `MISSING_EXPIRY` happens with **no** audit warning, though K17's table and AC11 require "accepted (logged)". Route acceptance through one mode-aware helper (new `accept_with_audit(verdict, *, strict, carrier, artifact_path)` in `hooks/shared/approval_artifact.py`, or a thin wrapper the three carriers share) that logs each compat-accepted legacy artifact once per evaluation via `hooks/shared/audit_logger.py`.
(b) `hooks/local/lib/active-approvals.sh:51-59` — the embedded Python accepts `Verdict.MISSING_EXPIRY` unconditionally (`:58`) and never reads `strict_approvals`; under strict mode an expiry-less deferral artifact still classifies as active (`EXCEPTION_IN_EFFECT`). Read the merged `approval-policy` via `policy_loader` and gate through `is_acceptable(verdict, strict=strict)`. **Array contract unchanged** (`:52-57` tripwire): status text goes in `ARTIFACT_NOTES` only.
**Files:** `hooks/shared/path_policy.py`, `hooks/shared/approval_artifact.py`, `hooks/local/lib/active-approvals.sh`, `hooks/tests/test-bootstrap-exception.sh` (extend), `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** `path_policy.py` must not grow past its current line count; helper lives in `approval_artifact.py`
**Cites:** decisions K1, K7, K17; review MAJOR #3
**Depends on:** T17 (same `approval_artifact.py` chain — serial after T18 lands if both touch it; T18→T23 ordering acceptable)
**Acceptance:** AC11 (tightened: compat acceptance is audited; strict is honored by every carrier)
**Tests:** RED without fix — (a) compat-accept an expiry-less `protected_path_edit` artifact through `path_policy.has_active_exception()` and assert an audit-log entry naming the artifact exists; currently no entry is written. (b) with `strict_approvals: true` in a temp policy, an expiry-less `health_check_deferral` artifact must NOT land in `ACTIVE_ARTIFACTS` / defer checks; currently it does. (c) `bash hooks/local/fusebase-flow-health-check.sh` still reports `EXCEPTION_IN_EFFECT` for a valid v2 deferral (array-contract regression stays green).
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `308f11b`

---

### T24. Truthful inventory — never `ACCEPT` what the gate rejects

**Track:** hooks
**Scope:** `hooks/local/lib/approval_inventory.py:45-49` — on `BINDING_MISMATCH` the row is re-evaluated with **both** binding fields stripped, so an artifact whose `repo_id` does not match the current repo (which the gate rejects here and everywhere) can print `ACCEPT`. Per K17/`verdict(strict)` truthfulness: (a) evaluate with `repo_id=compute_repo_id(root)` so repo binding IS checked against the inventory's own root; (b) `command_digest` alone is genuinely uncheckable without the command — when the sole failing binding is the command digest, report the verdict column as `UNCHECKED (command-bound)`, never `ACCEPT`; a repo mismatch reports `REJECT (BINDING_MISMATCH)`. Update the strict-reject count to count `UNCHECKED` rows separately (they are neither accept nor reject).
**Files:** `hooks/local/lib/approval_inventory.py`, `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** under ceiling (95 lines)
**Cites:** decisions K7, K17; review MAJOR #4 (table line 13)
**Depends on:** T18 (digest/binding semantics stable)
**Acceptance:** AC27, AC12
**Tests:** RED without fix — an artifact with a `repo_id` of a **different** repo currently prints `ACCEPT`; must print `REJECT (BINDING_MISMATCH)`. A command-bound artifact valid in every other respect currently prints `ACCEPT`; must print `UNCHECKED (command-bound)`. A fully valid repo-bound unbound-command artifact still prints `ACCEPT`.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `a8ae028`

---

### T25. K20(a) — classifier unavailable ⇒ fail closed

**Track:** hooks
**Scope:** `hooks/local/upgrade.sh:249-256` — when `managed_content_manifest.py` or `python3` is unavailable, the engine warns and falls back to hardcoded `CONTENT_DIRS`/`CONTENT_FILES`, then the `:491-502` legacy whole-directory copy overwrites consumer edits — the pre-4.7.0 destructive behavior, reachable on any hooks-off Windows install without `python3`, bypassing `--auto-yes` containment. Per K20(a): when the source tree ships the classifier module (i.e. the target version expects classification) and it cannot run, **abort** with a diagnostic naming the missing prerequisite and the recovery (`install python3` / `bash hooks/local/bootstrap-upgrade.sh`). Retain legacy copying ONLY behind a new explicitly named flag `--unsafe-legacy-copy` that no diagnostic ever suggests; a genuinely pre-4.7.0 source tree (no classifier module shipped) may keep the legacy path since classification does not exist for it — the fail-closed trigger is "classifier expected but unavailable", not "classifier absent from the universe".
**Files:** `hooks/local/upgrade.sh`, `hooks/tests/test-upgrade-conflict-classification.sh`
**Module-size (FR-25):** `upgrade.sh` at 770 of 800 — the new branch must be compact; move any non-trivial logic into the Python module or `hooks/local/lib/`
**Cites:** decision K20; review BLOCKER #7 (table line 9)
**Depends on:** T14
**Acceptance:** AC23
**Tests:** RED without fix — fixture where the source clone ships `managed_content_manifest.py` but the run is forced classifier-less (e.g. `PATH` without `python3` shims for the classify step, or the module made unreadable): current engine proceeds and a consumer-edited managed file is overwritten; must abort non-zero with the file byte-identical before/after (tree-wide `sha256sum` no-write assertion). With `--unsafe-legacy-copy` the copy proceeds (flag exists and is the only route). Pre-4.7.0 source tree without the module still upgrades (no false abort).
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `4d6a8f9`

---

### T26. K20(b) — preflight must not advise self-restamping a diverged base

**Track:** hooks
**Scope:** `hooks/local/preflight.sh:292-299` — the missing-base warning (`:293`) and the STALE warning (`:298`) both tell the consumer to run `bash hooks/local/stamp-managed-content-manifest.sh`, i.e. restamp a base **from their current tree**. That records local security edits as "upstream base"; the next upstream change to the same file classifies `upstream-only` (`managed_content_manifest.py:265-266`, `L == B`) and overwrites it — reproducing the original incident through the machinery built to prevent it. Per K20(b): missing base → advise ONLY `bash hooks/local/bootstrap-upgrade.sh` (tag-sourced synthesis, `bootstrap-upgrade.sh:189-246`); STALE base → state that local-edit drift since the last upgrade is **expected** and the base must never be restamped from the working tree — recovery only from the exact prior upstream tag/package, else the paths stay `unknown-base` (preserved). Audit `hooks/local/stamp-managed-content-manifest.sh` and `audit/README.md` guidance for the same self-restamp advice and correct in the same commit (generalize-principle rule: fix every carrier of the advice, not the reported one).
**Files:** `hooks/local/preflight.sh`, `hooks/local/stamp-managed-content-manifest.sh` (header/help text if it carries the advice), `audit/README.md` (if it carries the advice), `hooks/tests/test-upgrade-conflict-classification.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decision K20; review BLOCKER #6 (table line 8)
**Depends on:** T25 (shared test file — serial)
**Acceptance:** AC24
**Tests:** RED without fix — grep-discriminator: `bash hooks/local/preflight.sh` output (and the named files) currently contains `stamp-managed-content-manifest.sh` as consumer-facing restamp advice on the missing/stale paths; assert the advice is absent and `bootstrap-upgrade.sh` is named instead. Behavioral discriminator: consumer tree with a local edit + base restamped from that tree, then an upstream change to the same file → current classification is `upstream-only` (overwrite); the corrected guidance path (tag-synthesized base) classifies it `changed-by-both`/`consumer-only` and preserves — assert the tag-synthesized-base run preserves the edit.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `9af4256`

---

### T27. Bootstrap writes nothing before classification authorizes

**Track:** hooks
**Scope:** `hooks/local/bootstrap-upgrade.sh:128-167` — Step 2 copies the fetched engine scripts over `hooks/local/*.sh` (`:140-150`) and the **entire** `hooks/local/lib/` (`:161-166`) into the consumer tree, then `:249-256` `exec`s that installed copy. A later `changed-by-both` abort therefore cannot truthfully claim "nothing was written", and consumer customizations to engine/lib files are already replaced pre-classification. Fix per K10/K20: execute the fetched engine **from the source clone (or a temp staging dir)** — `exec bash "$SOURCE_CLONE/hooks/local/upgrade.sh"` with the engine reading its libs from the source tree; managed consumer paths (including the engine scripts and `hooks/local/lib/`) are written only by the classified per-file apply loop in `upgrade.sh`, which already treats them as managed content. Preserve the `:174-247` base-synthesis step (it writes only `audit/managed-content-manifest.json`, which is the classifier's own input — document that this one write precedes classification by design and is not consumer content). MINOR in the same file: the `:220-230` tripwire comment claims `git archive` applies `core.autocrlf` — it does not (`-c core.autocrlf=` at `:230` has no effect on `archive` output; `.gitattributes` governs). Correct the comment; if EOL conversion is actually needed for the base to match a CRLF working tree, materialize the tag via a checkout/worktree honoring `.gitattributes` — decide by the T29 `core.autocrlf=true` fixture's evidence, and document the outcome beside the code.
**Files:** `hooks/local/bootstrap-upgrade.sh`, `hooks/local/upgrade.sh` (only if the engine assumes an installed-lib path — keep the change minimal), `hooks/tests/test-upgrade-conflict-classification.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K10, K20; review MAJOR #5 (table line 14) + MINOR (line 16)
**Depends on:** T26 (shared test file — serial)
**Acceptance:** AC25
**Tests:** RED without fix — fixture: consumer with a locally customized `hooks/local/upgrade.sh` (sentinel) whose bootstrap run hits a `changed-by-both` abort on another file: currently the sentinel is already gone post-abort (engine overwritten at Step 2); assert a tree-wide pre/post `sha256sum` over the consumer tree (minus `audit/managed-content-manifest.json` and the log) is **identical** after an aborted run. Non-abort run still upgrades normally (engine executed from source works end-to-end).
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `e9f5d8c`

---

### T28. K21 — `rm` pattern gap + truthful evasion documentation + backlog

**Track:** policy/docs
**Scope:** (a) `policies/command-policy.yml:118` — pattern `\brm\s+(-r|-rf|-fr)?\s+` requires a second whitespace run when the flag group is absent, so plain `rm build.log` matches nothing. Fix to gate flagless deletes too (e.g. `\brm\s+(-[A-Za-z]+\s+)*\S`), keeping the deny-stage `rm -rf` interplay intact (deny still short-circuits). Close `docs/backlog/rm-rule-pattern-single-space-gap/` (mark resolved with this SHA). (b) Per K21: document truthfully in the `policies/command-policy.yml` header and `docs/hook-coverage.md` that rule matching is regex over the raw command string and is defeatable by quote-fragmentation (`fusebase de'pl'oy`, `npx prisma mi"grate" deploy`) and dynamic construction — the gate is a guardrail, not a sandbox. (c) File `docs/backlog/command-gate-shell-evasion/README.md` for the real fix (shell-aware parsing or conservative deny of dynamically constructed gated commands; note the false-positive risk that kept it out of this round) and add its row to `docs/backlog/index.md`.
**Files:** `policies/command-policy.yml`, `docs/hook-coverage.md`, `docs/backlog/command-gate-shell-evasion/README.md` (new), `docs/backlog/rm-rule-pattern-single-space-gap/README.md` (close-out), `docs/backlog/index.md`, `hooks/tests/test-command-policy.sh` (incl. superseding the `:130-134` workaround note — the pattern now matches `rm build.log` directly)
**Module-size (FR-25):** N/A (policy/docs) — backlog README ≤1 page (FR-23)
**Cites:** decisions K21, K3; review BLOCKER #5 (table line 7)
**Depends on:** T21 (shared test file `test-command-policy.sh` — serial after the validator chain)
**Acceptance:** AC26
**Tests:** RED without fix — `decide(repo, "rm build.log")` currently falls through to `default: allow`; must deny requiring `destructive_file_delete`. `rm -rf /tmp/x` still hits the `deny` stage first. Adversarial cases `fusebase de'pl'oy` and `npx prisma mi"grate" deploy` are added as **documented-limitation** cases asserting current behavior (allow) with a comment linking the backlog ticket — they exist so the future fix flips them, not to pretend coverage.
**Worker-undisturbed:** `policies/**` — FR-07 bootstrap approval. **Mirrors:** none (no flow-skills touched).
**SHA:** `7a1372f`

---

### T29. Regression-discriminator test sweep

**Track:** tests
**Scope:** Make the advertised regressions actually discriminate old code from new (review MAJOR #6, table line 15):
(a) Handler fixtures 22/23 (`hooks/tests/fixtures/22_pre_tool_use_compound_requires_all_actions.json`, 23) carry **no** artifact, so the old first-match code also denies them — non-discriminating. Rework (or add sibling fixtures) so the first matched action IS satisfied by a valid artifact and the deny hinges on the second: old first-match code allows, all-match code denies. Update `run_hook_tests.py` `EXPECTED_HANDLER_FIXTURES` if the count changes.
(b) `hooks/tests/test-upgrade-conflict-classification.sh:293-297` — the AC16 bootstrap fixture deliberately leaves the validator **unchanged** in upstream 4.7.0 (`:293` comment), so the incident file is never `changed-by-both` and the adoption-path abort is never exercised. Supersede in place: upstream 4.7.0 must also rewrite `hooks/shared/command_policy.py`, making the consumer-patched validator `changed-by-both`; assert `--auto-yes` **aborts**, the sentinel survives, and the path is named literally in the report (spec AC16's actual contract).
(c) All EOL fixtures force `core.autocrlf=false` (`:283`, `:302`). Add a `core.autocrlf=true` consumer fixture proving classification is EOL-stable: an untouched CRLF-checked-out file must classify `current`/`upstream-only`, not consumer-divergent — this is also the evidence input for T27's archive/EOL decision.
**Files:** `hooks/tests/fixtures/22_*.json`, `hooks/tests/fixtures/23_*.json` (or new sibling fixtures), `hooks/tests/run_hook_tests.py`, `hooks/tests/test-upgrade-conflict-classification.sh`
**Module-size (FR-25):** N/A (tests)
**Cites:** decisions K18, K13; review MAJOR #6
**Depends on:** T19, T20 (fixtures assert the corrected all-match/denial behavior), T27 (bootstrap fixture runs the corrected no-write hop)
**Acceptance:** AC6, AC16 (test-coverage halves); regression-discriminators section of `verification-gate.md`
**Tests:** each reworked case is itself the deliverable; the RED criterion is against **old** code, verified analytically per case and recorded in the gate's Regression discriminators table: (a) old first-match ⇒ fixture allows (wrong), new ⇒ denies; (b) old whole-tree copy ⇒ sentinel lost, new ⇒ abort + sentinel intact; (c) if T27 leaves the archive EOL behavior broken, the autocrlf=true fixture fails — it must pass at gate.
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** `c2bdb58`

---

### Corrections-round serialization

```
T14 ─→ T17 ─→ T18 ─→ T23          (approval_artifact.py chain)
        │      └──→ T24           (inventory; after digest semantics)
        └─→ T19 ─→ T20 ─→ T21 ─→ T28   (command_policy.py / test-command-policy.sh chain)
                    └─────→ T22   (after T18 + T20)
T14 ─→ T25 ─→ T26 ─→ T27          (upgrade arc; shared test file — serial)
T19,T20,T27 ─→ T29 ─→ T15(gate) ─→ T16(deploy)
```

Never delegate two tasks from the same chain concurrently. T15 (gate) and T16 (deploy) keep their original numbers and detail blocks below; their dependency set is now T1..T14 + T17..T29.

---

### T15. Verification gate

No code change. AI Developer produces the gate report from `templates/gate-report.md`; required fields per `policies/gate-contracts.yml: gate_report`. The gate run must be **unscoped** — no `FF_ONLY` — and may cite only `state/audit/hook-test-results.md`, never `hook-test-results-scoped.md`.

After the gate report, the AI Developer waits for an explicit deploy handoff. Do NOT proceed to T16 on initiative.

---

### T16. Deploy + probes + single docs commit

**Procedure:** per `workflows/greenlight-deploy.md`.

1. Final pre-deploy worker-undisturbed re-check
2. Version bump 4.6.1 → 4.7.0: `VERSION`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `bash hooks/local/sync-version-strings.sh`
3. Capture deploy hash
4. Probes G-M..G-Q (see `verification-gate.md`)
5. Smoke S1..S5 (see `verification-gate.md`)
6. Single docs commit (FR-14): `spec.md` DRAFT → DONE with hash + `tasks.md` SHAs + backlog index update
7. Output deploy report

**Approval artifact required:** `state/approvals/production_deploy-approval-binding-and-upgrade-classification-<YYYYMMDD>.json` per `policies/approval-policy.yml`, authored by the Deploy session on the operator's DP.6 phrase.

**VERIFIED 2026-07-28 (Deploy phase).** Artifact minted `production_deploy-approval-binding-and-upgrade-classification-20260728.json` (schema v2, repo-bound, command-bound). Release commit / deploy hash `6224bbe`, tag `v4.7.0` — **local only, not pushed, not merged to `main`**.

| Probe | Verdict | Evidence |
|---|---|---|
| G-M version sync | PASS | `VERSION`=4.7.0; `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json` all 4.7.0; `sync-version-strings.sh` → empty diff |
| G-N fresh-clone preflight | PASS | clone of `6224bbe`: errors 0, warnings 1 (benign `.claude/settings.json` overlay notice) |
| G-O full unscoped suite on released state | PASS | 665/666, **0 FAIL**, 1 INCONCLUSIVE = `cli-flow-recovery` (ratified D9, host load) — `…-smoke/G-O-hook-test-results.md` |
| G-P both manifests verify | PASS | hook-layer 134 MATCH · managed-content 279 MATCH, `flow_version=4.7.0` |
| G-Q single docs commit | PASS | this commit — spec flip + tasks SHAs + backlog index together |

**Smoke 6/6 PASS** (threshold 6/6) on fresh consumer clones with hooks wired — S1, S2, S3, S4a, S4b, S5, each with its adversarial control. Evidence + recorded execution deviations: `docs/tmp/handoff/2026-07-28-approval-binding-and-upgrade-classification-smoke/README.md`.

**Post-plan corrections (T30..T32, ratified before the gate):** T30 `1e3fbc3` · T31 `5f84188` · T32 `ee2f295`.

## Parallelism diagram

```
T1 ─→ T2 ─┬─→ T3 ─→ T4 ─→ T5 ─→ T6 ─→ T7 ─→ T8 ─→ T9 ─┐
          │        (serial: all edit command_policy.py)  │
          ├─→ T10 ─────────────────────────────────────  ├─→ T14 ─→ T15 ─→ T16
          └─→ T11 ─→ T12 ─→ T13 ──────────────────────── ┘
```

Three arcs, safely parallel **only** at arc granularity once T2 lands:

| Arc | Tasks | Parallel-safe with |
|---|---|---|
| Validator | T3→T9 (strictly serial — T3, T4, T5, T6, T7 all edit `hooks/shared/command_policy.py`) | the other two arcs |
| Cross-carrier | T10 | Validator, Upgrade |
| Upgrade | T11→T12→T13 (serial) | Validator, Cross-carrier |

All three must complete before T14. **Never** delegate two tasks from the same arc concurrently — the Validator arc in particular is a single-file chain, and T8 additionally depends on T7's `any_of`/`flags` rule shape. Declared dependencies in the task table are authoritative where this diagram is ambiguous.

## Task chain audit

| Constitution invariant | Affirmed in tasks |
|---|---|
| Worker-undisturbed | Every task T1..T14 and T17..T29 touches `fusebase_flow_internals` and declares the FR-07 bootstrap-approval mint → commit → `--consume` cycle; no task uses `--no-verify` |
| Mixed-fleet | T9 (compat mode + inventory), T12 (`unknown-base` preserve), T13 (≤4.6.1 adoption hop) |
| Migration approach | No data migration. Two-stage schema rollout per K7; legacy artifacts never auto-mutated |
| FR-25 module size | T2, T4, T6, T12 name their extraction seams explicitly; `path_policy.py` must not grow (T10) |
| FR-22 comments | Only the K6 canonicalization tripwire is specified as a required comment; every task emits `comment-policy review: applied (FR-22)` |
