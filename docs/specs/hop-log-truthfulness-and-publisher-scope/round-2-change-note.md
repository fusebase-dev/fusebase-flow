# Round 2–3 change note — hop-log truthfulness and publisher scope

Plan: `corrections.md` § Round 2. Base `13ebe20` (round 1 ACCEPTED, not revisited). Nothing released,
tagged or version-bumped; `v4.15.3` is still the last tag.

## Commits — one correction per commit, in the plan's order

| # | SHA | Correction | Files |
|---|---|---|---|
| 1 | `2508a85` | **R2** — CR/LF normalized at source; classifier compares both sides identically | `lib/plugin-parity.sh`, `lib/partial-upgrade-check.sh`, `test-plugin-parity-scope.sh`, both manifests |
| 2 | `7b02b53` | **R1** — preflight failure recorded as its own fact; packaging-only requires positive establishment; the two `err` wrappers | `fusebase-flow-health-check.sh`, `preflight.sh`, `lib/partial-upgrade-check.sh`, `test-plugin-parity-scope.sh`, both manifests |
| 3 | `d763f6c` | **R3** — CONTRACT inventory → pointer; the C2 vector tripwire | `lib/recovery-outcome.sh`, both manifests |
| 4 | `1555e79` | **R4 (round 3 blocker)** — escape at render time; the comparison sees the values as found | `lib/plugin-parity.sh`, `test-plugin-parity-scope.sh`, both manifests |

Per-task wall clock (UTC): T83 `00:46:13`→`00:55:56` (9m43s) · T84 `00:55:56`→`01:12:48` (16m52s) ·
T85 `01:12:53`→`01:15:28` (2m35s) · T86 `03:25`→`04:31:52` (~66m, most of it the two bounded
suite runs).

## R1 — the blocker

**Fix shape.** `:388` now sets `FFHC_PREFLIGHT_FAILED=1` beside the saved output on the same line;
`:510` gates on that flag, not on `-n "$FFHC_PREFLIGHT_FAIL_OUT"`. Empty, unreadable and
unparseable captures therefore all reach BROKEN. `ffhc_preflight_is_packaging_only` now requires
three necessary conditions: **(a) completed** — the `[preflight] preflight finished — errors: N,
warnings: M` marker is present; **(b) reconciled** — `N` equals the number of matched prefixed
lines; **(c) text** — every prefixed line equals a finding from this run, and there is ≥ 1.

**Mechanism 1 — empty failure output (the false-HEALTHY).** Fixture: copied publisher tree, no
manifest lag, `hooks/local/preflight.sh` replaced by `exit 1`, fixture hook manifest re-stamped so
integrity cannot carry the verdict.

| Bytes | Verdict | Exit | Preflight recorded? |
|---|---|---|---|
| `13ebe20` | `HEALTHY` | **0** | nowhere — not BROKEN, not UNVERIFIED, not OK |
| HEAD | `BROKEN` | **2** | `preflight: errors detected (run 'bash hooks/local/preflight.sh' to inspect)` |

**Mechanism 2 — unprefixed failure beside packaging findings.** Fixture: same tree with the lagged
`.claude-plugin/plugin.json` plus `flow-skills/zoom-out/SKILL.md` prefixed with `\xff\xfe`
(`read_text(encoding="utf-8")` raises).

| Bytes | Verdict | Exit |
|---|---|---|
| `13ebe20` | `PUBLISHER_PACKAGING_DRIFT` | 1 |
| HEAD | `BROKEN` | 2 |

**Authorized preflight relaxation — declared.** Round 1 promised preflight itself was unmodified.
That is relaxed for exactly two lines: `hooks/local/preflight.sh:74` (skill frontmatter) and `:291`
(command policy), the bare `errors=$((errors + 1))` wrappers, now
`err "preflight subcheck did not complete cleanly: <check> (python rc ${PIPESTATUS[0]})"`.
**Count of bare `errors=$((errors + 1))` outside `err()` found at `13ebe20`: 2.** Both changed;
`grep` at HEAD returns only the one inside `err()` itself. Nothing else in preflight changed.

Direct `bash hooks/local/preflight.sh` on the traceback fixture, same fixture both ways:

