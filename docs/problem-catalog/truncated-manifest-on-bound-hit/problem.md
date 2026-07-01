# Problem: release commit shipped a truncated skill-mirror manifest

**Slug:** `truncated-manifest-on-bound-hit`
**Filed:** 2026-07-01
**Severity:** medium
**Status:** resolved
**Filed by:** PO per FR-15 (self-inflicted mistake, roadmap §4.1)

## Symptom

Release commit `bbaf53a` shipped a duplicated/truncated `audit/skill-mirror-manifest.txt`; corrected post-deploy in `12a543f`.

## Root cause

`sync-version-strings.sh` hit its run bound mid-write on the manifest, AND repeated `mirror-skills.sh --check` calls — a flag that DID NOT EXIST at the time, so each invocation silently ran a FULL mirror (write mode) — raced the version sweep concurrently. Two writers to one generated file under a bound → duplicated + truncated output staged into the release.

## Why it matters

- A truncated manifest defeats the drift gate it exists to power (`mirror-skills.sh --check`, preflight §5) — the release ships with a broken integrity check.
- A bound-terminated write to a generated file is invisible: the file looks present, just wrong.

## Mitigation / workaround

1. Never stage a bound-terminated generated file — verify `raw == unique == expected` line counts before staging.
2. Verify 0 mirror drift (`mirror-skills.sh --check`) before committing any manifest.
3. Never run a generator concurrently with another writer to the same file.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `12a543f` (manifest corrected); `mirror-skills.sh --check` real read-only mode added in v3.30.3 G1 (WS3) |

## Recurrence triggers (so future sessions recognize this)

- A generated file (`audit/skill-mirror-manifest.txt`, baselines) is about to be committed after a bounded generator run.
- `mirror-skills.sh` invoked WITHOUT confirming `--check` is a real read-only flag (it is, since v3.30.3 — earlier it was not).
- Two scripts writing the same generated file in one turn.

## Guardrail (the lesson)

There is no substitute for verifying a generated artifact's line integrity (`raw==unique==expected`) + 0 drift BEFORE committing it; a bound-hit mid-write leaves a plausible-looking but corrupt file. Tool flags must be verified against source before being relied on (see `inaccurate-consumer-prompt`).

## Related

- `docs/problem-catalog/inaccurate-consumer-prompt/problem.md` — sibling self-mistake (assert-without-verify).
- `hooks/local/mirror-skills.sh` — the `--check` read-only drift mode (v3.30.3).
