<!-- Thanks for contributing to Fusebase Flow! -->

## What & why

<!-- What does this change, and why? Link the ticket/spec if applicable (docs/specs/<slug>/). -->

## Type of change

- [ ] Docs only
- [ ] Skill / sub-agent (canonical edited + mirrors regenerated)
- [ ] Workflow / policy / template
- [ ] Hook / enforcement
- [ ] Other:

## Checklist

- [ ] Edited the **canonical** source (not a mirror) and ran `mirror-skills.sh` / `mirror-agents.sh` if skills/agents changed
- [ ] `bash hooks/local/preflight.sh` → errors: 0, warnings: 0
- [ ] `bash hooks/tests/run-tests.sh` → all PASS
- [ ] No new heavy dependencies (stdlib-first; PyYAML only)
- [ ] Clean-room respected — no text copied from proprietary frameworks
- [ ] `CHANGELOG.md` updated for user-visible changes

## Notes for reviewers

<!-- Anything specific you want a reviewer to focus on (rollback risk, security-sensitive paths, etc.). -->
