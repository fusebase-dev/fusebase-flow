# FuseBase Apps CLI 0.29.8 compatibility

**Status:** SPECIFIED — adversarial review of the plan complete (Fable 5, `SOUND-WITH-FIXES`, `/c/tmp/plan-review-fable.md`); corrections applied. Ready for implementation planning.
**Opened:** 2026-08-14
**Trigger:** operator supplied `apps-cli-main (1).zip` = `fusebase-apps-cli` **0.29.8**; Flow vendored its CLI-owned assets at **0.25.16** (`docs/compatibility.md` 2026-07-07 entry). Four minor versions.
**Analysis:** Codex 5.6 Sol High adversarial review of the CLI delta (`/c/tmp/cli-compat-out.md`), every load-bearing claim re-verified locally before this spec was written. The plan itself then survived a second adversarial review (Fable 5), which confirmed B1/B2/F1 and corrected the shipping unit, the above-range verdict, the S2 scope, and the provenance derivation.

## Verdict

**PARTIALLY-BROKEN.** Nothing Flow *executes* against the CLI is broken. What is broken is what Flow
*teaches* — and this framework's product is the artifacts agents read, so a document that instructs a
failing command is a product defect, not a typo.

## Established — verified locally, not taken on trust

### Intact (do not touch)

| Surface | Evidence |
|---|---|
| 4 CLI quality hooks (`quality-check-apps.js`, `run-lint-on-stop.sh`, `run-typecheck-apps.js`, `run-typecheck-on-stop.sh`) | byte-identical to 0.29.8 (`cmp`) |
| Stop-chain wiring + `enabledMcpjsonServers` | `.claude/settings.json.example` preserves all 3 CLI Stop hooks in order; MCP server list matches exactly |
| Every CLI command Flow invokes | all 22 top-level commands still present in `index.ts` |

Command *removal* was the obvious failure mode and it did not happen. The real damage is in flags and
resolution semantics.

### B1 — Flow documents an `--app` value the CLI can no longer resolve

CLI 0.29.8 matches `--app` by **local `apps[].path` only**, stated in its own source:

- `lib/commands/sidecar.ts:99-102` — *"`--app` is matched by local `path` only — consistent with `fusebase job`"*
- `lib/commands/secret-create.ts:14-17` — *"`--app` is matched by local `path` (no platform id yet)"*

Flow's vendored `app-sidecar` still says `--app <appId>` (lines 29, 54, 60). An agent following it
passes a platform ID to a matcher that compares against paths. **It does not error usefully — it
reports the app as not found**, which reads as a missing app rather than a wrong argument.

### B2 — Flow ships unrendered template source as instructions (not in Codex's findings)

Flow's vendored copies contain raw ETA template syntax:

```
fusebase secret create --app <%= it.flags?.includes("declarative-manifest") ? "<appPath>" : "<appId>" %> --secret "KEY:description"
```

**20 occurrences across 6 files**, mirrored to `.agents/` — **12 files (6 × 2 surfaces), 40 occurrences (20 × 2)**:

`app-backend/SKILL.md` · `app-secrets/SKILL.md` · `app-sidecar/SKILL.md` · `fusebase-cli/SKILL.md` ·
`fusebase-gate/references/app-magic-links.md` · `fusebase-gate/references/fusebase-auth.md`

**CLI 0.29.8's `project-template` contains ZERO `<%=` occurrences** — it ships rendered output. Flow
vendored from a pre-render source. Two of the six are auth references, so the contamination sits on
the sign-in / magic-link surface.

This is worse than staleness: the reader is not given outdated instructions, it is given *program
source for a template engine* and must guess which branch applies.

### F1 — the health check cannot fail on an incompatible CLI

- `audit/cli-vendor-manifest.json:4` — `"source_cli_version": "unknown"`, described in the file itself as `UNVERIFIABLE_LOCALLY` and *"freshness is advisory only"*.
- `fusebase-flow-health-check/SKILL.md:86` — `CLI_SNAPSHOT_STALE`, `CLI_CUSTOM_AT_RISK`, `CLI_STOP_UNVERIFIED`, `CLI_STOP_BASELINE_DRIFT` are *"informational only — they do not change the verdict or exit code."*

