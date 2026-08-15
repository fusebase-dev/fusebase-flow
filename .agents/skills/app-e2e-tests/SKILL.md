---
name: app-e2e-tests
description: "Author and run environment-aware Playwright e2e tests for this Fusebase project. Use when: 1. Adding or scaffolding e2e tests (fusebase scaffold --template e2e), 2. Converting a manually verified scenario into a Playwright spec, 3. Running the same test set against dev and prod environments, 4. Wiring test users/fixtures per environment."
---

# App E2E tests (environment-aware)

One suite in `tests/e2e/`, same specs against every environment of the
project. Environments (`fusebase env`) supply everything varying between
stages: base URLs, org/app ids, test users.

When e2e is being added as part of an environment migration, first follow the
local guide **App Environment Migration Guide**, then use this skill for the
Playwright harness and CI details.

When adding e2e to an existing project, first follow the local guide
**E2E Playwright Setup Guide**: audit environments, prefer non-prod targets,
warn before any prod run, scaffold from the CLI template, and wire GitLab CI.

## Scaffold

```bash
fusebase scaffold --template e2e --dir tests/e2e
cd tests/e2e && npx playwright install chromium
FUSEBASE_ENV=<env> npm test
```

## Layout — one project per app

`playwright.config.ts` generates **one Playwright project per app** in
`fusebase.json` (`name` = the app's `key`, falling back to `subdomain`), each
pinned to that app's env-effective URL. Specs live in:

- `specs/common/**` — universal specs, run for EVERY app, app-aware via
  `test.info().project.name`.
- `specs/<appKey>/**` — that app's own specs.

**Adding an app:** give it a short `key` in `fusebase.json` (e.g. `probe`),
`mkdir specs/<key>`, add specs, add the key to the CI matrix `APP` list. Run a
single app with `--project=<appKey>`.

**Cross-app / portal flows** (registration → access propagation across apps +
portal) span more than one app and have NO single baseURL — they do not
belong to any app's project. Put them in `specs/integration/`; the config
adds an `integration` project whose specs build each app's URL via
`appBaseUrl(env, key)`. Add `integration` to the CI matrix `APP` list.
Recipes: `examples/cross-app-access.spec.ts`, `examples/portal-access.spec.ts`.
(Product-scoped magic links + one org = shared session across app subdomains,
which is exactly what these flows assert.)

## Non-negotiables

1. **Stage guard stays.** `specs/common/stage.spec.ts` asserts each app's
   deployed `fusebase-env.json` matches the target env AND app. Never delete
   it — a run against the wrong stage/app is worse than no run.
2. **No hardcoded env data.** Hosts, org/app ids, credentials come only from
   `helpers/env.ts` (`environments/<name>.json` + `.env.<name>`) and the
   project's `baseURL`. A spec that embeds a URL or id silently breaks on
   another environment or app.
3. **Fixtures self-skip.** Use the `fixtureUser(env, key)` + `test.skip`
   pattern (see `examples/role-matrix.spec.ts`) so specs stay runnable while
   fixtures roll out per env.
4. **Cleanup.** Tests that create data must delete it — prod-test environments
   are real orgs.
5. **No secrets in git.** Passwords via `PW_USER_<KEY>_PASSWORD` in
   `.env.<name>` locally / CI variables in pipelines. Reports and traces are
   gitignored.

## The first run after a deploy hits a cold backend

This suite runs against a cold backend (skill **app-backend** § Cold Starts). A
first-request timeout is therefore not flakiness — `playwright.config.ts` is already
sized for it; do not paper over it with `retries` or per-call `timeout:` overrides.

## Before minting magic links: pin the app's access principals

`createAppMagicLink` appends a **user principal** to the app
(`addToAccessPrincipals` defaults to true). If the app's principal list was
EMPTY (platform default = "open for org roles"), that first append flips the
semantics to "ONLY the listed principals" — locking out the owner and
everyone else (`Access Denied` on `/_auth/`). Field incident, not a theory.

Fix/prevention: give the app explicit principals **before** the first
magic-link test run, e.g.

```bash
fusebase app update <appId> --env <name> \
  --access=orgRole:owner,orgRole:manager,orgRole:member,orgRole:client
```

(add `visitor` for public envs). Fixture users keep access via
`orgRole:client`.

## Converting a manual QA scenario into a spec

When the user (or QA) describes a manually verified scenario:

1. Identify the **role** it runs under → fixture key (add the identity to
   `environments/<name>.json` `fixtures.testUsers` if missing; ask the human
   to set the password secret — never invent or commit one).
2. Write one spec per behavior; assert **role-differential** outcomes: what
   this role must see AND what it must not (403/absence assertions catch the
   platform's fail-open regressions, which are the expensive ones).
3. Prefer stable selectors: `data-testid` in app code (add them when missing)
   over text/CSS. The env panel exposes `fbs-env-panel*` test ids.
4. On failure, surface triage data: response status + body and the
   `x-request-id` header in the assertion message where relevant.
5. Run against dev first, then the prod-test env:
   `FUSEBASE_ENV=dev npm test && FUSEBASE_ENV=prod-test npm test`.

## Reports / CI

`reports/<env>.json` is the machine-readable result per environment — the
contract for any CI is `FUSEBASE_ENV=<env> npm test`. Ready-made templates
ship in `tests/e2e/ci/`: `gitlab-e2e.yml` (copy the job into the root
`.gitlab-ci.yml`) and `github-e2e.yml` (copy to `.github/workflows/e2e.yml`).
CI has no dotenv files — the harness falls back to process env, plain or
env-suffixed (`GATE_MCP_TOKEN_DEV`, `PW_USER_CLIENT_PASSWORD_PROD_TEST`).
Keep protected environments on schedules/manual runs. Central publishing to
the platform registry is planned as `fusebase test publish`.
