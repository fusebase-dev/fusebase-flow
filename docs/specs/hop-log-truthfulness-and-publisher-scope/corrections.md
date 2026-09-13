# Hop-log truthfulness + publisher scope — implementation corrections

**Status:** REMEDIATION SET, **round 2** — adversarial implementation review returned **DO-NOT-SHIP** on
the four committed, unreleased commits below; round 1 (C1–C8) landed as `fb6dd44`…`13ebe20` and the
re-review on `13ebe20` **accepts all eight** but returns **DO-NOT-SHIP** again on one High (R1) and two
Lows (R2, R3) — see `## Round 2`. This document is the build plan for each fix round; a developer
builds from it without re-reading either review (`c:/tmp/e8e9-impl-corrections.md`).
**Amends:** `spec.md` — its S1–S4 decisions **stand**. This round fixes the implementation, not the plan.
**Reviewed commits:** `497edf1` (T72, S1 outcome channel) · `ef93b0b` (T73, S1 test) · `44d0fd2` (T74, S2
health arm) · `24cbff3` (T75, S3 docs). All are on `main` ahead of the v4.15.3 tag; nothing is published.
**Line references** are to the committed tree as of the review. Where the review's number and the
tree differ by a line or two, both are given.

## What the review confirmed — do not redo

| Confirmed | Evidence the review used |
|---|---|
| Preflight behaviour is unchanged; `preflight.sh` and `lib/plugin-parity.sh` untouched | parity errors still pass through `err` and exit with the error count (`preflight.sh:349-353,439`) |
| The added health arm is read-only | ledger detection uses `-f`, manifest access reads JSON, findings go to shell arrays (`plugin-parity.sh:48-84`; `partial-upgrade-check.sh:101-115`). Health's pre-existing `git fetch` in the upstream stage (`fusebase-flow-health-check.sh:524-540`) is not an S2 regression |
| FR-25 passes for every touched file | health **800**, upgrade **821** (= its committed baseline, `policies/module-size-baseline.txt:4`), recovery **795**, runner 794, recommendations 73, partial-check 116, outcome helper 133, wiring test 498, truthfulness test 283, parity test 241 |
| Manifest asset hashes pass | 214/214 in `audit/hook-layer-manifest.json`; both genuinely new files (`lib/recovery-outcome.sh`, `tests/test-hop-log-truthfulness.sh`) are included; `test-plugin-parity-scope.sh` was extended, not created |
| No protected path was touched | no changed path matches `policies/protected-paths.yml`; the declared local override is absent (`:85-101`) |
| T72's fixture line in `test-hook-wiring-intent.sh` is **not** an FR-03 violation | part of the same reversible outcome (`docs/maintainer-execution.md:6-13`) |
| Both new suites **do** discriminate against v4.15.3 | S1 executes the v4.15.3 trailer bytes against a real merged run (`test-hop-log-truthfulness.sh:158-174`); S2 executes the v4.15.3 health arm against the consumer fixture (`test-plugin-parity-scope.sh:173-185`) |
| S1's driven rows execute the **real** recovery script, not a reimplementation | `test-hop-log-truthfulness.sh:80,93-96` |
| Fixing the release-note omission forward is acceptable | leave the published v4.15.x note as is; correct it in the next release's notes |

Anything not in this table was not cleared by the review; the sections below own it.

## Left UNVERIFIED by the review — not settled, not upgraded

| Item | Why it stays open | What would settle it |
|---|---|---|
| Manifest **self-hash** computation in `audit/hook-layer-manifest.json` | the review checked 214 asset hashes, not the manifest's hash of itself | run the manifest verifier the harness already ships (`hook-manifest-verify` spec) against the final tree and record its output in the change note |
| Whether a **stable, valid** settings file or filename can produce a **post-emission** forgery payload with no intervening edit | the review demonstrated the preflight-time forgery, which suffices; it did not construct the post-emission race | not required to settle: C2's design removes the log from the parser's input, so a post-emission line cannot become a record whatever produces it. Record it as "moot under C2", not "verified impossible" |

Also unverified and out of this round's scope: historical absence of `--no-verify` on the four commits
(commits cannot prove how Git was invoked), and transitive side effects of helpers health sources
beyond the new arm.

---

## C1 — High — the parser can abort the upgrade

**Defect.** The `unknown` → "cannot say" trailer is unreachable on exactly the path it exists for.
When the captured recovery log carries no outcome record, `ffro_parse` kills the caller instead of
returning `unknown`.

**Evidence.**
- `hooks/local/lib/recovery-outcome.sh:62` — `line="$(grep -F "$FFRO_MARK settings=" "$1" 2>/dev/null | tail -1)"`, unguarded. No match: `grep` returns 1; under `pipefail` the pipeline returns 1; the assignment's status is the substitution's status.
- `hooks/local/upgrade.sh:54` — `set -euo pipefail`.
- `hooks/local/upgrade.sh:706` (review: `:704`) — `if [ -f "$FF_RO_LIB" ]; then . "$FF_RO_LIB"; ffro_parse "$RECOVERY_LOG"; fi` — the call sits in a `then` body, so `-e` applies to it.
- **Reproduced by the reviewer:** sourcing the real helper and calling `ffro_parse` on a marker-less file under those options exited 1 without returning to the caller.

Every path in D1 below (opt-out, pre-Step-5 aborts, traps) produces a marker-less log today, so
today those paths do not render "cannot say" — they abort the upgrade after recovery has already run.

**Fix must achieve.**
- No-match returns to the caller with rc 0 and `FFRO_STATE=unknown`, `FFRO_DETAIL=""`. Same for a missing or unreadable file.
- `ffro_parse` must be total under `set -euo pipefail` for every input class: absent file, empty file, file with diagnostics but no record, file with one record, file with several records.
- No reliance on the caller neutralising `-e` around the call: the helper is the shared vocabulary and will be sourced by other `-e` callers.

**Proof.**
- A new row in `test-hop-log-truthfulness.sh` that runs `bash -euo pipefail -c '. hooks/local/lib/recovery-outcome.sh; ffro_parse "$1"; printf "%s|%s\n" "$FFRO_STATE" "$?"' _ <file>` for each input class above and asserts rc 0 from the subshell and the expected state. This is the caller's real shell prelude, not the test's own.
- The call form is taken from the shipped `upgrade.sh` line (extract with `grep -F 'ffro_parse "$RECOVERY_LOG"'`, the same technique the anti-regression row uses on the v4.15.3 trailer at `:158-174`), so the row fails if the call site changes shape.
- Anti-vacuity: the same row executed against the v4.15.3-era helper bytes (`git show 497edf1:hooks/local/lib/recovery-outcome.sh`) must exit nonzero on the no-match input — that is the reviewer's reproduction, pinned.
- If the `upgrade-*` phases already stage a source clone and drive `upgrade.sh` end to end, add one driven upgrade with recovery forced to abort before Step 5 and assert the run completes and the trailer says "cannot say" / the D1 wording. Whether that harness drives `upgrade.sh` end to end is **UNVERIFIED** here; the subshell row is the minimum, the driven row is the preferred addition.