| | `13ebe20` | HEAD |
|---|---|---|
| finished line | `errors: 1, warnings: 4` | `errors: 1, warnings: 4` |
| exit code | 1 | 1 |
| prefixed `ERROR:` lines | 0 | 1 (the fixed phrase) |

Same count, same exit code, one more line — as specified.

**Residual (b) does not cover, recorded not built.** A Python block printing exactly **one** prefixed
line whose text equals a packaging finding reconciles (N = p+1, matched = p+1). That needs the text
collision the reviewer looked for and did not find; it stays UNVERIFIED.

## R2 — CR normalization

Probe input is a CRLF **inside** the value: `.claude-plugin/plugin.json` with
`"version": "4.15.2\r\n-rc1"` (JSON escapes → a real CR+LF in the parsed value).

| | `13ebe20` | HEAD |
|---|---|---|
| `ffpp_errors` lines for one violation | **2** (`…version (4.15.2␍␍` / `-rc1) != VERSION (4.11.0); bump them together`) | **1** (`…version (4.15.2\r\n-rc1) != VERSION (4.11.0); bump them together`) |
| CR/LF bytes in the finding | present | none |
| `ffhc_preflight_is_packaging_only` | **rc 1 — rejected → BROKEN** | **rc 0 — packaging-only** |

Fix (as landed after R4): the value is **escaped**, not stripped, and the classifier strips the
trailing CR from the **finding** side as well as the preflight side. `2508a85`'s strip-at-source
was the R4 blocker and is gone; the HEAD column above is the rendering after `1555e79`.

## R3 — FR-22 trim

`lib/recovery-outcome.sh` `:10-16` (function inventory + state list) → one line:
`# CONTRACT: spec.md § S1 "Outcome contract"; the state vocabulary is FFRO_STATES below.`
The four tripwires stay. One C2 line added beside the channel tripwire: the channel is exclusive
against consumer **bytes**, not against executable descendants of recovery. `plugin-parity.sh:44-46`
was **not** widened into. File: **194 → 189 lines**.

## R4 — the rendering must not decide the comparison (round 3 blocker)

Probe: `VERSION=4.15.3` + `.claude-plugin/plugin.json` `"version": "4.15.\r\n3"` — raw bytes differ
from VERSION, stripped text is identical to it. Native Windows `python3` 3.12.10, real helper bytes.

| `plugin-parity.sh` bytes | `ffpp_errors` finding lines |
|---|---|
| `13ebe20` | 2 (one violation, CR-split) |
| `2508a85` (R2) / `d763f6c` | **0 — the mismatch is gone** |
| `1555e79` | 1 — `.claude-plugin/plugin.json version (4.15.\r\n3) != VERSION (4.15.3); bump them together` |

