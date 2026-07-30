# Tasks — upgrade-source-integrity-and-observability

**T-counter going in:** T0 (next task is T1)
**Task range:** T1..T8
**Gate task:** T7
**Release task:** T8
**Linked spec:** `docs/specs/upgrade-source-integrity-and-observability/spec.md`
**Linked decisions:** `docs/specs/upgrade-source-integrity-and-observability/decisions.md` (M1..M8)
**Baseline for every discriminator:** `85b97dd` — each fix's assertion must be observed **RED** there first.

## Task chain

| T# | Track | Scope | Cites | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | hooks | Materialize managed source from git objects; verify non-git `--source` | M1, M2 | — | — | pending |
| T2 | hooks | Prune exact Flow backup families from sync-allowlist discovery | M4 | — | — | pending |
| T3 | hooks | `cleanup-flow-backups.sh` + retire raw `rm -rf` guidance | M5 | — | — | pending |
| T4 | hooks | Parent-owned heartbeat on captured long runs | M3 | — | — | pending |
| T5 | hooks | `created_at` + stale-approval health warning | M4 | — | — | pending |
| T6 | docs | Bootstrap-route prominence; F1/F3/F4 corrections recorded; F7 deferral | M7, M8 | T1..T5 | — | pending |
| T7 | — | verification gate (no commit) | — | T1..T6 | — | pending |
| T8 | — | release: restamp, re-point `v4.7.0`, publish | M6 | T7 | — | pending |

T1..T5 are **independent** — different files, no shared edits. They may be delegated in parallel, but each commit must restamp the manifests, so **serialize the commits** even if the work overlaps.

## Per-task detail

### T1. Materialize managed source from canonical git objects

**Track:** hooks
**Scope:** `hooks/local/upgrade.sh:496` copies bytes from the persistent source clone's **working tree** (`:473-508` classification/copy loop; `:471,513-520` legacy dir copies). A clone whose fixtures were checked out under `core.autocrlf=true` before the `*.jsonl` pin (`601574d`) still holds CRLF on disk — `git pull` does not rewrite unchanged files — so CRLF is copied into the consumer and the byte-exact manifest (`hook_manifest.py:106-111,208-215`) reports permanent `FLOW_LAYER_DRIFT`.

Materialize from the selected commit's object database instead. New `hooks/local/lib/materialize-managed-source.sh` owns this: given a source clone and a ref, produce a canonical tree (`git archive` piped to extraction, or a detached worktree) and hand `upgrade.sh` that path. For a plain non-git `--source`, verify its bytes against its shipped manifest **before** any copy and abort with the offending path if non-canonical (AC2).

**Do not** touch `.gitattributes` (the pins already exist and are correct) and **do not** normalize in the hasher (M2 — it would hide transport corruption).

Preserve `-c core.autocrlf` handling on any clone/archive call — `bootstrap-upgrade.sh:193` proves that flag is load-bearing on Git for Windows (`git -c core.autocrlf=true archive` emits CRLF), and removing it previously made the whole managed tree misclassify. Reference `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` pitfall 5.
**Files:** `hooks/local/upgrade.sh`, `hooks/local/lib/materialize-managed-source.sh` (new), `hooks/tests/test-upgrade-conflict-classification.sh`, both manifests
**Module-size (FR-25):** `upgrade.sh` is at **790/800** — logic goes in the new lib, shell stays orchestration. Extraction here is in-scope.
**Cites:** M1, M2
**Acceptance:** AC1, AC2
**Discriminator (must be RED at `85b97dd`):** build a source clone whose fixture worktree carries CRLF (check out pre-pin, then advance without rewriting), run the upgrade, assert destination bytes are **LF** and `verify-hook-manifest.sh` = MATCH. Current code copies CRLF → drift.
**Negative control:** a canonical LF source still upgrades identically (proves the change is not just "normalize everything").
**Worker-undisturbed:** `hooks/local/**` is `fusebase_flow_internals` → FR-07 mint → commit → `--consume`. Never `--no-verify`.

---

### T2. Prune exact Flow backup families from allowlist discovery

**Track:** hooks
**Scope:** `hooks/tests/test-sync-allowlist.sh:100-109` builds `TRUE_TARGET` with a repo-wide `find` that prunes some generated paths but not `<name>.pre-upgrade-<UTC-timestamp>` families, so Flow's own upgrade backups become unreachable targets and fail at `:82-87,112-118`. Prune **exact shape only** per M4 — a known managed name, `.pre-upgrade-`, then a UTC timestamp. No `.pre-*` wildcard.
**Files:** `hooks/tests/test-sync-allowlist.sh`, both manifests
**Module-size:** under ceiling
**Cites:** M4
**Acceptance:** AC6
**Discriminator (RED at `85b97dd`):** create `agents.pre-upgrade-20260730T120000Z/ai-developer/AGENT.md` → phase currently FAILS as an unreachable target; after the fix it passes.
**Negative control:** `agents.pre-upgrade-notatimestamp/ai-developer/AGENT.md` and a genuinely unreachable non-backup target both **still fail**. A prune that swallows these is over-broad and must be rejected.
**Explicitly NOT in scope:** any secret-scan exclusion. `test-secret-scan-staged.sh:158-177` enumerates via `git ls-files`, so untracked backups never enter it; the reporter's premise is false and a bypass would create a hole (M4).
**Worker-undisturbed:** `hooks/tests/**` is **not** in `policies/protected-paths.yml` — verified; no FR-07 approval needed for this file. `audit/**` restamps do need it.