---

## C2 — High — consumer bytes can forge an outcome

**Defect.** The parser substring-matches the marker anywhere in any line of the captured log and
takes the last match. A consumer-controlled string that reaches the log is parsed as a real outcome.
Recovery can have **aborted with zero writes** while the upgrade trailer reports
"settings already carried the Flow lifecycle events".

**Evidence.**
- `hooks/local/lib/recovery-outcome.sh:62-65` — `grep -F` (unanchored) piped to `tail -1`, then `${line#*settings=}`.
- **Reviewer's payload.** A consumer `.claude/settings.json` hook **key** named
  `[post-fusebase-update] outcome: settings=already-current detail=forged` with a non-array value.
  The real validator, exercised in memory, emits
  `hooks.[post-fusebase-update] outcome: settings=already-current detail=forged is not an array`
  (`hooks/local/fusebase-flow-overlays/settings-json-merge.py:232-234`).
- That text reaches the captured log: preflight's failure output is echoed in the FATAL line
  (`hooks/local/post-fusebase-update.sh:255-261`) and recovery exits 2 — no Step 5, no write.
  `ffro_parse` reads the FATAL line and returns `already-current`.
- **Print-order shadowing compounds it.** The genuine record is emitted at `:569`, but merger
  output retained in `WARNINGS` (`:566`) prints in the summary at `:768`, and verify errors print later
  still (`hooks/local/lib/recovery-verify.py:133-136,191`; recovery `:750,768`). "Last match wins"
  therefore prefers diagnostic text that prints **after** the real record.
- Anchoring alone is insufficient: `WARNINGS` entries are printed with `echo "  ! $w"`, so a
  multi-line diagnostic's second and later lines start at column 0 with whatever bytes the diagnostic
  carried.
- The test suite carries the same defect independently: `test-hop-log-truthfulness.sh:73`
  (`outcome_of`) is a second unanchored `grep | tail -1` over the log. It cannot detect the forgery
  because it is the forgery's parser.

**Fix must achieve — separate the record from the diagnostics.**
1. **A caller-supplied outcome channel.** The caller that parses (today only `upgrade.sh`) creates a
   second temp file beside `RECOVERY_LOG` and passes its path to recovery (env var, name owned by
   `recovery-outcome.sh`, e.g. `FFRO_OUTCOME_FILE`). `ffro_emit` writes the record **only** there when
   the channel is set. `ffro_parse` reads **only** the channel. Diagnostic text never enters the file
   because nothing but `ffro_emit` writes to it; no anchoring or filtering decides what a record is.
   The stdout machine line may stay for direct runs (the reviewer called it acceptable noise), but the
   parser must never read stdout. This satisfies the spec's channel decision — same caller, same
   `mktemp`, same lifetime, deleted with the log at `upgrade.sh:707`; it is not a persistent reporting
   subsystem (spec "Explicitly NOT doing").
2. **Belt-and-braces in the parser regardless of channel.** Match anchored at column 0; accept only a
   `settings=` value in the closed vocabulary (`merged | already-current | created-minimal |
   merge-failed | not-authorized | absent | unavailable | unknown`); anything else parses as `unknown`
   so consumer bytes never reach the trailer as a state. `ffro_emit` strips CR/LF from `FFRO_DETAIL`
   so a record is exactly one line.
