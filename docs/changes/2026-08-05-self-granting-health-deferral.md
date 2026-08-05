```
change_tier: lightweight
ticket: self-granting-health-deferral
Problem:      DEFERRED_CHECKS is the ONE artifact-derived input that MOVES the health verdict
              (record_drift reclassifies a matching finding to LOCAL_DEFERRED => verdict
              EXCEPTION_IN_EFFECT, exit 3). check_ids were carried newline-delimited from a
              Python block into `while IFS= read -r cid`, and a check_id is artifact-controlled
              text — so ONE JSON element containing a newline became TWO bash entries, the
              second being any canonical check_id the author chose. An artifact could grant
              itself an exception it never carried. Predates 382a05e; not a regression.
Change:       hooks/local/lib/active-approvals.sh — validate-and-reject (re.fullmatch on
              [A-Za-z0-9._-]{1,120}, NEVER sanitize), NUL-delimited K/R transport read straight
              from process substitution, rejections surfaced via APPROVAL_WARNINGS, and the
              artifact traversal moved to find -print0 / read -d ''.
              hooks/local/fusebase-flow-health-check.sh — heading widened from "Approval age
              warnings" to "Approval warnings" now that the channel carries rejections too.
              New hooks/tests/test-deferral-checkid-validation.sh + `deferral-checkid` phase.
Verified:     Red arm on the OLD lib: the ticket's payload yields TWO entries —
              [harmless_id] and [claude_md_overlay] — the self-grant, reproduced exactly.
              All four residency assertions fail against the old lib (no fullmatch, no NUL
              read, no -print0, and deferred_list=$(...) present).
              End-to-end through the SHIPPED lib with a real artifact in state/approvals:
                DEFERRED_CHECKS (1): [mirror_drift]
                APPROVAL_WARNINGS (1): REJECTED malformed deferred check_id
                                       'harmless_id\nclaude_md_overlay'
              Unit: 16/16 PASS. Harness: FF_ONLY=deferral-checkid,manifest-freshness 23/23.
              Real tree unaffected: 10 active artifacts collected, rc 0, 0 policy errors.
Rollback:     git revert 0e29ed5
Commit:       0e29ed5
Deploy:       NOT DEPLOYED — local commit only; awaiting explicit operator go-ahead.
```

## Why reject and never repair

Deleting disallowed characters **manufactures** identifiers. `claude<LF>_md_overlay` with the
newline stripped is `claude_md_overlay` — a real canonical check_id. A repaired value that
collides with a genuine identifier is strictly worse than a dropped one, because the drop is
visible and the collision is not. Six collision probes (LF, TAB, CR, NUL, space, VT) are
asserted to be rejected and never folded into the canonical id.

`re.fullmatch` is used deliberately rather than `re.match(... + '$')`: `$` also matches *before*
a trailing newline, which is the exact character being defended against.

## Why the rejection goes to APPROVAL_WARNINGS

That channel is visibility-only by construction — printed outside every verdict array and count,
so it can move neither the verdict nor the exit code. A malformed check_id belongs there
precisely **because** the defect was an artifact moving the verdict. Reporting it through any
channel that feeds a verdict would reintroduce the same shape from the other direction.

The health-check heading was widened from "Approval age warnings" to "Approval warnings" in the
same commit, because a heading narrower than its contents is the repo's other standing defect
class — a claim that does not match the thing it describes.

## Two transports, one rule

| Carrier | Was | Now |
|---|---|---|
| `deferred_checks` payload | `print(cid)` + `read -r cid` — content can split the record | `K`/`R` tag + NUL terminator, read directly from process substitution |
| artifact traversal | `find ... \| read -r artifact_file` — a newline in a FILENAME splits before any validation runs | `find ... -print0` + `read -r -d ''` |

The extraction must never be wrapped in `$(...)`: command substitution **discards NUL bytes**,
which would silently empty the stream the fix depends on. There is a dedicated assertion for
that, because it is a change a future editor could make while believing it was cosmetic.

## Acceptance criteria

| From the ticket | Result |
|---|---|
| The payload yields ONE entry, and it is not `claude_md_overlay` | met — 0 accepted from the hostile element; the honest sibling still deferred |
| `claude\n`, `claude\t`, `c\0laude` each rejected, not folded into the canonical id | met — 6 probes, all rejected |
| A well-formed multi-entry list still populates; EXCEPTION_IN_EFFECT still classifies | met — `mirror_drift` still deferred end-to-end; classification path untouched |
| A malformed check_id is reported, not silently dropped | met — `APPROVAL_WARNINGS` entry naming the artifact and the rejected repr |

## A note on the test's own defect

The first revision of the test spelled the hostile ids as shell string literals, one carrying a
**literal NUL byte**. Bash strips NULs from script source, so the hostile probe silently became
the canonical id and the test failed while the validator was correct. Every control character is
now produced by Python's json encoder and never appears in the file; the file is asserted to
contain zero NUL, CR and TAB bytes.

That is the ticket's own defect class — content splitting its transport — occurring inside the
test written to prevent it. It is recorded here rather than quietly fixed, because it is the
second time in this session a fix reproduced the defect it was closing.
