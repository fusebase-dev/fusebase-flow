# Preserved: the `manifest-fresh` phase (built, proven, removed on placement grounds)

**This code works.** It is not here because it failed. It is here because whether it belongs in the shipped default gate is an open operator decision, and shipping it would have pre-empted that.

## Provenance

| | |
|---|---|
| Built in | `cli-0298-compatibility` (T10), rewritten non-mutating (T12) |
| Proven by | hosted CI **GREEN on both platforms, 1094/1094, zero skips** at `2e9315d` — every row ran, including both controls |
| Caught | a real consumer-facing defect on its **first hosted run** (see below) |
| Removed by | `cli-0298-compatibility` T14, on **placement** grounds only |
| Removed because | the defect it caught is already fixed and green **without** it (`b57c62f`), so the phase was not carrying the value that had been credited to it |

## Adopting it

Copy `test-manifest-freshness.sh` to `hooks/tests/`, then register it in `hooks/tests/run-tests.sh`:

1. add `manifest-fresh` to the `FF_TAGS` array (it sat after `module-size`);
2. add the phase call before `git-smoke`:

```bash
run_shell_phase test-manifest-freshness.sh   "manifest-fresh"
```

Do **not** add it to `FF_FAST_TAGS` without a fresh ruling — an earlier version did, and that escalation was withdrawn.

## What it asserts

| Row | Property |
|---|---|
| `hook-layer-manifest-fresh` | re-stamping a clean checkout of the ref is a no-op (CI's exact `git diff --exit-code` property) |
| `managed-content-manifest-fresh` | same for the managed-content manifest |
| `control-detects-an-unstamped-covered-file` | mutates a covered file **inside the scratch worktree** and requires the rows above to fail — they are not vacuous |
| `verify-hook-manifest-MATCH` / `verify-managed-content-manifest-MATCH` | read-only verifiers agree |
| `control-eol-detector-discriminates` | synthetic listing: flags an `eol=lf` offender, ignores `text=auto`, correct-lf and binary |
| `no-eol-mismatched-covered-paths` | no path requiring lf is non-lf in the working tree |

## Constraints it satisfies (from the 2026-08-05 review)

- **Does not mutate the tree it judges.** Every arm is read-only against the judged tree, or runs inside a disposable `git worktree`. The first version snapshotted and restored real manifests under an `EXIT` trap; that was rejected and is gone.
- **Does not touch worktree registrations it does not own.** No blanket `git worktree prune`; cleanup removes only its own worktree by path.
- **Does not use `stamp --out`**, so the documented Windows `Path.is_absolute()` bug for MSYS-style paths is untouched and still applies to any future attempt that does.

## The defect it caught (the evidence for the placement argument)

```
manifest entry  4145ce9c5081a11b   7208 bytes   working tree, CRLF
committed blob  b084434258f3970e   7054 bytes   LF
tr -d '\r' < worktree | sha256sum == b084434258f3970e
git ls-files --eol:  i/lf  w/crlf  attr/text eol=lf
```

Three files were affected. The stampers hash **working-tree bytes**, so `audit/hook-layer-manifest.json` — a published integrity artifact, and the input to the health check's tamper-detection property — recorded a digest of bytes that never ship. Invisible to every other local signal by construction: the stamper and the verifier read the same wrong bytes and agree.

Reproduce against the pre-fix commit:

```bash
FFMF_REF=22873d6 bash hooks/tests/test-manifest-freshness.sh
# -> FAIL hook-layer-manifest-fresh, FAIL managed-content-manifest-fresh
```

## Why it was still removed

`b57c62f` fixed the defect **and** its root cause (two writers using `Path.write_text()`, which emits CRLF on Windows and regenerated the problem on every stamp). That commit is independent of this phase. So the argument "keep it, it caught a real consumer-visible defect" credits this phase with a benefit that belongs to a different commit — the defect stays fixed whether or not this ships.

What is genuinely lost by removing it: **local pre-push detection** of the class. CI still catches it — that is where it went red — so the guard is not gone, only later.
