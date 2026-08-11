# Consumer escalation v4.8.0 - specification

**Status:** DRAFT | **documentation_tier:** 4 | **change_tier:** Full (`S1`, `S2`, `S4a`)
**Implementation-ready:** S1, S4a | **Design-blocked:** S2, S3, S4b, S5
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

For Git, the materializer resolves the exact commit before archiving it; direct upgrade receives `FF_SOURCE_COMMIT`, and bootstrap passes `--source-commit`. For plain sources under M10, `content_digest` is SHA-256 of the exact materialized snapshot archive bytes consumed by upgrade; Git is not required.

`INSTALLED_FROM` ownership is generated-unmanaged target state. It is absent from managed/source manifests, is not copied from source, and is atomically replaced by same-directory temporary-file rename only after a successful provenance-aware upgrade. Failure or no-op preserves a prior marker.

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

## Guardrails

- S1 provides attribution only; R3 moved-tag detection remains S3+S5 and unknown remains possible for consumers that never perform a provenance-aware upgrade.
- S4b owns every parser/matching/location change under K21/M8; no heuristic is authorized.
- No production code or framework files are edited in this Product Owner session.