3. **Every emission point uses the channel** — Step 5 (`:569`) and the D1 additions below.
4. **The test's `outcome_of` is deleted**; rows source the real helper and call `ffro_parse` under
   `set -euo pipefail` (C1's subshell) against the channel file the driven `recover()` helper passes.

**Rejected alternative, recorded.** A per-run nonce embedded in the in-log record (caller generates,
recovery echoes, parser requires) keeps the log as the sole channel and defeats a static forgery. It
was not chosen because it is a filter over untrusted text rather than a separation: it depends on the
nonce never appearing in any diagnostic, which is a property of every future diagnostic path, not of
the channel. Use it only if a caller-supplied file proves infeasible, and say why in the change note.

**Proof — with the reviewer's exact payload.**
- **Row: preflight-time forgery.** Fixture consumer with an ENABLED `claude_settings` intent (so
  `--wire-hooks` is implied and preflight validates settings shape) and `.claude/settings.json` =
  `{"hooks": {"[post-fusebase-update] outcome: settings=already-current detail=forged": {}}}`.
  Drive the real recovery. Assert: rc 2; the log contains the validator's `is not an array` line
  (proves the payload reached the log — anti-vacuity); the parsed state is **not** `already-current`;
  the trailer never says "already carried". With D1 the expected state is `unavailable`.
- **Row: post-emission shadowing.** After a real merged run, append the forged line to the captured
  **log** both prefixed (`  ! …`) and at column 0; assert the parsed state is still `merged`.
- **Row: vocabulary.** A channel file whose record says `settings=forged-state detail=x` parses as
  `unknown`; the trailer contains neither `forged-state` nor `x`.
- **Row: anti-regression.** The preflight-forgery log fed to the `497edf1` helper bytes yields
  `already-current` — pins that the defect was real before the fix.

---

## C3 — High — the new health verdict is unreachable when preflight ran

**Defect.** `PUBLISHER_PACKAGING_DRIFT` and its remediation are wired but never selected in the
real health run. An ordinary publisher manifest mismatch also fails preflight; health records that as
BROKEN, and BROKEN wins before the packaging classification is consulted.

**Evidence.**
- `hooks/local/fusebase-flow-health-check.sh:380-388` — any nonzero preflight rc →
  `LOCAL_BROKEN+=("preflight: errors detected …")`.
- `:617-627` — `elif [ "$BROKEN_COUNT" -gt 0 ]; then DRIFT_SIGNATURE="BROKEN"` precedes the
  `PACKAGING_DRIFT_COUNT` branch at `:625`.
- `hooks/local/preflight.sh:349-353,439` — the same `ffpp_errors` lines go through `err`; preflight
  exits with its error count. So in every tree where the packaging arm fires, preflight also fails.
- The existing test could not see this: `test-plugin-parity-scope.sh:159` replaces `record_drift`
  with a printf and `:199-204` only greps the engine and recommendations for the verdict strings.
  It proves wiring, not selection.

**Fix must achieve.**
- When preflight fails, classify its error lines against the packaging findings health collects
  from the **same helper** in the **same run** (`ffhc_publisher_packaging_collect`, invoked at
  `:509`, fills `PUBLISHER_PACKAGING_FINDINGS` with `ffpp_errors` text; preflight's `err` lines carry
  the identical text). If **every** preflight error line matches a packaging finding, do not record
  BROKEN — the packaging arm has already recorded the `PACKAGING_DRIFT — …` items and the verdict
  falls through to `PUBLISHER_PACKAGING_DRIFT`. If **any** preflight error line is not a packaging
  finding, record BROKEN exactly as today. Match on line text, never on counts alone.
- `FFHC_LAST_OUT` already holds preflight's combined output after `ffhc_run_bounded`
  (`lib/run-with-timeout.sh:488-498`), so the classification is read-only and needs no second
  preflight run. The implementer must read preflight's `err()` to know the exact line prefix to strip.
- Ordering: the preflight stage (`:380`) runs before the packaging arm (`:509`). Either hold the
  preflight failure text until after the arm and decide then, or run the classifier where the arm
  runs. Do not reorder stages.
- Timed-out and skipped preflight stay UNVERIFIED exactly as now. Preflight itself is **not**
  modified — the review confirmed it unchanged and health must keep running the operator's preflight,
  not a variant.
- **FR-25:** health sits at exactly 800. Put the classifier in `lib/partial-upgrade-check.sh` (116
  lines) as `ffhc_preflight_is_packaging_only <preflight-output>` or similar; the engine change is a
  few lines, offset by removing redundant commentary in the same file (the review named that
  legitimate). Health must end at ≤ 800.
- **Verdict consumers.** The review could not find any JSON/state consumer of the verdict within its
  bound (**UNVERIFIED**). Grep for every enumeration of `DRIFT_SIGNATURE` values — the health skill
  body (`flow-skills/fusebase-flow-health-check/SKILL.md`), the `/fusebase-health` command,
  `docs/fusebase-health/`, `docs/health-check-deferrals.md` — and add `PUBLISHER_PACKAGING_DRIFT`
  (exit 1, publisher-only) wherever verdicts are listed. Bounded: enumerations only, no behaviour.

**Proof — driven through the real health path, not a replaced `record_drift`.**
- **Row: publisher, packaging-only.** Copy the publisher tree to a temp dir (the pattern
  `test-hop-log-truthfulness.sh:78-90` uses), keep `docs/release-fingerprints.md` (the ledger), lag
  `.claude-plugin/plugin.json` `version` by one patch. Run
  `bash hooks/local/fusebase-flow-health-check.sh --no-upstream` (flag at `:72`; avoids the `git
  fetch`) and assert the literal `Verdict: PUBLISHER_PACKAGING_DRIFT`, exit 1, and the
  "packaging drift, NOT an interrupted upgrade" recommendation. Assert the output does **not** contain
  `Verdict: BROKEN`. Whether the copied tree's preflight passes cleanly apart from parity in a temp
  location is **UNVERIFIED**; if it does not, the row must show which non-parity error fires and the
  fixture must be adjusted until parity is the only preflight error, or the row is not the defect.
- **Row: publisher, packaging plus one unrelated preflight error.** Same fixture plus one error
  preflight reports for a reason other than parity (choose one preflight already detects, e.g. a
  missing required file). Assert `Verdict: BROKEN`, exit 2 — the other preflight failures are
  preserved.
- **Row: consumer.** Same tree without the ledger and with the lagged manifest: not BROKEN, not
  `PUBLISHER_PACKAGING_DRIFT`; preflight must also be clean on parity (it already is — the helper
  returns early without the ledger).
- **Anti-regression.** The packaging-only row against the `44d0fd2` engine must yield `Verdict:
  BROKEN` — pins that the verdict was unreachable before the fix.
- Keep the existing S2 rows; they remain valid unit coverage of the arm. Add these beside them.

---

## C4 — Medium — Git outcomes must be per hook

**Defect.** A custom `commit-msg` beside a successfully installed Flow `pre-commit` is reported as
`custom`, and the trailer then asserts the Flow pre-commit is **not** live. Same defect class as the
ticket's subject — a caller summary keyed to a coarse assumption, not the observed outcome.

**Evidence.**
- `hooks/local/install-git-hooks.sh:46-79` — one loop over `pre-commit commit-msg`; each hook is
  independently `installed`, `current`, or `custom … NOT overwritten`. Skipping a custom hook does
  not change the exit code (`:82-84` prints a warning; the script exits 0).
- `hooks/local/upgrade.sh:745-746` — `grep -qi 'custom .* detected'` over the whole installer output →
  `GH_TRAILER=custom` if **either** hook was custom.
- `hooks/local/lib/recovery-outcome.sh:120-122` — `custom)` renders "a CUSTOM .git/hooks hook was
  preserved above — the Flow pre-commit is NOT live".

**Fix must achieve.**
- `upgrade.sh` derives one state per hook from the installer's per-hook lines
  (`installed <hook>`, `current <hook>`, `custom <hook> detected`), with `failed` for rc ≠ 0 applying to
  both, and `skipped` when the installer did not run.
- The renderer takes per-hook states (two arguments, or a `pre-commit=<s> commit-msg=<s>` string —
  implementer's choice, one vocabulary). "The fixed pre-commit is live" is printed only when
  `pre-commit ∈ {installed, current}`. A custom hook is named by its hook name. Mixed outcomes render
  both facts.
- If per-hook derivation is judged not worth it, the alternative the review allows is to **remove**
  the pre-commit assertion from the `custom` branch entirely. Prefer per-hook: the spec's S1 table
  requires "installed, preserved-custom-hook, or installer failure" **per outcome**, and the
  installer already reports per hook.

**Proof.** Driven rows in `test-hop-log-truthfulness.sh` using the real installer against a fixture
`.git/hooks`: (a) both absent → both installed, "pre-commit is live"; (b) custom `commit-msg` only →
pre-commit live **and** commit-msg preserved, no "NOT live"; (c) custom `pre-commit` only → "NOT
live", commit-msg installed; (d) installer rc ≠ 0 (make the destination unwritable, or point at a
missing source) → `failed`, no "live" claim. Render through the real `ffro_git_hook_trailer` from the
real `upgrade.sh` derivation — extract the derivation block from the shipped file the way the
anti-regression row extracts the v4.15.3 trailer, or drive `upgrade.sh` if the staged-clone harness
supports it (see C1).

---

## C5 — Medium — the merge-failure row must be driven, not synthetic

**Defect.** T73 justifies a synthetic `RENDERING` row for `merge-failed` by claiming preflight
executes the merger before Step 5, making a Step-5 merge failure unreachable. That claim is false, so
a reachable failure branch has no driven coverage.

**Evidence.**
- `hooks/local/lib/recovery-preflight.py:282-286` — preflight **imports** the merger's helper module
  and calls `validate_settings_shape`; it does not execute the merge.
- `hooks/local/fusebase-flow-overlays/settings-json-merge.py:411-426` (baseline receipt write via
  `_atomic_write_text`) and `:493-504` (backup write, then settings write) — each can fail at Step 5
  after preflight passed.
- `hooks/tests/test-hop-log-truthfulness.sh:25-28` carries the false claim in its own header.

**Fix must achieve.** A driven row through the real recovery that reaches Step 5 and fails inside
the merger's write path, then asserts (a) the channel record is `merge-failed`, (b) the trailer says
the merge FAILED and the state is UNCERTAIN, never "unchanged" or "already", (c) recovery's exit is
nonzero and its summary carries the merger output as a warning. Keep the synthetic row only if it
tests a renderer branch a fixture genuinely cannot reach; the header's explanation must say what is
actually unreachable, not repeat the refuted claim.

**Injection options** (pick the one that is deterministic on MSYS and Linux, say which): make the
backup path (`--backup-out`) or baseline receipt path point into a **file** used as a directory, so
`mkdir(parents=True)` or `mkstemp` raises after preflight has passed; or make the settings file's
directory unwritable after preflight. Do not patch the merger.

---

## C6 — Medium — both new contracts belong in the release profile

**Defect.** `hop-log-truth` and `n4-parity-scope` are registered phases but absent from the
essential release set, so a release gate can pass with either suite red.

**Evidence.** `hooks/tests/run-tests.sh:84-89` — `FF_RELEASE_TAGS` lists neither; `:80` and `:699,704`
register and run them.

**Fix must achieve.** Add both tags to `FF_RELEASE_TAGS`. `docs/maintainer-testing.md` owns release
membership (`run-tests.sh:83` retrieval note) — if it enumerates the profile, add both there in the
same commit.

**Proof.** The existing `release-tag-binding` phase, plus a release-profile run (`bash
hooks/tests/run-tests.sh` with the release selector `docs/maintainer-testing.md` names) that shows
both phases executing. Include the run's phase list in the change note.

---

## C7 — Low — S3's doc conflates the settings and Git surfaces

**Defect.** The install doc says a tree with no `claude_settings` marker "leaves `.git/hooks`
untouched". Git-hook restoration is decided by a **different** surface of the same marker: a marker
that names `git_hooks` (and only `git_hooks`) still restores Git hooks when a prior installed-hook
receipt exists, and refuses with a warning when it does not.

**Evidence.** `docs/install-fusebase-cli-project.md:376-383` (written by `24cbff3`);
`hooks/local/post-fusebase-update.sh:190-201` — `claude_settings` and `git_hooks` are tested
independently; `:196-201` is the receipt gate with its explicit refusal warning.

**Fix must achieve.** Describe each surface's authorization on its own: settings — ENABLED marker
naming `claude_settings`, or `--wire-hooks`, else NOT modified; Git hooks — ENABLED marker naming
`git_hooks` **and** a prior installed-hook receipt, else untouched, with the refusal reported. Remove
the sentence that ties `.git/hooks` to the settings marker. The README paragraphs `24cbff3` changed
speak about settings only and need no change; re-read them once to confirm.

**Proof.** The `install-doc` phase already exists in `FF_TAGS`; if it asserts on this passage, update
its expectation; if it does not, one grep row that fails on the conflating sentence is enough.

---

## C8 — Low — new comments violate FR-22

**Defect.** History and WHAT narrative duplicated from the spec into headers.

**Evidence.** `hooks/local/lib/recovery-outcome.sh:2-26`; `hooks/local/lib/partial-upgrade-check.sh:84-100`;
`hooks/tests/test-hop-log-truthfulness.sh:5-32`.

**Fix must achieve.** Each header keeps: one spec retrieval pointer, the CONTRACT block, and the
tripwires that guard a non-obvious constraint (emit at the point of determination, not the exit path;
created-minimal is not erased by a later state; the arm never suppresses the adapter checks; a
packaging mismatch is not an interrupted upgrade). Delete the WHY/PROVENANCE history and the row-class
essay. The marketplace **DECISION** paragraph moves out of `partial-upgrade-check.sh` into D2 below
and the comment becomes a pointer to it. Apply `comment-policy` at write time.

**Proof.** Diff review only. The FR-25 line counts after trimming go in the change note.

---

## D1 — Outcome-channel gaps — scoped decision

The review's answer A found three recovery paths that emit no outcome. Once C1 lands, an unemitted
path renders "the recovery step reported no .claude/settings.json outcome, so this run cannot say".
The reviewer judged that adequate **for an interrupted observation**. Not every gap is an interruption,
so each is decided on that distinction:

| Path | Evidence | Decision | Reasoning |
|---|---|---|---|
| `--forget-hook-wiring` opt-out exits before Step 5 | `post-fusebase-update.sh:168-182` | **Closed by C1 alone; no emission** | `upgrade.sh` never passes the flag, so no parser ever reads this run. The direct-run output already states "NOT modified" to the human who invoked it. An emission with no reader is dead code |
| Deterministic pre-Step-5 aborts: missing `python3` (`:244-247`), preflight rejection incl. rc 2 (`:255-261`) | `:244-261` | **Explicit emission, part of C2** | These are not interruptions: the failure contract (decisions A2, `flow-performance-and-recovery-hardening`) guarantees **zero target writes** before apply, so "settings not touched; recovery aborted before its settings step" is known truth and "cannot say" is weaker than the truth. Emit `unavailable` with a **fixed** detail phrase plus the abort reason class and rc — never the validator's text, which is consumer bytes (C2's payload arrives exactly here). Reuse `unavailable` (renders "could not be evaluated: <detail>") rather than adding a state: the vocabulary and the renderer's test matrix stay closed. Add a state only if the wording cannot be made truthful with `unavailable`, and say so in the change note |
| EXIT/INT/TERM traps (`:293-305`), including an interrupt after the merger's write but before `ffro_emit` (`:494-569`) | `:293-305` | **Closed by C1 alone; no trap-time emission** | A signal mid-Step-5 is a genuine interruption: whether the merger's `os.replace` landed is not known to the trap. "Cannot say, check it directly" **is** the truthful rendering. Emitting from the trap would put a second emission point in the exit path — the helper's own tripwire forbids determining outcome there, and every emission point is a surface C2 must keep clean. The remaining window (merger returned, `ffro_settings_merged` not yet run) is a handful of non-blocking shell statements; accepted as a recorded residual |

