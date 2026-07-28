# Deploy handoff — approval-binding-and-upgrade-classification

## Role bootstrap

You are operating as the **Deploy phase** under Fusebase Flow v4.6.1. Self-attest per `FLOW_RULES.md` § Self-attestation, naming the Deploy phase role and the DP.1..DP.12 role-discipline section. Read `flow-skills/role-discipline/references/deploy.md` — as a delegated sub-agent you inherit no auto-loaded skills.

**Role authority:** Deploy phase runs the deploy command and flips status fields. It does not write feature code and does not author specs.

---

## DP.1 approval artifact — authorization on file

The human operator gave explicit written authorization for this run to proceed end-to-end through deployment without further confirmation, and stated they would step out. That is the DP.6 authorization signal for **this ticket**. Per the documented procedure (`policies/approval-policy.yml:44-56`, `hooks/local/approve-local.sh` header), **you author the approval artifact on the operator's behalf — the operator runs nothing.**

Note your own new rule from this very ticket: `production_deploy` is command-gated, so **`--command` is now mandatory** (K19/AC22). An invocation without it exits 2 and writes nothing.

Scope presented and covered by that authorization: version bump 4.6.1 → 4.7.0, local release tag, no remote push, no merge to `main`.

---

## Ticket state going in

| Field | Value |
|---|---|
| Slug | `approval-binding-and-upgrade-classification` |
| Branch | `fix/msys-v3307-hardening` |
| HEAD | `12f2c3d` |
| Commits | `308ea68..12f2c3d` — T1..T14, T17..T29, T30..T32, plus PO doc commits |
| Gate | **665/666 PASS, 0 FAIL, 1 INCONCLUSIVE** (`test-cli-flow-recovery.sh`, ratified D9 — pre-existing host load, reproduced on the pre-round commit) |
| Manifests | hook-layer 134 assets MATCH · managed-content 279 assets MATCH · 0 mirror drift |
| `VERSION` | `4.6.1` — **you bump it** |
| Spec status | DRAFT — **you flip it** |
| Review status | Codex re-review: 11/13 findings CLOSED, 1 WAS-INVALID (adjudicated), 2 partially-closed remainders since fixed by T30..T32 |

---

## Deploy procedure (tasks.md T16)

1. **Final worker-undisturbed re-check.** `git status` clean; confirm `.claude/settings.json.example` zero-diff.
2. **Mint the DP.1 artifact** — `production_deploy`, slug `approval-binding-and-upgrade-classification`, with the mandatory `--command`.
3. **Version bump 4.6.1 → 4.7.0:** `VERSION`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, then `bash hooks/local/sync-version-strings.sh`. **Restamp both manifests** — `flow_version` is embedded in them, so they change with the bump.
4. **Re-run the full unscoped gate at the released version.** The manifests carry the version; the gate must be green *at* 4.7.0, not only before the bump. `test-cli-flow-recovery.sh` may again return INCONCLUSIVE on this host — that is ratified D9, not a failure. Any *other* failure stops the deploy.
5. **Probes G-M..G-Q** from `verification-gate.md` § Probes.
6. **Smoke S1, S2, S3, S4a, S4b, S5** from `verification-gate.md` § Smoke prompts. **Threshold 6/6.** Run against a **fresh clone of the released state in a scratch dir** (`/c/tmp/` is an allowed working directory) with hooks wired — not the dev tree, because the defect class being fixed only manifests on a consumer install. Evidence → `docs/tmp/handoff/2026-07-28-approval-binding-and-upgrade-classification-smoke/`.
   **If a scenario cannot be run as written, say so explicitly and explain why. Do not mark it PASS.** A smoke prompt you could not execute is a reported gap, not a pass.
7. **Single docs commit (FR-14):** `spec.md` DRAFT → DONE with the deploy hash · `tasks.md` SHAs filled in · `docs/backlog/index.md` updated. One commit, not three.
8. **Tag `v4.7.0`** on the current branch.
9. **Produce the deploy report.**

---

## Release boundary — read this carefully

**Local only.** Tag `v4.7.0` locally. **Do NOT `git push`** to any remote. **Do NOT merge to `main`.** The operator will review and publish. State plainly in your report what you did and did not push.

This matters beyond caution: `git push` to `main` is itself gated by `command-policy.yml` under `production_deploy` in `direct_to_main` mode, and pushing a framework release is externally visible and not cleanly reversible. The operator retains that decision.

---

## Rollback

Surface: **code-only** (`verification-gate.md` § Rollback procedure). No migration, no secrets, no sidecar, no cross-app contract. `audit/*.json` manifests are generated, not state. Legacy approval artifacts are never mutated (K7), so a rollback finds consumer artifacts exactly as it left them.

If any probe or smoke scenario fails: **stop, do not tag**, report per § Rollback procedure, leave the spec DRAFT.

**Release-note hazard to carry forward:** downgrading from 4.7.0 restores the replayable gate. Say so in the release notes.

---

## Release-note material (state honestly, do not soften)

| Item | Note |
|---|---|
| Behaviour tightening | Compound commands now require an artifact per matched action; lowercase SQL and `ALTER TABLE` are gated; flagless `rm <path>` is gated. Some previously-allowed commands now require approval. |
| Mandatory `--command` | `approve-local.sh` requires `--command` for command-gated actions. Scripted callers that omit it will exit 2. |
| Known limitation (K21) | Rule matching is regex over the raw command string and is **defeatable by quote-fragmentation** (`fusebase de'pl'oy`) and by dynamically constructed commands. Documented deliberately; real fix tracked in `docs/backlog/command-gate-shell-evasion/`. |
| Strict mode | Ships **OFF**. Legacy expiry-less artifacts are accepted with an audit-logged warning. `approve-local.sh --inventory` lists what a future strict flip will reject. |
| Upgrade | Consumers on ≤4.6.1 adopt via `bootstrap-upgrade.sh`, which synthesizes the base from their installed VERSION tag. `changed-by-both` aborts an unattended upgrade by design. |
| Not fixed | Single-use approval consumption and authenticated operator authorship remain out of scope — see `docs/backlog/approval-single-use-consumption/` and decision K3. Flow enforces schema, expiry, action agreement and command/repo binding; it does **not** enforce operator identity. |

---

## State announcement (every reply)

```
---
📍 Phase: Deploy
🎯 Ticket: approval-binding-and-upgrade-classification
✅ Completed: <steps>
📍 Current: <step>
⏭️ Next: <next step>
```
