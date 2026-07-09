# Hook coverage matrix — Fusebase Flow

Lists every Fusebase Flow lifecycle hook handler and which provider / fallback surface invokes it.

## Coverage table

| Hook handler | Anthropic Claude Code | OpenAI / ChatGPT Codex | Git fallback | Local script | Status |
|---|---|---|---|---|---|
| `session_start` | yes (`SessionStart`) | yes (`session_start`) | n/a | `preflight.sh` runs equivalent checks | implemented |
| `user_prompt_submit` | yes (`UserPromptSubmit`; reads both `prompt` (native) and `user_prompt` (Flow-schema) — see § Host field-shape) | yes (`user_prompt_submit`) | n/a | n/a | implemented |
| `pre_tool_use` | yes (`PreToolUse`; matchers: Bash, Edit, Write, MultiEdit) | yes (`pre_tool_use`; matchers: Bash, Edit, Write, MultiEdit) | partial (`pre-commit` blocks at commit time) | n/a | implemented |
| `permission_request` | reserved (returned `ask` decision honored when host invokes) | yes (`permission_request`) | n/a | `approve-local.sh` authors approval artifacts the handler reads | implemented |
| `post_tool_use` | yes (`PostToolUse`; matchers: Edit, Write, MultiEdit) | yes (`post_tool_use`; matchers: Edit, Write, MultiEdit) | n/a | n/a | implemented |
| `stop` | yes (`Stop`; claim detection reads the final assistant message from `transcript_path` (native) or `agent_message` (Flow-schema) — see § Host field-shape) | yes (`stop`) | partial (`verify-gate.sh` checks pasted gate report shape) | `verify-gate.sh` for ad-hoc validation | implemented |

## Host field-shape (per-host input coverage)

Claude Code's native events do NOT use the Flow-schema keys the earlier fixtures injected. Two handlers must read the native field or the gate is inert live:

| Handler | Native Claude Code field | Flow-schema field | Behavior |
|---|---|---|---|
| `user_prompt_submit` | `prompt` | `user_prompt` | reads `user_prompt` **or** `prompt` (dual-key). FR-12 secret warn, bypass-attempt warn, and the `/product-owner` reminder now fire on native `UserPromptSubmit`. |
| `stop` | `transcript_path` (JSONL; final assistant message = the claim) | `agent_message` | claim detection runs against `agent_message` when present, else the **last** assistant message parsed from the tail of `transcript_path` (never the whole transcript — a historical claim phrase does not over-trigger). FR-04/05/14 done/deploy deny + FR-22 recommended-warn now fire on native `Stop`. |

Warns surface via `hookSpecificOutput.additionalContext` (JSON stdout) so the model actually receives them; deny reasons print to stderr before the non-zero exit (Stop exit-2 semantics feed stderr, not stdout JSON). The deny/warn LOGIC (`CLAIM_PATTERNS`, `BYPASS_PATTERNS`, secret scan, `signal_definitions`) is unchanged — only the INPUT source was fixed.
| `task_complete` | n/a (Stop covers this) | n/a (stop covers this) | n/a | n/a | retired v3.18.0 (handler was wired nowhere; `stop` owns completion gating) |
| `pre_compact` | yes (`PreCompact`) | reserved (host-dependent) | n/a | n/a | implemented |

## Surface notes

- **Cursor** has no native lifecycle-hook surface in v0.1. Enforcement on Cursor sessions falls back to git hooks (`pre-commit`, `commit-msg`) and operator vigilance.
- **GitHub Copilot / VS Code** has no native lifecycle-hook surface in v0.1 for arbitrary command interception. Same fallback as Cursor.
- **Gemini-style IDE agents** have no documented lifecycle-hook surface in v0.1. Same fallback.
- **Generic local repo workflow** uses git fallback hooks only; no provider event integration.

## Hook event protocol

All handlers read a JSON event from stdin matching `flow_hook_event.schema.json` and write a JSON decision to stdout. Hosts that read exit codes also receive `0` (allow), `2` (deny), or `1` (handler error).

## Test coverage

21 deterministic fixtures at `hooks/tests/fixtures/*.json` (plus companion `*.jsonl` transcripts referenced by the stop fixtures 18–21), driven by the **single-process runner** `hooks/tests/run_hook_tests.py`: one python process imports each handler and drives `main()` in-process — same fixtures, same assertions as the retired fork-per-case loop, and a `--compare-subprocess` mode proves in-process ≡ subprocess for the **(exit_code, decision, rule_id)** triple (21/21, run as a permanent CI step). The full local gate `bash hooks/tests/run-tests.sh` runs **24 phases** (the fixture runner + module-size + health-check-timeout + git-smoke + hook-manifest + the upgrade/installer/CLI/security shell suites + cli-flow-recovery). Latest run output is written to `state/audit/hook-test-results.md` (gitignored runtime path) and uploaded by the GitHub Action as the `fusebase-flow-audit` workflow artifact. Coverage matrix:

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
  verdict; the DEFAULT `run-tests.sh` + CI stay FULL.

## Audit-log integration

Every hook execution appends a JSONL record to `state/audit.log.jsonl` (gitignored) with: timestamp, event, decision, reason, rule_id, session_id, host_tool, plus event-specific extras. Operators can grep / aggregate audit log post-hoc.

## Last amended

```
2026-05-08 — Phase 4; added GitHub Action verification of hook tests + preflight.
2026-07-03 — Phase C S1; documented per-host field-shape (native `prompt` / `transcript_path` vs Flow-schema `user_prompt` / `agent_message`) — the live enforcement fix. Fixture count 11→19; added rows 12-19.
```
