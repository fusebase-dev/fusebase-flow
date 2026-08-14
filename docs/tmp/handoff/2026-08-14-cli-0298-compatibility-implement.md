# AI Developer handoff — CLI 0.29.8 compatibility

**Spec (authoritative, read it first):** `docs/specs/cli-0298-compatibility/spec.md`
**Branch:** create `fix/cli-0298-compatibility` off `main` (`9b45a9e`)
**Reference tree (READ-ONLY, never write to it):** `c:/tmp/apps-cli-latest/apps-cli-main` — FuseBase Apps CLI **0.29.8**
**Reviews behind this plan:** Codex 5.6 Sol High (CLI delta, `/c/tmp/cli-compat-out.md`) · Fable 5 (plan, `/c/tmp/plan-review-fable.md`, `SOUND-WITH-FIXES`, corrections already applied to the spec)

FR-03: **one task = one commit**. Stop at the verification gate (IM.8) and report. Do not push, do not tag,
do not bump `VERSION`. No protected path is in scope — if you find yourself needing to edit
`hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`, `policies/*.yml`, `.github/workflows/**` or
`FLOW_RULES.md`, STOP and report instead of minting an approval.

## Shipping unit

**T1 + T2 + T3 are one release** and must all land before this is releasable. T1 alone would stamp a
manifest claim the tree does not yet satisfy. T4 and T5 may trail. Build in the order below — T1 first
is required so T3's RED arm can prove the check catches the pre-re-vendor state.

## Ground truth already verified — do not re-derive, trust these

| Fact | Evidence |
|---|---|
| CLI is 0.29.8; Flow vendored at 0.25.16 | `package.json:58`; `docs/compatibility.md:24` |
| `--app` resolves by local `apps[].path` ONLY | `lib/commands/sidecar.ts:99-102`, `lib/commands/secret-create.ts:14-17` |
| Flow's `app-sidecar` wrongly says `--app <appId>` | `.claude/skills/app-sidecar/SKILL.md:29,54,60` |
| 20 `<%=` occurrences / 6 files, mirrored → 12 files / 40 occurrences | `grep -rl '<%=' .claude/skills/ .agents/skills/` |
| 0.29.8 ships ZERO `<%=` anywhere in its tree | verified across `project-template`, `feature-templates`, `managed-template`, `lib` |
| 3 files carry `CUSTOM:SKILL` blocks (×2 surfaces = 6) | `app-dev-practices/SKILL.md`, `file-upload/references/upload-lifecycle.md`, `fusebase-flow-health-check/SKILL.md` |
| `mirror-skills.sh` mirrors skills ONLY, not `.codex/agents/` | `MIRRORS=( ".agents/skills" ".claude/skills" )` |
| 4 CLI quality hooks + Stop wiring are byte-identical/correct | `cmp`; `.claude/settings.json.example` |

## T1 — CLI version check with a real verdict (S1)

Build the check; **do NOT stamp the manifest version here** (that lands in T2).

