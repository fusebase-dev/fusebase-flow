"""The Flow 5.x line-ending pins a 5.x project's .gitattributes carries outside Flow 6.0's marked block (6.0.0-m7 item 2).

5.x wrote folder-wide `text eol=lf` lines (`hooks/**`, `templates/**`, `state/**` ...): git then treats a binary committed
under those folders as text and rewrites its CRLF bytes, so a PNG loses bytes and its signature breaks (review r1-03).
6.0's block pins exact paths only. These are the 5.x lines as the field carries them (Onboarding's tree at b176a73d):
each pin line is matched by its words (the pattern, then `text eol=lf`, nothing else; the column spacing may differ),
each comment line whole. Any other line is the project's and stays: `*.sql text eol=lf`, `*.png binary`, a 5.x copy of
Flow's own extension rules. migrate and install remove them (flow.py); a `flow:` commit may carry that removal
(flow_owned.py).
"""
from __future__ import annotations

SKILLS_5X = (
    "app-quality-patterns", "business-logic-guardian", "client-vs-internal", "code-review", "comment-policy",
    "communication", "design-discovery-ideation", "documentation-budget", "find-wasted-code", "find-wasted-effort",
    "fusebase-flow-health-check", "git-history-diagnostic", "handoff", "implementation-planning", "lightweight-lane",
    "liveness-discipline", "module-size-discipline", "north-star", "phase-audit", "product-apps-decomposition",
    "product-docs-first", "product-owner", "project-onboarding", "release-deploy-reporting",
    "repo-onboarding-context-map", "requirements-specification", "role-discipline", "security-permissions-review",
    "skill-authoring", "smoke-testing", "task-delegation", "token-economy", "validation-and-qa", "zoom-out",
)
PATTERNS_5X = frozenset((
    "hooks/**", "flow-skills/**", "agents/**", "policies/**", "templates/**", "workflows/**", "audit/**", "state/**",
    ".agents/skills/**", ".codex/agents/**", ".claude/commands/**", ".claude/agents/ai-developer.md",
    ".claude/agents/product-owner.md", "VERSION", "install.sh", "FLOW_RULES.md", "FLOW_RULES_HISTORY.md", "GEMINI.md",
    *(f".claude/skills/{name}/**" for name in SKILLS_5X),
))
COMMENTS_5X = frozenset((
    "# FuseBase Flow line-ending pins, scoped to Flow-owned paths only (so existing",
    "# app files are not renormalized). core.autocrlf=true would otherwise check these",
    "# out as CRLF and break the bash/python hooks and Flow's byte-hash integrity checks.",
    "# Flow skill mirrors in .claude/skills (CLI provider skills there are left alone)",
))


def is_5x_pin(line: str) -> bool:
    """A Flow 5.x pin or comment line (a CRLF file's line keeps its \\r)."""
    text = line.rstrip("\r")
    words = text.split()
    return text.rstrip() in COMMENTS_5X or (len(words) == 3 and words[0] in PATTERNS_5X and words[1:] == ["text", "eol=lf"])


def drop(text: str) -> tuple[str, list[str]]:
    """`text` without its 5.x pin lines, and those lines as they stood."""
    lines = text.split("\n")
    gone = [line.rstrip("\r") for line in lines if is_5x_pin(line)]
    return "\n".join(line for line in lines if not is_5x_pin(line)), gone
