# Hook-level role × path enforcement (role-path-hook-enforcement)

**Status:** parked
**Filed:** 2026-05-30 · **Refreshed:** 2026-06-10 (v3.16.0 baseline)
**One-liner:** Extend the `pre_tool_use` hook to enforce role × path rules — so PO's "don't edit application code" becomes a hook-level structural guarantee instead of a prompt-level rule.

## Operator pain (in their words)

The Product Owner sub-agent's tool surface today **says** "Write/Edit scoped to `docs/specs/` / `docs/backlog/` / `docs/tmp/handoff/` / `docs/problem-catalog/`" — but this scope is **prompt-level**, not enforced. A PO agent that decides to edit `src/feature.ts` will be **denied by good prompt behavior**, not by the hook layer. If the PO drifts and writes app code anyway, the only catch is the operator noticing in the diff. The bash wrapper (`po-investigate.sh`) protects against shell-side drift (v2.1.1), but Write/Edit on filesystem paths has no analogous structural guard.

## Why now

`hooks/handlers/pre_tool_use.py` already filters tool calls against `policies/command-policy.yml` (deny-list) and `policies/protected-paths.yml` (protected paths). Adding a role × path check is a natural extension of the same handler — no new handler infrastructure needed. **FR-25 (v3.16.0) strengthened the precedent:** the repo now ships an in-house `**`-aware glob matcher (`hooks/shared/module_size.py: _glob_to_regex`) and a policy-driven deterministic path gate — the exact plumbing this ticket needs, already tested cross-platform.

## Architectural sketch (rough)

- New policy file `policies/role-path-rules.yml` listing per-role write/edit allowlists. Example:
  ```yaml
  product-owner:
    write_scope_allowed:
      - "docs/specs/**"
      - "docs/backlog/**"
      - "docs/tmp/handoff/**"
      - "docs/problem-catalog/**"
    write_scope_denied:
      - "src/**"
      - "hooks/**"
      - "flow-skills/**"
      - "agents/**"
      - "policies/**"
      - "workflows/**"
      - "templates/**"
  ai-developer:
    write_scope_allowed:
      - "**"
    write_scope_denied:
      - "docs/specs/**"
      - "policies/**"
  ```
- Session-start handler (`hooks/handlers/session_start.py`) parses the self-attestation phrase to extract the `current_role` and writes it to `state/current-role` (or in-memory if hooks can't access prior session state — TBD).
- `hooks/handlers/pre_tool_use.py` reads `current_role` and the new policy file; denies Write/Edit calls outside the role's allowed paths. Glob matching reuses the FR-25 matcher (extract `_glob_to_regex` to a shared utility rather than duplicating).
- New hook test fixtures (next free numbers at the v3.16.0 baseline: `17_…`, `18_…`) verify deny/allow per role.
- Providers without native hooks (Codex / Cursor / Copilot / Gemini) fall back to prompt-level enforcement — the hook layer is best-effort; the discipline still propagates via `role-discipline`.
- Document the limitation in the new policy file's comments.

## Acceptance criteria (rough)

1. AC1 — `policies/role-path-rules.yml` exists with PO and AI Developer allowlists / denylists.
2. AC2 — `hooks/handlers/pre_tool_use.py` reads the new policy and denies a Write/Edit when the file_path falls in the denied paths for the current role.
3. AC3 — `current_role` extracted from the self-attestation phrase by a deterministic regex (no LLM call); a missing `current_role` falls back to "no role rule applied" (warn-level, not block — fail-open).
4. AC4 — Fixtures verify: (a) PO denied writing `src/feature.ts`; (b) PO allowed writing `docs/specs/foo/spec.md`; (c) AI Developer denied writing `docs/specs/foo/spec.md`; (d) AI Developer allowed writing `src/feature.ts`.
5. AC5 — All existing tests still pass (22/22 at the v3.16.0 baseline: 16 fixtures + 6 module-size scenarios).
6. AC6 — Preflight 0/0; mirror drift 0.

## Out of scope

- Cross-session role persistence — initial scope is "role known at session start, persists for that session only."
- Enforcement on providers without native hooks — those get prompt-level + git-pre-commit fallback only.
- Path rules for the Architect sub-agent — once [architect-sub-agent](../architect-sub-agent/README.md) lands, add its rules then.

## Risks / unknowns

- **Role extraction reliability** — agents vary in how literally they reproduce the attestation phrase. On regex miss the hook must fail-open (allow + warn), never fail-closed. Log extraction outcomes to `state/audit/`.
- **Multi-role sessions** — `role-discipline` already says "multiple roles attested in one session → STOP"; role-path enforcement assumes single-role-per-session.
- **Glob semantics** — largely de-risked by FR-25's `_glob_to_regex` (anchored, `**`-aware, stdlib-only); extraction into `hooks/shared/` is the remaining design step.
- **Adoption friction** — ship with a permissive default; operators tighten via `policies/role-path-rules.local.yml` (the `policies/*.local.yml` gitignore rule already covers it since v3.16.0).

## Related

- `agents/product-owner/AGENT.md` — "Tool surface" + "Denied" tables (prompt-level today)
- `policies/protected-paths.yml` — existing path-based enforcement (universal, role-agnostic)
- `hooks/handlers/pre_tool_use.py` — the handler to extend
- `hooks/shared/module_size.py` — FR-25 glob matcher + policy-gate precedent (v3.16.0)
- `hooks/local/po-investigate.sh` — v2.1.1's structural analog for Bash
- `ROADMAP.md` — "Next likely"