Fix: one injective escape (`\`→`\\`, CR→`\r`, LF→`\n`) held once as `FFPP_ESC_PY` and applied
inside the python that reads the field **and** to the `VERSION` string via `ffpp_esc`. Injective ⇒
escaped equality is raw equality, so no comparison ever sees a normalized value, and the one-line
CONTRACT holds by construction. `VERSION` drops only its trailing terminator (LF, or the CR of a
CRLF) — file framing, not content. Ownership (`name`) is again an exact identifier match, which is
`13ebe20`'s behaviour; R2's strip had silently widened it to CR/LF-bearing names.

Side effect worth keeping: the escape is applied **before** the value crosses the `python3 → $()`
boundary, so the result no longer depends on the platform. Native Windows `python3` writes
`…\r\n` and MSYS `$()` eats the pair, while Linux writes `…\n` — under `13ebe20` those two
platforms could disagree about a value's trailing bytes; now the payload is CR/LF-free before
either rule applies. `lib/plugin-parity.sh` **86 → 108** lines.

## Test rows added (`hooks/tests/test-plugin-parity-scope.sh`, tag `n4-parity-scope`)

| Row | Proves |
|---|---|
| `r4-stripped-equal-is-still-a-mismatch` | a version equal to VERSION only after stripping still reports exactly one CR/LF-free line; `d763f6c`'s helper reports **nothing** on the same fixture (pinned) |
| `r4-ownership-compares-raw-name` | a `fusebase-flow\r\n` name is not the identifier, so the manifest is left alone — ownership is not decided by a normalization either |
| `r2-crlf-value-is-one-finding` | one CR/LF-free parity line for a CRLF-bearing version (now asserts the escaped rendering, not the stripped text) |
| `r2-classifier-normalizes-both-sides` | CR on either side or both still matches; a non-finding still does not |
| `r2-crlf-fixture-is-packaging-only` | rc 0 now; rc 1 on `13ebe20`'s helper + classifier (pinned) |
| `r1-packaging-only-must-be-positively-established` | unit table: no marker / N=2 vs 1 line / N=1 vs 1 line / empty / no findings / marker-only / unparsable N |
| `r1-unprefixed-failure-beside-packaging-is-broken` | `2\|BROKEN` now; `1\|PUBLISHER_PACKAGING_DRIFT` on `13ebe20` (pinned) |
| `r1-exception-path-emits-a-prefixed-error` | same `errors:` count, same exit, exactly one more prefixed line |
| `r1-empty-failure-output-is-broken-not-healthy` | `2\|BROKEN` now; `0\|HEALTHY` on `13ebe20` (the false-HEALTHY, pinned) |

The anti-regression stages all three changed files (`engine`, `lib/partial-upgrade-check.sh`,
`preflight.sh`) from `13ebe20` **together**, and re-stamps the fixture's `audit/hook-layer-manifest.json`
after each swap so an integrity finding can never carry a row. Round 1's packaging-only row still
prints `Verdict: PUBLISHER_PACKAGING_DRIFT`, exit 1 — the positive path holds.

## Verification

| Check | Result |
|---|---|
| `FF_RELEASE=1 bash hooks/tests/run-tests.sh` | at `1555e79`: **RELEASE PROFILE 682/682 PASS** (31 explicit phases), exit 0, zero `^FAIL` lines (round 2: 680/680; +2 = the two R4 rows) |
| `FF_FULL=1 bash hooks/tests/run-tests.sh` | round 2 only: **1285/1286 PASS**, exit 1 — the single FAIL is `signal-reap launch-window-signal-still-reaps`, pre-existing (pair below). Not re-run for R4: the diff is one lib + its own phase |
| `bash hooks/tests/test-plugin-parity-scope.sh` | **24/24 PASS**, exit 0 (round 2: 22/22). The first R4 run showed 23/24 with `s2-publisher-packaging-only-is-not-broken` reporting `FLOW_LAYER_DRIFT` — its own message names the cause: the source tree's `audit/hook-layer-manifest.json` was not yet re-stamped. Re-stamped (hook layer first, then managed content) → 24/24 |
| `bash hooks/local/verify-hook-manifest.sh` | `MATCH (listed=214 matched=214 modified=0 missing=0 extra=0; flow_version=4.15.3)` — includes `manifest_self_sha256` (`hook_manifest.py:230`) |
| `bash hooks/local/verify-managed-content-manifest.sh` | `MATCH (listed=378 drifted=0)` — includes `manifest_self_sha256` (`managed_content_manifest.py:218`) |
| `bash hooks/local/check-module-size.sh --all` | rc 0 |
| `bash hooks/local/preflight.sh` (this tree) | `errors: 0, warnings: 1` (pre-existing overlay-drift warn) |
| `git status --short` | identical to the session-start snapshot; no new untracked or modified paths |

**FR-25.** health **800** (ceiling, unchanged) · preflight **439** (unchanged) ·
`lib/partial-upgrade-check.sh` 133 → **152** · `lib/plugin-parity.sh` 85 → 86 → **108** ·
`lib/recovery-outcome.sh` 194 → **189** · `test-plugin-parity-scope.sh` 344 → 557 → **605** ·
`upgrade.sh` 819 and `run-tests.sh` 795 untouched. `check-module-size.sh --all` rc 0.

## `signal-reap` — the independent run the plan required

`FF_ONLY=signal-reap bash hooks/tests/run-tests.sh` on MSYS, clean process table
(`ps` showed no concurrent `run-tests`/`health-check`/`preflight`).

| Tree | Result |
|---|---|
| HEAD `d763f6c` (run twice) | **7/8 PASS, 1 FAIL** — `launch-window-signal-still-reaps (window=open child_gone=-1s grandchild_gone=-1s (-1 = alive at 8s) — the launch-to-record window published nothing, so the guard had no identity to act on)` |
| `24cbff3` (detached worktree, last pre-round-1 commit) | **7/8 PASS, 1 FAIL — the same row, byte-identical message** |

**Pre-existing, shown by the pair, not asserted.** The only change to `run-tests.sh` between
`24cbff3` and HEAD is T81 appending `hop-log-truth n4-parity-scope` to the `FF_RELEASE_TAGS` array
literal — a selection list `FF_ONLY` does not consult and the reaping guard never reads.
Round 1's justification ("no file it exercises is in my diff") was **wrong** and is withdrawn:
`signal-reap` does exercise `run-tests.sh`, which T81 edited. The correct evidence is the pair above.

## Round-1 claims corrected — not cited as precedent

- **The "latent `set -e` abort" was OVERSTATED.** `|| true` at `upgrade.sh:742` did not fix what it
  claimed; under `-euo pipefail` a false left operand ending an `if` branch survives. It is harmless
  and stays. Not used as a precedent for guarding `&&` lists anywhere in round 2.
- **The `unset FFRO_OUTCOME_FILE` does not exist.** Grepped at HEAD across `hooks/`: the only
  lifetime hygiene is `rm -f "$RECOVERY_LOG" "$FFRO_OUTCOME_FILE"` (`upgrade.sh:707`) — a file
  deletion, not an environment `unset`. Round 1's description was inaccurate. The reviewer's point
  stands either way: it does not close the descendant-write vector.

## UNVERIFIED table (round 2) — status of every item

| Item | Status after round 2 |
|---|---|
| Command chronology; full managed-manifest regeneration a no-op on the final tree; repo-wide mirror drift; protected-path approval coverage | **Settled by closeout evidence.** Both manifests re-stamped (hook layer first, then managed content) and both verifiers return MATCH on the final tree — a re-stamp is now a no-op. No protected path (`policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`, `FLOW_RULES.md`) was touched, so no FR-07 approval was minted or needed; all three commits passed the pre-commit unmodified, no `--no-verify`. |
| Consumer code executing **inside** the recovery process tree | **Still UNVERIFIED / not established.** Precondition of the C2 residual; C2 deliberately deferred, vector documented in `recovery-outcome.sh`. |
| Timed-out / skipped preflight | **Still UNVERIFIED by design** (`fusebase-flow-health-check.sh:381-384`). R1 does not touch those branches; they remain `LOCAL_UNVERIFIED`, never OK. |
| Text collision between an ordinary non-packaging preflight error and a packaging finding | **Still UNVERIFIED.** Not depended on; the (b) residual above is the part it would defeat. |
| `signal-reap` on the final tree | **RESOLVED — red, and red identically at `24cbff3`.** Pre-existing; evidence pair above. |
| `ffro_parse` huge-line / memory behaviour (C1) | **Still UNVERIFIED.** No row required by the plan; none added. |
| Manifest self-hash (round 1) | **CLOSED** by the re-review and re-confirmed here: both verifiers check `manifest_self_sha256` and return MATCH. |

## C2 — deferral recorded

Decision carried from the plan: defer the non-inherited channel; document the vector now. The
narrowing that mattered is done — consumer **bytes** can no longer forge an outcome; only consumer
**code** inside the recovery process tree can. One tripwire line now states exactly that in
`hooks/local/lib/recovery-outcome.sh`. Re-open only if consumer code execution inside recovery is
ever established.

## Not built as written

Nothing in R1/R2/R3 was skipped or substituted. Two deliberate implementation choices worth naming:

1. The completed/reconciled logic went **inside** `ffhc_preflight_is_packaging_only` (the plan's
   first option) rather than as a sibling, so the engine keeps one call on `:510`'s line and health
   stays at exactly 800.
2. The R1 fixture rows re-stamp the **fixture's** hook manifest after each byte swap. The plan
   offered "regenerate the copy's manifest" or "assert on the preflight-specific BROKEN entry" — both
   are done: the manifest is regenerated (so the pre-fix `HEALTHY`/0 is reachable and pinned) **and**
   the preflight-specific entry text is asserted.
