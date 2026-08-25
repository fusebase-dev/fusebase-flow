# `hooks/` — local lifecycle hooks

Hooks here are **local guardrails** invoked by IDE/agent runtimes (Claude Code, Codex, and other providers/IDEs that support local hook surfaces) and by git. They are NOT external HTTP/webhook services — there is no network surface in v0.1.

## Layout

```
hooks/
├── README.md                      ← this file
├── flow_hook_event.schema.json    ← unified event schema all handlers accept on stdin
├── handlers/                      ← Python lifecycle handlers
│   ├── session_start.py
│   ├── user_prompt_submit.py
│   ├── pre_tool_use.py
│   ├── permission_request.py
│   ├── post_tool_use.py
│   ├── stop.py
│   └── pre_compact.py
├── shared/                        ← reusable utilities
│   ├── policy_loader.py
│   ├── audit_logger.py
│   ├── git_utils.py
│   ├── secret_scanner.py
│   ├── path_policy.py
│   ├── command_policy.py
│   ├── command_rules.py           ← rule shape: pattern/flags/action|any_of
│   ├── denial_message.py          ← the one FR-12 denial renderer (both entry points)
│   └── approval_artifact.py       ← the one approval-artifact judge (every carrier)
├── git/                           ← git fallback hooks (bash; symlinked into .git/hooks/)
│   ├── pre-commit
│   └── commit-msg
├── local/                         ← local helper scripts (agent- or operator-run)
│   ├── install-git-hooks.sh
│   ├── preflight.sh
│   ├── verify-gate.sh
│   ├── approve-local.sh            ← authors artifacts; --inventory reports them
│   ├── stamp-managed-content-manifest.sh   ← records the upgrade classifier's base
│   ├── verify-managed-content-manifest.sh  ← 0 MATCH / 1 DRIFT / 2 BROKEN / 4 ABSENT
│   └── mirror-skills.sh
└── tests/                         ← deterministic test fixtures
    ├── run-tests.sh
    └── fixtures/
        └── *.json                 ← input fixtures with expected outputs
```

## Event protocol

Every handler reads a JSON event from stdin matching `flow_hook_event.schema.json`, applies its policy, and writes a JSON response to stdout. The host's compatibility file (`.claude/settings.json.example`, `.codex/hooks.json.example`, etc.) is responsible for normalizing the host's native event shape into this schema before calling the handler.

### Standard input shape

```json
{
  "event": "pre_tool_use",
  "session_id": "abc-123",
  "cwd": "/path/to/repo",
  "host_tool": "claude_code",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /tmp/foo" }
}
```

### Standard output shape

```json
{
  "decision": "deny",
  "reason": "FR-06: rm -rf is in command-policy.yml deny list.",
  "rule_id": "FR-06",
  "audit_event_id": "..."
}
```

| Decision | Meaning |
|---|---|
| `allow` | Allow the action. Handler may have logged or warned via stderr. |
| `deny` | Block the action. Reason printed to stderr; host tool surfaces to operator. |
| `ask` | Ask operator for explicit confirmation (only for `permission_request` event). |
| `warn` | Allow, but include a warning. Decision is `allow` but `reason` is surfaced. |

### Exit codes (for hosts that read exit codes only)

- `0` — allow
- `2` — deny (Claude Code convention; host-specific shim translates if needed)
- `1` — handler error (host should treat as allow with warning, not deny)

## Provider-specific compatibility files

| Provider / surface | Compatibility file | Calling convention |
|---|---|---|
| Anthropic Claude Code | `.claude/settings.json.example` | reads `hookSpecificOutput.permissionDecision` for PreToolUse |
| OpenAI / ChatGPT Codex | `.codex/hooks.json.example` + `.codex/config.toml.example` | requires `codex_hooks = true` and project trust |
| git | `hooks/git/*` | copied into `.git/hooks/` by `install-git-hooks.sh` |
| Other providers | route via `AGENTS.md` + git fallback hooks | host-specific shim, when host supports stdin/stdout hook handlers |

## Consumer-authored hooks (your own hook beside Flow's)

If you wire your own enforcement hook — a veto, a composed security gate — three host behaviours govern the shared surface, and the third is security-relevant:

| # | Host behaviour | Consequence for your hook |
|---|---|---|
| 1 | Hooks in a matcher group run **in parallel** | Order is not a control — never assume your hook runs after Flow's, or that it sees Flow's result |
| 2 | **Deny takes precedence** | Any denying hook blocks the call, so yours need not be first, and Flow's allow never overrides your deny |
| 3 | A hook that **cannot start, or that exceeds its configured `timeout`, is NON-BLOCKING** — the host fails open | A hung, crashed or slow security hook does not deny: the tool call proceeds, and nothing in your hook's own output says it was abandoned |

Fact 3 is what turns a security hook into decoration. So a consumer security hook must **bound its own runtime well below its configured `timeout`** with its own watchdog — the reporting consumer's veto bounds itself at **≤8 s under `timeout: 20`**, and that ratio is the shape to copy — and must **convert every local failure into a deny** (exit 2), never an error exit and never a silent fallthrough: missing interpreter, unreadable policy, unexpected exception all deny. Flow's own handlers follow the same rule; `docs/problem-catalog/security-check-fail-open-class/problem.md` records what it costs when they don't.

**Source of the three claims.** Read from the Claude Code hooks reference by the consumer who filed them (their strength label: `INFERRED`). Fusebase Flow has **not** measured host fail-open-on-timeout in its own suite — treat these as documented host behaviour, not a Flow-verified result, and check your own host's hook documentation before relying on them on another surface.

## Audit log

Every handler appends a JSONL event to `state/audit.log.jsonl` (gitignored). Rotation is the operator's responsibility (e.g., a periodic move to `audit.log.<date>.jsonl`).

## Running tests

```bash
bash hooks/tests/run-tests.sh
```

Tests feed fixtures from `tests/fixtures/*.json` into each handler and compare output against expected. Phase 3 ships 11 fixtures; see `tests/run-tests.sh` for the matrix. Tests do NOT require network and run in <5 seconds total.

## Clean-room note

All handlers, shared utilities, git fallback hooks, and local scripts here are original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md` (Phase 4).

## Limitations

- **Pre-tool-use is a guardrail, not a complete security boundary.** A malicious prompt could find ways to phrase commands that bypass regex matching. The git fallback hooks are a second line; the operator's vigilance is the third.
- **Project trust is required.** Codex and Claude Code load project-local hooks only when the project is trusted by the operator. Hooks do not run in untrusted-project mode.
- **Host coverage varies.** Not every host implements every lifecycle event. See `docs/hook-coverage.md` (Phase 4) for the current support matrix.