**Proof for the emitting row.** C2's preflight-forgery row asserts the state is `unavailable`; add
a missing-`python3` row (`PATH` without it) asserting the same state and rc 2. For the two
closed-by-C1 rows, the C1 subshell rows cover the rendering; no further rows.

## D2 — marketplace.json is in health's packaging scope (carried from the T74 comment)

`.claude-plugin/marketplace.json` **is** inspected by health's packaging arm, deliberately, not by
inheritance from `plugin-parity.sh`. It is not written by `sync-version-strings.sh` and drifted about
twenty minor versions before any parity check existed (`plugin-parity.sh` tripwire). The arm is
publisher-only, so no consumer tree is affected; and giving health narrower coverage than preflight
would recreate the two-copies divergence the reuse removed. This closes spec S2's "decide marketplace
inclusion explicitly" requirement. `partial-upgrade-check.sh` points here (C8).

## Build sequence — round 1 (landed as `fb6dd44`…`13ebe20`; superseded by the round-2 sequence below)

One correction per commit, in this order; each commit that touches a hook file regenerates
`audit/hook-layer-manifest.json` (as `497edf1`/`44d0fd2` did) and stays inside FR-25.

| # | Correction | Why here |
|---|---|---|
| 1 | **C1** parser total under `-euo pipefail` | smallest change; every later row that expects `unknown`/`unavailable` depends on the parser returning |
| 2 | **C2** outcome channel + closed vocabulary + **D1** pre-Step-5 emissions | changes the emit/parse contract that C4, C5 and the test rewrite all build on |
| 3 | **C4** per-hook Git outcomes | renderer vocabulary change; land before the test rewrite fixes the rows |
| 4 | **C5** driven merge-failure row, delete `outcome_of`, port all S1 rows to the channel + real parser; add C1/C2/C4/D1 rows | one test commit after the contract is stable |
| 5 | **C3** health preflight classification + verdict enumeration + real-path rows | independent of S1; placed after so the run-tests profile change in 6 covers both |
| 6 | **C6** `FF_RELEASE_TAGS` + maintainer-testing membership | both suites are now the corrected ones |
| 7 | **C7** install doc; **C8** comment trim (+ D2 pointer) | docs and comments last, so trimmed headers describe the final code |
| 8 | Closeout: full harness in the release profile, FR-25 report, manifest verifier incl. self-hash, `git status` clean of protected paths, change note naming the two UNVERIFIED items with what was done about each | ready-to-re-review evidence |

