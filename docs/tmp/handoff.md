# Active handoff — v4.7.0 unpublished; round-7 corrections landed and gated, round-7 review returns 2 × (a) — STOPPED FOR GOOD

**Updated:** 2026-08-03 (rev 5 — items 1/2/3 fixed and gated; Windows 743/743 + Linux 740/740; review 7 = NO-SHIP, two **(a)**, zero **(b)**) · **Branch:** `fix/msys-v3307-hardening` · **HEAD:** `4abbdf1` · **VERSION:** 4.7.0
**Hard stop by operator instruction.** The round-7 authorization was explicit: *if the review is not SHIP, stop for good — do not fix, do not iterate, regardless of how small the remaining items look.* Two (a)s came back. **No further implementation pass without a fresh operator decision.**

## State — nothing shipped, nothing to undo

| | |
|---|---|
| `origin/main` | `85b97dd` — untouched, CI green |
| Tag `v4.7.0` | `b11c60d` — **not** moved; no GitHub Release (404) |
| Local | `4abbdf1`, tracked tree clean, 59 commits unpushed |
| Gate at `4abbdf1` | Windows unscoped **743/743 PASS, 0 FAIL**; Linux `ubuntu:24.04` **740/740 PASS, 0 FAIL**, every CI step rc 0 |
| FR-07 | empty diff `c77b139..4abbdf1` on `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` |
| Locked files | empty diff: M2 hashers, M3 `run-with-timeout.sh`, `.gitattributes`, `templates/**` |
| Line ceilings | `bootstrap-upgrade.sh` **799/800**, `test-upgrade-repair-managed.sh` **799/800** — the next edit to either must shrink before it grows |
| Release prerequisites | four version carriers 4.7.0, README badge 4.7.0, `sync-version-strings.sh` empty diff — verified twice, still unused |
| Operator DP.6 | never consumed |

## Round 7 — what was authorized, and what landed

Exactly three items, no more. The review confirmed **no unauthorized fourth change**.

| Item | Commit | Discriminator |
|---|---|---|
| 1 — shell-quote the operator's `--source` in the emitted `RECOVER:` line | `c5949cf` | **RED first**: at `c8bb73c` the emitted command died with `Unknown argument: source/flow`. GREEN after |
| 2 — state the write-order claim as what is provable | `fca5b39` | **No discriminator claimed** — behaviour unchanged, the sentence was the defect |
| 3 — qualify "immutable snapshot" in M16 | `4abbdf1` | wording only |

## Round-7 review: NO-SHIP, two (a), zero (b) — `docs/tmp/handoff/2026-08-03-round7-review.md`

Both findings are **item 2 done incompletely**, both self-inflicted in that one commit. Verified first-hand, not relayed.

| # | Defect | Where | Class |
|---|---|---|---|
| 1 | The **headline phrase was left standing while its own explanation was rewritten**, so the text contradicts itself in one breath: "binds the manifest layers it must confirm **before it writes any content** … Precisely: no file you already had is touched before the bind. **Writes can precede it.**" A consumer reads both halves | `v4.7.0.md:105` (consumer-facing), `decisions.md:256` M13, `decisions.md:300` M16 + the M13 matrix row, `bootstrap-upgrade.sh:463` section heading | **(a)** |
| 2 | 3h-10's **title overclaims what its snapshot measures**. `m13-no-pre-existing-file-changes-…` is broader than the measurement: the snapshot excludes `.git/`, the staging clone, the repaired path and its backup twin, and compares FINAL bytes. It proves "no collateral change among the measured, non-target regular files in the consumer root". The inline comment is honest ("does NOT observe write ORDER"); the name and the `ok()` string are not | `test-upgrade-repair-managed.sh` 3h-10 | **(a)** |

**Zero class-(b).** Nothing about M13/M16/M17, the bound-set rule, the symlink refusal or the remediation is wrong. Round 6's three items were confirmed fixed; every prior invariant (B1–B8, R1–R5, K10, M2, M3, FR-07) re-verified intact.

## Noticed and deliberately NOT fixed (scope was three items)

"immutable snapshot" survives outside M16, describing the same plain-source `cp -R` copy. The runtime one is operator-facing and therefore the one that actually misleads:

- `hooks/local/bootstrap-upgrade.sh:419` — **printed to the operator**: `materialized plain source -> immutable snapshot`
- `docs/release-notes/v4.7.0.md:122` — "immutable tree materialized from git objects", not true for a plain source
- `docs/specs/…/decisions.md:200` (M10 reasoning) · `hooks/local/lib/materialize-managed-source.sh:85` (comment)

Non-blocking from the review: `printf '%q'` is Bash-safe but not portable to arbitrary POSIX `sh` (the emitted command invokes `bash`, so this is contained).

## The remaining work, if the operator restarts it

Both items are text. No code, no test logic, no decision.

1. Delete the "before any content write" **headline** in all four homes and let the true sentence stand alone: *no file that already existed is touched before the bind; earlier writes only create new locations.*
2. Rename 3h-10 (and its `ok()` string) to the measurement: *no collateral change among the measured non-target files in the consumer root.*
3. Optionally fold in the four out-of-scope "immutable" instances above — the runtime message first.

Then: unscoped Windows + Linux container, one review, and the release sequence below. **The operator must re-authorize** — no DP.6 phrase survives a NO-SHIP.

## Release sequence, unchanged, for when the verdict is SHIP

Restamp both manifests → unscoped Windows + Linux `ubuntu:24.04` → one review → DP.1 mint (command-bound) → `git push origin HEAD:refs/heads/main` → `git push origin :refs/tags/v4.7.0` → re-tag → `git push origin v4.7.0` → watch verify+publish via the public REST API in a bounded loop (`gh` is not installed) → confirm `GET /repos/fusebase-dev/fusebase-flow/releases/tags/v4.7.0` returns 200 → FR-14 single docs commit. Publish is `needs: verify`, so a red suite cannot release.

## Constraints (unchanged, all still binding)

Never `--no-verify`. FR-07 protected = `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` only. Locked: M2 byte-exact hashers, M3 tempfile capture, `.gitattributes`, `templates/**`, the FR-06 deny. Linux parity is mandatory before any release claim. Before diagnosing a timing FAIL, run `ps -W | grep run-tests`. The unscoped Windows suite needs **>40 min**; bound any wrapper at ≥5400s. `run-tests.sh:342` still misnames the running phase during a bounded wait (`cli-flow-recovery` appears as `upgrade-repair`).

## Reproducing the gate

Linux: build from `ubuntu:24.04` + `git python3 python3-pip`, clone `/src` INSIDE the container, run the CI step list (`c:/tmp/ffgate/linux-full.sh`). A container without PyYAML produces ~20 false FAILs — an environment defect, not a code defect.

## Filed, deferred

`docs/backlog/`: `repair-trust-root-outside-workspace` (M17's rejected option (b)) · `command-gate-shell-evasion` · `approval-single-use-consumption` · `approval-binding-omits-head` · `rm-rule-pattern-single-space-gap` · `provenance-and-single-seam-guarantees`.
Reviews: `docs/tmp/handoff/2026-08-03-round7-review.md` · `docs/tmp/handoff/2026-08-02-round6-review.md` · `docs/tmp/handoff/2026-08-02-m16-review.md` (round 5); earlier rounds in `docs/tmp/handoff/2026-07-2[89]-*`, `2026-07-3[01]-*`.
