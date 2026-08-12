# Consumer escalation v4.8.0 - specification

**Status:** DRAFT | **documentation_tier:** 4 | **change_tier:** Full (`S1`, `S2`, `S4a`)
**Landed:** T1 (`9fdba11`), T3 (`ac0879d`) | **SHIP-BLOCKER fix-forward:** T4-T8
**Design-blocked:** S2, S3, S4b, S5
**Decision gate:** S2 requires explicit operator lock of closure C3 before implementation.

## Outcome

- Successful provenance-aware upgrades expose the exact Git commit or consumed plain-source content digest.
- Committed deploy evidence can identify what approval was validated and what deploy resulted.
- A denial names its rule and pattern and warns about quoted prose without claiming match location.

## S1 provenance contract

`INSTALLED_FROM` is one-line UTF-8 JSON with no insignificant whitespace, keys ordered as listed below, and one trailing newline. Schema: `fusebase-flow/installed-from/v1`.

| State | Required members | Forbidden members |
|---|---|---|
| Git | `schema`, `source_kind:"git"`, `git_commit:<lowercase 40-hex>` | `content_digest` |
| Plain | `schema`, `source_kind:"plain"`, `content_digest:"sha256:<lowercase 64-hex>"` | `git_commit` |
| Unknown | No valid marker is available; health state only | Never written as a successful marker |
| Invalid | Marker exists but fails schema/type/value validation; health failure | Never normalized to unknown |

For Git, the materializer resolves the exact commit before archiving it. Direct recording uses `FF_SOURCE_COMMIT`; caller-supplied `--source-commit` cannot override that value. An adopted-bootstrap handoff binds the resolved commit and canonical-tree digest, both verified against the consumed tree. For plain sources under M10, `content_digest` covers the canonical regular-file path/byte content consumed by upgrade; symlink identity/targets and mode bits are excluded and must not be represented as covered.

`INSTALLED_FROM` ownership is generated-unmanaged target state. It is absent from managed/source manifests, is not copied from source, and is atomically replaced by same-directory temporary-file rename only after a successful provenance-aware upgrade. Writer failure preserves the prior marker with zero residue. Orchestration must reject an unbound source or non-invalidatable stale marker before target writes; helper load/record failure after materialization is warning-only and cannot leave or report stale provenance as current.

## S1 acceptance criteria

1. **AC1 - typed schema:** health and writers enforce the Git/plain/unknown/invalid states above; irrelevant or extra provenance members fail validation.
2. **AC2 - Git direct:** direct Git upgrade writes the exact resolved `FF_SOURCE_COMMIT`, not a tag, branch, version, or caller HEAD.
3. **AC3 - Git bootstrap:** bootstrap passes and writes the exact resolved `--source-commit` value for the archived object.
4. **AC4 - plain source:** supported plain-directory upgrade writes `source_kind:"plain"` plus the SHA-256 digest of the consumed snapshot; it never invents a commit SHA.
5. **AC5 - ownership:** managed/source manifests exclude `INSTALLED_FROM`; the public install/upgrade contract documents generated-unmanaged ownership, schema, atomic replacement, and preservation rules.
6. **AC6 - early no-op:** already-current exit before marker write preserves a valid prior marker; with no prior marker it reports `unknown (provenance marker unavailable)` without becoming unhealthy.
7. **AC7 - failure preservation:** failure after materialization but before completion does not create, delete, truncate, or change a prior marker.
8. **AC8 - health states:** valid Git and plain markers print their typed value; missing marker prints the exact unknown text and names possible causes: pre-marker install, early already-current no-op, or removed marker; malformed marker fails integrity.
9. **AC9 - regression matrix:** registered tests cover Git direct, Git bootstrap, plain source, early no-op with and without prior marker, failure after materialization, prior-marker preservation, atomic replacement, source-manifest exclusion, missing marker, and malformed marker; `VERSION` and existing tag/manifest verification stay unchanged.

## S2 closure C3 - proposed receipt contract

The committed deploy report contains one `fusebase-flow/deploy-approval-receipt/v1` receipt:

| Class | Fields |
|---|---|
| Receipt identity | `receipt_schema`, `approval_artifact_schema` (exact stored schema identifier value), `approval_artifact_digest` (`sha256:<64-hex>`) |
| Copied with stored field names | `action`, `repo_id`, `command_digest`, `scope`, `created_at`, `expires_at`, `approved_by`, `reason` |
| Computed at validation | `observed_at`, `observed_verdict`, `remaining_ttl_seconds` |
| Deployment binding | `deploy_hash` |

