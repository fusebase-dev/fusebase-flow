# Hook coverage matrix — Fusebase Flow

Lists every Fusebase Flow lifecycle hook handler and which provider / fallback surface invokes it.

## Coverage table

| Hook handler | Anthropic Claude Code | OpenAI / ChatGPT Codex | Git fallback | Local script | Status |
|---|---|---|---|---|---|
| `session_start` | yes (`SessionStart`) | yes (`session_start`) | n/a | `preflight.sh` runs equivalent checks | implemented |
| `user_prompt_submit` | yes (`UserPromptSubmit`; reads both `prompt` (native) and `user_prompt` (Flow-schema) — see § Host field-shape) | yes (`user_prompt_submit`) | n/a | n/a | implemented |
| `pre_tool_use` | yes (`PreToolUse`; matchers: Bash, **PowerShell**, Edit, Write, MultiEdit, NotebookEdit) | yes (`pre_tool_use`; matchers: Bash, **PowerShell**, Edit, Write, MultiEdit) | partial (`pre-commit` blocks at commit time) | n/a | implemented |
| `permission_request` | not wired (`PermissionRequest` is absent from `.claude/settings.json.example`); its reply is not host-valid there — see § Host output shape | yes (`permission_request`) | n/a | `approve-local.sh` authors approval artifacts the handler reads | implemented |
| `post_tool_use` | yes (`PostToolUse`; matchers: Edit, Write, MultiEdit) | yes (`post_tool_use`; matchers: Edit, Write, MultiEdit) | n/a | n/a | implemented |
| `stop` | yes (`Stop`; claim detection reads the final assistant message from `transcript_path` (native) or `agent_message` (Flow-schema) — see § Host field-shape) | yes (`stop`) | partial (`verify-gate.sh` checks pasted gate report shape) | `verify-gate.sh` for ad-hoc validation | implemented |

## Command-tool coverage (E6)

The command arm (FR-06 deny, FR-12 `require_approval`, K4 policy-error fail-closed) reaches
a tool only if BOTH are true: the host matcher routes the event to `pre_tool_use`, AND the
tool name is in `COMMAND_TOOL_NAMES` (`hooks/shared/command_policy.py` — the single set both
`pre_tool_use.py` and `permission_request.py` read). Claude Code exposes a `PowerShell` tool
beside `Bash` on Windows and it was in neither, so the whole command arm was bypassable there
by choosing the other shell tool. Fixed; frozen by fixtures 24/25/26. The protected-path and
secret arms were never affected — they key on Edit/Write.

**Measured residual — patterns are bash-shaped, not shell-aware.** Routing a PowerShell event
to the gate does not make the *rules* PowerShell-aware. Measured against the shipped policy:

| Command shape | Example | Gated |
|---|---|---|
| Shell-agnostic gated commands | `git reset --hard`, `git push --force`, `--no-verify`, `git commit -n`, `core.hooksPath` changes, `npx prisma migrate deploy`, `fusebase deploy` | yes (identical text in both shells) |
| bash destructive form | `rm -rf <path>` | yes |
| PowerShell alias + native flags | `rm -Recurse -Force <path>` | partial — `destructive_file_delete` (FR-12), not the FR-06 deny |
| PowerShell cmdlet / short alias / pipeline | `Remove-Item -Recurse -Force <path>`, `ri -r -fo <path>`, `... \| Remove-Item -Recurse` | **no** |

`policies/command-policy.yml` is shell-agnostic by design and models POSIX `sh`/`bash`; adding
PowerShell-native patterns is rule authoring blocked on decisions D1/D2 in
`docs/backlog/command-gate-shell-evasion/`. Do not read "PowerShell is gated" as "PowerShell-native
destructive commands are denied" — the shell-agnostic majority is, the cmdlet forms are not.

## Host field-shape (per-host input coverage)

Claude Code's native events do NOT use the Flow-schema keys the earlier fixtures injected. Two handlers must read the native field or the gate is inert live:

