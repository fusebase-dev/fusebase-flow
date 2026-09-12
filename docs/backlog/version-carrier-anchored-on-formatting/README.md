# version-carrier-anchored-on-formatting

**Status:** open — one carrier fixed and pinned; the second is a DECISION, not a regex widening
**Filed:** 2026-09-11, while fixing the `CLAUDE.md` banner carrier (schema-3 release prep)
**Surface:** `hooks/local/sync-version-strings.sh` `SED_EXPRS`, `hooks/local/lib/partial-upgrade-check.sh` `banner_re`, `hooks/tests/test-sync-allowlist.sh` `LIVE_RE`
**Severity:** low — no wrong value is ever written; a derived string silently stops being derived

## What was found, and what was fixed

`sync-version-strings.sh` rewrites derived strings by matching a CONTEXT anchor. For the banner
the anchor included the **bold markers**: `runs \*\*Fusebase Flow v<semver>\*\*`. This repo's
`CLAUDE.md:3` writes the same sentence unbolded, so the file was in the allowlist, was scanned
on every release, and matched nothing — for seven releases, in the published tree, with no
failing check anywhere. The same shape appeared in all three readers of that phrase: the
rewriter, the partial-upgrade DETECTOR, and the under-reach guard's discovery regex.

**Fixed and pinned** (`fix(T109)`): the markers are optional in all three, `CLAUDE.md` is bolded
and current, and `test-sync-allowlist.sh` now drives the real sweep over a fixture repo carrying
both spellings plus both attestation spellings, asserts both readers see both, and asserts this
repo's carrier is the bolded current version. The row fails on the pre-fix tree with all three
assertions red.

## What is NOT fixed, because widening the regex would be wrong

The skill-count carrier anchors on a literal `(`: `s/\(([0-9]+) canonical/(${SKILL_COUNT} canonical/g`.

| Line | Text | Kind |
|---|---|---|
| `docs/compatibility.md:23` | `68 = 34 canonical (\`flow-skills/\`) x 2 approved provider mirrors` | **LIVE** — derived, not matched today |
| `docs/compatibility.md:81` | `v3.14.1 refresh; 27 canonical Flow skills (flow-skills/), 54 Flow mirrors` | history |
| `docs/compatibility.md:82` | `v3.16.0 refresh; 28 canonical Flow skills (module-size-discipline added)` | history |
| `docs/compatibility.md:86` | `Codex plugin wrapper …; 33 canonical Flow skills, 66 Flow mirrors` | history |

A bare `NN canonical` rewrite would falsify three dated rows **in the same file** as the live one.
So the `(` is not laziness: it is the only thing separating a live count from a historical one,
and it separates them imperfectly — the live row at `:23` is the one it misses. The remedy is a
different mechanism, not a wider pattern. Options, uncosted:

1. A marker on live derived values (`<!-- derived:skills -->` or a trailing `<!-- live -->`),
   matched by the sweep; history carries no marker. Explicit, but it is new syntax in prose.
2. Move the live counts OUT of prose into a generated block the sweep rewrites wholesale.
3. Leave the sweep alone and add a preflight PARITY check: the live count in
   `docs/compatibility.md` must equal `find flow-skills -maxdepth 1 -type d | wc -l`, failing
   the build instead of silently rewriting. Cheapest, and consistent with how plugin metadata is
   already handled (preflight §8 checks, never seds).

Option 3 is the closest fit to the lesson: where content cannot be distinguished from history by
pattern, CHECK it rather than rewrite it.

## Also observed (not a carrier defect; record so it is not rediscovered)

`sync-version-strings.sh` runs under `set -e -o pipefail` and derives `FR_HI` from `FLOW_RULES.md`
and `SKILL_COUNT` from the skills directory through command substitutions. If either is absent the
failing pipeline exits the whole script — rc 2 and rc 1 respectively — **with no message and
nothing rewritten**. Every real tree has both, so this is not live exposure; it cost an hour of
fixture debugging, and a partially-recovered tree would see the sweep look like a silent no-op.