So `/fusebase-health` returns **HEALTHY** against any CLI version, including one whose flag semantics
Flow's own documents contradict. Four minor versions drifted with nothing asserting anything. This is
the defect that let B1 and B2 exist unnoticed, and it outranks both.

### Stale (real, not urgent)

11 of the 20 shared skills drifted; 9 are byte-identical.

| Skill | Lines | Note |
|---|---:|---|
| `app-backend` | 769 → 975 | +206 |
| `handling-authentication-errors` | 137 → 293 | **+156, auth/session/token surface** |
| `fusebase-cli` | 709 → 809 | +100 |
| `app-dev-practices` | 271 → 332 | +61, carries a CUSTOM block |
| `fusebase-portal-specific-apps` | 34 → 65 | +31, portal authorization caveats |
| `app-sidecar`, `app-secrets`, `api-exploration`, `file-upload`, `fusebase-dashboards`, `fusebase-gate` | small | — |

New supporting references Flow lacks: `fusebase-gate/references/{portals,portals-create,portal-theme-variables}.md`, `fusebase-dashboards/references/members.md`.

Absent skills: **`app-e2e-tests`**, **`invite-with-password`** (22 in CLI, 20 in Flow).

Not only skills: `audit/cli-vendor-manifest.json` also vendors agent assets — `.claude/agents/` and
`.codex/agents/` (`app-architect.md`, `app-create-checker.md`). **`app-architect.md` has drifted with a
behavioural delta**, verified by hash against 0.29.8: the current CLI requires visitor/public-link
uploads to broker through a feature backend using `FBS_FEATURE_TOKEN` and never store file bytes in
isolated SQL. Flow's vendored copy predates that rule.

### Other surfaces — verified clean, do not re-investigate

`.codex/`, `.cursor/`, `.github/`, and `GEMINI.md` contain no `<%=` and no `--app <appId>`; the
manifest confirms vendored assets live only under `.agents/`, `.claude/`, and `.codex/`.
`feature-templates/` and `managed-template/` are CLI scaffolding Flow never vendors (and carry zero
template syntax anyway). Verified during the plan review — a future reader does not need to re-check.

### The risk that makes the obvious fix dangerous

Three files carry `<!-- CUSTOM:SKILL:BEGIN -->` blocks — Flow-authored content inside CLI-owned files,
mirrored to both surfaces (6 files total):

- `.claude/skills/app-dev-practices/SKILL.md` — a full *"Consuming Another Fusebase App's API"* workflow (Gate operation discovery, contract-first integration)
- `.claude/skills/file-upload/references/upload-lifecycle.md`
- `.claude/skills/fusebase-flow-health-check/SKILL.md`

**A blind `cp -r` from 0.29.8 destroys these.** The existing `CLI_CUSTOM_AT_RISK` advisory exists
precisely to warn about this and cannot stop it, because it does not change the exit code.

## Slices

Ordered by risk retired per unit of work. **Shipping unit: S1 + S2 + S4 ship as ONE release.** S1 is
not independently shippable: shipped alone, the manifest would assert `0.29.8` provenance over a tree
still carrying 0.25.16-era templated skills — health goes green for a 0.29.8 adopter while Flow still
teaches `--app <appId>`, converting today's honest `"unknown"` into a false claim. S1-first remains
correct as **build** order (the RED-first oracle needs the check to exist before the re-vendor proves
it catches the old state); the version stamp itself lands with S2. S3 and S5 may trail separately.

### S1 — the health check must be able to fail on CLI version

**Why first (build order):** F1 is the reason B1/B2 survived four releases. Re-vendoring without it makes today's
tree look current and silently rebuilds the same gap at 0.30.0. Codex named this as the single most
likely way this work is wasted, and it is right.

