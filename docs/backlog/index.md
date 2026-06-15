# Product Backlog Index

| Slug | Status | One-liner |
|---|---|---|
| install-into-existing-fusebase-cli-project | parked | Safer installer for repos that already have FuseBase CLI and MCP configuration |
| architect-sub-agent | parked | Dedicated 3rd sub-agent for deep cross-cutting investigation, keeping the PO lean |
| role-path-hook-enforcement | parked | `pre_tool_use` role × path gate — PO "no app code" as a structural guarantee (FR-25 plumbing precedent) |
| health-check-fast-timeout | done (v3.24.0) | Bound the health-check's unbounded git-fetch + sub-script invocations so it never appears to hang (timeouts + partial verdict + `--fast` mode) |
| upgrade-tooling-hardening | done (v3.25.0) | Harden the refresh/upgrade scripts from two consumer reports — Windows perf (batched spawns), EOF-newline preserve, baseline/policy merge-preserve, sync allowlist + under-reach guard, GEMINI version sync, `PARTIAL_UPGRADE` |
| upgrade-baseline-bootstrap-hop | done (v3.25.1) | Hotfix — the v3.25.0 U3/W2 baseline merge-preserve now runs on the FIRST upgrade adopting v3.25.x (merge lib sourced from authoritative target tree + re-source before Step 1a + loud no-skip warning; `bootstrap-upgrade.sh` stages `hooks/local/lib/`; README routes pre-v3.25 installs through bootstrap; RED-then-GREEN adoption-hop test). Found by post-ship Codex adversarial review (`ea85585`) |
| adapter-overlay-refresh-parity | parked | U6 follow-up — marker-anchored overlay-refresh path for GEMINI/copilot/cursor (parity with AGENTS/CLAUDE), so secondary adapters get the Flow overlay content refreshed, not just the version string |
