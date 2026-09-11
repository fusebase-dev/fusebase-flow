# Backlog — stamper-hashes-worktree-not-artifact

**Status:** open — consumer CRLF upgrade block fixed in classification only (2026-09-11); AC1 and the stamping decision (options A–D) still open
**Filed:** 2026-08-15 (during `cli-0298-compatibility`, from a hosted RED at `22873d6`)
**Owner:** unassigned
**Lane guess:** Full — it changes a shared stamper every manifest depends on, and the choice below is a genuine trade-off

## READ THIS FIRST — this is not a free improvement

The obvious framing is *"the stamper should hash committed content instead of working-tree bytes, so the manifest always describes the artifact."* That is **half true and half a regression.**

The manifest has **two** jobs:

| Job | Served by hashing WORKING-TREE bytes | Served by hashing INDEX/COMMITTED bytes |
|---|---|---|
| Describe the artifact that ships | ✗ (the defect below) | ✓ |
| Detect local tampering | ✓ | ✗ **lost** |

Job 2 is not incidental. `flow-skills/fusebase-flow-health-check/SKILL.md` states the hook-layer integrity critical *"ALSO catches local tampering (which re-running tests does NOT — tampered code can still pass tests)"*, and the whole point of the v3.30.5 `mutable-python-load-point` work was that a security check reading working-tree code can be neutralized by editing that copy. Hashing `git show :path` would make an **unstaged edit to a hook verify clean** — precisely the hole that entry closed.

So: anyone picking this up must decide which property wins, or design for both. Do not implement it as a one-line swap.

## Problem

`hooks/local/lib/hook_manifest.py`, `managed_content_manifest.py` and `stamp-cli-provenance.sh` all hash **working-tree bytes**. When a file's working-tree bytes differ from what git materializes — the `.gitattributes` eol case is the known instance — the manifest records a digest of bytes that never ship.

It is undetectable locally **by construction**: the stamper and the verifier read the same wrong bytes, so they agree with each other and both are wrong about the artifact. `verify-*.sh` reports MATCH; CI checks out normalized content and disagrees.

## Observed (the occurrence that produced this ticket)

```
manifest entry  4145ce9c5081a11b   7208 bytes   working tree, CRLF
committed blob  b084434258f3970e   7054 bytes   LF
tr -d '\r' < worktree | sha256sum == b084434258f3970e   exactly
git ls-files --eol:  i/lf  w/crlf  attr/text eol=lf
```

Three files affected (`hooks/local/check-vendored-rendered.sh`, `audit/cli-vendor-manifest.json`, `audit/cli-upstream-manifest.json`). Hosted verify RED on both platforms at `22873d6`; fixed in `b57c62f`.

**Any newly created `.sh`/`.json` on a Windows host reproduces it.**

## What was already done (so this ticket is not re-doing it)

`cli-0298-compatibility` T11 fixed the *occurrence* and the *proximate cause*, and added detection:

- The two new writers (`stamp-cli-provenance.sh`, `refresh-cli-vendor.sh`) used `Path.write_text()`, which translates `\n` to CRLF on Windows — they **regenerated** the defect on every stamp. Both now use `open(..., newline="\n")`, matching `hook_manifest.py:150`.
- Worktrees normalized; manifests re-stamped.
- `hooks/tests/test-manifest-freshness.sh` now stamps a **clean scratch worktree** and requires a no-op, which catches this class regardless of cause, plus a direct row naming any `eol=lf` path that is non-lf in the worktree.

`health-check-enforcement-blind-spot` S3a (2026-08-19) added the **stamp-time refusal** for the one proven subclass: `hooks/local/lib/eol_guard.py` resolves `eol` via `git check-attr -z --stdin`, and a covered file holding CRLF under a resolved `eol=lf` makes all three stampers emit the diagnostic, return non-zero, and **not write the manifest**. Wired into `hook_manifest.py::stamp`, `managed_content_manifest.py::stamp`, `stamp-cli-provenance.sh`; phase `stamp-eol-guard`.

