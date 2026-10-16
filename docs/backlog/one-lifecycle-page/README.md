# one-lifecycle-page

**Status:** open — 6.0.0 rebuild, **wave 3**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 3 (R §2). **Surface:** `workflows/` (13 files), `flow-skills/lightweight-lane/`, `hooks/local/lane-router.sh`, `hooks/local/lane-assessment.py`, `policies/command-policy.yml:116-124`, `policies/approval-policy.yml:65, 73-85`, `hooks/tests/run-tests.sh` (tags `lane-router`, `lane-workflow`, `:80`, `:143`), `.github/workflows/fusebase-flow-maintainer.yml:86`. **FR-07:** yes (both policies, `policies/protected-paths.yml:89`); the workflow line is `ci_cd_config` (`:77`).

## Delivers

- The 13 workflow files become one page, plan, build, verify, ship (under 4 KB, H recommendation), plus the quickstart: a project's documentation is two pages (H:90).
- Lanes go (D §3 row 1): `flow-skills/lightweight-lane/`, the lane router and the lane assessment. The evidence class of a row follows from the paths its task touched against `policies/evidence-classes.yml`; the risk tag may raise it, never lower it (H WP 3).
- One protected change removes `lightweight_deploy` from both policies (the `any_of` alternative at `command-policy.yml:123` and the artifact class at `approval-policy.yml:73-85`) **and** adds the environment-scoped, pre-minted dev deploy approval for the exact command (5.11 decisions 1 and I). Without the pre-mint in the same change, every `fusebase deploy` needs `production_deploy` and the consumer's unattended dev deploys are refused.
- Preflight's action-name consistency check (`hooks/local/preflight.sh:302-306`) passes after the change.
- The `lane-router` and `lane-workflow` tags retire from `run-tests.sh` (`FF_TAGS :80`, `FF_FAST_TAGS :143`) and from the maintainer workflow's fixed `FF_ONLY` list (`fusebase-flow-maintainer.yml:86`): **that workflow line goes on the CI edit list** sent to the owner before any workflow file is touched.

## Decisions and asks carried

| Item | Effect here |
|---|---|
| 5.11 decisions 1 and I (pre-minted dev deploy) | Lands in the same protected change as the `lightweight_deploy` removal |
| Ask 6 (one approval per protected commit; CI edits asked once) | One mint for the policy commit; the `FF_ONLY` line is on the CI list |
| Decision 3 (`gate_rounds` in the approval policy) | Not here: `seven-policies` adds the key in wave 1; this change must not disturb it |
| H WP 3 | The rest of the scope |

## Estimate

R §2: 2 to 3.5 agent-h (mid 2.75). Review: 1 to 2 rounds (the policy diff touches the approval model).

## Depends

`four-document-model` (document names), `six-skills-and-optional-pack` (skill names), `seven-policies` (the approval-policy shape), the owner's answer to the CI edit list. Blocks: `eight-rule-kernel-and-cards` (the page is a boot-list target).

## Acceptance

1. 13 workflow files become 1 page under 4 KB; `lightweight-lane`, the lane router, the assessment and both `lightweight_deploy` entries are gone (H WP 3).
2. `preflight.sh` passes after the change (hosted).
3. A `fusebase deploy` to dev with the pre-minted approval for the exact command is allowed; the same command with no approval, or a different command, is denied (`command-policy` and `approval-binding` groups, hosted).
4. No retired tag remains in `FF_TAGS`, `FF_FAST_TAGS` or a workflow `FF_ONLY` list.

## Wave split

Wave 3. Planned as two commits: (a) the protected policy change with its fixtures (one FR-07 approval); (b) the page, the lane removal and the tag retirement (workflow line after the CI list is answered). Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
