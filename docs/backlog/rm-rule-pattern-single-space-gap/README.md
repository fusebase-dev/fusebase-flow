# rm-rule-pattern-single-space-gap

**Status:** parked
**Found:** 2026-07-28, while implementing `approval-binding-and-upgrade-classification` T4 (K16 consequence assertion)
**Surface:** `policies/command-policy.yml` — the `destructive_file_delete` `require_approval` rule
**Severity:** medium — an FR-12 gate that does not fire on the most common form of the gated command

## Defect

Pattern: `'\brm\s+(-r|-rf|-fr)?\s+'`

The flag group is optional but the trailing `\s+` is not, so a plain `rm <path>` with a single
space matches nothing. Reproduced 3/3 (FR-10):

| Command | Matches | Gated? |
|---|---|---|
| `rm build.log` | no | **NO** — ungated |
| `rm -f build.log` | no | **NO** — ungated (`-f` is not in the flag alternation) |
| `rm ./a ./b` | no | **NO** — ungated |
| `rm  build.log` (two spaces) | yes | yes |
| `rm -r build/` | yes | yes |

`rm -rf` is unaffected — it is caught earlier by the `deny` stage, which short-circuits.

## Why it was not fixed in-ticket

Out of scope for `approval-binding-and-upgrade-classification` (FR-11 / IM don't-list): that ticket
changes rule **evaluation** semantics, not rule **content**. Widening the pattern changes which
commands are gated for every consumer and deserves its own lane + release note. The T4 test asserts
the K16 all-match consequence with `rm -r build/`, a form the shipped rule does match, so it tests
all-match rather than the pattern.

## Proposed fix

Replace with something like `'\brm\b(?!\s*-rf)\s+(-[A-Za-z]+\s+)*\S'` — i.e. `rm` followed by any
argument, flags optional. Must be checked against false positives (`npm rm`, `git rm`, `charm`) and
against the `deny`-stage `rm -rf` rule so the two do not double-report.

## Acceptance sketch

- `rm build.log`, `rm -f build.log`, `rm ./a ./b` all require `destructive_file_delete`.
- `rm -rf x` still hits the `deny` stage first (rule_id `FR-06`), never `require_approval`.
- `git rm x` / `npm rm pkg` are NOT gated as destructive file deletes.