**This ticket is NOT closed by it, and S3a is none of options A–D below.** It is a refusal, not a hashing change: it prevents the wrong baseline for `eol=lf` only, degrades open off git, and deliberately leaves a CRLF file with no `eol` pin alone. AC1 is still open for every non-eol divergence (filters, smudge/clean, case-folding), and AC2 — the tamper-detection trade — is untouched and still the decision this ticket exists to make.

## Landed 2026-09-11 — classification-only LF↔CRLF equivalence (consumer upgrade block)

Decision (premise review, SOUND-WITH-FIXES): *keep all three stampers and integrity verifiers unchanged; add manifest-anchored, Git-proven LF↔CRLF equivalence only to managed-content classification.*

Closed: a consumer on `core.autocrlf=true` with no `.gitattributes` held CRLF checkouts of LF-baselined files, so an upstream-changed path classified `changed-by-both` (`managed_content_manifest.py::_classify_one`) → `plan` rc 9 → `upgrade.sh` exit 3. The v4.16.5 release note named this as still open.

| Contract point | Implementation (`managed_content_manifest.py`) |
|---|---|
| Raw `L == U`, `L == B` decided first | `_classify_one`; the proof runs only for `L != B` and `L != U` |
| `C` = pinned consumer HEAD regular-file blob; strict LF text (no CR, no NUL, ≥1 LF) | `_git_confirm`, `_lf_text` |
| `B ∈ {H(C), H(R(C))}` and `L ∈ {C, R(C)}` — anchored to the INSTALLED digest, never HEAD alone | `_eol_proven` digest prefilter (no git launch unless it passes) |
| `filter`/`ident`/`working-tree-encoding` presence blocks; git checkout of `C` at the path `== L`; any missing evidence, unsafe path or conversion failure grants nothing | `check-attr --all -z` snapshots the conversion inputs ONCE; the checkout then runs in a scratch repository that reads no consumer config and no consumer attribute file, so no consumer filter driver can be named there |
| A byte change or path swap landing DURING the git evidence grants nothing | `_eol_proven` re-reads the local bytes and re-runs `_safe_rel` AFTER `_git_confirm` returns, not only before |
| Git output is read at its own record boundary, never by line-splitting | `config --null --get-regexp` + NUL records (a config VALUE may hold a newline and would otherwise mint a second setting); `check-attr -z` and `ls-tree -z` are already NUL-delimited; `cat-file --batch` is size-delimited; `rev-parse`, which has no `-z`, refuses on an unexpected record count |
| Proved relation feeds the K9 table; `B` and the manifest untouched | `local_matches_base`; row key `eol_proven`; report line `(line endings only)` |
| Trusted boundary: stdlib-only, inline, no consumer-tree helper import | runs under the `-I -S` classifier interpreter |

Residual limits, stated so the contract is not read as stronger than it is:

- The revalidation is **point-in-time, not a lock.** A symlink can be swapped between `_safe_rel` and `read_bytes`, and bytes can change after their re-read while another row is checked or before `build_plan` consumes `proven`. Paths are reopened by name; no descriptor or lock binds validation to later use. This closes the reported during-git window, not arbitrary concurrent-writer safety.
- Isolation assumes a **trusted git executable.** `_git` resolves `git` through the inherited `PATH`, so a wrapper on `PATH` could reintroduce the environment and config the scratch repository exists to exclude. Same-user tampering with the scratch directory is equally out of scope.
- `core.autocrlf` and `core.eol` values outside git's own vocabulary grant nothing rather than being guessed at; the same is true of unlisted `text`/`eol` attribute values.

Git launches are constant (8) whatever the candidate count: 5 against the consumer (`rev-parse`, `ls-tree`, `cat-file --batch`, `check-attr`, `config`) and 3 against the scratch repository (`init`, `add`, `checkout-index`). Tampering table, the two interleaving rows and RED/GREEN: phase `upgrade-classify-eol` (`hooks/tests/test-upgrade-classify-eol.sh`).