---

### T3. Sanctioned backup cleanup

**Track:** hooks
**Scope:** `upgrade.sh:743-749` says backups may be removed once validated and `:776-781` recommends `rm -rf .fusebase-flow-source`, which `policies/command-policy.yml:47-50` hard-denies. FR-06 is correct; the guidance is the bug. Add `hooks/local/cleanup-flow-backups.sh`: resolve and assert the repo root, accept **no caller-supplied glob**, and delete only paths matching an approved managed-name prefix + `.pre-upgrade-` + exact UTC timestamp shape, plus `.fusebase-flow-source/`. Refuse anything else with a non-zero exit and no deletion. Replace the raw-delete guidance with a pointer to it.

**Do not** add an exception to the FR-06 deny (M5) — narrowing the destructive surface by validation is the point.
**Files:** `hooks/local/cleanup-flow-backups.sh` (new), `hooks/local/upgrade.sh`, `hooks/tests/test-msys-tree-cleanup.sh`, `README.md`, both manifests
**Module-size:** under ceiling
**Cites:** M5
**Acceptance:** AC4
**Discriminator (RED at `85b97dd`):** grep upgrade guidance for a raw recursive delete → currently present; after the fix, absent. And: no cleanup entry point exists at HEAD.
**Negative controls (all must refuse, exit non-zero, delete nothing):** a lookalike name (`agents.pre-upgrade-nope`), a path outside the repo root, an unapproved prefix, and a symlink pointing outside the tree.
**Worker-undisturbed:** `hooks/local/**` → FR-07 mint/commit/consume.

---

### T4. Parent-owned heartbeat on captured long runs

**Track:** hooks
**Scope:** `run-with-timeout.sh:440-457` designs tempfile capture, `:462-493` redirects the child's whole stream into it, and `:534-539` reads it only after completion — so `run-tests.sh`'s already-immediate stderr markers (`:112-129`) are swallowed, producing ~13 minutes of silence in a 25-minute run. The health deep-run wraps the whole suite this way (`hook-integrity-check.sh:117-125`).

Add an **optional parent-owned heartbeat**: while the child runs, the parent prints a bounded-interval progress line to **stderr**. `run-tests.sh` and the health deep-run opt in. `bounded-run.sh:26-97` already implements this pattern in this codebase — mirror it rather than inventing one.

**Keep tempfile capture** (M3). Do **not** switch to `tee` or a pipe: the tempfile design is documented protection against MSYS native grandchildren holding an inherited pipe open past the deadline and freezing the harness. Do **not** add `stdbuf`/`PYTHONUNBUFFERED` — child-side flushing cannot escape a parent redirect, so it would ship as a fix and change nothing.
**Files:** `hooks/local/lib/run-with-timeout.sh`, `hooks/tests/run-tests.sh`, `hooks/local/lib/hook-integrity-check.sh`, `hooks/tests/test-health-check-timeout.sh`, both manifests
**Module-size:** under ceiling
**Cites:** M3
**Acceptance:** AC5
**Discriminator (RED at `85b97dd`):** run a slow child under the wrapper and read stderr **before** the child exits → currently zero intermediate bytes; after the fix, ≥1 heartbeat line.
**Negative control:** the final captured payload is asserted **byte-identical** to the pre-change behaviour. A heartbeat that contaminates captured output is a regression, not a fix.
**Worker-undisturbed:** `hooks/local/**` → FR-07.

---

### T5. `created_at` + stale-approval visibility

**Track:** hooks
**Scope:** Non-bootstrap `protected_path_edit` exceptions are reusable until expiry (`path_policy.py:221-230,291-294`) and the health check lists approvals without age (`active-approvals.sh:63-88`, `fusebase-flow-health-check.sh:128-162,723-727`). A consumer found two forgotten approvals leaving the FR-07 guard on their deploy config open for months.

Add `created_at` to newly minted artifacts (`approve-local.sh:165-180`). Add `stale_approval_warn_after_days: 7` to `policies/approval-policy.yml`. Emit one health-check **warning** per active `protected_path_edit` exception older than the threshold, naming **path, age and expiry**. An artifact without `created_at` is unknown-age → warn, never reject.

The warning must **not** change the health exit status, and must not invalidate any approval — this is visibility, not enforcement (spec § Auth model).