`approval_artifact_digest` covers the exact validated artifact bytes. `observed_verdict` and `remaining_ttl_seconds = expires_at - observed_at` are computed observations, not stored approval fields. The live approval remains gitignored and mandatory for pre-deploy validation.

## S2 acceptance criteria

10. **AC10 - decision gate:** S2 is Full and no implementation starts until the operator locks C3 and the exact v1 field set above.
11. **AC11 - evidentiary retention:** the receipt includes every listed binding field, exact artifact digest, computed observation, and deploy hash; it uses `created_at`, never `approved_at`, and does not label `ttl` or `verdict` as stored.
12. **AC12 - gate unchanged:** local validation still checks schema/action/repository/command/scope/expiry before deploy; the live artifact stays gitignored and committed outputs contain no dangling local approval path.
13. **AC13 - regression and census:** registered tests validate receipt completeness/digest formatting/stored-vs-computed labels/deploy binding and rejection of the old assertion-only shape; approval readers and report writers receive explicit dispositions.

## S4a acceptance criteria

14. **AC14 - exact message:** every applicable deny renders `Denied: raw command matched rule <rule_id>, pattern <matched_pattern>. Quoted prose can match this pattern; no match location is claimed.`
15. **AC15 - retained facts only:** rendering uses deny-decision `rule_id` and `matched_pattern`; it performs no re-match, tokenization, quote parsing, payload extraction, or span inference.
16. **AC16 - behavior invariant:** allow/deny outcomes, matched rule/pattern selection, exit behavior, and executable surface are unchanged.
17. **AC17 - regression/protection:** tests cover executable text and quoted prose denials with exact identifiers and no location claim; the `hooks/shared/**` commit follows `policies/protected-paths.yml`.

## SHIP-BLOCKER fix-forward acceptance criteria

18. **AC18 - direct identity binding:** direct upgrade records only the materializer-resolved `FF_SOURCE_COMMIT`; caller `--source-commit` never takes precedence and cannot pair canonical tree A with commit B.
19. **AC19 - adopted-bootstrap receipt:** the handoff carries resolved commit plus canonical-tree `sha256` digest; upgrade verifies both against the consumed tree before any target write or provenance record, rejects either mismatch with zero target change, and preserves normal materializer/bootstrap resolution behavior.
20. **AC20 - stale-marker invalidation:** deletion is followed by an absence check; an undeletable valid stale marker fails cleanly before target writes, and output says `removed` only after verified absence.
21. **AC21 - marker failure atomicity:** injected marker write and final-move failures preserve the prior marker, leave zero temporary residue, and make no successful attribution claim; orchestration never exposes a prior valid marker as current after target mutation.
22. **AC22 - helper isolation:** malformed, syntax-failing, top-level-exiting, or record-failing provenance helpers execute inside an isolated subshell; they emit a warning without aborting the core upgrade or falsely claiming trustworthy provenance.
23. **AC23 - independent plain-digest proof:** a committed fixed fixture has an independently fixed expected digest; changed regular-file bytes change it, while tests and public contract state that symlink and mode changes are excluded.
24. **AC24 - live malformed health row:** a registered automated row feeds an encoded malformed marker through the live health engine and asserts integrity failure; manual evidence alone does not satisfy this AC.
25. **AC25 - complete denial reason:** every deny sample asserts the complete expected reason; substring-only checks, keyword blacklists, and appended location prose fail.
26. **AC26 - renderer signature:** a registered test asserts the denial renderer has exactly two required parameters and no alternate call shape.
27. **AC27 - reproducible mutation evidence:** the seven RED-first provenance/denial mutants are verified by a committed harness that reproducibly makes each targeted test fail and restores the tree; a report assertion is insufficient.
28. **AC28 - public-contract correction/discovery:** `docs/install-existing-project.md` says bootstrap synthesis uses the tag's current target and cannot prove historical installed bytes until S3/S5; it contains no `byte-identical` claim. `docs/install-fusebase-cli-project.md` points to that canonical `INSTALLED_FROM` contract without duplicating it.

## Guardrails

- S1 provides attribution only; R3 moved-tag detection remains S3+S5 and unknown remains possible for consumers that never perform a provenance-aware upgrade.
- S4b owns every parser/matching/location change under K21/M8; no heuristic is authorized.
- No production code or framework files are edited in this Product Owner session.
