# Decisions - cli-first-flow-second-recovery

**Letter prefix:** A
**Approval status:** LOCKED by operator on 2026-05-29 via `lock recommended`
**Linked spec:** `docs/specs/cli-first-flow-second-recovery/spec.md`

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| A1 | Ownership manifest | Store a parseable path ownership map under `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json`. | LOCKED |
| A2 | CLI drift depth | Runtime checks are shape-only; no CLI text hashes in Flow. | LOCKED |
| A3 | Recovery order | CLI-owned drift is fixed by current FuseBase CLI first; Flow recovery runs second and writes only Flow-owned or shared Flow additions. | LOCKED |
| A4 | Installer scope | Build health/recovery/dry-run diagnostics now; defer write-capable installer. | LOCKED |
| A5 | Shared merge preservation | Treat `.claude/settings.json`, `AGENTS.md`, `CLAUDE.md`, and `.codex/config.toml` as shared-merge surfaces with preservation tests. | LOCKED |
| A6 | Simulation coverage | Add local fixture simulation that asserts ownership behavior, not exact long-term CLI wording. | LOCKED |

## A1. Ownership manifest

**Recommendation:** Add `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json` as the machine-readable ownership source for conflict-prone agent surfaces.

**Reasoning:** Recovery already keeps durable overlay sources in `hooks/local/fusebase-flow-overlays/`, outside the CLI refresh surface documented by `hooks/local/post-fusebase-update.sh`. Keeping the manifest beside those templates lets health/recovery tooling read the same source without putting a new file under protected `policies/*.yml`.

**Alternatives considered:**

- **Option A:** Put the manifest in `policies/` - rejected for this ticket because `policies/*.yml` is a protected-path category and the manifest is operational data for the recovery engine.
- **Option B:** Keep ownership only in docs - rejected because dry-run conflict reporting needs a parseable source.

**Lock status:** LOCKED

---

## A2. CLI drift depth

**Recommendation:** Detect CLI-owned drift by presence and structural markers only.

**Reasoning:** The supplied CLI archive proved current CLI provider skills can change independently from this repository. Hashing CLI-owned text in Flow would freeze or downgrade CLI instructions, which violates the operator's requirement that new CLI versions remain authoritative.

**Alternatives considered:**

- **Option A:** Compare against Flow's bundled CLI provider copy - rejected because it can overwrite or flag valid newer CLI instructions as drift.
- **Option B:** Version-aware verification - deferred until FuseBase CLI exposes a stable template manifest or equivalent read-only contract.

**Lock status:** LOCKED

---

## A3. Recovery order

**Recommendation:** Health output should tell operators to restore CLI-owned assets with the current FuseBase CLI first, then run `bash hooks/local/post-fusebase-update.sh` for Flow.

**Reasoning:** The current recovery script already lives outside the CLI refresh surface and restores Flow mirrors, overlay blocks, settings merge, health skill, and slash command. It must not become a shadow copy of CLI provider assets.

**Alternatives considered:**

- **Option A:** Flow restores all collided files - rejected because it would copy stale CLI instructions.
- **Option B:** Flow never touches shared files - rejected because `AGENTS.md`, `CLAUDE.md`, and `.claude/settings.json` require additive Flow overlay/merge behavior.

**Lock status:** LOCKED

---

## A4. Installer scope

**Recommendation:** This ticket ships diagnostics, recovery guardrails, and tests. A write-capable existing-project installer remains in `docs/backlog/install-into-existing-fusebase-cli-project/`.

**Reasoning:** The immediate risk is incorrect ownership and recovery behavior. A write-capable installer has larger blast radius and should consume this ticket's manifest/reporting once stable.

**Alternatives considered:**

- **Option A:** Build installer now - rejected because it combines ownership semantics with automated writes before the health model is proven.
- **Option B:** Spec only - rejected because the operator asked to proceed and the recovery model needs executable checks.

**Lock status:** LOCKED

---

## A5. Shared merge preservation

**Recommendation:** Shared files are append/merge only and must preserve CLI hooks, MCP allowlists, non-MCP Codex settings, and CLI custom blocks.

**Reasoning:** `settings-json-merge.py` already preserves existing Stop hooks and appends Flow `stop.py`; `AGENTS.md` uses the CLI-preserved `CUSTOM:SKILL` wrapper; `.codex/config.toml` must be treated as an active config that Flow does not rewrite.

**Alternatives considered:**

- **Option A:** Replace shared files with Flow templates - rejected because it destroys project and CLI state.
- **Option B:** Avoid shared files entirely - rejected because agents need visible Flow rules and lifecycle hooks to operate.

**Lock status:** LOCKED

---

## A6. Simulation coverage

**Recommendation:** Add a local simulation test that creates a temporary CLI-like project, runs Flow recovery, and asserts CLI-owned sentinels remain current while Flow overlay pieces are restored.

**Reasoning:** The supplied archive path is operator-local and temporary extraction paths are not durable. A minimal fixture can lock the ownership invariant without depending on exact CLI wording.

**Alternatives considered:**

- **Option A:** Test only against the downloaded archive - rejected because the fixture path is machine-local and would break for other operators.
- **Option B:** No simulation - rejected because the primary risk is a regression in overwrite behavior.

**Lock status:** LOCKED

---

## Lock confirmation

| ID | Final option | Locked by | Date |
|---|---|---|---|
| A1 | Ownership manifest in recovery overlay directory | operator | 2026-05-29 |
| A2 | Shape-only CLI drift detection | operator | 2026-05-29 |
| A3 | CLI-first, Flow-second recovery | operator | 2026-05-29 |
| A4 | Health/recovery/dry-run now; installer later | operator | 2026-05-29 |
| A5 | Shared append/merge preservation | operator | 2026-05-29 |
| A6 | Local ownership simulation fixture | operator | 2026-05-29 |