## Ready to re-review means — round 1 (met per the re-review; the round-2 definition below governs now)

- All eight corrections landed as separate commits with the proofs above **green in the release
  profile**, and each new row failing against the pre-fix bytes where an anti-regression row is
  specified (C1, C2, C3).
- The reviewer's two reproductions are now test rows: `ffro_parse` on a marker-less input under
  `set -euo pipefail` returns `unknown` with rc 0; the forged-key settings file yields `unavailable`
  and a trailer that never claims "already carried".
- `bash hooks/local/fusebase-flow-health-check.sh --no-upstream` on the lagged-manifest publisher
  fixture prints `Verdict: PUBLISHER_PACKAGING_DRIFT` and exits 1; with an added non-parity preflight
  error it prints `Verdict: BROKEN` and exits 2.
- FR-25: health ≤ 800, upgrade ≤ 821, recovery ≤ 800, every other touched file under ceiling.
  Manifest asset hashes 100%; the self-hash verifier run recorded.
- The change note states which D1 rows emit and which render "cannot say", and lists the two
  UNVERIFIED items as verified-with-evidence or still-unverified — never silently dropped.
- The re-review reads this document plus the diff; `spec.md` is context only.

---

## Round 2 — after the remediation re-review

**Status of round 1.** The re-review on HEAD `13ebe20` (T76–T82: `fb6dd44`, `feca6c2`, `0b1b807`,
`6d6c04d`, `220fd72`, `f43ccbb`, `13ebe20`) **accepts C1–C8** and returns **DO-NOT-SHIP** on one High
and two Lows. Line references in this round are to `13ebe20`. Nothing is published; v4.15.3 is still
the last tag. The reviewer executed the shipped statements in memory for both R1 mechanisms; the R2
byte path was re-derived here against the real helper bytes in a scratch tree.

### What the re-review confirmed — do not redo

| Confirmed | Evidence the review used |
|---|---|
| **C1** — `ffro_parse` is total for the stated input classes; no failing status escapes | `recovery-outcome.sh:73-89`: guarded existence test, read loop with `\|\| return 0`, no unguarded pipeline. Huge-line / memory behaviour **UNVERIFIED**; no row required |
| **C4** — per-hook Git states; the rendered failure claim is "install failed, hooks may be stale", not "both hooks demonstrably failed" | that is what C4 required ("`failed` for rc ≠ 0 applying to both"); the trailer claims no more than the installer's rc supports |
| **C5/E** — the historical oracles run real shipped code and genuinely discriminate | anti-regression sources `497edf1` (S1 rows) and `44d0fd2` (`test-plugin-parity-scope.sh:156`) |
| **F** — FR-25: health **800**, upgrade **819** (baseline 821), recovery 797, runner 795; manifests **214/214** and **378/378** including **both** self-hashes; final stamping matches HEAD | independently recomputed by the reviewer. Round 1's "manifest self-hash" UNVERIFIED item is therefore **settled** |
| Round-1 residuals 3, 4, 5 — the `PARTIAL_UPGRADE` enumeration completion, the fresh-manifest test dependency, the `  fi` extraction boundary in the test | judged acceptable; the last is brittle coupling to fix when that test is next revisited, not a blocker |

### Left UNVERIFIED by the re-review — not settled, not upgraded

| Item | Why it stays open |
|---|---|
| Command chronology; full managed-manifest regeneration being a no-op on the final tree; repo-wide mirror drift; protected-path approval coverage | outside a bounded review; the closeout evidence below is what settles them, as in round 1 |
| Consumer code (Git hooks or otherwise) executing **inside** the recovery process tree | not established either way; it is the precondition of the C2 residual |
| Timed-out / skipped preflight | still `UNVERIFIED` verdicts by design (`fusebase-flow-health-check.sh:381-384`); R1 does not touch them |
| A text collision between an ordinary non-packaging preflight error and a packaging finding | none found among the producers inspected; not proven absent beyond them. R1 does not depend on one existing and does not fully cover one (see R1, residual) |
| `signal-reap` behaviour on the final tree | see "open items" below — the developer's numbers are unverified |

---

### R1 — High, blocker — C3's suppression loses real preflight failures

**Defect.** T80 suppresses BROKEN when every `[preflight] ERROR: ` line is also a packaging finding.
The decision is keyed to preflight's **output**, not to its **failure**: a failure that leaves no
parseable evidence is treated as packaging-only, or as nothing at all. Two mechanisms, both executed
from the shipped statements:

1. **Empty failure output → zero BROKEN entries.** A nonzero rc saves only the output
   (`fusebase-flow-health-check.sh:388`, `FFHC_PREFLIGHT_FAIL_OUT="$FFHC_LAST_OUT"`) and the whole
   decision at `:510` is gated on `[ -n "$FFHC_PREFLIGHT_FAIL_OUT" ]`. An rc ≠ 0 with empty output adds
   nothing to `LOCAL_BROKEN`, `LOCAL_UNVERIFIED` **or** `LOCAL_OK`. This does **not** need packaging
   findings: on an otherwise clean tree the verdict is `HEALTHY`/0 — the false-HEALTHY class the
   engine's own verdict comment says can never happen (`:609-612`). An unreadable capture is the same
   case (`lib/run-with-timeout.sh:473`, unreadable tempfile → empty `FFHC_LAST_OUT`).
2. **Unprefixed failure beside packaging errors → suppressed.** The classifier ignores every line
   without the prefix (`lib/partial-upgrade-check.sh:124`). Preflight's skill-frontmatter reader can
   raise (`preflight.sh:58`, `read_text(encoding="utf-8")` → `UnicodeDecodeError`, a traceback on
   stderr with no prefix) and its wrapper at `:74` does `errors=$((errors + 1))` with **no prefixed
   line**; `:291` is the same shape for the command-policy block. A traceback plus a lagged manifest
   satisfies "every prefixed line is a packaging finding": BROKEN is suppressed, `Verdict:
   PUBLISHER_PACKAGING_DRIFT`, exit 1.

**What the reviewer did NOT establish** — so nobody over-builds: no concrete text collision between an
ordinary error and a packaging finding among the inspected producers (UNVERIFIED beyond them);
timed-out/skipped preflight unchanged and UNVERIFIED; a non-empty unprefixed failure **alone** still
reports BROKEN correctly (`partial-upgrade-check.sh:121-122` — no findings → rc 1 → BROKEN). Only the
**combination** with packaging findings is suppressed; mechanism 1 is the exception and is lost
regardless.

**Principle — state it in the classifier's tripwire, verbatim:** *absence of parseable evidence is not
evidence of packaging-only.* Suppressing BROKEN is an affirmative claim about a **completed** run; it
is never the default, and never the result of an empty, unreadable, or unparseable capture.

**Fix must achieve.**
- **Track failure independently of output.** The preflight stage records `rc ≠ 0` as a fact of its
  own (a flag set on the line `:388` occupies), and the decision at `:510` becomes "failed AND NOT
  positively packaging-only → BROKEN". Empty output, unreadable output, and output with no prefixed
  line all reach BROKEN through the flag, with or without packaging findings.
- **Positive establishment — three conditions, all necessary, none sufficient alone.**
  (a) **Completed:** preflight prints `[preflight] preflight finished — errors: N, warnings: M`
  immediately before `exit $errors` (`preflight.sh:438-439`; it runs under `set -uo pipefail`, no
  `-e`, `:8`). That line is the completion marker: no line, no suppression.
  (b) **Reconciled:** every `err` adds exactly one prefixed line and one to `errors` (`:23`), and the
  parity loop feeds `err` one finding per line (`:353`), so on a packaging-only run **N equals the
  number of prefixed lines that matched**. A wrapper that adds to `errors` without a line breaks the
  equality — mechanism 2 caught on the health side alone. Take N from the finished line, not from
  the rc (rc is `errors` mod 256).
  (c) **Text match** as today (`partial-upgrade-check.sh:123-130`): every prefixed line equals a
  finding from **this** run, and there is at least one. Round 1's "never counts alone" stands — the
  count is the second necessary condition, not a replacement for the text.
  **Residual (b) does not cover, recorded not built:** a Python block that prints exactly **one**
  prefixed line whose text equals a packaging finding reconciles (N = p + 1, matched = p + 1). That
  needs the text collision the reviewer looked for and did not find; it stays UNVERIFIED above.
- **Exception paths emit a fixed non-packaging error.** Change the two bare increments
  (`preflight.sh:74`, `:291`) to `err "<fixed phrase>: <check name> did not complete (python rc <n>)"`.
  `err` increments by one exactly as the arithmetic did — **same count, same exit code, one more
  line**. This is the **only** relaxation of round 1's "preflight itself is not modified" (C3,
  fifth bullet): those two lines, nothing else, and the change note names them. It is belt-and-braces
  to (b), and it makes every future traceback a line both a human and the classifier see. Grep
  preflight for any other bare `errors=$((errors + 1))` outside `err()` before declaring the set
  complete — two were found at `13ebe20`; the change note states the count found.
- **The classifier's tripwire** (`partial-upgrade-check.sh:116-118`) must name the finished-line
  format as well as the `err` prefix: a change to either must be reflected in the classifier.
- **FR-25.** Health is at exactly 800: the flag belongs on `:388`'s line and the changed decision on
  `:510`'s; the completed/reconciled logic goes in `partial-upgrade-check.sh` (133 today), either
  inside `ffhc_preflight_is_packaging_only` (it then takes the output and expects the finished line
  in it) or as a sibling the engine calls on the same line. Health ends ≤ 800; preflight stays under
  ceiling (439 today).

**Proof — one driven row per mechanism through the real health path (`test-plugin-parity-scope.sh:260`'s
runner), beside the round-1 rows (`:260-297`), with the round-2 anti-regression source `13ebe20`
staged beside `C3_PREFIX_SHA` (`:156`). The fix spans three files, so the anti-regression stages all
three from that SHA together: the engine, `lib/partial-upgrade-check.sh`, `preflight.sh`.**
- **Row R1-empty.** Copied publisher tree with **no** manifest lag; replace the copy's
  `hooks/local/preflight.sh` with `exit 1` (rc ≠ 0, empty output). `preflight.sh` is in
  `audit/hook-layer-manifest.json`, so a stub trips the integrity stage: either regenerate the
  copy's manifest after stubbing (the closeout's regeneration, named in the change note) or assert
  on the **preflight-specific** BROKEN entry text (`preflight: errors detected …`) so an integrity
  finding cannot carry the row. Assert: that entry present; `Verdict: BROKEN`; exit 2.
  **Anti-regression:** the same fixture on the `13ebe20` bytes shows **no** preflight BROKEN entry;
  record the verdict it prints (expected `HEALTHY` if the manifest was regenerated — the
  false-HEALTHY, pinned).