Behavior change: an EOL-only file upstream did NOT change moves from `consumer-only` (preserved + reported) to `upstream-only` (refreshed with upstream's LF bytes). Intended: the proof has established those bytes ARE the recorded base, so the file is not a consumer edit and `consumer-only` was the wrong verdict; the visible effect is that a CRLF working copy is rewritten LF, which is what the consumer's own `core.autocrlf` will convert back on the next checkout.

**Not closed by it — still open here:**

- **AC1** — stampers still hash working-tree bytes; the publisher-side worktree≠artifact divergence (filters, smudge/clean, case folding, any eol drift the S3a guard misses) is untouched.
- **CRLF health checks** — `verify` (hook-layer + managed-content) stays exact bytes, so a CRLF consumer still reports DRIFT; deliberate (integrity is the tamper detector).
- **`--repair-managed`** — its post-repair re-verification of each bound layer (`bootstrap-upgrade.sh`) stays exact, so while other covered files remain CRLF it still reports the repair NOT confirmed.
- **Incoming source gate** — `materialize-managed-source.sh` verifies the SOURCE against its own manifest before classification; a bad publisher stamp still aborts there.
- **Rewrite content AND recompute its manifest/self-hash** — passes today and still passes; the self-hash is not authentication (`hook_manifest.py` self-hash tripwire).
- No automatic consumer restamp — it would bless current edits and destroy the historical base.

What remains unfixed is the **general** property: the stamper still describes the local copy, so a future divergence of a different kind (a filter, a smudge/clean driver, a case-folding checkout) reappears silently until the freshness phase runs.

## Options

| Option | Effect | Cost |
|---|---|---|
| **A — hash committed/index content** (`git cat-file`) | manifest always describes the artifact | **loses tamper detection** (see above); also fails on unborn/staged-only states and needs a story for the pre-commit path |
| **B — hash working-tree bytes, but assert worktree == index for covered paths at stamp time** | keeps both properties; the stamp refuses to record a digest that does not match what ships | stamping now fails while you have uncommitted edits to covered files — i.e. during normal development |
| **C — hash working-tree bytes normalized as git would** (apply the eol attr before hashing) | keeps tamper detection; fixes the known class | only fixes eol, not the general "worktree ≠ artifact" family; duplicates git's filter logic |
| **D — do nothing further; rely on the freshness phase** | zero code change; the class is caught before push | detection rather than prevention; depends on the phase staying in whichever gate tier the operator settles on |

No recommendation is recorded here on purpose — the trade-off is the ticket.

## Acceptance criteria (whichever option is chosen)

- **AC1** — A covered file whose working-tree bytes differ from what git materializes cannot produce a manifest that verifies MATCH locally while failing CI.
- **AC2** — The tamper-detection property is either preserved, or its loss is explicitly ratified by the operator and the health-check skill text is corrected in the same change (it currently promises tamper detection).
- **AC3** — RED-first: reproduce with a CRLF-created covered file on a Windows host (or a synthetic equivalent), fail, fix, pass.

## Second question for the same ticket — do we need TWO provenance manifests?

Raised by the 2026-08-15 zoom-out review and marked `UNVERIFIED` there: it found **no established adopter need** for both `audit/cli-vendor-manifest.json` and `audit/cli-upstream-manifest.json`.

They were split deliberately — the vendor manifest records what we shipped (local sha256, the `CLI_SNAPSHOT_STALE` input), the upstream manifest records what the source CLI tree held, which is what makes `source_cli_version` *derived* rather than asserted. But the vendor manifest already carries `upstream_sha256` / `matches_upstream` / `merge_derived` per asset, so the second file may be redundant to everything except `refresh-cli-vendor.sh`'s own bookkeeping.

**Question to decide:** can `cli-upstream-manifest.json`'s fields live inside `cli-vendor-manifest.json`, leaving one artifact?

Deliberately **not** collapsed in `cli-0298-compatibility` — that ticket already carried six review-driven fixes, and merging two published audit artifacts under time pressure is how a provenance surface acquires a silent regression. Whoever takes it should note that both files are consumer-facing and that `preflight.sh` accepts `schema_version` 1 **and** 2, so any collapse needs a schema story for trees stamped by an older Flow.

## Notes

Related: `docs/backlog/local-gate-misses-manifest-freshness/README.md` (the detection half — built, proven, and removed from the shipped gate on placement grounds; code preserved at `s9-manifest-fresh/`) · `docs/problem-catalog/mutable-python-load-point/problem.md` (why job 2 exists) · `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` (same family: local green that did not mean what the pusher thought).
