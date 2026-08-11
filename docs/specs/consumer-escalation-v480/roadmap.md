# Consumer escalation v4.8.0 - roadmap

**Status:** DRAFT | **documentation_tier:** 4 | **scope:** R1/R2/R3

North Star: on-vision. Attribution, durable evidence, and denial clarity add mechanism without adding ordinary-consumer ceremony.

## Slice disposition

| Order | Slice | Outcome | Lane | Blocker | State |
|---:|---|---|---|---|---|
| 1 | S1 / R3-attribution | Record typed consumed-source provenance for Git and plain sources | Full - new public upgrade contract | Plan approval only | IMPLEMENTABLE |
| 2 | S4a / R1-message | Explain denials from existing `rule_id` and `matched_pattern` without locating the match | Full - user-facing text in protected `hooks/shared/**` | Plan approval + normal FR-07 authorization before protected-path commit | IMPLEMENTABLE |
| 3 | S2 / R2 | Commit a verification receipt while the live approval remains gitignored | Full - shipped deploy-evidence contract | Operator lock of closure C3 and receipt schema in `spec.md` | DESIGN-BLOCKED |
| 4 | S3 / R3-policy | Lock and publish retag policy | Full - release-governance decision | Operator choice: immutable or explicitly movable tags | DESIGN-BLOCKED |
| 5 | S4b / R1-parser | Attribute a match to a shell payload/span or change matching | Full - parser/execution semantics | K21/M8 parser reserve | DESIGN-BLOCKED |
| 6 | S5 / R3-detection | Detect and surface moved-tag transitions during upgrade | Full - upgrade behavior follows retag policy | S3, then S1-compatible history design | DESIGN-BLOCKED |

## Ordering and independence

1. T1 implements S1; T3 implements S4a independently.
2. T2 does not start until the operator locks S2 closure C3 and its receipt schema.
3. Shared edits to `hooks/tests/run-tests.sh` are serialized only; they create no semantic dependency between T1, T2, and T3.
4. S5 is planned only after S3. S4b remains outside every implementation task.

## R3 claim boundary

S1 makes future Git consumption attributable and plain-source consumption content-addressed. It does not detect a moved tag, prove tag immutability, or notify a consumer that never upgrades. A pre-marker install or an already-current no-op before the first marker write remains `unknown (provenance marker unavailable)`. R3 detection remains open until S3 and S5 ship; release notes must not claim S1 alone closes R3.

## R2 closure comparison

| Closure | Durable evidence | Binding value | Cost/risk | Disposition |
|---|---|---|---|---|
| C1 - commit live approval artifact | Highest: original object survives clone | Full object is inspectable | Persists ephemeral consent; conflicts with gitignored-live-artifact design | Reject |
| C2 - report assertion only | Low | Unfalsifiable; can omit schema, `action`, `repo_id`, `command_digest`, `reason`, and object identity | Smallest edit but evidentiary regression | Reject |
| C3 - committed verification receipt | High: digest + actual binding fields + observed validation + deploy hash | Names the validated object and its deployment while preserving local consent | New public evidence schema requires Full-lane lock | Recommend; operator lock required |

Closure C3 is an inline receipt in the committed deploy report. Stored approval fields and computed validation observations are separate; `ttl` and `verdict` are never represented as stored approval fields.

## R1 split

S4a uses data already retained on deny decisions: `rule_id` and `matched_pattern`. Required text: `Denied: raw command matched rule <rule_id>, pattern <matched_pattern>. Quoted prose can match this pattern; no match location is claimed.` It changes no matching, permits no command, and does not reopen K21/M8.

S4b owns all payload/span attribution, shell-token interpretation, heuristic location claims, and matching changes. No span-location heuristic is proposed.

## Ownership and protected paths

- `INSTALLED_FROM` is generated-unmanaged target-repository state: excluded from managed/source manifests, never shipped as source content, and replaced only by successful provenance-aware upgrade.
- Apply `policies/protected-paths.yml` by matched path. Protected examples relevant here are `.github/workflows/**`, `policies/*.yml`, and `hooks/shared/**`; not all `.github/**` is protected.
- T1/T2 targets under `hooks/local/**`, `hooks/tests/**`, `templates/**`, `docs/**`, and root generated state are not protected by that policy; do not mint FR-07 authorization for them. T3's `hooks/shared/**` edit is protected.

## Out of scope

- M10 revision or a Git requirement for plain-directory sources.
- Parser work, match narrowing, deny bypass, payload/span attribution, or execution widening.
- Committing live approval JSON, authenticating operator identity, or weakening approval validation.
- Retag choice, tag mutation, release-history rewrite, app deploy, or consumer-repository mutation.
- Code or framework edits in this Product Owner session.