- Probe the installed CLI at health-check time (`fusebase --version`).
- Verdict contract, exactly:
  - in range → **HEALTHY**
  - **below** the reviewed floor → **NOT HEALTHY** (Flow's docs are known-incompatible with what is installed)
  - **above** the ceiling, version unreadable, or `fusebase` not on PATH → **`PARTIAL_UNVERIFIED` (exit 4)** — the existing "a critical check did not run" bucket, `fusebase-flow-health-check/SKILL.md:96-98`
- Every non-green outcome states three things: version found, reviewed range, next step. Below floor → the command to run. Above ceiling → supply the new CLI tree for review.
- **Only** the version check becomes verdict-affecting. `CLI_SNAPSHOT_STALE`, `CLI_CUSTOM_AT_RISK`, `CLI_STOP_UNVERIFIED`, `CLI_STOP_BASELINE_DRIFT` stay advisory — turning four signals into blockers at once reds every adopter's first run.
- Above-range must NOT be a hard red: the CLI ships ~4 minors per 5 weeks and Flow always trails it. A red with a remediation that cannot work yet trains operators to widen the range unreviewed, which kills the check. Exit 4 also keeps CI and this maintainer repo (no `fusebase` installed) from being permanently red.

**Oracle — RED-first, prove each arm:** simulated `0.25.16` → NOT HEALTHY naming the range; `0.29.8` → HEALTHY; simulated `0.30.0` → exit 4; unreadable version → exit 4; no `fusebase` on PATH → exit 4. Never silently green, never hard red above range.

## T2 — guarded re-vendor of every manifest asset (S2)

Scope is **every asset in `audit/cli-vendor-manifest.json`** — 20 skills **plus** vendored agents
(`.claude/agents/`, `.codex/agents/`: `app-architect.md`, `app-create-checker.md`).

- **Never `cp -r` blind.** Three-way: take 0.29.8 content, preserve every `CUSTOM:SKILL` block byte-for-byte.
- `app-architect.md`'s delta is behavioural, not cosmetic: visitor/public-link uploads must broker through a feature backend using `FBS_FEATURE_TOKEN`, never storing file bytes in isolated SQL.
- Agents need their own copy step — `mirror-skills.sh` will not carry `.codex/agents/`.
- Stamp `source_cli_version: 0.29.8` + T1's reviewed range here, retiring the `"unknown"` sentinel.
- **Derive provenance, don't assert it:** record each file's hash computed from the **0.29.8 source tree**, not from our own copy, so `CLI_SNAPSHOT_STALE` distinguishes "matches upstream" from "matches whatever we shipped". CUSTOM-block files are merge-derived — mark them exempt from exact-match rather than pretending they match.
- Re-mirror skills (`mirror-skills.sh`), re-stamp (`stamp-cli-provenance.sh`).

**Verify after:** `--app <appId>` gone from `app-sidecar`; `<%=` count is **0** across all vendored surfaces; all 3 CUSTOM blocks byte-identical to before; agent files match 0.29.8 source hashes.

**Oracle — prove preservation by deletion:** in a scratch copy delete a CUSTOM block, confirm the refresh keeps/restores it, and confirm a blind copy WOULD have dropped it. Byte-compare all three blocks before and after.

## T3 — `<%=` tripwire (S4)

- Assert **no vendored asset contains `<%=`** — every path named in `audit/cli-vendor-manifest.json` (`.claude/`, `.agents/`, `.codex/`; skills *and* agents). Drive it from the manifest, not from a hardcoded directory list, so it follows the manifest as it grows.
- **RED-first:** reintroduce one occurrence → fails naming the file; remove → passes.
- Add as a test phase in `hooks/tests/`, wired into `run-tests.sh` like other phases.

## T4 — adopt the 2 missing skills (S3, may trail)

Add `app-e2e-tests` and `invite-with-password` to both provider surfaces. Counts **20 → 22** skills,
**40 → 44** mirrors; update `docs/compatibility.md` and the provenance manifest.
`invite-with-password` is auth-adjacent — read it against the `handling-authentication-errors` deltas
before assuming it is purely additive; if it contradicts anything Flow ships, report rather than merge silently.

## T5 — problem-catalog entry (S5, may trail)

Record the platform-level finding: a **502 during `fusebase deploy` is misread as a logout**, falsely
signing users out. The corrected pattern is a 4-state session verdict
(`authenticated | anon | blocked | unknown`) so a deploy blip is never treated as anonymous; also the
proxy-returns-`302`-not-`401` case and `getMe` status `0` (CORS, not auth).

Follow the shape of `docs/problem-catalog/security-check-fail-open-class/problem.md` (header fields,
Symptom, Root cause, Why it matters, Mitigation, Recurrence triggers, Guardrail). T2 fixes the vendored
text; T5 records the incident class so the lesson survives the next re-vendor.

## Explicitly do NOT

- Bulk-copy CLI skills (destroys the 3 CUSTOM blocks, incl. a full "Consuming Another Fusebase App's API" workflow)
- Make the other four CLI advisories verdict-affecting
- Touch the 4 quality hooks or the Stop wiring — verified correct
- Re-vendor the 9 byte-identical skills — nothing to apply
- Change CLI behaviour; Flow owns what it *says* about the CLI, not the CLI

## Gate report must include

Per-task: the commit SHA, the RED-then-GREEN evidence for T1/T2/T3 (the actual failing output, not a
claim it failed), the `<%=` count before and after, byte-comparison of the 3 CUSTOM blocks, and
`preflight.sh` + full-suite results. If any oracle cannot be made to fail first, say so plainly rather
than reporting a green you cannot account for.
