# Problem: the framework's own CI was silently RED for ~3 releases, and releases published anyway

**Slug:** `ci-red-invisible-no-release-gate`
**Filed:** 2026-07-09
**Severity:** high
**Status:** resolved
**Filed by:** operator (per FR-15, after the v4.2.0 deploy surfaced it)

## Symptom

The v4.2.0 `fusebase-flow-verify` run failed on GitHub Actions. Investigating with the Actions API showed the SAME `verify` job had been failing at step 7 "Hook tests (deterministic fixtures)" on `main` for **v3.31.0 (`d953000`), v4.1.0 (`c401bad`), and v4.2.0 (`2a69660`)** — the framework's own test suite had been red on Linux CI for ~3 releases, and each release was tagged + published regardless.

## Root cause

Three compounding gaps let a red suite ship invisibly:

1. **No in-repo release gate.** Releases were cut with a manual `gh release create` (PUBLISHING.md) that never checked CI. Branch protection was documented as a "prerequisite," not enforced.
2. **The composed suite never completed on MSYS.** `run-tests.sh` on Windows/Git-Bash times out mid-run (fork-storm, see [[run-tests-never-completes-msys]]), so a full local pass was never observed — nobody saw the failures locally either.
3. **CI conclusions were never watched.** `gh` is not installed on the maintainer box, so no one checked the Actions tab; a green-looking local `--fast` verdict was mistaken for a healthy release.

Net: Linux-CI failures (env-specific tests — see [[ci-linux-msys-test-divergence]]) accumulated undetected across releases.

## Why it matters

- Releases shipped to consumers on a **red test suite** — the framework's own quality gate was non-functional AND unmonitored.
- A regression could reach `main` + a published Release with zero signal.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v4.2.0 (`hook-manifest-verify`): **in-repo release gate** — `.github/workflows/fusebase-flow-release.yml`'s `publish` job declares `needs: verify` (verify = the FULL suite via `workflow_call`); a red suite ⇒ `publish` is structurally unreachable ⇒ **no Release object for that tag**. Manual `gh release create` forbidden. Proven live: the first v4.2.0 tag (`2a69660`, red) produced NO Release; only the green `34409e1` published. |
| Shipped | v4.2.0 manifest-verify decoupled the release-health verdict from the slow suite so full HEALTHY is reachable on Windows (the reason (2) existed). |
| Discipline | **Watch CI after every push.** With no `gh`, poll the Actions REST API using the stored git credential: `TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill | sed -n 's/^password=//p')` then `curl -H "Authorization: Bearer $TOKEN" .../actions/runs`. Never treat a local `--fast` verdict as a release signal. |

## Recurrence triggers (so future sessions recognize this)

- The Actions API shows `fusebase-flow-verify conclusion=failure` on recent `main` SHAs.
- Operator says "releases publish even though CI is red" / "CI has been failing for a while and nobody noticed."
- A publish path (`gh release create`, a deploy step) that does not `needs:` a verify job.
- The composed suite cannot complete on a supported platform (so no full local pass is ever seen).

## Guardrail (the lesson)

Gate publication on CI **in-repo** (`publish` `needs: verify`) — never rely on manual release + documented branch-protection alone. **Actively read the CI conclusion after every push** (API-poll if `gh` is absent). And never allow the release-gating suite to be un-completable on a supported OS — an un-runnable suite hides failures as effectively as a missing one.

## Related

- [[ci-linux-msys-test-divergence]] — the four env-specific test failures this red state was hiding.
- [[run-tests-never-completes-msys]] — why the composed suite never completed on MSYS (reason 2).
- `.github/workflows/fusebase-flow-release.yml` — the gated publish job (`needs: verify`).
- `docs/specs/hook-manifest-verify/decisions.md` (D10) — the release-gate design + honest repo-admin-ruleset boundary.
