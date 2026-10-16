# task-slicer

**Status:** open — 6.0.0 rebuild, **wave 2** (with `heartbeat-reader`, one writer). **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 9 (R §2). **Surface:** `hooks/local/lib/slice.py` (new core file, row 34), `policies/agent-tools.yml` (project-owned; read only), the slice start stamp under `state/`. **FR-07:** no (`agent-tools.yml` is read, never shipped or written by Flow, `hooks/local/lib/managed_content_manifest.py:59`).

## Delivers

- **`slice.py`**, stdlib Python, written from scratch with the consumer's `scripts/ticket-slice.mjs` as the pattern and nothing imported (decision 2). It prints one task's slice and nothing else (H WP 9): the backlog item; its acceptance criterion or test id; the cited owner answers in full; its input references; the task's globs with their breadth and matched-file counts; the estimate; the reference project; the live `state/status.line` with the reader's last-seen age.
- **Inputs inline** (decision 2): an input written `path#anchor` is printed inline under a byte cap (cap value: this WP's plan), which keeps the consumer's measured cut of requirement reads.
- **`BLOCKED-AT-input`**: a task whose named input tool is not in the agent's profile prints `BLOCKED-AT-input` and stops. The map from input kind to tool lives in `policies/agent-tools.yml`: Flow declares the key, the project names the tools (decision 2), so Flow still names no tool (H non-negotiable 6). The tool-profile validator (row 29) must accept that key.
- **`--brief`**: the reviewer or skeptic brief for a slice, with the flag rows and the gate output inline, and no Flow rule text or default verdict.
- **The slice start stamp** check 3 measures minutes against (R §2 WP 9).
- A reader nobody launched shows as "last seen: never" in the agent's own slice (H non-negotiable 5).
- The consumer retires `ticket-slice.mjs` at the migration (decision 2; `flow-migrate` lists it among consumer references).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 2 (Flow owns `slice.py`; `path#anchor` inline under a byte cap; input-kind map in `agent-tools.yml`) | The whole package |
| R §4 lock (the slice contract: the WP 9 fields and nothing else) | No extra fields |
| Decision 10b ("stop and ask" is a card line) | `BLOCKED-AT-input` is its computed form |
| R §6 T152, T158 (tasks declare inputs; read by slice) | Computed here |

## Estimate

R §2: 4 to 6 agent-h (mid 5). Review: 1 to 2 rounds.

## Depends

`four-document-model` (parser), `heartbeat-reader` (status line), `overbuilding-flags` and `slice-gate` (flag rows and gate block for `--brief`, by interface); decision 2. Blocks: `reader-agent-and-dispatch-check` (the brief path), `eight-rule-kernel-and-cards` (the builder's boot list names the slice, not `backlog.md`).

## Acceptance

1. A builder's slice carries no more task text than the consumer's measured 1.8k tokens per agent (about 7.2 KB at 4 bytes a token), plus the cited answers in full (H WP 9; fixture).
2. The builder's bootstrap read list names the slice, not `backlog.md` (H WP 9).
3. A slice printed with no reader registered shows "last seen: never" (fixture).
4. `BLOCKED-AT-input` stops the slice when the named input tool is absent from the profile (fixture).
5. `--brief` carries the flag rows and the gate block and no Flow rule text (fixture).
6. A `**` glob prints with its breadth.

## Wave split

Wave 2, one commit planned (slicer plus fixtures); `--brief` may be a second commit if the gate block is late. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
