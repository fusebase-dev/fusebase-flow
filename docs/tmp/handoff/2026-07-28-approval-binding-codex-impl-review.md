| Severity | Axis | File:line | Problem | Concrete fix |
|---|---:|---|---|---|
| **BLOCKER** | 1 | [approval_artifact.py:90](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/approval_artifact.py:90>) | Extreme valid ISO offsets such as `9999-12-31T23:59:59-14:00` raise `OverflowError` during UTC conversion. The exception escapes `evaluate_artifact()`, so the handler emits no deny. AC3 is false. | Catch conversion/range errors and make `parse_expiry()` total; add boundary-year/offset tests through both handlers. |
| **BLOCKER** | 1, 6 | [approve-local.sh:139](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/approve-local.sh:139>), [denial_message.py:63](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/denial_message.py:63>) | Normal DP.6/recovery invocations omit `--command`, so new schema-v2 artifacts are repo-bound but not command-bound. They remain replayable against every matching command in that repo, contrary to AC9/K2. | Require `--command` for command-gated actions and include the safely quoted blocked command in the resolving invocation. |
| **BLOCKER** | 1 | [approval_artifact.py:101](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/approval_artifact.py:101>) | K6 canonicalization collapses whitespace inside quoted arguments. `fusebase deploy --app "safe  prod"` and `--app "safe prod"` hash identically although they can target different values. Command binding is not one-command binding. | Re-open K6; hash the raw hook command, or use a proven quote-aware canonicalizer that never changes quoted/heredoc content. |
| **BLOCKER** | 1 | [command_policy.py:198](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/command_policy.py:198>) | Requirements are de-duplicated by display action. With only `lightweight_deploy`, `fusebase deploy && git push origin main` is allowed: the deploy `any_of` records display `production_deploy`, and the later rule that genuinely requires `production_deploy` is skipped. | Evaluate every matching rule independently; deduplicate only identical requirement sets after satisfaction is known. |
| **BLOCKER** | 1 | [command_rules.py:80](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/command_rules.py:80>), [command-policy.yml:118](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/policies/command-policy.yml:118>) | Raw regex matching is shell-evasive: `fusebase de'pl'oy` and `npx prisma mi"grate" deploy` execute the gated tokens but match no rule. Plain `rm build.log` is also ungated because the optional flag group still requires a second whitespace run. | Parse/validate shell structure or conservatively deny dynamically constructed gated commands; fix the `rm` regex and add execution-equivalent adversarial cases. |
| **BLOCKER** | 3 | [preflight.sh:293](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/preflight.sh:293>), [managed_content_manifest.py:265](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/managed_content_manifest.py:265>) | Preflight tells consumers to restamp a missing/drifted base from their current tree. That records local security edits as “upstream base”; when upstream later changes the same file, `L == B` classifies it `upstream-only` and overwrites it—the original incident. | Never restamp a base from a consumer-diverged tree. Recover only from the exact prior upstream tag/package; otherwise keep `unknown-base` and preserve. |
| **BLOCKER** | 3, 6 | [upgrade.sh:249](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/upgrade.sh:249>), [upgrade.sh:491](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/upgrade.sh:491>) | If Python/the classifier/list operation is unavailable, including hooks-off Windows installs with no `python3`, upgrade deliberately falls back to whole-directory copying and overwrites consumer edits. `--auto-yes` containment is bypassed. | Fail closed when the target version expects the classifier. Allow legacy copying only through a separately named, explicit unsafe override. |
| **MAJOR** | 1, 2 | [command_policy.py:235](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/command_policy.py:235>), [test-command-policy.sh:123](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-command-policy.sh:123>) | Denials contain only unsatisfied actions. With a deploy artifact present, the compound deploy+migration denial names only `database_migration`, while AC6/AC14/S5 require both actions. The test explicitly encodes the wrong one-action result. | Track `all_required_actions` separately from `unsatisfied_actions`; render and audit all requirements with each verdict. |
| **MAJOR** | 1 | [command_policy.py:183](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/command_policy.py:183>), [command_policy.py:284](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/command_policy.py:284>) | K4 is not total. A non-mapping `only_when` raises `AttributeError`; a malformed `match_order` that omits `require_approval` silently reaches `default: allow`. | Validate the complete policy schema and exact stage set before evaluating any command; convert every defect into `FLOW-POLICY-ERROR`. |
| **MAJOR** | 4, 6 | [path_policy.py:251](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/path_policy.py:251>), [active-approvals.sh:51](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/active-approvals.sh:51>) | Cross-carrier strict/compat behavior diverges. `path_policy` compat-accepts missing expiry without the required audit warning; `active-approvals.sh` never reads `strict_approvals`, so strict mode still classifies expiry-less deferrals as active. | Route both through one mode-aware acceptance/logging helper and test strict plus compat behavior in the health-check path. |
| **MAJOR** | 1, 2 | [approval_inventory.py:42](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/approval_inventory.py:42>) | Inventory removes both binding fields after a binding mismatch and can print `ACCEPT` for an artifact the gate rejects. This is not a truthful `verdict(strict)`. | Validate `repo_id` against the current root; report command binding as `UNCHECKED` without a command, never `ACCEPT`. |
| **MAJOR** | 3, 4 | [bootstrap-upgrade.sh:128](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:128>), [bootstrap-upgrade.sh:249](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:249>) | Bootstrap overwrites the installed engine and entire `hooks/local/lib/` before classification, then executes that installed copy. A later `changed-by-both` abort therefore cannot truthfully say “NOTHING was written,” and consumer engine customizations have already been replaced. | Execute the fetched engine from a temporary/source location; write managed consumer paths only after classification authorizes them. |
| **MAJOR** | 2 | [test-command-policy.sh:117](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-command-policy.sh:117>), [fixture 22:4](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/fixtures/22_pre_tool_use_compound_requires_all_actions.json:4>), [test-upgrade-conflict-classification.sh:293](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-conflict-classification.sh:293>) | Several advertised regressions are non-discriminating: fixtures 22/23 have no artifact and would also be denied by the old first-match code; the bootstrap AC16 fixture deliberately leaves the validator unchanged, so it never exercises adoption-path `changed-by-both`; all EOL fixtures force `core.autocrlf=false`. | Add old-code discriminators: one satisfied first action, exact bootstrap incident with both sides changed, `core.autocrlf=true`, classifier-unavailable, and tree-wide no-write assertions. |
| **MINOR** | 7 | [bootstrap-upgrade.sh:220](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:220>) | The comment claims `git archive` applies `core.autocrlf`; it does not. The configuration passed at line 230 has no EOL-conversion effect. Current v4.6.1 managed files remain safe because `.gitattributes` pins their EOL. | Correct the comment; if checkout conversion is needed, materialize the tag through a checkout/worktree honoring `.gitattributes`. |

