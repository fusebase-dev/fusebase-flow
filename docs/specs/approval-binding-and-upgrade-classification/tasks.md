# Tasks — approval-binding-and-upgrade-classification

**T-counter going in:** T0 (next task is T1)
**Task range:** T1..T16
**Gate task:** T15
**Deploy task:** T16
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
| T15 | — | verification gate (no commit; gate report only) | — | T1..T14 | — | pending |
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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

---

### T5. Binding enforcement

**Track:** hooks
**Scope:** When an artifact carries `command_digest`, it authorizes only a command whose digest matches; when it carries `repo_id`, only that repository. Absent fields → action-scoped as before (K2 additive rule). `repo_id = sha256(realpath(git_root))`. `command_digest = sha256(collapse_whitespace(command))` per K6 — collapse runs of whitespace and trim, normalize nothing else, and document the rule in a ≤1-line FR-22 tripwire beside the function since a future editor "improving" normalization would silently widen what an artifact authorizes.
**Files:** `hooks/shared/approval_artifact.py`, `hooks/shared/command_policy.py`, `hooks/tests/test-approval-binding.sh`
**Module-size (FR-25):** under ceiling
**Cites:** decisions K2, K6
**Depends on:** T3
**Acceptance:** AC9
**Tests:** matching digest → allow; one-character-different command → deny; same command different repo → deny; artifact with neither field → legacy allow (compat) and reject (strict); whitespace-only difference → allow (proves collapse)
**Worker-undisturbed:** `hooks/**` — FR-07 bootstrap approval.
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
**SHA:** <captured on commit>

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
| Worker-undisturbed | Every task T1..T14 touches `fusebase_flow_internals` and declares the FR-07 bootstrap-approval mint → commit → `--consume` cycle; no task uses `--no-verify` |
| Mixed-fleet | T9 (compat mode + inventory), T12 (`unknown-base` preserve), T13 (≤4.6.1 adoption hop) |
| Migration approach | No data migration. Two-stage schema rollout per K7; legacy artifacts never auto-mutated |
| FR-25 module size | T2, T4, T6, T12 name their extraction seams explicitly; `path_policy.py` must not grow (T10) |
| FR-22 comments | Only the K6 canonicalization tripwire is specified as a required comment; every task emits `comment-policy review: applied (FR-22)` |
