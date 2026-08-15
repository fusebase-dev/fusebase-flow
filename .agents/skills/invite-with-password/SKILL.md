---
name: invite-with-password
description: "Build an app-owned account UI — your own sign-up/login form and your own password setup and reset — instead of handing users to platform auth pages and platform emails. Use when the app invites people in (addOrgUser / createAppMagicLink) and they must end up with a password they chose: the invitee sets it inside your form (needsInitialPassword + setFusebaseInitialPassword) and signs in with loginFusebaseUser, no 'Trying to reset your password?' email in the middle."
---

# Invite With Password

## When to use this

The app owns its account UI: a custom login form, a custom onboarding screen, its own password
setup and reset — the user never leaves the app and never sees a Fusebase auth page. Typical asks:
"invite my clients into the portal app", "our own branded sign-in", "let them pick a password when
they accept the invite".

Without this, an invited user has no password they know, so the only way in is the platform's
"Trying to reset your password?" email — nonsense for somebody who never registered, and it drops
them onto a platform page in the middle of your onboarding. `setFusebaseInitialPassword` is what
makes an app-owned form possible: the invitee sets their first password inside the app.

The **reset** half of app-owned auth is a different op: `requestFusebaseRestoreKey` mints a restore
key without sending the platform email, so the app can send its own branded reset mail — see
`fusebase-gate/references/fusebase-auth.md` § Password Restore. This skill covers the first
password only.

## Flow

Invite → invitee opens the app through the magic link → app shows a **Create your password** form →
the account signs in with email + password from then on. No platform email beyond the invite itself.

Both pre-provisioning paths — `addOrgUser` (`orgRole: 'client'`, `autoConfirmClientInvite: true`) and
`createAppMagicLink` (`addToAccessPrincipals: true`) — create an account holding a **random password the
user never learns**, which is why the invitee needs `setFusebaseInitialPassword` to get one they know.

1. **Invite** — app backend, `process.env.FBS_FEATURE_TOKEN`: `addOrgUser` or `createAppMagicLink`.
2. **Open** — invitee clicks the link, the platform activates it, the app host gets the invitee's
   `fbsfeaturetoken`. Do the mandatory magic-link exchange first (`fusebase-gate/references/fusebase-auth.md`).
3. **Detect** — SPA reads `needsInitialPassword` from `/auth/context`. `true` = this account has never had a
   password → render the password form. Absent/`false` → do not offer it.
4. **Set** — app backend forwards the **invitee's own** token to Gate. `FBS_FEATURE_TOKEN` gets `403`.
5. **Sign in right away** — a `200` mints no session and drops every existing session of the account,
   including the magic-link one, so log the user back in with the password from the same form.

```typescript
// SPA — step 3
const ctx = await fetch('https://app-api.{FUSEBASE_HOST}/v4/api/auth/context', {
  headers: { 'x-app-feature-token': appToken },
}).then((r) => (r.ok ? r.json() : {}))
if (ctx.needsInitialPassword) showCreatePasswordForm(ctx.user.email)

// App backend — steps 4 and 5, on POST /api/account/set-initial-password
const GATE = 'https://app-api.{FUSEBASE_HOST}/v4/api/proxy/gate-service/v1'
const userToken = c.req.header('x-app-feature-token') || getCookie(c, 'fbsfeaturetoken')

const res = await fetch(`${GATE}/auth/fusebase/set-initial-password`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', 'x-app-feature-token': userToken },
  body: JSON.stringify({ password }),
})
if (res.status === 409) return c.json({ error: 'password_already_set' }, 409)
if (!res.ok) return c.json({ error: 'set_password_failed' }, 502)

// the magic-link session is gone now — sign in with the password we just set
const auth = new FusebaseAuthApi(createClient({ baseUrl: GATE })) // no token: visitor-safe op
const login = await auth.loginFusebaseUser({ body: { email, password } })
if (login.status === 'challenge_required') return handleChallenge(login.challenge)
// set login.session.sessionId as the app-domain cookie, then redirect to login.redirectPath
```

## Limits

- **One-shot.** A second call returns `409` with `errorCode: fusebase_password_already_set`. That means the
  account already has a password its user chose — route to sign-in or password restore, never retry.
- **Acts on the caller only.** The body is `{ password }`; there is no `email` and no `:orgId`, so an app can
  never target another account. Authz is identical to `getMyOrgAccess` — user context, no extra app grant.
- **Platform flag `password_invite`.** Off on the target backend → `403`. Keep password restore as the
  fallback path.
- **No SDK method yet** — `@fusebase/fusebase-gate-sdk` does not expose `setFusebaseInitialPassword` yet, so
  call the documented endpoint with `fetch` (the AGENTS.md "documented endpoint" exception). Switch to
  `FusebaseAuthApi.setFusebaseInitialPassword` once `sdk_describe` shows it.
- **Older accounts** provisioned before the platform started marking password-less accounts report
  `needsInitialPassword: false`; they use password restore.
