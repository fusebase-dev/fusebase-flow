# Repo context - Fusebase Flow CLI edition

Generated: 2026-07-26
Status: CURRENT
Freshness gate: stale after 2026-10-24 or after major repo restructuring
Consumer: `workflows/session-initiation.md` step 5

## Identity

| Field | Value |
|---|---|
| Project | Fusebase Flow - Fusebase CLI edition |
| Current version | `VERSION` = `4.6.1` |
| Repo kind | Plain-file workflow framework/template, not an app runtime |
| Purpose | Fusebase Flow lifecycle layer packaged with Fusebase Apps CLI provider-domain skills/assets |
| Runtime | Local shell + Python hook handlers; no server, daemon, SaaS, telemetry, or app manifest |
| Python | `.python-version` = `3.12`; hooks require Python 3.11+ |
| Dependency | `pyyaml>=6.0,<7` from `hooks/requirements.txt` |
| Workflow mode | `direct_to_main` (`policies/approval-policy.yml`) |

## Current repo state

| Signal | Value |
|---|---|
| Branch | `fix/msys-v3307-hardening` |
| HEAD | `61f7502` (`docs(closeout): record v4.6.1 deploy hash + post-deploy verification`) |
| Remotes | `origin` -> `https://github.com/fusebase-dev/fusebase-flow.git`; `shared-template` -> `https://github.com/fusebase-dev/fusebase-flow-classic.git` |
| Active handoff | `docs/tmp/handoff.md` | `Mode: run-ledger`, current as of 2026-07-26; ticket `token-floor-remediation` DONE | Dirty state observed | Many untracked formal handoff/smoke files under `docs/tmp/handoff/`; preserve unless operator assigns cleanup |
| Project onboarding docs | `docs/north-star.md`: absent; `docs/en/business-logic.md`: absent; no app `product.md` / `business-logic*` found |

## Topology

| Area | Canonical paths | Notes |
|---|---|---|
| Always-on rules | `FLOW_RULES.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Session starts by reading `FLOW_RULES.md` only down to `## Amendment log` |
| Flow lifecycle skills | `flow-skills/` | Canonical source; mirror with `hooks/local/mirror-skills.sh` |
| Provider skill mirrors | `.agents/skills/`, `.claude/skills/` | Contains 34 Flow mirrors plus 20 CLI provider skills; Flow mirror manifest tracks Flow skills only |
| Flow sub-agents | `agents/` | Canonical source; mirror to `.claude/agents/` and `.codex/agents/` |
| CLI provider assets | `.agents/skills/<cli-skill>/`, `.claude/skills/<cli-skill>/`, `.claude/hooks/`, `.claude/agents/app-*.md`, `.codex/agents/app-*.md` | CLI/domain layer; do not copy into `flow-skills/` |
| Lifecycle workflows | `workflows/` | Full lane, Lightweight lane, handoffs, verification, deploy, recovery |
| Machine policies | `policies/` | Approval, command, protected path, required artifact, secret, module-size, gate schemas |
| Enforcement | `hooks/handlers/`, `hooks/shared/`, `hooks/git/`, `hooks/local/` | Local guardrails plus git fallback hooks |
| Templates | `templates/` | Spec, tasks, decisions, gates, handoffs, reports, change-note |
| Audit manifests | `audit/` | Skill mirror, agent mirror, CLI vendor, hook-layer provenance |

## Commands

| Use | Command |
|---|---|
| Install hook dependency | `pip install -r hooks/requirements.txt` |
| Primary structural validation | `bash hooks/local/preflight.sh` |
| Hook/test suite | `bash hooks/tests/run-tests.sh` |
| Mirror Flow skills | `bash hooks/local/mirror-skills.sh` |
| Mirror Flow agents | `bash hooks/local/mirror-agents.sh` |
| Check health/read-only drift | `bash hooks/local/fusebase-flow-health-check.sh` |
| Check CLI/Flow ownership conflicts | `bash hooks/local/check-cli-flow-conflicts.sh` |
| Check module-size ratchet | `bash hooks/local/check-module-size.sh --all` |
| Adopt module-size baseline | `bash hooks/local/check-module-size.sh --write-baseline` (agent-run only after operator chat go-ahead) |
| Stamp hook-layer manifest after covered hook changes | `bash hooks/local/stamp-hook-manifest.sh` |
| Verify hook-layer manifest | `bash hooks/local/verify-hook-manifest.sh` |
| Sync version strings from `VERSION` | `bash hooks/local/sync-version-strings.sh` |
| Post-CLI-update Flow recovery | `bash hooks/local/post-fusebase-update.sh` |
| Opt-in Flow lifecycle hook wiring | `bash hooks/local/post-fusebase-update.sh --wire-hooks` |
| Upgrade Flow content from `.fusebase-flow-source/` | `bash hooks/local/upgrade.sh` (`--dry-run` for preview) |
| First-hop upgrade for older installs | `bash hooks/local/bootstrap-upgrade.sh -- --auto-yes` |
| Optional Codex prompt installer | `bash hooks/local/install-codex-prompts.sh` |

## Validation defaults

