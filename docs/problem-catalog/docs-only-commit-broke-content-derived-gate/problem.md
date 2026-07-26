# Problem: a docs-only closeout commit landed AFTER the gate and broke main — a content-derived gate treats "adding a markdown file" as a code change

**Slug:** `docs-only-commit-broke-content-derived-gate`
**Filed:** 2026-07-26
**Severity:** high
**Status:** resolved (v4.6.1)
**Filed by:** AI Developer (FR-15, during the v4.6.0 red-main incident)

## Symptom

v4.6.0 was tagged and pushed; **both CI workflows went red immediately** (`fusebase-flow-verify` run `30206381761`, failing step "Hook tests (deterministic fixtures)"; `fusebase-flow-release` run `30206381844` failed only because it is gated on verify). The immediately preceding commit `18f2ffa` was green. The release had a recorded **619/619 local green, 0 FAIL, 0 INCONCLUSIVE** and had passed **two adversarial reviews**.

The working hypothesis on entry was **"Windows-passes / Linux-fails platform divergence"** — plausible because [[ci-linux-msys-test-divergence]] is exactly that, and because the local suite was believed green at the pushed commit.

**That hypothesis was wrong.** The suite failed **identically on Windows/MSYS** at the pushed commit. There was no platform component at all.

## Reproduction

| # | Action | Observed |
|---|---|---|
| 1 | `bash hooks/tests/test-sync-allowlist.sh` on MSYS-local @ `9b62819` | **5/7 PASS** (2 FAIL) |
| 2 | Same, `ubuntu-latest` (docker `python:3.12-slim`, clean clone) @ `9b62819` | **5/7 PASS** — byte-identical failures |
| 3 | Full suite on `ubuntu-latest` @ `9b62819` | **614/616**; preflight 0 errors / 0 warnings; the ONLY 2 failures are these |
| 4 | Same test @ `4323b23` (HEAD~1) on Linux | **7/7 PASS** |

Deterministic, both platforms, every run. **The regression is the final commit `9b62819` — a `docs(closeout)` commit.**

## Root cause — two defects in `hooks/tests/test-sync-allowlist.sh`, one trigger

**Trigger.** `9b62819` added `docs/backlog/rule-inventory-version-literal-noise/README.md`. That backlog note quotes the self-attestation string **verbatim, as an illustration of the noise it describes** (`"Operating as {role} under Fusebase Flow v4.6.0…"`). Quoting it made it match the test's `LIVE_RE`.

**Defect 1 — an unfalsifiable name in a hand-maintained deny-list.** The test's `TRUE_TARGET` derivation pruned record/consumer doc trees **by enumerated name**, and the enumeration listed `./docs/product-backlog` — **the CONSUMER layout name, a path this repo has never had in its entire history** — while never listing this repo's own `docs/backlog`. So every backlog note defaulted to "framework file that must be version-synced". The trap was latent for as long as no backlog note happened to carry a live token; `9b62819` was the first one that did. Nothing anywhere asserted that a prune-list entry corresponds to a real directory, so a dead entry looked exactly like a live one.

**Defect 2 — `pipefail` + `grep -q` early exit turned a passing check into a FALSE FAILURE.** The AC27 self-verification ran:

```bash
elif ! missing_set "$MUTATED_REACHABLE" | grep -qxF "FLOW_RULES.md"; then
```

Under this file's `set -uo pipefail`, `grep -q` **exits at the first match**; every further byte the producer writes then raises **SIGPIPE**, so the pipeline reports **141** even though the line *was* found — and `!` flips that into the failure branch. With exactly one missing entry the producer finished before `grep -q` exited, so it passed **by accident**. Defect 1 added a second missing entry, `missing_set` kept writing after the match, and the control emitted `"production missing_set did NOT report the omitted FLOW_RULES.md"` — a claim that was simply false. Isolated proof: same producer, `rc=0` direct vs **`rc=141` piped**.

So **one added markdown file produced two failures**: one real (defect 1 correctly detecting a misclassification) and one entirely spurious (defect 2), which is why the failure signature looked exotic enough to suggest a platform quirk.

## Why it evaded 619/619 local green + two adversarial reviews

