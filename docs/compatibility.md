# Compatibility matrix — Fusebase Flow

The public template targets the following provider / IDE surfaces. **No other compatibility surfaces are claimed.**

| Surface | Files | How operator activates | What works | What does not work yet |
|---|---|---|---|---|
| **Anthropic Claude Code** | `CLAUDE.md`, `.claude/settings.json.example`, `.claude/skills/<56>/SKILL.md` (34 Flow mirrors + 22 CLI provider skills), `.claude/commands/<7>.md` (incl. `/handoff`, `/find-wasted-effort`, `/find-wasted-code`), `.claude/agents/<4>.md` | Open repo in Claude Code; copy `settings.json.example` to `settings.json` if hooks desired | Self-attestation, state-announcement footer, Flow skills auto-loaded by description match, slash commands (`/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort`, `/find-wasted-code`), CLI provider skills available for Fusebase Apps domain work, optional Flow lifecycle hooks plus CLI Stop hooks | Hooks require explicit settings.json activation; active downstream settings must be merged, not overwritten |
| **OpenAI / ChatGPT Codex** | `AGENTS.md`, `.codex/config.toml.example`, `.codex/hooks.json.example`, `.codex-plugin/plugin.json`, `.agents/skills/<56>/SKILL.md` (34 Flow mirrors + 22 CLI provider skills), `.codex/agents/<4>.md` | Open repo in Codex; copy `config.toml.example` to `config.toml`; accept project trust prompt; install/refresh the Codex plugin when using plugin distribution | Self-attestation, state-announcement footer, Flow skills and CLI provider skills available by skill matching/reference, Codex plugin metadata pointing at `.agents/skills/`, `product-owner` skill bridge discoverable by `/product` or `/skills`, command parity via the `AGENTS.md` command-equivalents convention (every agent) plus optional `bash hooks/local/install-codex-prompts.sh` for native `/prompts:<cmd>` (per-machine, namespaced, Codex-deprecated), 6 hook events wired via repo-root-stable paths | Codex may still render plugin provenance before skill names; bare custom `/product-owner` slash-command parity is not a modern Codex plugin feature; project-trust prompt required before hooks load |
| **Cursor** | `.cursor/rules/fusebase-flow-{always,specs,implementation,validation,security}.mdc`, `AGENTS.md` | Open repo in Cursor; rules load automatically | Always-on rule + 4 scoped rules (specs / implementation / validation / security); reads `AGENTS.md` | No native lifecycle hooks in v0.1; enforcement falls back to git hooks + operator vigilance |
| **GitHub Copilot / VS Code** | `.github/copilot-instructions.md`, `.github/instructions/{fusebase-flow,security,validation}.instructions.md`, `AGENTS.md` | Open repo in VS Code with Copilot enabled | Repository-wide instructions + 3 scoped instruction files; reads `AGENTS.md` | No native lifecycle hooks in v0.1; enforcement falls back to git hooks + operator vigilance |
| **Gemini / Antigravity-style IDE agents** | `GEMINI.md`, `AGENTS.md` | Open repo in the host IDE | Always-on baseline via `AGENTS.md` and `GEMINI.md` | No documented lifecycle-hook surface in v0.1; enforcement falls back to git hooks + operator vigilance |
| **Generic local repo workflow** | `AGENTS.md`, `*` (rules, skills, workflows, policies, templates), git fallback hooks, local scripts | Clone repo; install git hooks via `hooks/local/install-git-hooks.sh` | Full rule / workflow / template substrate; git pre-commit and commit-msg enforcement; local approval / preflight / mirror scripts | Provider-specific skill mirrors only useful when paired with Claude Code or Codex; otherwise read canonical `flow-skills/` directly |

## Surfaces explicitly NOT claimed

The public template does not advertise compatibility with any AI coding assistant outside the table above. If a future surface is added, it appears here first.

## Verification