| Scenario | Minimum checks |
|---|---|
| Routine Flow framework change | `preflight.sh`; targeted hook/unit tests; mirror check if skills/agents changed; `check-module-size.sh --all`; `git status --short` |
| Hook/policy/security change | Targeted RED/GREEN where possible; `preflight.sh`; relevant `hooks/tests/*.sh` or `FF_ONLY=<tag> bash hooks/tests/run-tests.sh`; hook manifest stamp/verify when covered paths change |
| Skill/agent change | Edit canonical `flow-skills/` or `agents/`; run mirror script; run `preflight.sh`; confirm manifest drift is zero |
| CLI provider asset refresh | Preserve CLI-owned boundary; byte-identity/parity checks; update `audit/cli-vendor-manifest.json`; run `check-cli-flow-conflicts.sh` |
| Release/publication | `preflight.sh`; `run-tests.sh`; `mirror-skills.sh`; public-surface allowlist; clean git status; tag push lets `.github/workflows/fusebase-flow-release.yml` publish only after verify |
| Windows/MSYS long tests | Prefer scoped `FF_ONLY` while developing; default/full suites can be slow. Do not launch long work without a timeout/watchdog or durable progress record. |

## Protected paths and approvals

| Policy | Current state |
|---|---|
| Hard-denied commands | `rm -rf`, `find -delete`, force push, `git reset --hard`, `git checkout -- .`, `git clean -fdx`, `git add .`, `git add -A`, `--no-verify` |
| Approval-gated commands | production deploys, pushes to main/master in direct-to-main, DB migrations, destructive deletes, customer-visible outbound messages |
| Protected path categories active | env/secrets; deployment config; CI/CD config; Fusebase Flow internals |
| Worker-undisturbed paths | none configured |
| Migration/schema protected paths | none configured |
| Module-size ceiling | 800 source lines |
| Module-size baseline | `hooks/tests/test-cli-flow-recovery.sh` frozen at 954 lines; may shrink, not grow while over ceiling |

## Risk boundaries

| Boundary | Rule |
|---|---|
| CLI-first, Flow-second | `fusebase update` owns CLI provider assets; Flow recovery restores only Flow-owned/shared surfaces |
| Provider mirror edits | Edit canonical Flow source first; mirrors are generated. Do not hand-edit provider Flow mirrors unless debugging drift |
| CLI provider skills | Keep in `.agents/skills/` and `.claude/skills/`; never promote into `flow-skills/` without `skill-authoring` clean-room classification |
| Overlay blocks | `AGENTS.md` / `CLAUDE.md` overlay blocks should stay aligned with `hooks/local/fusebase-flow-overlays/*`; preserve `FLOW:PRESERVE` region |
| Release creation | Do not run `gh release create` manually for normal release; `v*` tag push triggers gated release workflow |
| Approval artifacts | Operator authorizes in chat; owning role runs approval commands. Do not ask operator to type terminal commands as gates |
| Secret scanner | Added-line staged scan excludes designed-token files (`policies/secret-patterns*.yml`, `hooks/tests/fixtures/`); never use whitelist to bypass a real secret |
| Long/silent work | FR-27: timeout/watchdog, completed-in-turn, or durable record pointer before launch |

## Ticket routing

| User ask | First skill/workflow |
|---|---|
| New feature / fix with uncertain scope | `requirements-specification` then `implementation-planning` |
| Small reversible low-risk change | `lightweight-lane`; if any doubt, Full lane |
| UI/product options before lock | `design-discovery-ideation` |
| App runtime/API/dashboard/gate/secrets work | Load relevant CLI provider skill from `.agents/skills/` / `.claude/skills/` plus Flow lifecycle skill |
| Code review | `code-review`; add `security-permissions-review` only on auth, permissions, secrets, env, deploy config, external messages, production data |
| Deployed app backend debugging | `remote-logs`; local app debugging uses `dev-debug-logs` |
| Health/drift question | `fusebase-flow-health-check` |
| Regression/history question | `git-history-diagnostic` |
| Skill creation/import/update | `skill-authoring` |
| Long session stop/resume | `handoff` |

## Backlog signals

| Slug | Status | Why it matters |
|---|---|---|
| `architect-sub-agent` | parked | Dedicated deep-investigation role; PO currently handles Architect escalation inline |
| `role-path-hook-enforcement` | parked | Hook-level role/path gate for PO no-code boundary |
| `adapter-overlay-refresh-parity` | parked | Refresh parity for GEMINI/Copilot/Cursor overlays |
| `fr22-predelegation-hook` | parked | Warn-only predelegation check for comment-policy push block |
| `fr27-prelaunch-nudge` | parked | Warn-only prelaunch liveness nudge |
| `codex-plugin-packaging` | active | `.codex-plugin/plugin.json` packages the Codex skill surface; Product Owner is bridged as a skill rather than a custom slash command |

## AGENTS.md update candidates

Do not apply without operator approval.

| Field | Suggested value |
|---|---|
| Project name | `Fusebase Flow - Fusebase CLI edition` |
| Stack | `Plain-file workflow framework; POSIX shell + Python hook handlers; PyYAML; provider skill/agent mirrors` |
| Workflow mode | keep `direct_to_main` |
| Worker-undisturbed paths | keep `none` |
| Decision letter prefix | keep `A` unless next ticket increments |
| T-counter | keep current value unless planning a ticket |

## Protected-path candidates

Do not apply without operator approval.

| Candidate | Reason |
|---|---|
| `audit/skill-mirror-manifest.txt` | Release-critical mirror integrity manifest |
| `audit/agent-mirror-manifest.txt` | Release-critical agent mirror integrity manifest |
| `audit/cli-vendor-manifest.json` | CLI provider provenance used by conflict diagnostics |
| `audit/hook-layer-manifest.json` | Hook-layer trust manifest |
| `.claude-plugin/plugin.json` | Plugin distribution metadata/version |
| `.claude-plugin/marketplace.json` | Plugin marketplace metadata/version |
