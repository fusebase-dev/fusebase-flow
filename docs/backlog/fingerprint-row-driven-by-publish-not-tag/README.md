# fingerprint-row-driven-by-publish-not-tag

**Status:** fixed — enforced by `hooks/local/preflight.sh` § 10, proved by `hooks/tests/test-fingerprint-row-per-tag.sh`
**Found:** 2026-08-14, consumer finding N3 against the published `v4.9.2` tag
**Severity as filed:** LOW (no code defect; a permanent gap in adopter-facing identification data)

## Finding

`v4.9.2`'s published tree ends its fingerprint table at `v4.9.0`. `v4.9.1` has no row.

```
git show v4.9.2:docs/release-fingerprints.md   # table stops at v4.9.0
```

`v4.9.2`'s own row cannot be in its own tree — the self-reference limit is documented in the file
and is real (adding the row changes the manifest digest being identified). **`v4.9.1`'s row was
not subject to that limit.** `v4.9.1` was tagged well before `v4.9.2` was cut, so `v4.9.2` was
capable of carrying it. Both rows were appended in `42446ae`, AFTER tagging.

A tag is permanent and can never be re-cut, so an adopter holding either tree cannot be given the
missing row later.

## Mechanism — the step was triggered by the wrong event

`PUBLISHING.md`'s append step lived under **"After publication"** and, in practice, ran only after
a *successful* publish. That produces a silent, compounding drop:

| Release | Run | Row appended? | Why |
|---|---|---|---|
| v4.9.0 | RED | no | publish failed, so the post-publish step never ran |
| v4.9.1 | RED | no | same — and the next release only remembers the tag it supersedes |
| v4.9.2 | GREEN | v4.9.0 + v4.9.1 appended, after tagging | two reds had queued up; v4.9.1 was appended too late to be inside v4.9.2 |

**Two consecutive reds silently drop one row.** One red is survivable because the next release
remembers the tag it superseded; two are not, because only the most recent is remembered. The
prose already said "If publication failed, label the row as an unpublished tagged tree" — the
instruction was correct and was not followed, because its placement said otherwise. That is a
process-shape defect, not a memory defect, and remembering harder does not close it.

**Third instance, found by the fix itself:** `v4.7.1` never received a row at all. Not a
two-reds case — simply missed — which is the same failure mode from a different direction and
confirms that nothing was asserting the invariant.

## Fix

Drive the assertion off **the tag**, not off a release run, in `hooks/local/preflight.sh` (§ 10):

> for every `v*` tag, `docs/release-fingerprints.md` must contain a row

so a missing row **blocks the next cut** instead of being reported by a consumer afterwards.

| Rule | Why it is load-bearing |
|---|---|
| Self-reference exemption: a tag pointing at `HEAD` is exempt | A tagged tree cannot contain its own row. Without this, cutting any release becomes impossible |
| Coverage window: only tags at or after the oldest version the table already covers | The table starts at `v4.7.0` by design; ~85 older tags predate it. The floor is derived FROM the file, so it advances by itself and hardcodes nothing |
| Ownership (`VERSION` at the tag == the tag's version) checked only for a candidate miss | Zero cost on the healthy path, and a consumer's own `v*` tags — which this file does not describe — can never fail their preflight |

Failure names the missing tag(s) and the exact generating command
(`bash hooks/local/print-release-fingerprints.sh <tag>`); rows are generated, never
hand-transcribed (a transcribed count was wrong once and a consumer propagated it).

`PUBLISHING.md` retitled to "After TAGGING — not after publishing", with the ordering rule
(all prior tags must have rows before the next tag is cut) and the explicit statement that a red
run does not excuse the row.

## Evidence

`hooks/tests/test-fingerprint-row-per-tag.sh` (phase `fingerprint-rows`), driven against a local
clone carrying this repo's real tags:

| Row | Class | Asserts |
|---|---|---|
| `green-tree-stays-green` | CONTROL | healthy tree stays silent |
| `missing-row-fails-naming-the-tag` | DISCRIMINATOR | delete the real `v4.9.1` row => preflight fails naming `v4.9.1` |
| `failure-names-the-generating-command` | CONTROL | the message is actionable on its own |
| `restored-row-passes` | CONTROL | row restored => silent |
| `head-tag-is-exempt` | EXEMPTION | tag at HEAD with no row => not reported |
| `exemption-is-scoped-not-a-mute` | CONTROL | the same run still names `v4.9.1` |

The RED arm caught two defects in the check itself before it could ship:

1. It matched the **whole file** rather than a table row. Line 42 is prose naming `v4.9.0` and
   `v4.9.1`, so a deleted ROW still "matched" and the check reported nothing.
2. The phase cloned the repo and therefore graded the **previous commit**, passing the pre-fix
   preflight while the working tree held the fix.

Both are tripwired at the site. A first cut of the check also added **4m15s** to preflight (grep +
sort per tag over 92 tags); the healthy path is now spawn-free per tag.

## Related

- `release-gate-flaky-job-probe` — the two consecutive RED Windows runs that queued the rows were
  its occurrences; that flake is what exposed this. Fixing the probe removes the trigger, not the
  defect: any future red pair would drop a row again without this check.
- `gate-bounds-lack-headroom` — same family: a release-time invariant whose enforcement depended
  on someone noticing.