| Handler | Native Claude Code field | Flow-schema field | Behavior |
|---|---|---|---|
| `user_prompt_submit` | `prompt` | `user_prompt` | reads `user_prompt` **or** `prompt` (dual-key). FR-12 secret warn, bypass-attempt warn, and the `/product-owner` reminder now fire on native `UserPromptSubmit`. |
| `stop` | `transcript_path` (JSONL; final assistant message = the claim) | `agent_message` | claim detection runs against `agent_message` when present, else the **last** assistant message parsed from the tail of `transcript_path` (never the whole transcript — a historical claim phrase does not over-trigger). FR-04/05/14 done/deploy deny + FR-22 recommended-warn now fire on native `Stop`. |

Warns surface via `hookSpecificOutput.additionalContext` (JSON stdout), which reaches the model only in a host-valid reply (§ Host output shape; `stop` is a residual there); deny reasons print to stderr before the non-zero exit (Stop exit-2 semantics feed stderr, not stdout JSON). The deny/warn LOGIC (`CLAIM_PATTERNS`, `BYPASS_PATTERNS`, secret scan, `signal_definitions`) is unchanged — only the INPUT source was fixed.
| `task_complete` | n/a (Stop covers this) | n/a (stop covers this) | n/a | n/a | retired v3.18.0 (handler was wired nowhere; `stop` owns completion gating) |
| `pre_compact` | yes (`PreCompact`) | reserved (host-dependent) | n/a | n/a | implemented |

## Host output shape (v5.11 O22)

`pre_tool_use`, `user_prompt_submit`, `post_tool_use` and `session_start` print one host-valid JSON object (Claude Code hooks reference): Flow's verdict is `flow_decision` (allow / warn / deny / ask), never a top-level `decision` (the host accepts that only as `"block"`). Text for the model goes in `hookSpecificOutput.additionalContext`, text for the user in `systemMessage`. Before O22 the host rejected these replies on every non-blocking run ('Hook JSON output validation failed' → a 'hook error' notice, output dropped; observed in the transcripts of two wired consumer projects, 2026-10-15).

| Handler | allow | warn | deny / ask |
|---|---|---|---|
| `pre_tool_use` | `flow_decision` only, exit 0 | `additionalContext` + `systemMessage`, exit 0 | `permissionDecision` `deny` (exit 2, same line on stderr) or `ask` (exit 0), with `permissionDecisionReason` = the stderr line |
| `user_prompt_submit` | `flow_decision` only | `additionalContext` (secret, bypass, implementation-without-spec, PO reminder); the FR-12 secret warn also sets `systemMessage` | — (never blocks a prompt) |
| `post_tool_use` | `flow_decision` only | FR-07 protected-path warn in `additionalContext`, capped at 5 paths | — |
| `session_start` | the bootstrap summary in `additionalContext` (~900 chars; also on stderr) | not a git repo: `systemMessage` | — |

- **PreToolUse never emits `permissionDecision: "allow"`.** An allow skips the host's permission prompt, so it would auto-approve every tool call no rule matched. Silence leaves the normal permission flow in charge.
- **PreToolUse `ask`** is Flow's verdict for a require-approval command when `on_missing_artifact` is not `deny`. The shipped policy sets `deny` (`policies/approval-policy.yml`) and a local downgrade is refused, so `ask` is unreachable as shipped. A project that reaches it now gets a real prompt, even in auto mode; before O22 the reply was dropped and the call ran.
- **Newly reaching the model:** the SessionStart summary once per session, and the FR-07 PostToolUse warn after every Edit/Write while any protected path differs from `HEAD`.
- **Residual — `stop.py`** (wired as `Stop`) still prints a top-level `decision` (`allow` / `warn` / `deny`). The host rejects its non-blocking replies the same way, so a Stop warn is dropped; a deny still blocks through exit 2 + stderr. The Stop rework is deferred to the minimal-core rebuild, which retires the Stop gate.
- **Residual — `pre_compact.py`** (wired as `PreCompact`) still prints `{"decision": "allow", …}`; the one-line fix is `decision` → `flow_decision`. Outside operator decision 8's four files.
- **Residual — `permission_request.py`** prints a top-level `decision` (`deny` / `ask` / `allow`) and denies by exit 2. It is not wired for Claude Code; if it were, the reply would fail validation and exit 2 is not honored on `PermissionRequest` (a deny needs `hookSpecificOutput.decision.behavior`).
- **Codex:** `.codex/hooks.json.example` wires the same handlers; their reply shape on Codex stays unverified, now including `flow_decision`.
- `hooks/tests/run_hook_tests.py` checks every reply of the four handlers against the per-event host shape and these channel rules (fixtures 27–30 pin one handler each; a synthetic `_host-shape-invariant` row proves the check rejects the pre-O22 shapes). `stop` and `permission_request` replies are not shape-checked (residuals above). Backlog `hook-output-host-validity`.

