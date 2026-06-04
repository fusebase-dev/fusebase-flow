change_tier: lightweight
ticket: u13-noncanonical-provider-mirrors

Problem:   Issue 2 (downstream). The health check reported CLI_LAYER_DRIFT for CLI provider
           skills MISSING from .agents/skills/ (e.g. app-backend/-routing/-secrets/-sidecar),
           with the dead-end advice "run fusebase update". Verified against the CLI source
           (apps-cli lib/copy-template.ts, commands/product.ts): `fusebase update` writes CLI
           provider skills to .claude/ ONLY — never .agents/ or .codex/. Flow's guardrail also
           forbids Flow writing CLI provider skill text. So the .agents/.codex CLI-provider
           mirror is maintained by NEITHER tool → its absence is benign-by-design, and the
           "run fusebase update" recommendation can never clear it.
Change:    check-cli-flow-conflicts.sh — .claude/skills (and .claude/agents) is the AUTHORITATIVE
           CLI-provider surface (full F4/U10 drift logic kept). The non-authoritative mirrors
           (.agents/skills, .codex/agents) now report a single benign INFO ("N/M present, K absent
           — expected; CLI maintains provider skills in .claude only; copy from .claude for Codex
           parity"), never MISSING/CLI_LAYER_DRIFT. Genuine .claude drift still escalates with the
           correct "fusebase update" advice. (feature-* vs app-* orphans need no fix — Flow only
           checks current app-* known_names, so orphans are invisible to it.)
Verified:  recovery sim — U13 (.agents partial CLI-provider gap benign, not CLI_LAYER_DRIFT, INFO
           points at .claude not fusebase update); AC4 updated (per-agent attribution on .claude
           only); CUSTOM:SKILL at-risk test moved to .claude (the surface the CLI actually
           refreshes); precision retained (missing .claude provider skill still CLI_LAYER_DRIFT;
           U10/U11/U12 pass). 24/24 sim assertions; run-tests 16/16; preflight 0/0; health HEALTHY.
Rollback:  git revert <SHA>
Commit:    b42a3d2
Deploy:    plain operator go-ahead -> v3.8.4 (tag + GitHub release).
