# Deploy handoff — token-floor-remediation (T25 + T20)

**Role:** Deploy phase · **Ticket:** `token-floor-remediation` · **Lane:** Full (FR-21)
**Branch:** `fix/msys-v3307-hardening` · **HEAD at handoff:** `a2214b3` · **Target:** `origin/main` + tag `v4.6.0`

## Attestation (first response)

> "Operating as Deploy phase under Fusebase Flow v4.5.0. I will follow FR-01 through FR-27. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for Deploy phase."

## Gate status — PASS

`docs/specs/token-floor-remediation/gate-report.md` · **28/28 AC PASS** · `run-tests.sh` **619/619, 0 FAIL, 0 INCONCLUSIVE** (1298s) · preflight 0/0 · hook manifest 121/121 MATCH · module-size clean · health-check HEALTHY · CLI/Flow conflicts none · mirrors 0 drift.

## DP.1 approval — operator authorization on file

Operator grant, 2026-07-26, verbatim: *"If you need to do any migration, you can execute migration because there is no real data or any users on production, so you can migrate any data and tables if needed. Also, deploy to production if needed. You have my full authorization."* Plus: *"I'm the human operator, and I will step out. I expect you to accomplish all of the slices end to end in one run."*

Per the Operator Gate Protocol, the operator authorizes in chat and **you** run every command the approval requires — mint the deploy approval artifact yourself, then deploy. This is executing the operator's decision, not self-approval.

## PO rulings carried into this dispatch

**D5 — re-baseline the rule inventory (T25, do this first).** The inventory diff is non-empty by design: T23 was *required* to reword the FR-27 rule statement, which legitimately moves its row. Evidence: `85c85` (FR-27, `FLOW_RULES.md`, resident) and `170c170` (WT.FR-27, `role-discipline/SKILL.md`, resident) — both **`c` (change), zero `d` (delete)**, row count unchanged at 170, no residency flips. That is an intentional reword, not rule loss.

Ruling: **re-baseline at `a2214b3`**, do not carry a permanent known-delta. A baseline with an accepted standing diff trains every future reader to skim past it — which is exactly how the T5 phantom-row defect nearly masked real losses. Record the 2-row delta and its cause in the commit message. Commit as `T25`.

**D4 — confirmed, no action.** The A2 3rd amendment had half-landed and you synced the live statements to 42,200 from the PO's own table. Correct. Note that `test-budget-literals.sh` — shipped by T18 for exactly this failure mode — is what caught it.

## T20 — release + deploy

| Step | Action |
|---|---|
| 1 | `VERSION` → `4.6.0` · `CHANGELOG.md` · new `docs/release-notes/v4.6.0.md` · `.claude-plugin/plugin.json` + `marketplace.json` · `.codex-plugin/plugin.json` · README badge |
| 2 | `bash hooks/local/sync-version-strings.sh` |
| 3 | **FR-14 single docs commit:** spec `Status: DRAFT` → `DONE`, tasks marked, `docs/backlog/index.md`, and the whole untracked `docs/specs/token-floor-remediation/` tree (spec, decisions, tasks, verification-gate, gate-report, rule-inventory-baseline) — **one commit** |
| 4 | Also fold in the pre-existing worktree edits `ROADMAP.md` and `docs/tmp/handoff.md` (PO-owned, dirty since session start, intended for this commit) |
| 5 | Mint the deploy approval artifact, then `git push origin HEAD:main --follow-tags` with an annotated `v4.6.0` tag. **Never** `gh release create` — the tag push triggers the gated release workflow |
| 6 | Run the post-deploy probes below |

### Release-note content requirements (accuracy matters more than the headline)

- Boot floor **78,148 → 41,321 bytes, a 47.1% cut** — measured, role-aware, `wc -c`.
- State plainly that the escalation's ≤5k-token target was **arithmetically impossible** (operative `FLOW_RULES.md` alone is ~5k tokens) and that we report the honest number.
- State that lazy `references/` content is **re-tiered, not deleted** — `shared-protocols.md` (21,233 B) and `mode-b-detail.md` load on demand. Do not imply total content shrank.
- Narrow F2's premise honestly: the measured "double-pay" was largely sessions reading bodies that were **never auto-injected**. Descriptions inject; bodies do not. The anti-reread rule still pays on genuine in-session re-reads.
- Credit the six BLOCKERs found by adversarial review *after* the first gate passed — the gate alone did not catch them.

## Probes (post-deploy)

| # | Probe | Pass condition |
|---|---|---|
| P1 | `bash hooks/local/fusebase-flow-health-check.sh` | `HEALTHY`; VERSION 4.6.0; hook-layer integrity matches 4.6.0 |
| P2 | GitHub Actions for tag `v4.6.0` | verify + release workflows green — the public-surface allowlist must admit `FLOW_RULES_HISTORY.md` |
| P3 | `bash hooks/local/upgrade.sh --dry-run` from a consumer clone | lists `FLOW_RULES_HISTORY.md` among content files |

## Smoke (post-deploy) — `verification-gate.md` § Smoke prompts

S1 boot floor on a clean clone of the tag (falsify against the previous tag — it must FAIL the budget) · S2 rule inventory zero removals with the deliberate-removal control · S3 history unreachable by accident + actually distributed · S4 audit tool labels rather than hides (the size-differs-only fixture must stay LIVE).

## Rails

FR-06 (never `--no-verify` / force-push / `git add -A`) · FR-14 (one docs commit) · FR-03 (T25 is its own commit) · FR-27 (bound long commands; the suite takes ~22 min). If a probe or smoke check fails, **stop and report** — do not fix forward into production without a new ruling.

## Report back

Deploy report per `templates/deploy-report.md`: deploy commit SHA, tag, workflow run URLs/verdicts, all probe results, all smoke results with evidence, and anything that did not go to plan. The ≤80-line cap does **not** apply to a canonical deploy report (AC13 exemption) — completeness wins here.
