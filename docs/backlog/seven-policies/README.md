# seven-policies

**Status:** open — 6.0.0 rebuild, **wave 1**, with a wave-3 tail and one release-close commit. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 11, policies (R §2). **Surface:** `policies/` (10 tracked `.yml` files plus the baseline today), `hooks/shared/policy_loader.py`, `hooks/local/lib/validator_tier.py` (the declaration path, `:16`, `:23-24`, `:126`), `hooks/local/lib/managed_content_manifest.py:59`, `hooks/tests/test-validator-evidence.sh:25-27, 151`. **FR-07:** yes for every commit that edits `policies/*.yml` or `hooks/shared/**` (`policies/protected-paths.yml:89, 92`); the fold commit touches neither and is not protected.

## Delivers

- **Seven policies** (D §2; decision 11): command policy, protected paths, secret patterns, module size with its baseline, approval policy (Flow ships these five), plus `agent-tools.yml` and `evidence-classes.yml`, which the project creates and Flow never ships (`managed_content_manifest.py:59`).
- **`policies/evidence-classes.yml`** (decision 11): the trivial-tier lists, the class globs (auth, data and migration, UI, deploy config), the vendored list, the finding marker and the row-status pattern. Read from HEAD with no `.local` twin; never a trivial-tier path.
- **The fold of `validator-free-paths.yml` into it** (ask 11b): `validator_tier.py`'s declaration moves (`:16`), the key check becomes `schema_version` plus a closed key set while keeping the "exactly the keys" text and `schema_version` 1 (`:126`), `_PROJECT_OWNED` names the new file (`managed_content_manifest.py:59`), and four setup lines of the T160 fixtures change (`test-validator-evidence.sh:25-27, 151`); no assertion changes. `flow-migrate` copies a 5.11 list into the new key.
- **`gate_rounds: 2`** in `policies/approval-policy.yml` with its provenance (decision 3a). A local override may lower it, never raise it (3b): `policy_loader` already filters approval-policy overrides to tightening only (`hooks/shared/policy_loader.py:79-82`); lower must count as tighter for this key. Raising it is a protected-policy edit the owner approves.
- **Deny lists additive under a local override** (R §4 lock): today `_deep_merge` lets a `.local` list replace the base list (`policy_loader.py:54-62`), so `command-policy.local.yml` with `deny: []` would erase the T162 bypass denies. One branch makes command-policy denies additive, as protected paths already are (`:93-94`). This is the one named exception in `hooks/shared/` to the byte-identical kernel lock (R §4).
- **Retirements ride with their last reader:** `required-artifacts.yml` with `stop.py` (`stop-gate-retirement`), `gate-contracts.yml` with `gate_contract_check.py` (`slice-gate`), `ratchet-governance.yml` with the find-wasted-effort audit into the optional pack (`six-skills-and-optional-pack`). `model-routing.yml` and `comment-policy.yml` go in the wave-3 tail, because live skills, workflows and three tests still name them (`test-codex-plugin-surface.sh`, `test-codex-prompt-parity.sh`, `test-transient-exclude.sh`). The untracked `policies/model-routing.local.yml` in this clone is left for its owner.
- **Protect `hooks/local/**`** (ask 10) by adding it to `fusebase_flow_internals` (`protected-paths.yml:84-101`) in the **release-close commit**, not earlier, so the build commits under `hooks/local/` do not each need an approval.
- **Two named 5.11 gaps carried labelled, not fixed** (R §3): `deploy-store-provisioning-ungated` (command policy) and `secret-pattern-escaped-glue` (secret patterns). Closing them is the owner's call.
- Not here: removing `lightweight_deploy` and adding the pre-minted dev deploy (`one-lifecycle-page`).

## Decisions and asks carried

Decision 3 (a, b); decision 11; ask 10; ask 11b; ask 6 (one single-use, digest-bound approval per protected commit); R §3 named gaps; R §4 locks (T162 denies cannot be emptied by a local override; tier lists read from HEAD only).

## Estimate

Share of R §2 WP 11 (21.5 to 29.5 agent-h for the four WP 11 entries): 4 to 5.5 (mid 4.75): the fold 2, `gate_rounds` and its tighten rule 1, additive denies 0.75, the deletions and the close commit about 1.

## Depends

The decision table (answered). Blocks: `evidence-row-validator`, `trivial-tier-and-task-ids` and `overbuilding-flags` (the `evidence-classes.yml` keys, by interface), `slice-gate` (`gate_rounds`), `one-lifecycle-page` (the approval-policy shape).

## Acceptance

1. Policies 7; each is read by at least one core hook (R §3 table); `hook_manifest.py` and the release note say 7 with no "about".
2. A `.local.yml` cannot widen the tier lists, cannot raise `gate_rounds`, and cannot remove a base deny (fixtures; the last two through `policy_loader`).
3. The T160 tier keeps its 5.11 outcomes bit for bit; only the four named setup lines change (`validator-evidence` group, hosted).
4. The kept policy fixtures pass unchanged (`command-policy`, `approval-binding`, `approval-writer`, `approval-schema3`, `secret-patterns`, hosted).
5. After the close commit, a staged edit under `hooks/local/` needs a `protected_path_edit` approval (fixture in `trusted-enforcer`).

## Wave split

- **Wave 1**, three commits: (a) the fold (not FR-07); (b) `gate_rounds` plus the tighten-only rule for it (FR-07: `approval-policy.yml` and `policy_loader.py`); (c) additive denies (FR-07: `policy_loader.py`). Plan proposal: (b) and (c) may share one approval if the plan makes them one outcome, "local overrides can only tighten".
- **Wave 3 tail:** delete `model-routing.yml` and `comment-policy.yml` with the skill and workflow sweep (FR-07).
- **Release close (wave 5):** protect `hooks/local/**` (FR-07).

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
