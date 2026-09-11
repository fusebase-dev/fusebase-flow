# Backlog — prune-base-omit-count-double-value

**Status:** open — cosmetic stderr noise, guard behaviour correct
**Source:** found while reviewing the T96 EOL-classification diff (2026-09-11); out of that outcome's scope, filed instead of fixed.
**Lane (when picked up):** Lightweight (one line, one shell contract, existing `n6-truthful-base` coverage).

## Defect

| Field | Value |
|---|---|
| Site | `hooks/local/lib/truthful-base.sh:69` (`fftb_prune_base`) |
| Trigger | `$omit` is `/dev/null` or an empty file — the ordinary case on every upgrade that omits nothing |
| Observed | `[: 0\n0: integer expected` on stderr, once per `[ "$n" -gt 0 ]` evaluation (two call sites, `:73` and `:79`) |
| Expected | no diagnostic; `n` holds one integer |
| Behaviour impact | none — `[` fails, so `|| return 0` still takes the "nothing omitted" branch |

## Cause

```sh
n="$(grep -c . "$omit" 2>/dev/null || echo 0)"
```

`grep -c .` on an empty file prints `0` **and** exits 1, so the `||` arm also runs and `n` becomes `0\n0`. The
substitution strips only trailing newlines, not the embedded one.

Reproduced: `printf '' > e; n="$(grep -c . e || echo 0)"; [ "$n" -gt 0 ]` → `[: 0\n0: integer expected`.

## Fix shape

Take one value, not two — e.g. `n="$(grep -c . "$omit" 2>/dev/null)"; n="${n:-0}"` with the rc discarded, or
`n=$(grep -c . "$omit" 2>/dev/null); [ -n "$n" ] || n=0`. Keep `/dev/null` as the absent-file fallback at `:68`.

## Coverage

`n6-truthful-base` already drives `fftb_prune_base`; it asserts the reported counts, not the absence of stderr
noise. A fix should add one row asserting an empty omit file produces no `integer expected` on stderr.

## Family check (do this before patching)

`grep -c` with `|| echo 0` is the general shape. Sweep the other `hooks/local/**` call sites for the same
pattern before touching this one — `undecided-contract-drives-repeat-defects` is the standing lesson.