## Detail — BLOCKER and MAJOR

### Approval gate

The in-memory probes produced these concrete results:

```text
DIGEST_COLLISION ... "safe  prod" == ... "safe prod"  True
RULE_MATCH "fusebase de'pl'oy"                         False
RULE_MATCH 'npx prisma mi"grate" deploy'              False
RULE_MATCH 'rm build.log'                             False
DUP_DISPLAY_DECISION                                  allow
```

The expiry probe also raised `OverflowError` for both upper- and lower-bound aware timestamps. This is exactly the AC3 class that claimed “any artifact content never raises.”

The usual recovery command compounds the binding problem: it creates only the missing action’s artifact and omits `--command`. Thus the path users are explicitly told to take creates the weaker, replayable artifact.

### Test reality

Specific acceptance criteria not adequately constrained:

- **AC3:** no timezone-boundary overflow case.
- **AC6/AC14:** the test expects only the unsatisfied action, contradicting the contract’s “every action.”
- **AC9:** the writer test always supplies `--command`; the normal unbound invocation is never checked.
- **AC10:** interrupted-write behavior is not simulated.
- **AC11:** no path-policy compat audit assertion and no strict health-deferral assertion.
- **AC16:** no bootstrap run where the incident file is actually `changed-by-both`.
- Classifier-unavailable fallback, quote-fragmented shell commands, duplicate-display `any_of`, binding-aware inventory, and `core.autocrlf=true` have no effective test.

Mutation assessment: removing action agreement, repo binding, SQL flags, or the basic all-match loop would turn existing tests red. Reintroducing old first-match behavior in handler fixtures 22/23, leaving default writer artifacts unbound, breaking strict health deferrals, or restoring destructive classifier fallback would not be reliably caught.

### Upgrade classifier

The Python K9 state function and normal per-file loop implement the ten intended states correctly. The safety boundary fails around that core:

1. Base provenance can be destroyed by the documented “restamp” recovery.
2. Classifier unavailability deliberately returns to destructive whole-directory copy.
3. Bootstrap mutates managed engine files before the supposedly no-write classification abort.
4. An unresolvable base can still advance VERSION while preserving most old content; this is disclosed by K9 but remains a false-success risk.

### Cross-carrier and self-hosting

The pre-commit import closure is complete: `approval_artifact.py` appears in both `FR07_SENTINELS` and the trusted PREP extractor. `path_policy.py` retained bootstrap operation binding, staged digest, exact membership, and no-glob behavior. `write-bootstrap-approval.sh` remains compatible. The active-approval array shape is unchanged, but its strict-mode semantics are not.

### Confirmed clean points

- Scope exclusions stayed excluded: no command-approval consumption, authenticated authorship, ticket-as-security control, or executable validator seam leaked in.
- `strict_approvals` ships `false`; straightforward legacy command artifacts are compat-accepted and normally audit-logged.
- Straightforward Full/Lightweight `fusebase deploy` cases work through both handlers.
- Hooks remain opt-in.
- All reviewed source modules are below the 800-line ceiling; largest is `upgrade.sh` at 770.
- No added code TODO/FIXME/WIP and `git diff --check` is clean.
- No files were edited during this review.

**Verdict: not ready. Seven BLOCKERs and six MAJORs. The reported 649/649 result does not establish the contract.**

---
🧭 Phase: Verify  
🎫 Ticket: approval-binding-and-upgrade-classification  
➡️ Next: Route the BLOCKER/MAJOR table to the AI Developer, then re-review the corrected range.