## Approval-artifact trust model (FR-12)

What the approval gate enforces, and what it deliberately does not. Canonical home: `policies/approval-policy.yml` § trust model (decision K3) — this table is the hook-surface view, not a second source of truth.

| Field | Status | Enforced by |
|---|---|---|
| `schema_version`, `expires_at`, `action` (body vs filename) | **enforced** | `hooks/shared/approval_artifact.py` |
| `command_digest`, `repo_id` | **enforced when present** (absent → action-scoped, K2) | `hooks/shared/approval_artifact.py` |
| `approved_by`, `ticket`, `scope`, `reason` | **audit metadata — never authenticated authority** | nothing; unenforceable (agent and operator share one OS principal) |

`policies/approval-policy.yml: approval_authors` carries `enforced_by_hooks: false`: it is a declaration of intent, not a control. Do not add an `$USER == approved_by` check — it is forgeable by the process it gates.

### Rule matching is regex over the raw command — a guardrail, not a sandbox (K21)

`hooks/shared/command_rules.py::rule_matches` runs `re.search` against the literal command string the hook received. Consequences, stated because the opposite is easy to assume:

| Evasion class | Example | Gated today |
|---|---|---|
| Quote fragmentation | `fusebase de'pl'oy`, `npx prisma mi"grate" deploy` | **no** |
| Dynamic construction | `eval "$CMD"`, `$(printf 'fusebase deploy')`, aliases | **no** |

Both are pre-existing properties of regex-on-raw-command, not regressions, and both are deliberately unfixed this release (K21): the real fix is shell-aware parsing or a conservative deny of dynamically constructed gated commands, tracked in `docs/backlog/command-gate-shell-evasion/`. `hooks/tests/test-command-policy.sh` pins the current behaviour so the future fix flips a red case rather than inventing one. Treat the command gate as defence-in-depth behind process discipline, never as a containment boundary.

## Surface notes

- **Cursor** has no native lifecycle-hook surface in v0.1. Enforcement on Cursor sessions falls back to git hooks (`pre-commit`, `commit-msg`) and operator vigilance.
- **GitHub Copilot / VS Code** has no native lifecycle-hook surface in v0.1 for arbitrary command interception. Same fallback as Cursor.
- **Gemini-style IDE agents** have no documented lifecycle-hook surface in v0.1. Same fallback.
- **Generic local repo workflow** uses git fallback hooks only; no provider event integration.

## Hook event protocol

All handlers read a JSON event from stdin matching `flow_hook_event.schema.json` and write one JSON object to stdout carrying Flow's verdict as `flow_decision` (`stop`, `permission_request` and `pre_compact`: `decision`; see § Host output shape). Hosts that read exit codes also receive `0` (allow), `2` (deny), or `1` (handler error).

## Test coverage