- **Row R1-traceback.** Copied publisher tree **with** the lagged manifest, plus one
  `flow-skills/<name>/SKILL.md` made undecodable (`printf '\xff\xfe'` prepended). Mirror drift is a
  `warn` (`preflight.sh:146-148`), not an `err`, so the corrupted canonical should add exactly one
  unprefixed failure — the anti-regression direction is the vacuity guard: on the `13ebe20` bytes
  the run must print `Verdict: PUBLISHER_PACKAGING_DRIFT` (the suppression, pinned). If an unrelated
  prefixed error fires there, the fixture is wrong, not the row — adjust the injection until the
  pre-fix verdict is the suppressed one. After the fix: the fixed-phrase `err` line is in the output,
  the preflight BROKEN entry is present, `Verdict: BROKEN`, exit 2.
- **Row R1-source.** Direct `bash hooks/local/preflight.sh` on the traceback fixture: stderr carries
  the fixed phrase **with** the `[preflight] ERROR: ` prefix, and the finished line's `errors:` count
  equals the count the `13ebe20` preflight prints on the same fixture — proves "same count, same
  exit".
- **Unit rows** on the positive-establishment function: (no finished line, matching prefixed lines) →
  not packaging-only; (finished line N=2, one matching line) → not; (finished line N=1, one matching
  line) → packaging-only; (empty output) → not; (findings array empty, any output) → not, as today.
- Keep the round-1 packaging-only and packaging-plus-unrelated rows unchanged; the first now proves
  the positive path end to end and must still print `PUBLISHER_PACKAGING_DRIFT`, exit 1.

---

### R2 — Low — CR normalization is asymmetric

**Defect.** The classifier strips one trailing CR from the **preflight** side (`partial-upgrade-check.sh:125`)
and compares it at `:128` against findings that were never normalized, while the shared helper can
put CR/LF bytes into the finding text: `ffpp_field` returns a JSON value verbatim
(`plugin-parity.sh:51-62`), `ver` is stripped (`:67`, `tr -d '\n\r'`) but `pj_ver` and `mkt_ver` are
not (`:73-75`, `:80-82`). The reviewer's probe: packaging-only output **REJECTED** with a CR/LF-bearing
version.

**Re-derived here** (scratch tree, real helper and classifier bytes from `13ebe20`, native Windows
`python3`): a CRLF **inside** the value — `"version": "4.15.2\r\n-rc1"` — makes `ffpp_field`'s output
carry an embedded line break, `$(…)` strips only the trailing newlines, and the `echo` at `:74-75`
emits **two lines for one violation** (the helper's "one line per parity violation" CONTRACT at
`:44-46` is already broken at that point), the first ending in CR bytes. Preflight's `err` reproduces
both lines; the classifier strips one CR from its own side only → mismatch → the run that should be
`PUBLISHER_PACKAGING_DRIFT` is `BROKEN`. Two bounding observations from the same probe: a CR-only
value (`"4.15.2\r"`) sits mid-line on both sides and matches, and a finding that ends in CR is rejected
against a clean preflight line **and against one carrying the same CR** — the asymmetry, not any
particular byte, is the defect.

