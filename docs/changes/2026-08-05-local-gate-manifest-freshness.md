```
change_tier: lightweight
ticket: local-gate-misses-manifest-freshness
Problem:      The local full suite and CI disagreed about manifest freshness and the local one
              was weaker. CI stamps + `git diff --exit-code` + verifies both manifests; the
              local gate's `hook-manifest` tag exercised the stamping MECHANISM, never the
              CURRENT tree's freshness. A change to any collected file that forgot to re-stamp
              passed locally (625/625 at eca925b) and reddened main.
Change:       New phase `manifest-freshness` in hooks/tests/run-tests.sh (:298) backed by
              hooks/tests/test-manifest-freshness.sh — replays BOTH CI steps for BOTH manifests
              against the actual tree. hook_manifest.py stamp gains `--out` (mirroring the
              sibling managed_content_manifest.py) so the check stamps to a scratch path and
              never writes the committed manifest.
Verified:     Red arm and green arm both executed on the real tree, not simulated:
              stale tree  -> 3/7 PASS, the four freshness assertions FAIL naming
                             hooks/local/lib/hook_manifest.py and hooks/tests/run-tests.sh
              restamped   -> 7/7 PASS
              via harness -> FF_ONLY=manifest-freshness,hook-manifest = 15/15 PASS, exit 0
              Bogus tag `manifest-freshnes` correctly exits 2 (tag is registered in FF_TAGS).
Rollback:     git revert 235f4a3
Commit:       235f4a3
Deploy:       NOT DEPLOYED — local commit only; awaiting explicit operator go-ahead.
```

## The red arm was not planted — it was already there

The stale tree used for the red arm was **this repo at `cb0ff8b`**, the immediately preceding
commit. That commit modified two manifest-collected files (`hooks/tests/run-tests.sh`,
`hooks/local/lib/hook_manifest.py`) and did not re-stamp. The local gate passed and the
pre-commit hook reported `all checks passed`; CI would have gone red.

So the defect reproduced on the very next commit after the ticket was read, which is the
strongest available evidence that the gap is not theoretical. Both manifests are restamped in
this commit.

## Why both arms are needed (neither subsumes the other)

| Arm | Catches | Misses |
|---|---|---|
| `verify-*-manifest.sh` | modified / missing listed assets; import-adjacent extras. Exit 1, names each path | a NEW collected file outside the narrow extra-scan — hook-layer verify reported `extra=0` for the new test file |
| stamp `--out` + `cmp` | any difference at all, including new collected files | nothing, but it reports "differs" without naming which path |

Observed directly: on the stale tree, hook-layer `verify` said `extra=0` and did not see
`hooks/tests/test-manifest-freshness.sh`; `hook-layer-restamp-identical` caught it. Dropping
either arm reopens part of the gap.

## AC2 is the load-bearing constraint

A freshness checker that stamps **in place** rewrites the manifest to match the tree, then finds
no difference — permanently green, and it would have masked exactly the drift above. Hence
`--out`, and hence the AC2 assertion compares the committed manifests' content hash before and
after the run.

That assertion deliberately does **not** use `git diff`: that asks "does this match the index",
which goes red the moment a legitimate restamp is staged, and green if a check wrote the manifest
while the tree happened to be stale in the same way. Content-in / content-out is the only
question AC2 asks.

## Acceptance criteria

| AC | Requirement | Result |
|---|---|---|
| AC1 | Touching a collected file without re-stamping FAILS the local suite, offending path named | met — four assertions fail, paths named |
| AC2 | Clean tree passes; the assertion does not modify the committed manifests | met — `checks-do-not-mutate-committed-manifests` passed in both the stale and clean runs |
| AC3 | Red arm proven by a planted whitespace edit; green arm on the unmodified tree | met — `red-arm-planted-edit-fails-and-names-the-path` + `red-arm-restores-the-tree-exactly` |

## Residual

The red arm temporarily appends a newline to a real collected file and restores it under an
unconditional `trap ... EXIT`, asserting byte-exact restoration afterwards. An interrupted run
between plant and restore leaves one whitespace character in
`hooks/local/stamp-managed-content-manifest.sh`, recoverable with `git checkout --` on that path.
A fully isolated red arm needs a scratch worktree, which costs more than the residual is worth.
