# Problem: a 502 during `fusebase deploy` is misread as a logout and falsely signs users out

**Slug:** `deploy-502-misread-as-logout`
**Filed:** 2026-08-14
**Severity:** high
**Status:** resolved upstream (CLI 0.29.8); Flow's vendored text corrected in T2 of `cli-0298-compatibility`
**Filed by:** AI Developer per FR-15 + the operator's standing rule (a platform-level behavioural finding surfaced by a re-vendor gets a catalog entry)

## Symptom

A Fusebase App boots its auth state from a backend session probe (`GET /api/account/me` or equivalent). While `fusebase deploy` restarts the backend, that probe returns **502/503/504** — or times out on a scale-to-zero cold start. Apps written to the pattern Flow was vendoring treat any non-`403`-business-code failure as "not authenticated": the SPA sets `status: 'anon'`, renders a login screen, and in the worst case clears the session cookie. The user is signed out by a deploy blip, and the httpOnly cookie that would have restored them may already be gone.

Two adjacent misreads of the same class:

| Signal | Naive reading | Actual meaning |
|---|---|---|
| Proxy answers `/api/*` with `302 Location: …/auth/?appSuccess=…` instead of `401` JSON | default `fetch` follows it → cross-origin CORS → `TypeError: NetworkError`, **no status, no body** → "logged out" | invalid/expired session, surfaced as a redirect; needs `redirect: 'manual'` + an `opaqueredirect` branch |
| `getMe` / Gate call returns HTTP status **`0`** | "auth failed" | network/CORS — the request never reached a backend that could judge auth (usually wrong runtime host resolution) |

## Root cause

The session probe returned a **boolean** (authenticated / not) over a **three-outcome** reality: authenticated, definitively rejected, and *no verdict available*. With no state for "the server did not answer", every transport failure collapsed into the `anon` branch — the same branch a real `401` uses. A deploy restart, a cold start, a 5xx, a CORS failure and a genuine logout all became indistinguishable at the call site.

Flow's vendored `handling-authentication-errors` predated the corrected pattern, so Flow was **teaching** the collapsing version. Nothing executed wrongly in Flow itself; the defect was in what Flow told agents to build.

## Why it matters

- A false sign-out during deploy is user-visible data loss (unsaved work) and destroys trust in the app's session handling.
- It is invisible in testing: the happy path and the real-`401` path both behave correctly. Only a deploy, a cold start or a flaky network reproduces it.
- Flow's product is the artifacts agents read. A vendored document that prescribes the collapsing pattern reproduces the defect in every app built from it — the blast radius is every consumer, not one repo.

## Mitigation / workaround

The corrected pattern is a **4-state session verdict** so a deploy blip can never be read as anonymous:

```typescript
type SessionVerdict = 'authenticated' | 'anon' | 'blocked' | 'unknown'
```

| Probe response | Verdict | UI |
|---|---|---|
| `401` | `anon` | login / anon state |
| `403` + known business code (`membership_revoked`, `tenant_suspended`, …) | `blocked` | dedicated blocked screen |
| `403` other, any 5xx, network error, timeout, abort | `unknown` | transient "Can't reach the server" + Retry. **Never** clear the session cookie, never force login |
| `2xx` | `authenticated` | app |

Plus: retry with a deploy-tolerant backoff (`[0, 400, 1200]` ms) before settling on `unknown` — that window survives the pod restart; a timeout on the *first* call after idle or deploy is a cold start, not a logout. Fetch mutations with `redirect: 'manual'` and branch on `res.type === 'opaqueredirect' || res.status === 302`; never retry an opaque redirect on a mutation. Treat status `0` as a host/CORS problem, and never let a failed `getMe` block the whole app load.

## Permanent fix

| Status | Detail |
|---|---|
| Upstream | FuseBase Apps CLI 0.29.8 `handling-authentication-errors` (137 → 293 lines) ships the 4-state verdict, the deploy-tolerant retry, the `302`-not-`401` proxy case and the status-`0` case |
| Flow | `cli-0298-compatibility` T2 (`3d3dcec`) re-vendored the skill to 0.29.8, replacing the text that taught the collapsing pattern |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- Writing or reviewing SPA auth bootstrap, a session probe, an `AuthExpiredModal`, or a global API error handler
- Any `catch` around a session/auth fetch that assigns a logged-out state
- A boolean `isAuthenticated` derived from a network call
- A bug report of the shape "users get logged out during deploys / randomly / on first load after idle"
- A `fetch` to `/api/*` without `redirect: 'manual'` whose failure path assumes auth

## Guardrail (the lesson)

**A probe whose transport can fail must have a state for "no verdict".** Collapsing "the server said no" and "the server did not answer" into one branch is the defect; the number of states in the verdict type must match the number of distinguishable outcomes, not the number the UI happens to render. Absence of evidence is not evidence of absence — and in auth, guessing "absent" is the destructive guess.

Corollary for this framework: a re-vendor is not only a freshness exercise. When upstream's diff encodes a **behavioural** correction rather than expanded prose, the lesson is filed here so it survives the next re-vendor — the vendored text can drift again, this entry does not.

## Related

- `.claude/skills/handling-authentication-errors/SKILL.md` — the corrected 0.29.8 pattern Flow now vendors
- `.claude/skills/app-backend/SKILL.md` § Cold Starts (Scale-to-Zero) — timeout sizing for the retry window
- `docs/specs/cli-0298-compatibility/spec.md` § S5 — the slice that filed this
- `docs/problem-catalog/security-check-fail-open-class/problem.md` — sibling class: a control that guesses "allow" when it cannot decide

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-08-14 | filed | `cli-0298-compatibility` T5; behavioural delta surfaced by the 0.29.8 re-vendor (T2 `3d3dcec`) |
