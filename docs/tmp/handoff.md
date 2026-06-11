# Active restart state — none

**Written:** 2026-06-10. Supersedes the context-floor-reduction handoff (ticket shipped as v3.17.0, deploy `0157f59`, spec DONE).

No ticket in flight. Repo baseline: v3.17.0 on origin/main, CI green expected (watch was armed at handoff time). Today's release chain: v3.16.0 → v3.16.1 → v3.16.2 → v3.16.3 → v3.16.4 → v3.17.0 (all tagged, all CI green through v3.16.4; v3.17.0 CI result in the session log / GitHub Actions).

Open candidates (see `ROADMAP.md`): architect sub-agent (Full) · role × path hook enforcement (Full; FR-25 plumbing precedent) · `.claude/commands` refresh path (Lightweight) · rail-mapping preflight automation (Lightweight).

Tripwires for the next session: inline AGENTS/CLAUDE overlay blocks must stay byte-identical to `hooks/local/fusebase-flow-overlays/` templates (edit canonical → re-splice); `## Amendment log` heading = sweep-guard anchor (never rename); session reads stop at that heading; new shell scripts need `git update-index --chmod=+x`; release recipe = single commit + annotated tag + `git push origin HEAD:main --follow-tags` + FR-14 docs flip + ff local main.
