# Decisions — approval-binding-and-upgrade-classification

**Letter prefix:** K
**Approval status:** LOCKED 2026-07-28 under the operator's standing end-to-end autonomous-run authorization. Each lock is a PO recommendation the operator did not individually confirm; every one is flagged **ASSUMPTION** where a different call would change the work.
**Linked spec:** `docs/specs/approval-binding-and-upgrade-classification/spec.md`

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| K1 | Where artifact validation lives | New `hooks/shared/approval_artifact.py`, shared by both validators | LOCKED |
| K2 | Additive binding, not replacement | Enforce `command_digest`/`repo_id` when present; action-scope when absent | LOCKED |
| K3 | Trust model is stated, not faked | `approved_by` + `ticket` = audit metadata; correct the contradictory comment | LOCKED |
| K4 | Fail-closed on policy defects | Bad regex / empty policy / malformed artifact → deny | LOCKED |
| K5 | Lightweight-lane gate parity | `fusebase deploy` accepts `production_deploy` **or** `lightweight_deploy`, boundary documented | LOCKED |
| K6 | Command-digest canonicalization | Hash the exact hook-received command after whitespace collapse only | LOCKED |
| K7 | Two-stage strict cutover | Compat + inventory this release; strict default next release | LOCKED |
| K8 | Compound commands require all matched actions | All-match, one denial listing every action | LOCKED |
| K9 | `unknown-base` is preserve, not abort | Only `changed-by-both` aborts an unattended upgrade | LOCKED |
| K10 | Classifier adoption via `bootstrap-upgrade.sh` | Staged-engine hop is the documented + tested transition | LOCKED |
| K11 | Defer single-use consumption | Backlog ticket, not this release | LOCKED |
| K12 | CLI output is a designed surface | Denial message + conflict report get explicit ACs and a shared renderer | LOCKED |
| K13 | Base synthesis at adoption + refresh after apply | Stamp base from the tag matching local `VERSION`; reinstall base last | LOCKED |
| K14 | Managed-content list has one home | Canonical in the Python module; `upgrade.sh` reads `list-managed` | LOCKED |
| K15 | Per-file apply, directory-level backup | Rewrite apply loop per file; keep existing dir snapshot | LOCKED |
| K16 | `fallthrough` is dead config — remove it | Delete the key; all-match semantics stated explicitly | LOCKED |
| K17 | Artifact verdict = state; acceptability = predicate | `Verdict` is state only; `is_acceptable(verdict, strict)` decides | LOCKED |
| K18 | Per-rule requirements; denials name all | No dedup by display action; render all + unsatisfied | LOCKED |
| K19 | `--command` mandatory for command-gated actions | Writer exits 2 without it; denial emits the bound invocation | LOCKED |
| K20 | Fail closed, never self-restamp a base | No destructive fallback; no restamp from a diverged tree | LOCKED |
| K21 | Regex evasion documented, not hidden | Fix `rm` gap; document the limitation; backlog the real fix | LOCKED |

## K1. Where artifact validation lives

**Recommendation:** Extract a new `hooks/shared/approval_artifact.py` owning artifact load, schema detection, expiry parsing and a verdict enum. `command_policy.py` and `path_policy.py` both consume it.

**Reasoning:** The "missing `expires_at` = valid forever" defect exists in **three** carriers — `command_policy.py:47-50`, `path_policy.py:237-239`, `active-approvals.sh:27-38`. Fixing only the reported one leaves two live copies and guarantees the next divergence. `path_policy.py` is already 316 lines and `command_policy.py` will grow past its current 165 with schema handling; FR-25 makes extraction on this responsibility seam in-scope rather than scope creep. One loader also means the writer and every verifier cannot drift — the property `write-bootstrap-approval.sh:70-96` already relies on for digests.

**Alternatives considered:**

- **Option A: patch `command_policy.py` only** — rejected: leaves the same defect live in two other carriers; the consumer's report would be closed while the hole stays open on the path-policy side.
- **Option B: duplicate the fix into all three carriers** — rejected: three copies of an expiry parser is exactly the drift FR-20 says to zoom out of.

**Lock status:** LOCKED

---

## K2. Additive binding, not replacement

