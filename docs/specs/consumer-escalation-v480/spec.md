# Consumer escalation v4.8.0 - specification

**Status:** CLOSED — partially shipped | **documentation_tier:** 4 | **change_tier:** Full (`S1`, `S2`, `S4a`)
**Shipped:** T2/S2 (`88b3ea6`), T3/S4a (`ac0879d`)
**REVERTED — NOT SHIPPED:** T1/S1 (`9fdba11`), reverted by `519170d`
**Moot:** T4-T8 were the fix-forward for T1 and have no implementation authority after its revert.
**Deferred:** S3, S4b, S5

## Outcome

- T2 shipped a clone-durable deploy-approval receipt under locked closure C3.
- T3 shipped denial diagnostics that name the rule and pattern without claiming match location.
- T1 did not ship. Release-tree identification is provided by `docs/release-fingerprints.md`.

## S1/T1 provenance contract — REVERTED — NOT SHIPPED

T1 (`9fdba11`) was reverted by `519170d`; `hooks/local/lib/installed-provenance.sh` does not exist in
the shipped tree. The design recorded the source of a future upgrade, so it could not identify the
tree already on disk. `docs/release-fingerprints.md` superseded it for installed-tree identification.
The contract and ACs below are parked as historical analysis only; they describe no delivered or
authorized current behavior.

The reverted design proposed `INSTALLED_FROM` as one-line UTF-8 JSON with no insignificant
whitespace, keys ordered as listed below, and one trailing newline. Proposed schema:
`fusebase-flow/installed-from/v1`.

| Proposed state | Proposed required members | Proposed forbidden members |
|---|---|---|
| Git | `schema`, `source_kind:"git"`, `git_commit:<lowercase 40-hex>` | `content_digest` |
| Plain | `schema`, `source_kind:"plain"`, `content_digest:"sha256:<lowercase 64-hex>"` | `git_commit` |
| Unknown | No valid marker is available; health state only | Never written as a successful marker |
| Invalid | Marker exists but fails schema/type/value validation; health failure | Never normalized to unknown |

The reverted design would have resolved the exact Git commit before archiving. Direct recording
would have used `FF_SOURCE_COMMIT`; caller-supplied `--source-commit` would not have overridden it.
An adopted-bootstrap handoff would have bound the resolved commit and canonical-tree digest to the
consumed tree. For plain sources under M10, `content_digest` would have covered canonical regular-file
paths and bytes; symlink identity/targets and mode bits would have remained excluded.

The reverted ownership model classified `INSTALLED_FROM` as generated-unmanaged target state,
excluded it from managed/source manifests, and proposed atomic replacement only after a successful
provenance-aware upgrade. It also proposed prior-marker preservation, pre-write rejection of unbound
or non-invalidatable state, and warning-only isolation of helper failures after materialization.

## S1 historical acceptance criteria — inactive

1. **AC1 - typed schema:** would have validated the proposed Git/plain/unknown/invalid states and rejected irrelevant or extra members.
2. **AC2 - Git direct:** would have written resolved `FF_SOURCE_COMMIT`, not a tag, branch, version, or caller HEAD.
3. **AC3 - Git bootstrap:** would have written the resolved `--source-commit` value for the archived object.
4. **AC4 - plain source:** would have written `source_kind:"plain"` plus the consumed-snapshot SHA-256 without inventing a commit SHA.
5. **AC5 - ownership:** would have excluded `INSTALLED_FROM` from managed/source manifests and documented generated-unmanaged ownership and replacement rules.
6. **AC6 - early no-op:** would have preserved a valid prior marker and reported unavailable provenance when none existed.
7. **AC7 - failure preservation:** would have preserved prior-marker bytes across incomplete upgrades.
8. **AC8 - health states:** would have distinguished valid, missing, and malformed markers.
9. **AC9 - regression matrix:** would have covered direct/bootstrap/plain/no-op/failure/atomicity/manifest/health cases without changing existing version or tag verification.

## S2 closure C3 - LOCKED and IMPLEMENTED in T2 (`88b3ea6`)

**Status: LOCKED by the operator on 2026-08-11; IMPLEMENTED.** Closure C3 and the exact v1 field set
below shipped in T2 (`88b3ea6`). The reporting
consumer reviewed C3 and recorded "we support it as specified and have no further design input".
The field set is the locked surface: adding, renaming or dropping a field is a new decision, not an
implementation detail.

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

## S4a acceptance criteria — SHIPPED in T3 (`ac0879d`)

14. **AC14 - exact message:** every applicable deny renders `Denied: raw command matched rule <rule_id>, pattern <matched_pattern>. Quoted prose can match this pattern; no match location is claimed.`
15. **AC15 - retained facts only:** rendering uses deny-decision `rule_id` and `matched_pattern`; it performs no re-match, tokenization, quote parsing, payload extraction, or span inference.
16. **AC16 - behavior invariant:** allow/deny outcomes, matched rule/pattern selection, exit behavior, and executable surface are unchanged.
17. **AC17 - regression/protection:** tests cover executable text and quoted prose denials with exact identifiers and no location claim; the `hooks/shared/**` commit follows `policies/protected-paths.yml`.

## T4-T8 fix-forward acceptance criteria — HISTORICAL AND MOOT

These ACs were drafted to repair T1 after its ship-blocker review. Revert `519170d` removed T1, so
none is current implementation scope. They remain only as historical analysis.

18. **AC18 - direct identity binding:** would have bound direct upgrades only to materializer-resolved `FF_SOURCE_COMMIT`.
19. **AC19 - adopted-bootstrap receipt:** would have verified resolved commit and canonical-tree digest before target writes.
20. **AC20 - stale-marker invalidation:** would have verified absence after deletion and failed before target writes otherwise.
21. **AC21 - marker failure atomicity:** would have preserved prior marker state and prevented stale attribution after mutation.
22. **AC22 - helper isolation:** would have isolated malformed or failing helpers without a false provenance claim.
23. **AC23 - independent plain-digest proof:** would have mutation-tested the proposed regular-file-only digest contract.
24. **AC24 - live malformed health row:** would have asserted live integrity failure for an encoded malformed marker.
25. **AC25 - complete denial reason:** would have required complete expected denial reasons in every sample.
26. **AC26 - renderer signature:** would have fixed the denial renderer to two required parameters.
27. **AC27 - reproducible mutation evidence:** would have required a committed harness for seven RED-first mutants.
28. **AC28 - public-contract correction/discovery:** would have documented bootstrap limits and pointed to the proposed contract without duplication.

## Guardrails

- S1/T1 is reverted and not shipped; its attribution contract and T4-T8 fix-forward ACs are inactive.
- S4b owns every parser/matching/location change under K21/M8; no heuristic is authorized.
- Installed-tree identification is owned by `docs/release-fingerprints.md`; moved-tag detection remains deferred to S3/S5.