| Check | Result |
|---|---|
| Public-surface grep (case-insensitive, full tree) for non-target tool names | 0 true-positive matches |
| Canonical Flow skill mirror count | 68 = 34 canonical (`flow-skills/`) x 2 approved provider mirrors |
| CLI provider skill count | 44 = 22 CLI provider skills x 2 provider surfaces (FuseBase CLI 0.29.8) |
| CLI provenance | `audit/cli-vendor-manifest.json` `source_cli_version: 0.29.8`, DERIVED from `audit/cli-upstream-manifest.json` (per-file sha256 computed from the source CLI tree by `hooks/local/refresh-cli-vendor.sh`), not asserted |
| Mirror dirs allowed | `.agents/skills/`, `.claude/skills/`; this edition also keeps CLI provider skills in those dirs |
| `mirror-skills.sh` target list | mirrors canonical Flow skills only (source `flow-skills/`) and preserves extra CLI provider skills |
| `preflight.sh` mirror drift check | validates canonical Flow skill mirrors only |
| Hook tests | `bash hooks/tests/run-tests.sh` is the FAST LOCAL DEFAULT (heavy phases skipped, `<=10` min); `FF_FULL=1 bash hooks/tests/run-tests.sh` is the full unscoped set and the only tier that prints the strict `[run-tests] N/N PASS`. Either way a clean run is 0 FAIL; N is the live tier total, not a fixed number |
| Preflight | 0 errors / 0 warnings |
| GitHub Action | runs preflight + hook tests + mirror drift check on `workflow_dispatch` and on the release workflow's call for a tagged SHA — **not** on ordinary pushes / PRs |

## Secret-scan scope (pre-commit + PreToolUse)

The pre-commit secret scan (`hooks/shared/staged_secret_scan.py`, decision D-A1) scans
ONLY added (`+`) lines of the staged diff. Two deliberate scope limits — by design, not bugs:

| Limit | Behavior | Why / legitimate path |
|---|---|---|
| Designed-token files path-excluded | A real secret added inside `policies/secret-patterns.yml`, `policies/secret-patterns.local.yml`, or `hooks/tests/fixtures/` is NOT caught by the commit scan | Those files hold fake example tokens that otherwise self-trip the scanner. Don't store real secrets there. PreToolUse / UserPromptSubmit still scan freely. |
| PreToolUse self-trip on full `secret-patterns.yml` writes | An agent that writes the FULL `secret-patterns.yml` content via Edit/Write can trip the PreToolUse scanner on the file's own fake example tokens | Known limitation. Legitimate path: stage the edit and commit (pre-commit path-excludes that file); the commit scan is the authoritative gate for it. |

To get a real-secret BLOCK past pre-commit: rotate the credential + `git reset HEAD -- <file>` to unstage. NEVER add a `whitelist:` entry — a non-empty whitelist disables a pattern globally and breaks fixtures 10/11.

## Windows / Git-Bash (MSYS)

Full `bash hooks/local/fusebase-flow-health-check.sh` (no flags) reaches
**HEALTHY / exit 0 on stock Windows + Git-Bash**: the CRITICAL is a hook-layer
**manifest verify** (one python hash pass over ~100 files — seconds, OS-independent),
not a re-run of the fork-heavy test suite. `--fast` / `--skip-hook-tests` stay the
quick escape (they skip the integrity critical ⇒ PARTIAL_UNVERIFIED / exit 4, never 0).

**Installed-CLI version (S1, cli-0298-compatibility):** exactly ONE condition is
verdict-affecting - an installed CLI **below `0.29.0`** is `CLI_VERSION_UNSUPPORTED` /
exit 1, the one claim backed by evidence (verified at `0.25.16`). An installed CLI matching
the bundled snapshot (`0.29.8`) contributes `HEALTHY`. Everything else - newer, older,
unreadable, a probe that exits non-zero, or `fusebase` not on PATH (CI runners, containers,
any machine that only edits the framework) - is a **verdict-neutral advisory, exit 0**.
Newer is deliberately not a failure: a full `fusebase update` rewrites the adopter's provider
skills from their own CLI, so their documents are correct and only Flow's review status is
unknown. See `flow-skills/fusebase-flow-health-check/SKILL.md` § Installed-CLI version gate.

