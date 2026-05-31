# Security Policy

## Scope

Fusebase Flow is a **repo-local workflow framework** — files (rules, skills, workflows, policies) plus optional local hooks. It has no server, no daemon, and makes no outbound network calls. Its hooks are **local guardrails**, not a complete security boundary; combine them with git hooks and operator vigilance.

Relevant security-sensitive surfaces in this repo:

- `hooks/handlers/*.py` and `hooks/shared/*` — local lifecycle enforcement (stdin → stdout JSON).
- `hooks/git/{pre-commit,commit-msg}` — git fallback safety net.
- `policies/*.yml` — deny lists, secret patterns, approval rules.
- `.claude/hooks/*` — CLI quality hooks (incl. the Windows `shell:true` patch mitigating CVE-2024-27980).

## Reporting a vulnerability

**Do not open a public issue for security reports.**

Instead, use **GitHub → Security → Report a vulnerability** (private advisory) on this repository, or email the maintainers privately. Please include:

- a description of the issue and the affected file(s)/surface,
- reproduction steps or a proof of concept,
- the impact you foresee (e.g. command execution via a hook, secret leakage, bypass of an approval gate).

We aim to acknowledge reports within a few business days and will coordinate a fix and disclosure timeline with you.

## What is in / out of scope

**In scope**
- A hook that can be made to execute unintended commands or bypass an approval/deny policy.
- A policy or pattern that fails to catch a secret it claims to catch.
- Mirror/manifest verification that can be defeated to ship tampered skills undetected.

**Out of scope**
- Risks inherent to the AI agent or IDE you run Flow under (report those to the respective vendor).
- The framework not preventing a determined operator from disabling their own local guardrails.
- Findings that require an already-compromised local machine.

## Supported versions

Security fixes target the latest released version on `main` (see [`VERSION`](VERSION) and [`CHANGELOG.md`](CHANGELOG.md)). Older versions are not separately patched.
