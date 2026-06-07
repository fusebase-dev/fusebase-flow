# Release handoff — comment-policy-fr22-write-time-delivery (T8)

> **Mode B.** PO-authored. Lean **framework release** handoff — no production runtime surface. Point an AI Developer (Deploy phase) session at this file, or continue the same implement agent.

## Role bootstrap (read BEFORE any other reads)

You are operating as the **AI Developer in the Deploy phase** under Fusebase Flow v3.10.0 (this release bumps it to 3.11.0).

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-22), naming Deploy phase + the DP.1..DP.12 role-discipline section.

### DP-gate waiver (stated, not silent)

This "deploy" is a **git commit to a framework repo** — no live runtime, no users/data affected at commit time, fully reversible via `git revert`. Therefore:

| DP gate | Status here | Why |
|---|---|---|
| DP.1 approval artifact (`state/approvals/...json`) | **N/A** | No production runtime surface (pre-scoped in `tasks.md` T8, operator-locked). |
| DP.6 magic phrase `APPROVE-DEPLOY-NOW` | **N/A** | DP.6 protects irreversible production pushes; this is a reversible commit. Release proceeds on the operator's **plain explicit go-ahead** (FR-21 safety-floor posture). |
| DP.10 smoke (operator-visible runtime outcome) | **N/A** | No runtime surface to smoke. Behavioral proof was the implement-phase dogfood (V7) + post-commit preflight/health. |
| Probes G-N/G-O/G-P (URL/health/feature) | **N/A** | No deployed service. Replaced by source probes G-M..G-Q below. |

**Safety floor that DOES apply (enforce all):** explicit operator go-ahead · one commit · SHA recorded · documented rollback (`git revert`) · post-commit `preflight.sh` 0/0 + health HEALTHY · worker-undisturbed re-check.

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01..FR-22
2. `docs/specs/comment-policy-fr22-write-time-delivery/spec.md` — flips DRAFT → DONE in this release
3. `docs/specs/comment-policy-fr22-write-time-delivery/verification-gate.md` — V1..V7 + source probes
4. `docs/handoff/2026-06-06-comment-policy-fr22-write-time-delivery-implement.md` — the gate report (T1..T7 PASS) you are releasing
5. `docs/release-notes/v3.10.0.md` — the release-note pattern to mirror

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `comment-policy-fr22-write-time-delivery` |
| **Status** | gate PASSED (PO-accepted 2026-06-06); ready for release |
| **Lane** | Full (design/planning rigor) · release step low-risk/reversible |
| **Gate verdict** | V1–V6 PASS (+V7 self-evidence); preflight 0/0; run-tests 16/16; health HEALTHY |
| **Implement commits** | `4e86d84`(T1) `5d23339`(T2) `9fdcb32`(T3) `0cd7a46`(T4) `978a703`(T5) `c680001`(T6) |
| **Pre-release base** | `c680001` · VERSION `3.10.0` |
| **Target version** | `3.11.0` |
| **Rollback** | `git revert <release SHA>` → re-run `preflight.sh` + health |

---

## Release steps (one task = T8; single release commit per FR-14)

Execute in order, then commit once.

| # | Step | Pre-cached target | Note |
|---|---|---|---|
| 1 | Worker-undisturbed re-check | engine scripts + `FLOW_RULES.md` FR-01..FR-21 + `docs/release-notes/**` historical | must be empty diff before proceeding |
| 2 | Bump `VERSION` | `VERSION` → `3.11.0` | single line |
| 3 | Sync attestation strings | run `bash hooks/local/sync-version-strings.sh` | rewrites version + FR-range (stays FR-01..FR-22) + `(NN canonical skills total)` tokens repo-wide. **Verify** it reports skill count **25** and bumps `v3.10.0`→`v3.11.0`; if it does NOT touch a file that still says v3.10.0 attestation, fix by hand. |
| 4 | README count fix (deviation 2 — folded into release) | see README table below | sync-version-strings will NOT catch the prose counts or the catalog table — these are manual |
| 5 | New release note | `docs/release-notes/v3.11.0.md` | mirror `v3.10.0.md` structure (title · release date 2026-06-06 · previous 3.10.0 · summary · why · the change · validation footer) |
| 6 | Spec flip | `docs/specs/comment-policy-fr22-write-time-delivery/spec.md` Status DRAFT → DONE + Deploy hash = release SHA; `tasks.md` mark T7/T8 done | FR-14 |
| 7 | Post-commit verify | `bash hooks/local/preflight.sh` + `bash hooks/local/fusebase-flow-health-check.sh` | expect 0/0 + HEALTHY (25 skills) |

**No `docs/changes/index.md` entry** — that ledger is Lightweight-lane only (`index.md` header says so). Full-lane record = the v3.11.0 release note.

### README.md manual edits (pre-cached line refs)

| Line | Current | Change to |
|---|---|---|
| `README.md:240` | "**24 canonical Flow skills**" | "**25 canonical Flow skills**" |
| `README.md:242` | "### Flow lifecycle skills (24)" | "### Flow lifecycle skills (25)" + add a `comment-policy` row to the catalog table below it (group it under a sensible category, e.g. "Meta" / "Code-writing"; one-line desc: "FR-22 write-time carrier — tripwire + retrieval-pointer comment policy") |
| `README.md:623` | "← 24 canonical skills (2 mandatory + 22 on-demand, …" | "← 25 canonical skills (2 mandatory + 23 on-demand, …)" (append `comment-policy` to the parenthetical list) |
| `README.md:646` | ".agents/skills/ … (24 Flow mirrors + 19 CLI provider skills)" | "(25 Flow mirrors + 19 CLI provider skills)" |
| `README.md:647` | ".claude/skills/ … (24 Flow mirrors + 19 CLI provider skills)" | "(25 Flow mirrors + 19 CLI provider skills)" |