30 deterministic fixtures at `hooks/tests/fixtures/*.json` (plus companion `*.jsonl` transcripts referenced by the stop fixtures 18–21), driven by the **single-process runner** `hooks/tests/run_hook_tests.py`: one python process imports each handler and drives `main()` in-process — same fixtures, same assertions as the retired fork-per-case loop, and a `--compare-subprocess` mode proves in-process ≡ subprocess for the **(exit_code, decision, rule_id)** triple (30/30, run as a permanent CI step). `run-tests.sh` is **tiered**: the bare command is the fast local default (a 9-phase allowlist, ≤10 min, developer feedback only), `FF_FULL=1` is the full unscoped set, `FF_ONLY="a,b"` is scoped. `FF_LIST=1` prints the live phase list — read it there rather than trusting a count in prose. Release evidence is neither: it is the required `verify-linux` + `verify-windows-msys` jobs on the tagged SHA (`PUBLISHING.md` § Release evidence authority), each of which takes the full path automatically and uploads its own `fusebase-flow-audit-<platform>` artifact. A local run writes `state/audit/hook-test-results.md` (gitignored runtime path); a subset run writes `-fast.md` / `-scoped.md` and can never be mistaken for a complete result. Coverage matrix:

| Test | Hook tested | Decision |
|---|---|---|
| 01 | `pre_tool_use` | deny `rm -rf` |
| 02 | `pre_tool_use` | deny `git add .` |
| 03 | `pre_tool_use` | deny `git add -A` |
| 04 | `pre_tool_use` | deny `git reset --hard` |
| 05 | `pre_tool_use` | deny `--no-verify` |
| 06 | `pre_tool_use` | deny `.env` write |
| 07 | `pre_tool_use` | deny deployment-config edit (protected path) |
| 08 | `pre_tool_use` | allow `git status --short` |
| 09 | `stop` | deny "implementation complete" without gate evidence (Flow-schema `agent_message`) |
| 10 | `user_prompt_submit` | warn on pasted GitHub PAT (Flow-schema `user_prompt`) |
| 11 | `pre_tool_use` | deny write that introduces `sk-ant-*` value |
| 12 | `pre_tool_use` | deny Write containing a session cookie (escalated) |
| 13 | `stop` | deny "deploy complete" when live-user verification used but cleanup marker absent |
| 14 | `stop` | allow "deploy complete" with cleanup marker present |
| 15 | `stop` | allow Lightweight-lane deploy-complete (safety floor present) |
| 16 | `stop` | deny Lightweight-lane deploy-complete missing rollback (safety floor) |
| 17 | `user_prompt_submit` | warn on pasted GitHub PAT via **native** `prompt` key (host field-shape) |
| 18 | `stop` | deny done-claim via **native** `transcript_path` (no `agent_message`) |
| 19 | `stop` | allow when done-claim is EARLIER in transcript (no over-trigger) |
| 20 | `stop` | deny **native** corrupt/format-drifted transcript that carries a done-claim but yields no extractable final message (fail-closed) |
| 21 | `stop` | allow **native** corrupt transcript with NO done-claim (no false-deny) |
| 22 | `pre_tool_use` | deny compound command with no approval artifact (K8 all-match) |
| 23 | `permission_request` | deny compound command with no approval artifact (K8 all-match) |
| 24 | `pre_tool_use` | deny FR-06 destructive command via the **PowerShell** tool (E6) |
| 25 | `pre_tool_use` | deny FR-12 require-approval command via **PowerShell**, no artifact (E6) |
| 26 | `permission_request` | deny FR-12 require-approval **PowerShell** request, no artifact (E6) |
| 27 | `pre_tool_use` | allow; host shape: `flow_decision` only, no `permissionDecision` (O22) |
| 28 | `user_prompt_submit` | warn: `/product-owner` reminder reaches the model as `additionalContext`, no `systemMessage` (O22) |
| 29 | `post_tool_use` | allow on a non-edit tool; host shape: `flow_decision` only (O22) |
| 30 | `session_start` | allow; the bootstrap summary in `additionalContext` (O22) |

## Manifest verification & trust model

The health check's critical is a **hook-layer content-hash manifest**, not a re-run
of the test suite. `audit/hook-layer-manifest.json` is a committed, **byte-stable**
manifest (no timestamps — a pure function of the covered file bytes + `VERSION`; the
stamp date is git history) covering the Flow-owned hook layer: `hooks/handlers/*.py`,
`hooks/shared/*.py`, `hooks/git/*`, `hooks/tests/*.sh` + `run_hook_tests.py` +
`fixtures/*`, `hooks/local/*.sh` (excluding operator `*.local.*`), and
`hooks/local/lib/*` (`*.sh` + `hook_manifest.py`). Regenerate with
`bash hooks/local/stamp-hook-manifest.sh`; CI freshness-gates it
(`stamp && git diff --exit-code`).