`--run-hook-tests` is an OPTIONAL deep diagnostic and is **platform-adaptive**: on
POSIX/Linux/macOS it runs the FULL `hooks/tests/run-tests.sh` suite (as before); on
MSYS/Git-Bash it runs the FAST subset — single-process fixtures + git-wrapper smoke +
manifest self-test — completing in **< 120 s** (measured ~52 s end-to-end incl. the
base health check). This is the AC3 resolution: the MSYS full suite (~950–1085 s —
bash-surface phases like `liveness` / `secret-scan` / `bootstrap` cost tens of seconds
each under MSYS spawn overhead) is impractical as a Windows default gate. The full MSYS
suite stays reachable via `--run-hook-tests-full` or `FFHC_RUN_HOOK_TESTS_FULL=1`, and
the authoritative full-suite green is the CI pair `verify-linux` + `verify-windows-msys`
(`fusebase-flow-verify`) on the tagged SHA — neither platform alone. Both deep paths pass
`FF_FULL=1` explicitly, because the
DEFAULT `bash hooks/tests/run-tests.sh` is now the FAST LOCAL tier on all platforms; CI
still takes the full path (it sets `GITHUB_ACTIONS`).

## Last amended

```
2026-05-27 - v3.1 Fusebase CLI edition matrix; reflects 14 Flow skills plus 19 CLI provider skills.
2026-06-07 - v3.14.1 refresh; 27 canonical Flow skills (flow-skills/), 54 Flow mirrors, 16/16 hook tests, /handoff slash command added.
2026-06-10 - v3.16.0 refresh; 28 canonical Flow skills (module-size-discipline added), 56 Flow mirrors, 22/22 hook tests (16 fixtures + 6 FR-25 gate scenarios), module-size pre-commit step added to git fallback.
2026-06-10 - v3.16.2 hardening; 24/24 hook tests (8 gate scenarios), template ships its own FR-25 baseline (gate live by default), CI --all step, additive-only local override, --write-baseline <path> re-key.
2026-06-29 - FuseBase CLI 0.25.9 re-vendor; 20 CLI provider skills (adds app-api-contract-testing), 40 CLI mirrors (20 x 2). The 0.25.9 Stop set wires run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js (run-typecheck-apps.js shipped but unwired); the merge is preserve-only.
2026-07-07 - FuseBase CLI 0.25.16 re-vendor; 7 provider skills refreshed (magic-link activation now platform-server-side, apps[].id declarative-optional, gate SDK ^v2.3.28-sdk.1); fusebase-gate drops isolated-sql-stores.md + isolated-sql-rls-plan.md, adds isolated-sql-integrator-troubleshooting.md; manifest 132->130 assets. Wired Stop set unchanged.
2026-07-11 - Codex plugin wrapper + `product-owner` skill bridge; 33 canonical Flow skills, 66 Flow mirrors.
2026-08-14 - Adopt the 2 CLI skills Flow lacked: app-e2e-tests, invite-with-password. 20 -> 22 CLI provider skills, 40 -> 44 mirrors, manifest 138 -> 142 assets. invite-with-password checked against the vendored fusebase-auth.md / handling-authentication-errors deltas before merge: purely additive (same 403-on-FBS_FEATURE_TOKEN, 409-once, needsInitialPassword semantics fusebase-auth.md already documents), no contradiction.
2026-08-14 - FuseBase CLI 0.29.8 guarded re-vendor (hooks/local/refresh-cli-vendor.sh); manifest 130->138 assets, source_cli_version unknown->0.29.8 (derived from the source tree, not asserted). Fixes: app-sidecar `--app <appId>` -> `<appPath>` (0.29.8 matches --app by local path only), and 40 unrendered `<%=` ETA interpolations across 12 vendored files -> 0. app-architect.md now requires visitor/public-link uploads to broker through a feature backend using FBS_FEATURE_TOKEN. Both Flow-authored CUSTOM:SKILL blocks were SUPERSEDED: 0.29.8 ships the same titled sections as supersets, correcting `client:<clientId>` -> `client:<productId>`. Health check gains a CLI version gate whose only hard failure is an installed CLI below 0.29.0; the bundled snapshot is 0.29.8 and every other state is a verdict-neutral advisory. Wired Stop set and the 4 quality hooks unchanged.
```
