# self-granting-health-deferral

**Status:** DONE 2026-08-05 (Lightweight lane — [`docs/changes/2026-08-05-self-granting-health-deferral.md`](../../changes/2026-08-05-self-granting-health-deferral.md)). validate-and-reject (`re.fullmatch` on `[A-Za-z0-9._-]{1,120}`, never sanitized), NUL-delimited transport, `find -print0` traversal, rejections surfaced via the visibility-only `APPROVAL_WARNINGS`. All four acceptance criteria met.

> Red arm on the old lib reproduced the self-grant exactly: the ticket's payload yielded **two** entries, `[harmless_id]` and `[claude_md_overlay]`. End-to-end through the shipped lib, the hostile entry is rejected and reported while the honest sibling `mirror_drift` still defers.

**Status was:** parked — real defect, small fix, not blocked on anything
**Filed:** 2026-08-04, found in passing while implementing `compat-approval-surfacing`
**Severity:** medium-high — an artifact can suppress a health finding it was never authorized to suppress
**Predates:** `382a05e` (untouched by the v4.7.1 work; NOT a regression)

## The defect

`hooks/local/lib/active-approvals.sh` extracts `deferred_checks` from a
`health_check_deferral-*.json` artifact with a small Python block that prints **one check_id per
line**, and bash reads that stream back with `while IFS= read -r cid`.

A check_id is artifact-controlled text. A single JSON element containing a newline therefore
becomes **two** bash entries:

```json
{ "action": "health_check_deferral",
  "expires_at": "2099-01-01T00:00:00Z",
  "deferred_checks": ["harmless_id\nclaude_md_overlay"] }
```

```
DEFERRED_CHECKS count=2
  deferred=[harmless_id]
  deferred=[claude_md_overlay]     <- never granted; a canonical check_id
```

`claude_md_overlay` is a real check_id, so `record_drift` reclassifies that finding to
`LOCAL_DEFERRED`. **This moves the health verdict to `EXCEPTION_IN_EFFECT` and the exit code to 3**
— an artifact granting itself the authority to hide a finding.

Observed, not reasoned: the probe above is the actual output of the shipped lib.

## Why it matters

`DEFERRED_CHECKS` is one of the few artifact-derived inputs that genuinely **moves the verdict**.
Everything else in the approval-reporting path is visibility-only by construction (M9's
`APPROVAL_WARNINGS[]`). This is the exception, and it is the one that was unguarded.

## The fix — validate-and-reject, never repair

**Do not sanitize by deleting disallowed characters.** That was attempted during the parked
surfacing work and is itself a defect: deletion *manufactures* identifiers.

```
'claude\n_md_overlay'  --delete-disallowed-->  'claude_md_overlay'   # a canonical check_id
```

The correct rule: a check_id must **full-match** the identifier charset (`[A-Za-z0-9._-]+`) and be
used **unchanged**, or be **rejected and reported**. Never coerce a nonconforming value into a
conforming one — the repaired value can collide with a real identifier, which is strictly worse
than dropping it.

Suggested shape:

1. In the extraction block, emit a check_id only if `re.fullmatch(r'[A-Za-z0-9._-]{1,120}', cid)`.
2. A rejected entry is **not silent** — surface it (an artifact carrying a malformed check_id is a
   finding about that artifact, not a no-op).
3. Prefer a NUL-delimited or JSON-array transport over newline-delimited so the protocol cannot be
   split by content at all. Same applies to the `find`-based artifact traversal (`-print0`), where
   a newline in a *filename* splits the record before any sanitization runs.

## Acceptance

- The payload above yields **one** entry, and that entry is **not** `claude_md_overlay`.
- `claude\n_md_overlay`, `claude\t_md_overlay` and `c\0laude_md_overlay` are each **rejected**, not
  folded into the canonical id (the collision test, and the one the parked work's own test missed).
- A well-formed multi-entry `deferred_checks` still populates `DEFERRED_CHECKS` and
  `EXCEPTION_IN_EFFECT` still classifies — the deferral feature is unchanged for honest artifacts.
- A malformed check_id is reported, not silently dropped.

## Related

- `docs/backlog/compat-approval-surfacing/README.md` — parked ticket where this was found; carries
  the same validate-and-reject and NUL-delimited-traversal requirements. **This ticket is not
  blocked on that one** and can be fixed independently.
- `docs/problem-catalog/security-check-fail-open-class/problem.md` — sibling class: a guard that
  admits what it should refuse.