- **What each layer attests.** The *manifest* attests *this install's Flow hook layer
  byte-matches release X* (a membership proof, not a re-derivation of correctness).
  *CI* attests *release X passes its full hook-test suite on Linux* — the verify job
  runs on `main` pushes/PRs and is re-run on the tagged sha by the release workflow,
  whose Release-creating `publish` job is gated `needs: verify`. Consumer verification
  is a fast hash compare (`bash hooks/local/verify-hook-manifest.sh`, seconds,
  OS-independent) — it also catches **local tampering** that re-running tests does not
  (tampered code can still pass tests).
- **Verifier exit codes:** `0` MATCH · `1` DRIFT (modified/missing/flagged-extra) ·
  `2` BROKEN (corrupt manifest / self-hash mismatch) · `4` ABSENT (pre-upgrade
  install — run `upgrade.sh`). Exit `3` is RESERVED (the engine's public exit 3 =
  EXCEPTION_IN_EFFECT). The health-check maps these to
  HEALTHY / FLOW_LAYER_DRIFT / BROKEN / PARTIAL_UNVERIFIED.
- **Injection surface (two DRIFT scans).** Beyond hashing listed files, verify flags
  UNEXPECTED extras: **Scan A** — any `hooks/handlers/*.py` or `hooks/shared/*.py` not
  in the manifest (the cheapest import-adjacent injection vector); **Scan B** — any
  file named `sitecustomize.py` / `usercustomize.py` at **any** depth under `hooks/`
  (a python startup file runs before any check), with **no exclusions** (`*.local.*`
  and `__pycache__` included), mirroring `policies/protected-paths.yml:93–100`.
- **Self-hash** (`manifest_self_sha256` over version + asset list) detects corruption
  and hand-edits; it is not a cryptographic defense against a recomputing attacker —
  that backstop is the committed manifest + git history + the CI freshness gate.
- **Deep diagnostic (platform-adaptive).** `fusebase-flow-health-check.sh
  --run-hook-tests` optionally runs a deep suite — the FULL `run-tests.sh` on
  POSIX/Linux/macOS, and on MSYS/Git-Bash the FAST subset (single-process fixtures +
  git-smoke + hook-manifest self-test) completing < 120 s. `--run-hook-tests-full` /
  `FFHC_RUN_HOOK_TESTS_FULL=1` forces the full suite on MSYS too. Observed FAIL/crash ⇒
  BROKEN; timeout/skip ⇒ a NOTE only (never forces PARTIAL). Never required for the
  verdict. Both deep paths pass `FF_FULL=1` explicitly: the DEFAULT `run-tests.sh` is the
  FAST LOCAL tier, while CI still takes the full path (it sets `GITHUB_ACTIONS`).

## Audit-log integration

Every hook execution appends a JSONL record to `state/audit.log.jsonl` (gitignored) with: timestamp, event, decision, reason, rule_id, session_id, host_tool, plus event-specific extras. Operators can grep / aggregate audit log post-hoc.

## Last amended

```
2026-05-08 — Phase 4; added GitHub Action verification of hook tests + preflight.
2026-07-03 — Phase C S1; documented per-host field-shape (native `prompt` / `transcript_path` vs Flow-schema `user_prompt` / `agent_message`) — the live enforcement fix. Fixture count 11→19; added rows 12-19.
2026-10-16 — v5.11 O22; host-valid replies from pre_tool_use / user_prompt_submit / post_tool_use / session_start (operator decision 8): `flow_decision`, model text in `additionalContext`, user text in `systemMessage`, never PreToolUse `allow`; runner host-shape check; fixture count 21→30 (26 already shipped); added rows 22-30.
```
