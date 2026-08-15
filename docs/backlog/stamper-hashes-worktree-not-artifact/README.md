# Backlog — stamper-hashes-worktree-not-artifact

**Status:** open — needs a DECISION, not an implementation
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

## Notes

Related: `docs/backlog/local-gate-misses-manifest-freshness/README.md` (the detection half, and the open placement decision) · `docs/problem-catalog/mutable-python-load-point/problem.md` (why job 2 exists) · `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` (same family: local green that did not mean what the pusher thought).
