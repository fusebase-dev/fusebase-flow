# Roadmap

FuseBase Flow ships **reactively** — each release is driven by real friction surfaced in operator and consumer-project workflows, not by a fixed multi-quarter plan. This document is the **public view of what's likely next** and what's explicitly out of scope. Items move from *Open / radar* → *Next likely* → released; the [CHANGELOG](CHANGELOG.md) records what actually shipped.

## Now (released)

What shipped, newest first: [CHANGELOG](CHANGELOG.md); current version: [`VERSION`](VERSION).

Current shape: **always-on rules FR-01..FR-27 · (34 canonical skills) · 2 sub-agents** — the FR range and skill count are re-derived from the tree at each release by `hooks/local/sync-version-strings.sh`.

## Next likely (no firm dates — when needed)

Items here have a clear shape but aren't scheduled. They land when real-world friction surfaces them or an operator explicitly asks.

| Area | What | Backlog ticket |
|---|---|---|
| **Architect sub-agent** | A dedicated 3rd sub-agent (alongside Product Owner + AI Developer) for deep cross-cutting investigation (>10 files / cross-cutting refactor / platform-blocker analysis). Today the PO absorbs Architect duties inline via `AR.1..AR.6` on escalation — works, but a dedicated agent could carry deeper investigation surface without bloating the PO. | [`docs/backlog/architect-sub-agent/`](docs/backlog/architect-sub-agent/README.md) |
| **Hook-level role × path enforcement** | PO's "don't edit application code" rule is prompt-level today. A `pre_tool_use` check reading a `current_role` signal would enforce role × path at the hook layer — a structural guarantee. FR-25 (v3.16.0) shipped the first path-aware deterministic gate, so the glob/policy plumbing precedent now exists in-repo. | [`docs/backlog/role-path-hook-enforcement/`](docs/backlog/role-path-hook-enforcement/README.md) |

## Open / radar (smaller items)

- **`docs/rail-mapping.md` automation** — rows are current as of v3.16.4 (FR-20..25 added), but `preflight.sh` still doesn't parse the file; a rule-count consistency check would prevent the 6-release drift from recurring.
- **`.claude/commands/` refresh path** — slash-command files have no regeneration step (mirroring covers skills + agents only), so their attestation ranges can drift between releases; candidates: mirror from the overlay templates or include in the version-string sweep.
- **Module-size baseline rename handling** — `--write-baseline <path>` (v3.16.2) makes the rename remedy a one-command targeted re-key; carrying baseline values across renames *automatically* remains a candidate refinement.
- **More provider integrations** — the current 5 surfaces (Claude Code, Codex, Cursor, GitHub Copilot, Gemini) were chosen for stable adoption signals; new surfaces land when an operator runs the framework on one and surfaces a need.

## Explicitly out of scope (anti-features — deliberate non-goals)

Considered and **deliberately deferred or rejected**. Surfacing them prevents misaligned PRs and keeps positioning clear.

| Non-goal | Why we don't do it |
|---|---|
| **A required CLI / install daemon / SaaS** | The whole framework is plain files in your repo. No external dependency, no runtime service. |
| **Plugin-marketplace-only distribution** | The copy/`install.sh` model is the canonical provider-neutral path. The Claude Code plugin (v3.3.0+) is an optional convenience on one surface, never the only path. |
| **Slash commands as the primary entry point** | Slash commands work on one provider. Skills, sub-agents, and trigger phrases work across all 5 supported surfaces; the eight slash commands (`/onboard`, `/product-owner`, `/fusebase-health`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort`, `/find-wasted-code`, `/step-out`) are Claude Code conveniences only. |
| **Telemetry / analytics / phone-home** | Local-only is a feature, not a missing capability. |
| **Heavy framework dependencies (FastAPI, daemons, etc.)** | Stdlib-first by design; one runtime dep (PyYAML). |
| **Vendor-specific content outside provider mirrors** | Canonical `flow-skills/` / `agents/` / `workflows/` / `templates/` are vendor-neutral; provider folders (`.claude/`, `.agents/`, `.codex/`, `.cursor/`, `.github/`) are generated mirrors or scoped adapters. |
| **Auto-running deploys without an approval artifact** | DP.1 (approval artifact) + DP.6 (magic phrase) on the Full lane — and an explicit operator go-ahead even on the Lightweight lane (FR-21) — are deliberate friction. Production cutovers need a human at the keyboard. |
| **Regex/lint gates for semantic rules** | FR-22 (comment quality) and FR-23 (doc tiers) are semantic judgments; a pattern gate would train agents to game it. Only objectively countable rules get gates (FR-25 line counts). |

## How to influence this roadmap

1. **File an issue** describing the pain you're hitting today — lead with the pain, not the proposed solution. See [CONTRIBUTING.md](CONTRIBUTING.md).
2. **Parked tickets** live under [`docs/backlog/`](docs/backlog/README.md) — per-ticket folders with rough acceptance criteria; promoted to `docs/specs/<slug>/spec.md` when the operator decides to ship.
3. **Specs in flight** live under `docs/specs/`.

## What we don't promise

- **No fixed dates.** Releases land when the friction-fix is ready, not on a calendar.
- **No guaranteed backward-compat across major restructurings** — but migrations ship with tooling (e.g., the v3.9.0 `skills/` → `flow-skills/` move auto-migrates via `upgrade.sh`) and are signaled in release notes.
- **No long-term vision for the next major line posted.** Pre-committing its shape would invite churn before the current line surfaces concrete pressure.