**Secondary wasted-work risk (value cap, not a blocker):** in consumer repos the CLI's own
refresh/update rewrites these skills from its current `project-template` — Flow's own doctrine routes
CLI-owned drift to the CLI refresh first — so vendored freshness mostly matters in the
install-to-first-refresh window. This caps S2/S3's value; it does not nullify it (CUSTOM-block
preservation and the S4 tripwire retain value regardless).

- Define the **reviewed-compatible range** and build the check. The manifest stamp itself (`source_cli_version: 0.29.8` + the range, retiring the `"unknown"` sentinel in `audit/cli-vendor-manifest.json`) lands with S2's re-vendor — stamped before the tree actually matches 0.29.8, the manifest would lie.
- Probe the installed CLI version at health-check time (`fusebase --version`).
- Verdict contract: **in-range → HEALTHY**; **below the reviewed floor → NOT HEALTHY** (Flow's documents are known-incompatible with what is installed); **above the reviewed ceiling, version unreadable, or `fusebase` not on PATH → `PARTIAL_UNVERIFIED` (exit 4)** — the health contract's existing "a critical check did not run" bucket (`fusebase-flow-health-check/SKILL.md:96-98`). Every non-green outcome carries the version found, the reviewed range, and the next step. "Unknown must not be healthy" still holds — exit 4 is not exit 0.
- **Why above-range is exit 4, not NOT HEALTHY:** the CLI moves ~4 minors per 5 weeks and Flow's vendoring is operator-supplied zips — Flow will always trail. A hard red on every CLI release day, with a remediation command that cannot work yet (no Flow release has reviewed the new version), is a treadmill; the predictable operator response — widening the range without review — would neutralize the check. Exit 4 also keeps CI and this maintainer repo itself (no `fusebase` on PATH) from being permanently red.
- **Internal-facing UX (operator + agent):** the failure text must state the three facts an operator needs — the CLI version found, the range Flow was vendored against, and the next step (below floor: the one command to run; above ceiling: supply the new CLI tree for review). No new flags; the escape hatch is the existing advisory posture, kept for the *pre-existing* advisories so this change does not turn four signals into four blockers at once.
- **Bound the blast radius:** only the version check becomes verdict-affecting. `CLI_SNAPSHOT_STALE`, `CLI_CUSTOM_AT_RISK`, `CLI_STOP_*` stay advisory. Turning them all fail-closed at once would make every adopter's first health run red.

**Oracle:** RED-first — with a simulated `0.25.16` CLI the check must report NOT HEALTHY and name the range; with `0.29.8` it must be HEALTHY; with a simulated `0.30.0`, an unreadable version, or no `fusebase` on PATH it must be `PARTIAL_UNVERIFIED` (exit 4) naming version, range, and next step — never silently green, never hard red.

### S2 — guarded re-vendor of every `cli-vendor-manifest.json` asset to 0.29.8

Fixes B1, B2, the auth/portal staleness, and the drifted agents in one pass, because 0.29.8 ships
rendered content. Scope is **every asset in `audit/cli-vendor-manifest.json`** — the 20 shared skills
**plus** the vendored agents (`.claude/agents/` and `.codex/agents/`: `app-architect.md`,
`app-create-checker.md`) and any other manifest surface. The agent delta is behavioural, not cosmetic:
0.29.8's `app-architect.md` requires visitor/public-link uploads to broker through a feature backend
using `FBS_FEATURE_TOKEN` and never store file bytes in isolated SQL.

- Three-way refresh: take 0.29.8 content, **preserve every `CUSTOM:SKILL` block byte-for-byte**.
- Stamp the manifest here: `source_cli_version: 0.29.8` + the S1 reviewed range, retiring `"unknown"` (see S1 — the stamp must not land before the tree matches it).
- **Derive provenance, don't assert it:** `stamp-cli-provenance.sh` hashes the *local* files — self-referential; the version claim would be asserted, never derived. Record each file's hash **computed from the 0.29.8 source tree**, so `CLI_SNAPSHOT_STALE` can distinguish "matches upstream 0.29.8" from "matches whatever we shipped". Files carrying CUSTOM blocks are merge-derived and exempt from exact-match — note them as such.
- Re-mirror skills to `.agents/` (`mirror-skills.sh`), re-stamp `stamp-cli-provenance.sh`. Verified: `mirror-skills.sh` mirrors **skills only** (`.agents/skills/`, `.claude/skills/`) — it does not handle `.codex/agents/`; the agent assets need their own copy step.
- Verify afterwards: `--app <appId>` gone from `app-sidecar`; `<%=` count is **0** across all vendored surfaces; all 3 CUSTOM blocks present and unchanged; agent files match the 0.29.8 source hashes.

**Oracle:** the CUSTOM-block preservation must be proven by deletion — remove a block in a scratch copy, confirm the refresh restores/keeps it, and confirm a blind copy would have dropped it. Byte-compare the three blocks before and after.

### S3 — adopt the 2 missing skills (may trail the S1+S2+S4 release)

Add `app-e2e-tests` and `invite-with-password` to both surfaces; counts move **20 → 22** skills and
**40 → 44** mirrors; update `docs/compatibility.md` and the provenance manifest.

`invite-with-password` is auth-adjacent — check against the `handling-authentication-errors` deltas
before assuming it is purely additive.

### S4 — a tripwire so B2 cannot recur (not in Codex's list)

The template contamination shipped because nothing asserts that vendored assets are *rendered*.

- Add a test: **no vendored asset may contain `<%=`** — every path named in `audit/cli-vendor-manifest.json`, which today spans `.claude/`, `.agents/`, and `.codex/` (skills *and* agents), not just the two skill dirs.
- RED-first: reintroduce one occurrence, watch it fail naming the file; remove it, watch it pass.

Same shape as the fingerprint-row invariant closed today — an invariant that holds by assertion
rather than by remembering.

### S5 — problem-catalog entry: deploy 502 misread as logout (may trail; not folded into S2)

CLI 0.29.8's `handling-authentication-errors` documents a platform behaviour Flow currently teaches
wrongly: a **502 during `fusebase deploy` is misread as a logout**, falsely signing users out. The
new skill prescribes a 4-state session verdict (`authenticated | anon | blocked | unknown`) precisely
so a deploy blip is not treated as anonymous, plus the proxy-returns-`302`-not-`401` case and the
`getMe` status `0` case (CORS, not auth). Flow's vendored copy predates all of it, and
`docs/problem-catalog/` has **no** entry for this.

- Add a `docs/problem-catalog/` entry recording: the platform-level problem, the pattern Flow was teaching, and the corrected 4-state pattern.
- Follow the existing structure of entries under `docs/problem-catalog/` (e.g. `security-check-fail-open-class/problem.md`: header fields, Symptom, Root cause, Why it matters, Mitigation, Recurrence triggers, Guardrail).
- S2 fixes the vendored skill text; S5 records the incident class so the lesson survives the next re-vendor. They are separate deliverables.

## Explicitly NOT doing

| Not doing | Why |
|---|---|
| Bulk `cp -r` of CLI skills | destroys 3 CUSTOM blocks including a full Gate-integration workflow |
| Making all four CLI advisories verdict-affecting | every adopter's first health run goes red on pre-existing conditions |
| Touching the 4 quality hooks or the Stop wiring | verified byte-identical and correctly wired |
| Re-vendoring the 9 byte-identical skills | no change to apply |
| Changing CLI behaviour | Flow does not own the CLI; Flow owns what it says about it |

## Platform-level note

`handling-authentication-errors` (+156) and the 2 contaminated auth references sit on sign-in,
magic-link and session-token behaviour. If S2 surfaces a **behavioural** change (not merely expanded
documentation), it is a platform-level finding and gets a `docs/problem-catalog/` entry per the
operator's standing rule. Documentation growth alone does not qualify. One such behavioural change is
already confirmed — the deploy-502-misread-as-logout pattern — and is carried as **S5**; any further
behavioural deltas S2 surfaces get their own entries.

## Surface classification

All of this is **internal** — operator and agent facing. No client/end-user UI is involved. The one
interface being changed is the `/fusebase-health` report, whose users are the operator and the agent
reading it; S1's design constraint is therefore legibility and actionability of the failure text, not
visual design.