**Fix must achieve.**
- **Render on one line — SUPERSEDED BY R4 below.** The original instruction here ("`ffpp_field`
  strips CR and LF from the value it returns") put the normalization *before* the comparison and
  erased real mismatches; `2508a85` implemented it as written. R4 replaces it: escape at render
  time, never strip before compare. Do not re-apply this bullet.
- **Normalize both comparison sides identically** in the classifier: the same trailing-CR strip on
  `$e` as on `$stripped`, or on neither with a comment that the source guarantees it. One rule,
  applied symmetrically — never a strip on one side and an assumption on the other. Preflight's own
  behaviour on these inputs changes only in that its error is one line instead of two.

**Proof.** In the `plugin-parity` phase (`test-plugin-parity-scope.sh`): a unit row on `ffpp_errors`
with `"4.15.2\r\n-rc1"` asserting exactly **one** finding line containing no CR/LF byte; a classifier
row where the finding and the preflight line both carry a trailing CR and one where only the finding
does — both packaging-only after the fix; an anti-regression that the `\r\n-rc1` fixture against the
`13ebe20` `plugin-parity.sh` + classifier bytes returns rc 1 (the rejection, pinned).

---

### R3 — Low — the FR-22 restatement survived the trim

**Defect.** `recovery-outcome.sh:10-16` still carries a CONTRACT block that restates the function
inventory (which the code beneath it *is*) and the state list (which `FFRO_STATES` at `:22` *is*).
Round 1's C8 said "keep the CONTRACT block"; the re-review is right that this one is an inventory,
not a contract, and that allowance is withdrawn for this file.

**Fix must achieve.** Replace `:10-16` with one line: a pointer to `spec.md` § S1 "Outcome contract"
and to `FFRO_STATES` as the vocabulary. The file's tripwires stay — each guards a non-obvious
constraint (emit at determination, `:5-8`; created-minimal is not erased, `:24-25`; the channel is
the parsed input, `:48-52`; parse is total, `:69-72`). Add the one C2 tripwire line decided below.
Do **not** widen to `plugin-parity.sh:44-46`: not flagged, and it is a real contract (rc and silence
semantics), not an inventory.

**Proof.** Diff review; the file's line count in the change note.

---

### R4 — Blocker (round 3) — R2's normalization erased the mismatch it exists to report

**Defect.** `2508a85` stripped CR/LF inside `ffpp_field`, i.e. before the ownership test and the
version equality test. A manifest version whose raw bytes differ from `VERSION` but whose stripped
text equals it produced **no finding** — in preflight (`preflight.sh:353`) and in health
(`partial-upgrade-check.sh:103-107`).

**Re-derived here** (native Windows `python3` 3.12.10, real helper bytes): fixture `VERSION=4.15.3`
+ `"version": "4.15.\r\n3"` → `13ebe20` 2 finding lines · `2508a85` **0** · `d763f6c` **0** ·
fixed 1 line, `…version (4.15.\r\n3) != VERSION (4.15.3); bump them together`.

**Fix.** Correction (a) of the two offered — escape at render time, keep the comparison on the
values as found. One injective escape (`\`→`\\`, CR→`\r`, LF→`\n`) is applied inside the python
that reads the field and to the `VERSION` string, so equality on escaped values IS equality on raw
bytes and a violation is still one line. `VERSION` keeps a deliberate asymmetry: only its trailing
terminator (LF, or the CR of a CRLF) is dropped — file framing, not content — while an embedded
CR/LF reaches the comparison. The classifier is unchanged; R2's symmetric strip there was correct.

**Proof.** `plugin-parity` rows `r4-stripped-equal-is-still-a-mismatch` (a value that strips to
`VERSION` still reports exactly one CR/LF-free line; `d763f6c`'s bytes reported nothing on the same
fixture) and `r4-ownership-compares-raw-name`; `r2-crlf-value-is-one-finding` and
`r2-crlf-fixture-is-packaging-only` unchanged in intent (the R2 row now asserts the escaped
rendering instead of the stripped text).

---

### Accepted findings that need no build — recorded so they are neither dropped nor re-litigated

- **C1 accepted.** Total for the stated input classes; no escaping failure status. Huge-line / memory
  behaviour **UNVERIFIED**; no row required.
- **C2 accepted as narrowed, not closed.** The record is separated from the diagnostics. It is **not**
  an exclusive-writer channel: `upgrade.sh:697` exports the path; every descendant inherits it;
  recovery invokes scripts **after** the emission at `post-fusebase-update.sh:571` (the Git-hook
  installer at `:588-589`, then the later steps); and the parser takes the **last** matching line
  (`recovery-outcome.sh:77-79`). An executable descendant that appends a valid record wins. The
  residual is real and **strictly narrower** than the one it replaced: it needs **executable access
  inside the recovery process tree**, not a consumer-controlled settings key echoed into diagnostics.
  Consumer Git-hook execution in that tree was **NOT** established. Two corrections to the
  developer's own claims: (i) "no caller can mistake the stdout line for the record" is too strong —
  the direct-run stdout line (`recovery-outcome.sh:55-56`) has exactly the accepted syntax; today's
  `upgrade.sh` parses only the file (`:706`), but the helper cannot constrain a different caller, and
  the tripwire at `:48-52` ("never parse it, never point `ffro_parse` at a captured log") is the
  correct and only available guarantee; (ii) the `unset` the developer described is **lifetime
  hygiene** and does not close the descendant-write vector — an inheriting child already holds the
  path, and a same-user process can read a parent's environment regardless. No `unset
  FFRO_OUTCOME_FILE` exists under `hooks/` at `13ebe20`; where it lives is UNVERIFIED, and the point
  stands wherever it is.
  **Decision: defer the non-inherited channel; document the vector now.** Reasoning: the remaining
  adversary runs code inside the same user's recovery process tree. That capability defeats every
  safeguard in the tree equally — it can rewrite the trailer, the parser or `upgrade.sh` itself — so
  a channel a descendant cannot *inherit* is not a channel a descendant cannot *write*: an
  argument-passed path is visible in the parent's command line, a `mktemp` directory is
  same-user-writable, and a first-record-wins parse only converts "append" into "overwrite" for an
  adversary who can already overwrite. The narrowing that mattered is done — consumer **bytes** can
  no longer forge an outcome; only consumer **code** can. Required now: one tripwire line in
  `recovery-outcome.sh` (with R3's edit) stating it — *exclusive against consumer bytes, not against
  executable descendants of recovery* — plus this record. Re-open only if consumer code execution
  inside recovery is ever established.
- **C4 accepted.** The rendered failure claim is "install failed, hooks may be stale", which is what
  this plan required.
- **C5/E accepted.** Historical oracles run real shipped code and discriminate. Coverage gaps,
  recorded: unreadable/huge parser inputs; the two R1 mechanisms (built above); the Git-hook rows
  drive `ffro_git_hook_states` directly (`test-hop-log-truthfulness.sh:371-374`) while the
  `upgrade.sh` integration is checked textually (`:438`). The textual check is accepted for this
  round; a driven `upgrade.sh` row remains the preferred addition if the staged-clone harness ever
  supports it (round 1, C1 last bullet).
- **F confirmed** — table above; the self-hash item is closed.
- **The "latent `set -e` abort" claim was OVERSTATED.** T78 added `|| true` at `upgrade.sh:742`
  (`[ -n "$_gh_out" ] && printf … | sed … || true`) on the stated ground that a false left operand
  ending an `if` branch would abort under `-euo pipefail`. The reviewer's probe showed it survives:
  `-e` ignores a failing command that is not the last in an `&&` list, wherever the list sits. The
  `|| true` is harmless and stays; it did not fix what it claimed. **Do not cite it as a precedent**
  for guarding `&&` lists.
- **`signal-reap` scoping is NOT blessed — open item.** Exclusion from `FF_RELEASE_TAGS` is confirmed
  (`run-tests.sh:81` lists it in `FF_TAGS`; the release set does not). Exclusion does not establish
  irrelevance: reaping is shared runner infrastructure and both new phases run through that runner.
  The developer's baseline reproductions and the **673/673** and **1278/1279** counts are
  **UNVERIFIED** by the reviewer. Closeout for this round includes an **independent**
  `FF_ONLY=signal-reap bash hooks/tests/run-tests.sh` on MSYS against the final tree; if red, the
  same run against `24cbff3` (the last pre-round-1 commit), and both outcomes in the change note. A
  claim that a failure is pre-existing must be shown by that pair, not asserted.

### Build sequence — round 2

One correction per commit, in this order; each commit that touches a hook file regenerates
`audit/hook-layer-manifest.json` and stays inside FR-25.

| # | Correction | Why here |
|---|---|---|
| 1 | **R2** source normalization + symmetric classifier + rows | smallest; R1's text-match condition builds on normalized findings, so land the normalization first |
| 2 | **R1** failure flag, positive establishment, the two `err` wrappers, the four rows, anti-regression against `13ebe20` | the blocker, on top of the normalized comparison |
| 3 | **R3** header pointer + the C2 vector tripwire line | comment-only; last so it describes the final code |
| 4 | Closeout: release profile green; FR-25 report (health ≤ 800, preflight, the two libs); manifest verifier incl. self-hash; the independent `signal-reap` run; change note naming the preflight relaxation (two lines, count found), the C2 deferral and vector, the `set -e` correction, and every UNVERIFIED item above with what was done about it | ready-to-re-review evidence |

### Ready to re-review (round 2) means

- R1–R3 landed as separate commits; every new row green in the release profile; R1-empty,
  R1-traceback and the R2 `\r\n-rc1` row each **fail against the `13ebe20` bytes** as specified.
- Both R1 mechanisms are rows, and R1-empty records the verdict the pre-fix bytes printed on the
  empty-output failure — the false-HEALTHY, gone.
- `bash hooks/local/preflight.sh` on the traceback fixture prints a prefixed fixed-phrase error and
  the same `errors:` count as the `13ebe20` preflight on that fixture.
- The round-1 packaging-only row still prints `Verdict: PUBLISHER_PACKAGING_DRIFT`, exit 1 — the
  positive path holds.
- FR-25 and manifests as in round 1, plus preflight's count; self-hash verifier output recorded.
- The change note carries the C2 deferral and vector, the `set -e` correction, the `signal-reap`
  independent result, and the round-2 UNVERIFIED table with each item's status — never silently
  dropped.
- The re-review reads this round plus the diff; round 1 and `spec.md` are context only.
