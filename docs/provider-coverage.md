# Provider coverage: Claude Code and Codex

The core's mechanisms work from provider-neutral signals: files under `state/`, `git`, and the typed return as a file. A provider hook is an extra signal, never the only one (handoff section 4a). This page replaces 5.x's `docs/hook-coverage.md`; it lives in the core repository and is not installed into projects. Status as of 6.0.0-m3: a fixture is `maintainer/tests/test_scripts.py`, run with no audit line and no provider hook wired; "run" means a real project slice on that provider, of which there is none yet for the scripts.

| Element | Provider-neutral form (required on both) | Claude Code adds, when wired | Codex adds, when wired | Status |
|---|---|---|---|---|
| Git hooks: secret scan, protected paths, module size, lint and typecheck | Git pre-commit and commit-msg; identical on both | nothing | nothing | Claude Code: measured in release 1 (27 of 29 blocks). Codex: unproven, no run |
| Deny list and tool-time approvals | Git fallback blocks at commit time | `PreToolUse` | `pre_tool_use` | Not in 6.0.0-m3 (hook wiring deferred). Codex: unproven |
| Audit line | none; the audit line is a hook product | `PostToolUse`, `PostToolUseFailure` | `post_tool_use` | Not in 6.0.0-m3 (hook wiring deferred) |
| Heartbeat reader (`hooks/local/reader.py`) | Heartbeat files under `state/audit/liveness/`, the git index mtime, the last commit time, mtimes under `state/`; alerts on silence from those alone; writes `state/status.line` | the audit line as a fourth signal | the audit line | Fixture passes with no audit line (Reader). Claude Code: no run. Codex: unproven, no run |
| Typed returns (`state/returns/<slice>.json`) | A JSON file the agent writes before it ends its turn; `done.py` and `checks.py` read it | the subagent's final message may carry the same content | the same file; a reader's return via `codex exec -s read-only --output-schema <schema.json> -o state/returns/<slice>-<role>.json` under `bounded_run` | Fixture (Done, Checks). Codex: unproven, no run |
| DONE check (`hooks/local/done.py`) | `git log` and the returns file | nothing | nothing | Fixture (Done). Same on both by construction; Codex: unproven, no run |
| Evidence-row validator (`hooks/local/validate_evidence.py`) | The evidence file, the captures, the run logs, `state/deploys/`, `state/runs/` and `policies/evidence-classes.yml` | nothing | nothing | Fixture (Validator). Codex: unproven, no run |
| Checks (`hooks/local/checks.py`) | `git diff` and `git show`, the manifests, the returns file, `phases.md` | the audit line could count calls; not read yet | the same | Fixture (Checks). Codex: unproven, no run |
| Slicer (`hooks/local/slice.py`) | The four documents, `policies/agent-tools.yml`, `state/status.line` | nothing | nothing | Fixture (Slicer). Same output on both by construction; Codex: unproven, no run |
| Gate (`hooks/local/gate.py`) | The three checks above and the ledger's verdict records | nothing | nothing | Fixture (Gate). Codex: unproven, no run |
| Reader as an agent | `agents/reader/AGENT.md`, tools Read, Glob, Grep | a subagent with that allowlist | not a canonical agent: `codex exec -s read-only` is the mechanism (Flow team finding, 2026-10-16) | Codex: unproven, no run |
| Hook wiring | `install --wire-hooks`, per provider, opt-in | merges into `.claude/settings.json` | writes `.codex/hooks.json` | Not in 6.0.0-m3: `state/status.line` reads `unenforced` for both |

Codex support is claimed only after one slice of the first consumer phase runs on Codex through the same core. Until then: Codex: unproven.