Note the upstream default TTL for `protected_path_edit` is 60 minutes (`approval-policy.yml:107-110`); the reporter's three-month artifacts came from consumer-local config. Do not change the default.
**Files:** `hooks/local/approve-local.sh`, `hooks/local/lib/approval_inventory.py`, `hooks/local/lib/active-approvals.sh`, `hooks/local/fusebase-flow-health-check.sh`, `policies/approval-policy.yml`, `hooks/tests/test-approval-writer.sh`, both manifests
**Module-size:** under ceiling
**Cites:** M4
**Acceptance:** AC7
**Discriminator (RED at `85b97dd`):** install an aged active `protected_path_edit` artifact, run the health check → currently merely listed; after the fix, an explicit warning carrying path + age + expiry.
**Negative controls:** health **exit status unchanged** with the warning present; a fresh approval produces no warning; `ffhc_collect_active_approvals`' array contract is unchanged so `EXCEPTION_IN_EFFECT` still classifies (the constraint that bit T10 of the previous ticket).
**Worker-undisturbed:** `hooks/local/**`, `policies/**` → FR-07.

---

### T6. Docs: corrections, bootstrap prominence, F7 deferral

**Track:** docs
**Scope:**
1. **Record the corrections** (M7) so the next reader is not misled: F1 and F3 were the stale-4.5-engine's last run, not 4.7.0 defects — `upgrade.sh:237-249` already drives the managed set through `list-managed` and `managed_content_manifest.py:34-49` already includes `FLOW_RULES_HISTORY.md`; F4 is refuted (`merge-module-size-baseline.sh:95-103` dedupes). Home: a short § in `docs/release-notes/v4.7.0.md` plus a cross-link from the staged report.
2. **Raise bootstrap-route prominence** — upgrading from ≤4.6.1 with the stale local engine is unsupported and is what produced F1/F3. `README.md`, `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`, `AGENTS.md` coexistence note.
3. **F7 deferral** (M8): promote `docs/backlog/command-gate-shell-evasion/README.md` with the semantic corpus and an explicit **"must not be attempted"** list (anchor-to-start, strip `-m`/`-F`, ignore heredoc bodies, argv-split). Add a one-line note in `policies/command-policy.yml`'s header that prose quoting a destructive pattern will be denied and `git commit -F <file>` is the sanctioned path.
4. CHANGELOG + `docs/release-notes/v4.7.0.md`: the T1..T5 fixes, the moved-tag notice (M6), and the F7 known-limitation entry.
**Files:** `README.md`, `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`, `AGENTS.md`, `docs/backlog/command-gate-shell-evasion/README.md`, `policies/command-policy.yml`, `CHANGELOG.md`, `docs/release-notes/v4.7.0.md`, mirrors if `AGENTS.md` overlay changes
**Cites:** M7, M8
**Acceptance:** contributes to AC8 (mirror drift zero)
**Worker-undisturbed:** `policies/**` → FR-07; re-run `mirror-skills.sh`/`mirror-agents.sh` and stage regenerated mirrors in the same commit if any canonical carrier changed.

---

### T7. Verification gate

No commit. Produce the gate report from `templates/gate-report.md`; fields per `policies/gate-contracts.yml: gate_report`. **Unscoped** run only — no `FF_ONLY`; cite only `state/audit/hook-test-results.md`.

Additionally required this ticket: confirm each T1..T5 discriminator was observed RED at `85b97dd`, and that every negative control passes. Then halt and wait for the release handoff.

---

### T8. Release

1. Restamp `audit/hook-layer-manifest.json` + `audit/managed-content-manifest.json`; confirm `sync-version-strings.sh` leaves an empty diff (all four version carriers already read `4.7.0` — `VERSION`, both plugin manifests, `.claude-plugin/marketplace.json`).
2. Full unscoped gate green **at the release commit**.
3. Recreate `v4.7.0` at that commit; delete the remote tag and re-push (M6). Not a force-push.
4. Release workflow publishes only if verify is green (`needs: verify`).
5. Probes + smoke per `verification-gate.md`.
6. Single docs commit (FR-14): spec DRAFT → DONE with hash, tasks SHAs, backlog index.
7. Deploy report.

**Requires** an explicit operator DP.6 authorization for the tag re-point — a published-ref mutation is not covered by a prior approval for a different action (DP.1).

## Task chain audit

| Invariant | Affirmed in |
|---|---|
| Worker-undisturbed | T1, T3, T4, T5, T6 declare FR-07 mint/commit/consume; T2 verified as touching only unprotected `hooks/tests/**` (plus manifests) |
| Mixed-fleet | T1 (canonical materialization helps every consumer), T6 (bootstrap-route prominence) |
| Migration | None. `created_at` additive; absent = unknown-age → warn, never reject |
| Anti-tautology | Every T1..T5 names a RED-at-`85b97dd` discriminator **and** negative controls; T6 is docs-only and claims no discriminator |
| FR-25 | T1 names the extraction seam (`upgrade.sh` at 790/800) |
| FR-22 | Tripwires required at: materialization (why not the worktree), heartbeat (why not `tee`), cleanup (why validation not an FR-06 exception) |
