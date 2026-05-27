---
name: mcp-gate-debug
description: "After Fusebase Gate MCP tool sessions, produce a concise debug-oriented summary — what went smoothly, what did not, and actionable improvements to fusebase-gate skills, prompts, or MCP server behavior. Prioritize isolated SQL/NoSQL store flows."
---

# MCP Gate debug summary

## Purpose

Close the loop on **Gate MCP** work: turn friction into **specific** improvement ideas for:

- `.claude/skills/fusebase-gate/` (especially `SKILL.md` and `references/*.md`)
- MCP prompts / tool descriptions (upstream server)
- Local app code only when the issue is clearly client-side misuse

## When to run

After you finish (or pause) a **coherent batch** of Gate MCP `tool_call` operations — especially:

- **Isolated stores** — `listIsolatedStores`, `createIsolatedStore`, `initIsolatedStoreStage`, migration status/apply, row CRUD, `queryIsolatedStoreSql`, NoSQL equivalents
- Org users, tokens, permissions, health/bootstrap when those sessions were rough

If the user only asked a one-line question with no tools, skip this summary unless they ask for it.

## Output format (in the conversation)

Keep it scannable:

1. **Went well** — bullets (tools, prompts, docs that helped).
2. **Friction** — wrong assumptions, missing context, repeated `tools_describe`, unclear errors, wrong `orgId`/`storeId`/`stage`, migration/drift confusion, permission surprises.
3. **Improvements** — ordered by impact. For each idea, prefer:
   - **Target:** file path (e.g. `fusebase-gate/references/isolated-sql-stores.md`) or “MCP tool X description / prompt Y”
   - **Change:** one sentence
   - **Why:** link to the failure you saw

## Isolated stores first

When isolated-store tools were used, **before** proposing doc changes, re-read if needed:

- `.claude/skills/fusebase-gate/references/isolated-sql-stores.md`
- `.claude/skills/fusebase-gate/references/isolated-sql-migration-discipline.md`
- `.claude/skills/fusebase-gate/references/isolated-nosql.md` (if NoSQL)

The summary should call out:

- Missing playbook steps (status before apply, `dryRun`, checksum/version discipline).
- Confusion between **dev** and **prod** stages.
- Whether **`structuredIssues`** / drift messaging was understandable.

## Boundaries

- Do **not** dump raw tool JSON; summarize patterns.
- If the fix belongs in **this repo’s** `project-template` only, say so; if it belongs to the **Gate MCP service** or platform, label it as upstream.

## Flag

This skill is copied into the project only when the global CLI flag `mcp-gate-debug` is enabled (`fusebase config set-flag mcp-gate-debug` then `fusebase update --skip-mcp --skip-deps --skip-cli-update --skip-commit`).