Verify no other live "24" canonical count survives: `grep -nE "\b24\b" README.md` and eyeball each hit (some legitimately reference v-history — do NOT touch historical "23 → 24" prose at README's release-history mentions).

### Independent-review fix to fold in (review 2026-06-06)

One framework-file defect from the independent review lands in this release pass (the artifact-text + handoff-numbering defects were already corrected by the PO):

| Site | Current | Change to |
|---|---|---|
| `FLOW_RULES.md:31` (FR-22 rule row, HOW-column) | "rule + `docs/comment-policy.md` (rationale + reusable audit prompt) + `code-review` … + `policies/comment-policy.yml` …" | Add the carrier skill + delivered reference so the row matches the re-pointed `:68`: "rule + **`flow-skills/comment-policy/` skill (write-time carrier) + its `references/audit-prompt.md`** + `docs/comment-policy.md` (rationale) + `code-review` … + `policies/comment-policy.yml` …". **FR-22 semantics unchanged — descriptive HOW-column only; FR-01..FR-21 rows untouched.** |

This is a one-line edit in the same spirit as T4's `:68` re-point. After it, re-confirm `git diff` on `FLOW_RULES.md` touches only FR-22 rows (`:31` + the prior `:68`).

---

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| Zero diff | engine scripts; `FLOW_RULES.md` FR-01..FR-21 rows; `docs/release-notes/v3.10.0.md` and older (historical) |
| Expected change | `VERSION`; sync-version-strings targets (version/FR-range/count tokens); `README.md` (5 refs + 1 catalog row); new `docs/release-notes/v3.11.0.md`; spec/tasks status flip |

---

## Release commit (FR-14)

One commit. **Stage everything below** — the ticket's planning artifacts are still untracked (the implement agent correctly left them out of the T1–T7 code commits) and land here with the version flip:

| Stage | Paths |
|---|---|
| Framework edits | `VERSION`, `FLOW_RULES.md` (the `:31` review fix), `README.md`, sync-version-strings outputs |
| Release note | `docs/release-notes/v3.11.0.md` |
| Ticket artifacts (first commit) | `docs/specs/comment-policy-fr22-write-time-delivery/` (spec now DONE + Deploy hash, decisions, tasks, verification-gate), `docs/handoff/2026-06-06-comment-policy-fr22-write-time-delivery-implement.md`, `docs/handoff/2026-06-06-comment-policy-fr22-write-time-delivery-deploy.md` |
| Any mirror/manifest deltas | from `sync-version-strings` / re-mirror if touched |

Use explicit `git add <path>` (no `git add -A`) — do NOT stage the `C:\tmp\v7-/v8-comment-test` evidence files (they're outside the repo anyway) or any unrelated working-tree state.

**Message:**
```
release(flow): FR-22 write-time delivery — carrier skill + role-discipline fix + audit-prompt reachability + sub-agent push (v3.11.0)
```

Spec `Deploy hash` field: set it to this commit's SHA. Since the commit can't contain its own hash, either (a) commit, then a tiny follow-up edit writes the SHA into the spec, or (b) record the SHA in the release report and the spec notes "deploy hash = release commit". Prefer (a) only if you want the field populated in-tree; otherwise (b) is fine for a framework release. Capture the SHA for the report either way.

---

## Per-output state announcement

```
---
📍 Phase: Deploy (framework release)
🎯 Ticket: comment-policy-fr22-write-time-delivery
✅ Gate: PASSED (PO-accepted) — implement c680001
⏭️ Next: <release step>
```

## Source probes (replace runtime probes)

| ID | Probe | Pass criterion | Evidence |
|---|---|---|---|
| G-M | `VERSION` bumped + sync ran | VERSION=3.11.0; sync-version-strings reports 25 skills, v3.11.0 | transcript |
| G-N | preflight | exit 0; 0/0 | transcript |
| G-O | health | HEALTHY (25 skills) | transcript |
| G-P | FR-01..FR-21 intact | `git diff` shows no FR-01..FR-21 row change | diff excerpt |
| G-Q | spec flip + release note | spec DONE + `v3.11.0.md` present in one release commit | `git log` + diff |

## Release report contract (final output)

Mode B: release SHA + rollback command in header · VERSION 3.10.0→3.11.0 · sync-version-strings result (count + version) · README edit confirmation · G-M..G-Q pass/evidence · spec DRAFT→DONE confirmation · v3.11.0 release-note path. Paste back, then **halt**.

## Rollback (if any source probe fails)

1. `git revert <release SHA>`
2. Re-run `preflight.sh` + health → confirm restored to 3.10.0 / 24-skill state
3. Spec stays DRAFT; file follow-up

---

## Notes / context (PO-authored)

- **Two deviations from the implement phase were PO-reviewed and accepted:** (1) overlay-source bump (`hooks/local/fusebase-flow-overlays/*.md`) — ratified; verified that `post-fusebase-update.sh` regenerates CLAUDE.md/AGENTS.md from those overlays, so leaving them at 24 would regress the count on next `fusebase update`. (2) README untouched in implement — correct FR-11 restraint; now folded into this release (step 4 above).
- **Dogfood holds through release:** keep any new comments you add (e.g. in the release note — none expected) tripwire+pointer only. The release note is prose (docs), so FR-22 doesn't gate it, but don't add code comments anywhere in this pass.
- **Do not** create a `docs/changes/` entry (Lightweight ledger only).
