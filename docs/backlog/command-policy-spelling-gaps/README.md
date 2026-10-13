# command-policy-spelling-gaps

**Status:** open — not scheduled. **Filed:** 2026-10-12 (T132 audit N1). **Severity:** medium (approval coverage). **Surface:** `policies/command-policy.yml` (FR-07 protected) + pattern compilation in `hooks/shared/command_rules.py` (matching via `hooks/shared/command_policy.py`).

## Observed

The T132 audit (`fusebase isolated-store sql bundle --apply` → `database_migration`) found spellings that bypass that rule AND the existing deploy/prisma/migration rules alike — T132 did not introduce them:

| Spelling | Example shape | Covered by |
|---|---|---|
| Mixed-case executable on Windows | `FuseBase deploy …` | none (patterns are case-sensitive on the verb) |
| `.exe` suffix / quoted full path | `fusebase.exe deploy …`, `"C:\…\fusebase.exe" deploy …` | none |
| npm/yarn/pnpm scripts | `npm run migrate` where the script runs the gated command | none |
| Line break inside the command words | `fusebase isolated-store sql \⏎ bundle --apply` | backlog K21 (shell-evasion) |

## Ask

Decide one normalization layer for ALL `require_approval` rules (executable basename + case-fold on Windows + `.exe` strip + continuation join), proven against the full `test-command-policy.sh` matrix with HEAD-vs-new comparison (no rule may change except by the intended normalization). npm-script indirection is a separate question (script bodies are not visible to the command gate).

## Constraints

FR-07 protected policy/shared code → single-use approval per file; security review (independent, strictest).