**Recommendation:** New artifacts carry `command_digest` and `repo_id`. The validator enforces each field **when present** (mismatch → deny) and falls back to action-scope + AC1–AC3 validation when absent.

**Reasoning:** The consumer's schema-v2 rejects every legacy artifact on day one — on their own project that is 98 artifacts. A hard cutover in the same release as the fix converts a security improvement into an outage. Additive enforcement is strictly stronger than today from the first release (a bound artifact cannot be replayed against a different command or repo) while legacy artifacts get the AC1–AC3 tightening immediately. K7 then makes the cutover a deliberate, announced second step.

**Alternatives considered:**

- **Option A: mandatory schema v2 immediately (consumer's design)** — rejected: breaks every existing consumer's in-flight approvals with no warning window; their own § 5 lists migration burden as an open caveat.
- **Option B: bind but only warn on mismatch** — rejected: a binding that does not deny is documentation, which is the exact failure mode this ticket exists to fix.

**Lock status:** LOCKED

---

## K3. Trust model is stated, not faked — ASSUMPTION

**Recommendation:** `approved_by` and `ticket` are documented as **audit metadata, not authenticated authority**. Correct `policies/approval-policy.yml:103-106`, whose comment claims hooks check the self-attested role against `approval_authors`, to match reality — which the same file already admits at `:44-46`. Do not add an authorship check.

**Reasoning:** The agent and the operator write as the same OS principal; `$USER`, self-attested role strings and any locally stored non-secret are forgeable by the process being gated. An enforcement check here would be theatre, and theatre in a security control is worse than an absent control because readers trust the documentation — the consumer's own § 2a argument, which is correct. Real authorship requires a host-signed approval event or a key the agent cannot read; Flow has neither today. What Flow **can** enforce (schema, bounded expiry, action agreement, command/repo binding, filename/body consistency) is what this ticket enforces.

**ASSUMPTION:** the operator accepts "documented limitation" over "attempted enforcement". If they instead want a host-authoritative signal, that is a separate, larger ticket (a Flow-side signing seam) and this decision changes.

**Alternatives considered:**

- **Option A: check `approved_by == $USER`** — rejected: trivially forged by the same process it gates; adds false assurance.
- **Option B: silently drop `approval_authors` from the policy** — rejected: loses the record that the gap is known and intentional; a future reader re-proposes it.

**Lock status:** LOCKED

---

## K4. Fail-closed on policy defects

**Recommendation:** An unparseable regex in `deny` or `require_approval` **denies** the command with a policy-error reason. A missing or empty command policy **denies** rather than reaching `default: allow`. Malformed artifact JSON of any shape is rejected without escaping the guard.

**Reasoning:** `command_policy.py:64-67,83-87,127-131` currently swallows `re.error` and continues; a typo in a deny pattern silently disables that rule and the command falls through to `default: allow`. Same for a policy file that fails to load. A security gate whose failure mode is "allow" is not a gate. `:43-48` also parses JSON inside the `try` but reads `expires` outside it, so a JSON array or numeric `expires_at` raises through `evaluate()` — the handler's behaviour on that exception is untested.

**Alternatives considered:**

- **Option A: keep skipping bad rules, log a warning** — rejected: warnings in a hook are invisible in practice; the operator learns about it after the unapproved deploy.
- **Option B: fail closed only for `require_approval`, skip bad `deny` rules** — rejected: a broken `rm -rf` deny pattern is the more dangerous of the two.

**Lock status:** LOCKED

---

## K5. Lightweight-lane gate parity — ASSUMPTION

**Recommendation:** The `fusebase deploy` rule in `policies/command-policy.yml:43-46` accepts **either** `production_deploy` or `lightweight_deploy` via an explicit `any_of` action list. Document in `flow-skills/lightweight-lane/SKILL.md` and `workflows/lightweight-lane.md` that lane classification is **process-authoritative** — the hook cannot verify a change was genuinely LL-eligible.

**Reasoning:** This is a live contradiction Codex found that the consumer missed. `policies/approval-policy.yml:57-73`, `policies/required-artifacts.yml:73-78`, `flow-skills/role-discipline/references/deploy.md:20` and `workflows/lightweight-lane.md:20` all state `lightweight_deploy` replaces `production_deploy` — but the only `fusebase deploy` rule requires `production_deploy`. Today an FR-21 Lightweight deploy following documented procedure is **denied** by the hook. Either the docs or the policy is wrong, and the docs describe the shipped intent. The honest cost is that an agent could self-declare Lightweight to take the cheaper gate — which is why the boundary is written down rather than left implied.

**ASSUMPTION:** FR-21's process-authoritative lane classification is acceptable as the trust boundary. If not, the alternative is to delete the Lightweight deploy lane, which is a product decision well outside this ticket.

**Alternatives considered:**

- **Option A: require `production_deploy` always; strike `lightweight_deploy` from the docs** — rejected: guts FR-21's stated purpose (removing the magic-phrase/artifact friction) and contradicts four shipped documents.
- **Option B: bind `lightweight_deploy` to a change-note file's existence** — rejected for this release: the agent writes the change-note too, so it adds ceremony without adding authority. Noted as a future refinement.

**Lock status:** LOCKED

---

## K6. Command-digest canonicalization — **REVISED 2026-07-28 (post-implementation review)**

**Recommendation (current):** `command_digest = sha256(command.strip())` over the exact command string the hook receives. **Trim leading/trailing whitespace only. Do not collapse interior whitespace. Normalize nothing else.**

**Reasoning:** The original decision said "collapse runs of whitespace", and the adversarial implementation review proved that unsafe with a concrete collision:

```
fusebase deploy --app "safe  prod"   ==   fusebase deploy --app "safe prod"     → same digest
```

Interior whitespace inside a quoted argument is *data*, not formatting. Collapsing it makes one approval authorize a command targeting a different value — which is precisely the "one artifact authorizes a command it was not minted for" failure this ticket exists to eliminate. My original reasoning had it backwards: I justified collapse as covering "the realistic mint/execute difference", but the writer captures the **same string the hook later sees**, so there is no such difference to absorb. The friction I was avoiding does not exist; the collision I created does.

Trimming the ends is retained because it is provably semantics-free in shell.

**Alternatives considered (revised):**

- **Option A: quote-aware canonicalization** — rejected: to know which whitespace is inside quotes you must parse shell, and a parser that is wrong in either direction either breaks approvals or creates a new collision class. Complexity with no gain over raw.
- **Option B: collapse interior whitespace (the original K6)** — **rejected on evidence**; see the collision above.
- **Option C: hash the fully raw string, not even trimmed** — rejected only because trailing-newline differences between capture paths are a real and semantics-free nuisance; `.strip()` is the minimal safe concession.

**Lock status:** LOCKED (revised). Supersedes the original; prior wording is in git history.

---

## K7. Two-stage strict cutover — ASSUMPTION

**Recommendation:** This release ships the strict validator with strict mode **OFF** (`strict_approvals: false` in `policies/approval-policy.yml`), a logged warning per legacy artifact, and `approve-local.sh --inventory` (AC12). The next release flips the default. Legacy artifacts are never auto-migrated — no synthesized `expires_at`.

**Reasoning:** A consumer with 22 expiry-less artifacts loses all of them the moment strict lands. Giving them one release with an inventory command that names exactly which files will be rejected turns a breakage into a scheduled reissue. Synthesizing an expiry onto a stale artifact would be Flow inventing an approval no operator gave — the precise thing this ticket is fixing.

**ASSUMPTION:** one release of warning is a sufficient window. A slower rollout would just move the flip further out; nothing else in the design changes.

**Alternatives considered:**

- **Option A: strict on by default now** — rejected: breaks in-flight consumer approvals silently at upgrade time, the same class of harm as the overwrite that started this ticket.
- **Option B: never flip; leave compat forever** — rejected: legacy artifacts stay replayable indefinitely, so § 1 is never actually closed.

**Lock status:** LOCKED

---

## K8. Compound commands require all matched actions

**Recommendation:** `_evaluate_require_approval` collects **every** matching rule and requires an artifact for each. A denial reports the complete required-action set in one message.

**Reasoning:** `command_policy.py:79-99` returns on the first match, so `fusebase deploy && npx prisma migrate deploy` is authorized by the deploy artifact alone and the migration is never gated. Serial denials (fix one, hit the next) would be the obvious implementation and the wrong UX — it forces the operator through N round-trips for one command line, which is why AC6 and AC14 require the full set up front.

**Alternatives considered:**

- **Option A: keep first-match, document the limitation** — rejected: it is a straightforward bypass of `database_migration`, one of the four gated actions the consumer named.
- **Option B: deny all compound commands outright** — rejected: `&&` chains are ordinary developer usage; blanket denial would drive `--no-verify`-shaped workarounds.

**Lock status:** LOCKED

---

## K9. Full classification truth table; `unknown-base` is preserve, not abort

**Recommendation:** Classification is a function of three inputs — base `B` (what upstream shipped last time), local `L`, upstream `U` — each of which may be absent. The complete table, with unattended (`--auto-yes`) behaviour:

| # | B | L | U | Classification | Attended | `--auto-yes` |
|---|---|---|---|---|---|---|
| 1 | any | present | present, `L == U` | `current` | no-op | no-op |
| 2 | present | `L == B` | `U != B` | `upstream-only` | overwrite | overwrite |
| 3 | present | `L != B` | `U == B` | `consumer-only` | prompt keep/overwrite, default keep | **preserve**, report |
| 4 | present | `L != B` | `U != B`, `L != U` | `changed-by-both` | prompt, default abort | **abort** |
| 5 | present | `L == B` | absent | `upstream-deleted` (clean) | delete with backup | delete with backup |
| 6 | present | `L != B` | absent | `upstream-deleted` (dirty) | prompt, default keep | **preserve**, report |
| 7 | absent | present | absent | `consumer-added` | no-op, silent | no-op, silent |
| 8 | absent | absent | present | `upstream-added` | install | install |
| 9 | present | absent | present | `consumer-deleted` | prompt, default leave absent | **leave absent**, report |
| 10 | absent | present | present, `L != U` | `unknown-base` | prompt, default keep | **preserve**, report |

Row 7 is silent because a consumer's own untracked file is not Flow's business; every other preserve/abort row is reported.

**Reasoning:** Rows 7–9 exist because Fable's review caught that the six-verdict set could not be "exactly one of" across the base × local × upstream presence cube — a consumer-added file and an upstream-added file fit none of the original verdicts, yet T12's own test matrix needed an "added" case. Row 10 is the residual genuine ambiguity. Aborting on `unknown-base` would make the classifier's first run unusable; preserving is the safe half, because the worst case is a stale consumer file the report names explicitly, versus the overwrite that caused this ticket. `changed-by-both` (row 4) is the only undecidable state and the only one that stops an unattended run.

**Critical interaction with K13:** rows 3, 4 and 10 are only distinguishable when a base exists. Without K13's base synthesis, *every* pre-4.7.0 path lands on row 10 and the first classifier upgrade would install nothing. K9 and K13 are load-bearing for each other.

**Alternatives considered:**

- **Option A: abort on `unknown-base`** — rejected: unusable first adoption.
- **Option B: overwrite `unknown-base` (treat upstream as canonical)** — rejected: this is exactly today's behaviour and reproduces the reported defect for every pre-4.7.0 consumer.

**Lock status:** LOCKED

---

## K13. Base synthesis at adoption, and base refresh after every upgrade

**Recommendation:** Two rules that make the classifier work more than once.

**(a) Synthesis at adoption.** A consumer with no `audit/managed-content-manifest.json` does not get a tree full of `unknown-base`. `bootstrap-upgrade.sh` checks out the upstream tag equal to the consumer's installed `VERSION` (e.g. `v4.6.1`) from the clone it already fetches, stamps a base manifest from *that* tree, and classifies against it. Only when the matching tag cannot be resolved (unreleased/forked VERSION) does the tree fall through to `unknown-base` (K9 row 10).

**(b) Refresh after apply.** Ordering is fixed and must not be reordered: **classify against the OLD base → apply per K9 → install the SOURCE tree's manifest as the NEW base.** `audit/managed-content-manifest.json` joins `CONTENT_FILES` in `hooks/local/upgrade.sh:233-235` and is applied **last**, after content.

**Reasoning:** Fable's F1/F2 caught that these were missing and that their absence is fatal in two directions. Without (a), `consumer-only` and `changed-by-both` are unreachable for every existing consumer — the entire fleet lands on `unknown-base`, everything is preserved, and the 4.7.0 upgrade delivers no content at all. Without (b), the classifier is single-shot: the 4.8.0 upgrade compares 4.7.0 files against a 4.6.1 base, calls every one of them consumer-divergent, and preserves them forever — reintroducing exactly the drift this ticket exists to remove, one release later.

Synthesis is sound because the tag *is* the ground truth for "what upstream shipped you": it is byte-identical to what the consumer's install/upgrade wrote. It is not a guess.

**Consequence for the incident file — AC16 corrected.** With a synthesized 4.6.1 base, the consumer's locally patched `hooks/shared/command_policy.py` is `L != B` **and** `U != B` (4.7.0 rewrites that file). It is therefore **`changed-by-both` (row 4)**, not `consumer-only`. The originally drafted AC16/S4 expectation was wrong. The invariant that actually matters — and what AC16 now asserts — is **preserved and explicitly reported, never silently overwritten**; the classification is `changed-by-both` and an unattended run aborts on it.

**Alternatives considered:**

- **Option A: no synthesis; `unknown-base` everywhere on first run** — rejected: the classifier release cannot deliver its own content (F2).
- **Option B: synthesize the base from the *incoming* upstream tree** — rejected: it would declare every consumer edit `current` or `consumer-only` against the wrong reference, and would mark a file the consumer never touched as diverged.
- **Option C: ask the consumer to hand-stamp a base before upgrading** — rejected: FR-12/FR-16 — the operator does not run setup commands the agent can run correctly.

**Lock status:** LOCKED

---

## K14. Managed-content list has one home: the Python module

**Recommendation:** The canonical list of managed paths lives in `hooks/local/lib/managed_content_manifest.py`, which exposes a `list-managed` subcommand printing one path per line. `hooks/local/upgrade.sh` populates `CONTENT_DIRS` / `CONTENT_FILES` by reading that output instead of declaring the arrays inline at `:232-235`.

**Reasoning:** Fable's F7: the arrays are bash literals inside `upgrade.sh`, and a Python module cannot consume them without parsing shell source or a `declare -p` shim — neither of which anyone should write. The list must live in exactly one place or the manifest and the upgrade engine will eventually disagree about what "managed" means, which is a silent correctness hole in the classifier. Python is the right home because the manifest tooling, the classifier, and the stamp/verify path are all Python; the shell is orchestration.

**Alternatives considered:**

- **Option A: a YAML/JSON data file both read** — viable and nearly as good; rejected only because it adds a third artifact and the Python module must exist regardless.
- **Option B: keep the bash arrays canonical, have Python shell out to `declare -p`** — rejected: parsing shell state from Python is fragile and platform-sensitive on MSYS.

**Lock status:** LOCKED

---

## K15. Per-file apply, directory-level backup

**Recommendation:** `upgrade.sh` applies per **file**, driven by the classification list, replacing today's whole-tree `copy_dir` at `:366-388`. A directory holding one `consumer-only` file among a hundred `upstream-only` files refreshes the ninety-nine and preserves the one. The existing directory-level `.pre-upgrade-<TS>` backup is **retained unchanged** — it already snapshots everything before any write, so no per-file backup scheme is added, and the retention pruning at `:561-607` is untouched.

**Reasoning:** Fable's F8: classification is per-path but the engine applies per-directory, and the plan never said the apply loop must be rewritten. Mixed-class directories are the normal case, not an edge case — `hooks/` is one directory and the whole ticket is about one file inside it. Keeping the dir-level backup avoids inventing a second backup mechanism to keep correct, and it is strictly more conservative than per-file backups.

**Alternatives considered:**

- **Option A: keep dir-granular apply; skip any directory containing a conflict** — rejected: one consumer-edited file would block every upstream fix in that directory, which is worse than today.
- **Option B: per-file backups replacing the dir snapshot** — rejected: no safety gain, and it breaks the existing prune/retention logic.

**Lock status:** LOCKED

---

## K10. Classifier adoption via `bootstrap-upgrade.sh`

**Recommendation:** Consumers on ≤4.6.1 adopt the classifier through the existing staged-engine hop at `hooks/local/bootstrap-upgrade.sh:9-28,123-174`, which runs the **new** engine from the fetched source rather than the installed one. Documented in release notes and install/upgrade docs; proven by AC16's end-to-end fixture.

**Reasoning:** Self-referential bootstrap problem: the first classifier release cannot install itself through the old `upgrade.sh`, because the old engine copies upstream over `hooks/**` — including the new engine and the patched validator — before any classification runs. The mechanism for exactly this already exists and is already tested (`test-ws5-upgrade-bounded.sh`, `test-bootstrap-baseline-hop.sh`); reusing it beats inventing a second transition path.

**Alternatives considered:**

- **Option A: ordinary `upgrade.sh` and accept one last overwrite** — rejected: the one overwrite it costs is the consumer's security patch, the exact harm reported.
- **Option B: a new one-off migration script** — rejected: duplicates `bootstrap-upgrade.sh` and adds a second thing to keep correct.

**Lock status:** LOCKED

---

## K11. Defer single-use consumption — ASSUMPTION

**Recommendation:** Do **not** implement reserve/consume in this release. File `docs/backlog/approval-single-use-consumption/README.md` recording the prerequisites: a stable host call ID shared by `permission_request.py:40-57` and `pre_tool_use.py:62-76`, consume-on-success / release-on-failure finalization, orphan-reservation TTL and recovery, and tested atomicity on Windows and network filesystems.

**Reasoning:** Both hook entry points evaluate the same command today, so a claim taken at the first evaluation is already burned at the second — the approval fails on the very first correct use. Consumption before command success also burns an approval on a transient deploy failure, which collides head-on with DP.6's low-friction retry flow. The consumer flags all of this themselves in their § 5. Binding (K2) removes most of the replay value without needing any of it: a bound artifact only ever authorizes one command in one repo.

**ASSUMPTION:** binding is sufficient risk reduction for this release. If the operator wants true one-shot semantics sooner, the host-lifecycle prerequisites above become their own ticket first.

**Alternatives considered:**

- **Option A: ship `O_EXCL` claim now (consumer's design)** — rejected: double-evaluation burns it before first use; failure semantics unspecified; network-FS behaviour untested.
- **Option B: consume in `PostToolUse` on success only** — rejected as premature: still needs the stable call ID that does not exist yet. This is the shape the backlog ticket should take once it does.

**Lock status:** LOCKED

---

## K12. CLI output is a designed surface

**Recommendation:** Treat the FR-12 denial message and the upgrade conflict report as UX deliverables with acceptance criteria (AC14, AC15), rendered through one shared formatter each rather than inline `echo`/f-strings scattered across handlers.

**Reasoning:** These two strings are the entire operator-visible product of this ticket — every other change is invisible when it works. The current denial reason (`command_policy.py:104-111`) is five lines of framework prose that says "no artifact found" regardless of whether the artifact was missing, expired, action-mismatched or digest-mismatched; the operator cannot tell a stale approval from an absent one. The audience is internal/developer (no `docs/audience.md`, no client surface), so the design target is *diagnostic precision and one copy-pasteable next command*, not visual polish. AC15's rule that safe groups collapse to counts while decision-needing groups enumerate every path is the same principle applied to the upgrade report: the consumer's report notes they were never told **which** files diverged.

**Alternatives considered:**

- **Option A: leave messages as-is; put the detail in docs** — rejected: the operator reads the denial, not the docs, at the moment they are blocked.
- **Option B: verbose output listing all classifications and all artifacts** — rejected: burying the two paths that need a decision under 100 `current` rows is the same failure as saying nothing.

**Lock status:** LOCKED

---

## K16. `fallthrough` is dead config — remove it

**Recommendation:** Delete `fallthrough: true` from the `rm` rule at `policies/command-policy.yml:88`. No code has ever read it. In its place, state the all-match semantics explicitly in the file header: **the `deny` stage still short-circuits** (a denied command never reaches `require_approval`), and within `require_approval` **every** matching rule contributes its action to the required set.

**Reasoning:** Fable's F5: T4's all-match change would turn a currently-dead key live in a way nobody designed, and an implementer would have to invent whether it suppresses, orders, or does nothing. Its stated intent — "only matches if not already denied above" — is already the actual behaviour of the deny→require_approval stage order (`command_policy.py:144-156`), so the key is redundant even as documentation. Deleting it is strictly clearer than defining semantics for a flag whose job the stage order already does.

**Accepted consequence:** under all-match, `fusebase deploy && rm build.log` newly requires `destructive_file_delete` alongside `production_deploy`. That is correct — the `rm` genuinely happens — and AC14's single-message denial keeps it from costing a second round-trip. Announce it in the release notes as part of the K8 tightening.

**Alternatives considered:**

- **Option A: implement `fallthrough` as "skip in all-match"** — rejected: it would let a compound command carry an ungated `rm`, which is the K8 bypass in a new costume.
- **Option B: leave the key, document it as ignored** — rejected: a config key that looks load-bearing and is not is how this ticket's `approval_authors` defect happened (K3).

**Lock status:** LOCKED

---

## K17. Verdict is state; acceptability is a separate predicate

**Recommendation:** `approval_artifact.Verdict` enumerates **artifact state only**: `VALID`, `EXPIRED`, `MISSING_EXPIRY`, `MALFORMED`, `ACTION_MISMATCH`, `BINDING_MISMATCH`. There is no `LEGACY_OK`. A separate predicate `is_acceptable(verdict, *, strict) -> bool` resolves state into a decision, and each carrier declares its pass-set:

| Carrier | Accepts |
|---|---|
| `command_policy` (strict=False) | `VALID`, `MISSING_EXPIRY` (logged once via `audit_logger`) |
| `command_policy` (strict=True) | `VALID` only |
| `path_policy` non-bootstrap | `VALID`, `MISSING_EXPIRY` (logged) |
| `path_policy` bootstrap | `VALID` only, **plus** the existing digest/operation/exact-path checks at `path_policy.py:241-275`, which are unchanged and additional |
| `--inventory` | reports every state; never accepts |

**Reasoning:** Fable's F10: `MISSING_EXPIRY` and `LEGACY_OK` were two names for one artifact state under different modes, mixing state with mode-resolved outcome. A consumer of `evaluate_artifact()` could not tell which it would receive, and `path_policy` had no defined mapping from verdict to its boolean `has_active_exception` return. Separating the two makes the contract single-valued and lets each carrier declare its own strictness without the loader knowing who called it.

**Alternatives considered:**

- **Option A: keep `LEGACY_OK` as a verdict** — rejected: the same artifact would report different verdicts on different calls, making the inventory (AC12) mode-dependent and confusing.
- **Option B: pass `strict` into the loader and return a bool** — rejected: destroys the per-state detail AC12 and AC14 both need.

**Lock status:** LOCKED

---

## K18. Requirements are per-rule, and denials name every requirement

**Recommendation:** Two corrections to the all-match loop, both proven necessary by the implementation review.

**(a) No de-duplication by display action.** Every matching `require_approval` rule is evaluated **independently**. The shipped code de-duplicated requirements by display name, so the `fusebase deploy` `any_of` rule (display name `production_deploy`) absorbed the *separate* `git push origin main` rule that genuinely requires `production_deploy`. Result: with only a `lightweight_deploy` artifact, `fusebase deploy && git push origin main` was **allowed**. That is a live gate bypass, and it is the exact class K8 existed to close.

**(b) Denials name every requirement, not only the unsatisfied ones.** AC6/AC14/S5 all say the operator sees the complete required-action set in one message. The shipped code rendered only unsatisfied actions — and the test encoded that wrong result as expected. Track `all_required_actions` separately from `unsatisfied_actions`; render and audit both.

**Reasoning:** (a) is a correctness defect with a concrete exploit. (b) is the difference between "here is everything this command needs" and "here is the next thing you're missing" — the latter is the serial-denial UX AC14 was written to prevent, and it silently re-appeared through the rendering path rather than the loop.

**Lock status:** LOCKED

---

## K19. Command binding is mandatory for command-gated actions

**Recommendation:** `approve-local.sh` **requires** `--command` for any action reachable from a `require_approval` rule; without it, exit 2 and write nothing. The FR-12 denial message emits the exact resolving invocation **including the safely quoted blocked command**, so the agent's copy-paste path always produces a bound artifact.

**Reasoning:** The review found that the normal DP.6 and recovery paths omit `--command`, so every artifact minted the documented way was repo-bound but **not** command-bound — replayable against every matching command in that repo. AC9's binding therefore existed in code and was absent in practice: the path users are told to take produced the weaker artifact. This is the same failure shape as K3's `approval_authors` (a control that is real in documentation and absent in the field), which makes it exactly the thing this ticket must not ship.

The Deploy session always knows the command it is about to run, so requiring it costs no operator interaction — DP.6 is unchanged, the agent fills it in.

**Alternatives considered:**

- **Option A: default to unbound, warn** — rejected: the warning path becomes the normal path, which is how we got here.
- **Option B: bind to the command only when supplied (shipped behaviour)** — rejected on evidence.

**Lock status:** LOCKED

---

## K20. Fail closed when the classifier cannot run; never restamp a base from a diverged tree

**Recommendation:** Two upgrade-safety corrections.

**(a) No destructive fallback.** When Python or the classifier is unavailable, `upgrade.sh` **fails closed** with a diagnostic. The shipped code fell back to whole-directory copying — which is the pre-4.7.0 overwrite behaviour, reachable on any hooks-off Windows install without `python3`, and it bypasses `--auto-yes` containment entirely. Legacy copying, if retained at all, sits behind a separately named explicit unsafe override that is never suggested by a diagnostic.

**(b) No self-restamping.** `preflight.sh` must **not** tell a consumer to restamp a missing or drifted base from their current tree. Doing so records their local security edits as "upstream base"; the next upstream change to the same file then classifies `upstream-only` and overwrites it — reproducing the original incident *through the machinery built to prevent it*. Base recovery comes only from the exact prior upstream tag/package; otherwise the path stays `unknown-base` and is preserved.

**Reasoning:** Both defects share a shape: a convenience path that quietly restores the destructive behaviour the ticket removed. (b) is the more insidious — it would have been recommended to the consumer by our own tooling.

**Lock status:** LOCKED

---

## K21. Regex matching is defeatable by quote-fragmentation — document it, don't pretend otherwise

**Recommendation:** Do **not** attempt shell parsing in this ticket. Instead: (i) fix the `rm` pattern gap (`docs/backlog/rm-rule-pattern-single-space-gap/`) as part of the corrections, since it is a one-line regex fix to a live hole; (ii) **document truthfully** in `policies/command-policy.yml` and `docs/hook-coverage.md` that rule matching is regex over the raw command string and is therefore defeatable by quote-fragmentation (`fusebase de'pl'oy`, `npx prisma mi"grate" deploy`) and by dynamic construction; (iii) file `docs/backlog/command-gate-shell-evasion/README.md` for the real fix.

**Reasoning:** The review is right that the gate is evadable. But this property is **pre-existing** — it is inherent to regex-on-raw-command and was equally true before this ticket. Closing it properly means parsing shell (or conservatively denying dynamically-constructed commands), which is a design change with its own large blast radius and its own false-positive risk against ordinary developer usage. Shipping a half-parser under time pressure is how you get a gate that is both evadable *and* obstructive.

The K3 principle governs the interim: **a limitation that is written down is safer than one that is implied not to exist.** An operator who knows the gate is regex-based will not treat it as a sandbox. What would be unacceptable is the current state — documentation that implies completeness the implementation cannot deliver.

**Alternatives considered:**

- **Option A: implement shell-aware matching now** — rejected: unbounded scope inside a corrections round, and a wrong parser fails in both directions.
- **Option B: say nothing and file the backlog quietly** — rejected: this is precisely the `approval_authors` mistake (K3) that this ticket exists to correct.

**Lock status:** LOCKED

---

## Lock confirmation

| ID | Final option | Locked by | Date |
|---|---|---|---|
| K1..K17 | as recommended above | PO under operator's standing autonomous-run authorization | 2026-07-28 |
| K6 | **REVISED** — trim only, no interior collapse | PO, on adversarial-review evidence | 2026-07-28 |
| K18..K21 | corrections round | PO under the same authorization | 2026-07-28 |

Implementation may start: every decision is LOCKED. K3, K5, K7, K9, K11 carry **ASSUMPTION** flags — an operator reversal on any of them re-opens that decision only, not the whole set.

**Revision note (FR-18):** K13–K17 were added, and K9 replaced with the full truth table, after an adversarial review of the first draft found that the original K9 made the classifier's first run a content no-op (no base ⇒ everything preserved) and that the incident file is `changed-by-both`, not `consumer-only`. Prior state is in git history.