| Evader | Mechanism |
|---|---|
| **The gate never ran on the tree that was pushed** | The 619/619 was measured at or before the release commit `ef7793e`. Two more commits (`4323b23` docs closeout, `9b62819` roadmap + backlog note) landed **after** the verification gate. The green number was real — for a tree that was never published. |
| **"docs-only ⇒ risk-free" is false for content-derived gates** | `test-sync-allowlist.sh` derives its expected set by `find`-ing the filesystem and grepping content. For such a gate, **adding a markdown file IS a change to the gate's input**. "Docs-only" describes the diff's intent, not its blast radius. |
| **The trap was content-conditional, not structural** | The dead `docs/product-backlog` entry had been wrong for the repo's whole history and was invisible until a file in the *real* backlog first quoted a live token. Reviewers reading the prune list see plausible-looking names; nothing distinguishes a live entry from a dead one. |
| **The false-failure control looked like it worked** | Defect 2's control passed continuously — on single-entry output. An assertion that is only ever exercised in its degenerate case is indistinguishable from a working one. Same family as [[tests-ran-without-set-e]]: green that proves nothing. |
| **Adversarial review reviews the diff, not the derived set** | Both reviews examined the change; neither re-ran the gate against the *post-closeout* tree, because closeout commits are not conventionally treated as gated changes. |

## Permanent fix (v4.6.1)

| # | Fix | Where |
|---|---|---|
| 1 | Replace the enumerated record-tree prune with the **structural rule the allowlist already declares**: the framework doc surface under `docs/` is **top-level `docs/*.md` only**, so every `docs/<subdir>/**` is a record tree (`-path './docs/*'` prune). No names to maintain, nothing to go dead, and new doc trees are correctly classified on creation. | `hooks/tests/test-sync-allowlist.sh` |
| 2 | Pure-bash `has_line()` exact-line membership (no pipe ⇒ no SIGPIPE), and capture `missing_set` output into a variable instead of piping it into `grep -q`. Removes the whole false-verdict class from this file. | same |
| 3 | `guard-detects-omission` now drops **two** files and requires **both** reported — the control now exercises multi-entry output, the exact shape that hid defect 2. | same |
| 4 | New `docs-surface-is-top-level-only` guard asserts the **other half** of the structural rule: no allowlisted path may live under a `docs/` subdirectory. Prune side and reach side can no longer silently disagree. | same |

Proof: **8/8 PASS on Windows/MSYS and on `ubuntu-latest`**; red arms confirmed biting (drop `FLOW_RULES.md` from `SYNC_FILES` → under-reach FAILs; add `docs/backlog` to `SYNC_ROOTS` → docs-surface FAILs).

## Recurrence triggers (so future sessions recognize this)

- A commit lands **after** the verification gate ran — especially `docs:` / `docs(closeout):` / ROADMAP / backlog / problem-catalog commits at the tail of a release.
- A test derives an expected set by `find` + `grep` over the repo, then compares it to a hand-maintained list. Any new file is an input to that gate.
- A deny/prune list contains a path that does not exist in this repo (`[ -d ]` would be false) — a dead entry that has never been exercised.
- `set -o pipefail` in the same file as `producer | grep -q` (or `head`, `sed -n '1p'`, any early-exiting consumer). Signature: an assertion whose message asserts something you can prove is true by running the producer alone.
- A control/self-verification whose expected output is **exactly one line**.
- General signal: "it was green locally, and the only thing that changed since was documentation."

## Guardrail (the lesson)

**The gate must run on the tree you actually push — a green measured before the last commit is not a green.** Re-run the full suite (or wait for CI) after the final closeout commit, no matter how documentation-only it looks; for content-derived gates there is no such thing as a docs-only change. And when a green suite goes red on CI, **verify the platform hypothesis before adopting it** — re-run the failing test locally at the pushed commit first (30 seconds), because the far more common explanation is that the local green was measured at a different commit. Two structural corollaries: prefer a **structural rule over an enumerated list** (an enumerated exclusion fails open for everything nobody remembered, and a dead entry is indistinguishable from a live one), and treat any assertion that only ever runs in its **single-element degenerate case** as unproven.

## Related

- [[ci-linux-msys-test-divergence]] — the genuine platform-divergence incident this one **imitated**; consulting it first is what made "Linux-only" the plausible-but-wrong entry hypothesis.
- [[tests-ran-without-set-e]] — same family: an assertion that could not fail.
- [[ci-red-invisible-no-release-gate]] — why CI redness must block publication.
- `docs/backlog/rule-inventory-version-literal-noise/README.md` — the file that tripped it (correctly classified as a record from v4.6.1).
- `hooks/local/sync-version-strings.sh` — `SYNC_ROOTS` / `SYNC_FILES`, the allowlist under test.
