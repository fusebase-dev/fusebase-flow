# Active restart state — context-floor-reduction (v3.17.0) at post-review fix stage

**Written:** 2026-06-10 (window reload). **Supersedes** any prior handoff.md content (FR-18).

## 1 · Session role / attestation
Product Owner under FuseBase Flow (repo baseline v3.16.4; attest v3.16.4 until the v3.17.0 release commit lands). Operator = Pavel (relay-thin; says "proceed" to approve; never bypass hooks; never `--no-verify`; never `git add -A`).

## 2 · Repo state
- Branch `feat/release-hygiene-v3141`. origin/main == local main == last pushed commit (backfill of v3.16.4 change-note SHA `2efd3d7`). All of today's releases on origin/main with annotated tags, CI green each: v3.16.0 (FR-25 ratchet, `81d35da`) · CI exec-bit hotfix `0bd8269` · roadmap publish `ad1fb7f` · v3.16.1 `32b4aee` · v3.16.2 FR-25 hardening `db43bf6` · v3.16.3 token-trim `a4a798c` · v3.16.4 efficiency repairs `2efd3d7`.
- **WORKING TREE IS DIRTY ON PURPOSE = the complete, reviewed v3.17.0 implementation (uncommitted).** Do NOT reset/checkout. `git status --short` ≈ 15 M + 3 new dirs (role-discipline references/ ×3 trees, spec dir).

## 3 · Current ticket
`context-floor-reduction` (v3.17.0, Full lane). Spec LOCKED: `docs/specs/context-floor-reduction/spec.md` (decisions C1..C5, ACs 1..7). Goal: cut always-on session floor ~30% (measured baseline ~34.5k tokens Claude / ~27.9k Codex).

## 4 · What is DONE in the working tree (implementer gate report clean)
- C1: role-discipline split → `flow-skills/role-discipline/references/{product-owner,ai-developer,architect,deploy}.md`; SKILL.md (50,261→23,441 B) keeps shared protocols + role→file table; all 55 rule IDs verified exactly-once; mirrors byte-identical incl. references/ (mirror-skills.sh already copies subdirs).
- C2: FLOW_RULES FR-16..24 rows + implications compressed (live region 24,655→16,451 B, −8,204). FR-01..15, FR-25, attestation, amendment log byte-identical to HEAD.
- C3/C4: canonical `claude-md-overlay.md` catalog → 3-line pointer; inline CLAUDE/AGENTS overlay blocks re-spliced byte-identical to canonical; CLAUDE base attestation/footer/operator-question sections → one pointer section; AGENTS base project-values + active-context tables → pointers (overlay FLOW:PRESERVE copy is the single copy).
- C5: README copy block → selective `cp $SRC/docs/*.md docs/` + dev-history exclusion note.
- Post-review fix already applied by PO: form-feed corruption in `docs/install-existing-project.md:143` (now reads `.fusebase-flow-source\flow-skills`).
- Gates all green on this tree: preflight 0/0 · run-tests 24/24 · check-module-size --all exit 0 · sweep dry-run clean · health-check heading anchors intact · preflight §8 satisfied.

## 5 · Independent review verdict: FIX-FIRST — REMAINING BLOCKERS (next actions)
- **B1 (stale pointers into moved role sections — sweep + repoint to `references/<role>.md` or "role-discipline (entry: SKILL.md)"):** `workflows/greenlight-implement.md:45` · `workflows/greenlight-deploy.md:43` · `templates/handoff-implement.md:30` · `templates/handoff-deploy.md:39` · `workflows/live-user-verification.md:81,205` · `agents/ai-developer/AGENT.md:137` · `agents/product-owner/AGENT.md:100,202` · `hooks/shared/command_policy.py:109` · `docs/rail-mapping.md:48`. Then `bash hooks/local/mirror-agents.sh` (+mirror-skills if skills touched). Grep to find any missed: `grep -rn "SKILL.md" --include="*.md" --include="*.py" | grep -E "(IM|DP|PO|AR)\.[0-9]|Section: "`.
- **B2 (C5 half-done):** `docs/install-existing-project.md` copy section (~lines 104-150) copies no docs/ — add the same selective block as README in BOTH bash and PowerShell (`mkdir -p docs && cp .fusebase-flow-source/docs/*.md docs/` + optional translations + dev-history-not-copied comment).
- Optional non-blockers: N2 CLAUDE.md:39 attestation-pointer wording (point at AGENTS.md overlay/FLOW_RULES, not "overlay below"); N3 trailing newline EOF canonical role-discipline SKILL.md + re-mirror.
- AC2 semantic attestation PASSED for all FR-16..24 (no substantive loss) — does NOT need re-review; re-review after fixes is mechanical only.

## 6 · Then: release mechanics v3.17.0 (exact recipe used 5× today)
1. `echo "3.17.0" > VERSION`; plugin.json version → 3.17.0 (python json edit); README badge `version-3.16.4` → wait, badge currently `3.16.4`? — badge says 3.16.4 (set during v3.16.4); update → 3.17.0.
2. CHANGELOG entry `## [3.17.0]` (context-floor reduction: −~8k tokens/session per role; C1..C5 summary; review B1/B2 fixed; AC7 numbers) + `docs/release-notes/v3.17.0.md` + FLOW_RULES Status → v0.21 line + amendment-log entry (token-trim structural; no rule semantics changed — reviewer-attested).
3. `bash hooks/local/sync-version-strings.sh` (re-mirrors). Verify guard: `grep -c "FR-01\.\.FR-23 / 27 skills" FLOW_RULES.md` == 1.
4. Verify: preflight 0/0 · run-tests 24/24 · --all 0 · sweep dry-run clean.
5. Stage EXPLICIT paths (`git add .agents .claude .claude-plugin .codex .cursor .github AGENTS.md CHANGELOG.md CLAUDE.md FLOW_RULES.md GEMINI.md README.md ROADMAP.md VERSION agents audit docs flow-skills hooks policies templates workflows` — never `-A`); single release commit `feat(flow): v3.17.0 — context-floor reduction …` + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`; annotated tag v3.17.0; `git push origin HEAD:main --follow-tags`.
6. FR-14 docs flip: spec `docs/specs/context-floor-reduction/spec.md` Status → DONE + deploy hash (separate docs commit, push).
7. Watch CI (`gh run list/watch`); `git fetch origin -q && git branch -f main origin/main`.
8. Memory update: `C:\Users\abcpa\.claude\projects\c--Users-abcpa-Projects-fusebase-flow-publish-fusebase-flow-template\memory\project_v3160_module_size_ratchet.md` (append v3.17.0 line) + MEMORY.md index if new file.

## 7 · Tripwires (learned today — do not violate)
- Inline AGENTS/CLAUDE overlay blocks MUST stay byte-identical to `hooks/local/fusebase-flow-overlays/*-overlay.md`; edit canonical first, then re-splice (python splice on `CUSTOM:SKILL:BEGIN/END` for AGENTS; on `---` before `## Fusebase Flow — additional rules (overlay)` → EOF for CLAUDE).
- `## Amendment log` heading text in FLOW_RULES = sweep-guard sed anchor — never rename; skip-marker lives UNDER it.
- Python string escapes: `\f` in replacement strings = form-feed (caused today's corruption) — use chr(92) or raw strings for backslash paths.
- New shell scripts need `git update-index --chmod=+x` (CI working-tree-clean fails otherwise).
- `policies/*.yml`/baseline/hooks are protected paths; release commits touch them legitimately (no local hooks installed in this repo clone... pre-commit IS installed? commits today passed without exception artifacts — hooks not installed locally).
- Session-start reads stop at `## Amendment log` (v3.16.3+).

## 8 · Today's full arc (context for reporting)
FR-25 module-size ratchet design→ship (v3.16.0, independent-reviewed) → CI exec-bit hotfix → roadmap+backlog published (v3.16.1) → stress test (empirical probe of paperclip+hermes-v1 + devil's-advocate agent; verdict net-positive 4-6×, wrong delivery posture) → v3.16.2 hardening (gate live by default) → token-economy audit (verdict net-positive-with-waste; amendment-log discovery) → v3.16.3 token-trim (~470k/100 sessions) → framework-wide efficiency audit (2 bugs: broken install copy, dead hooks via ${PROJECT_DIR}; floor 34.5k) → v3.16.4 repairs → v3.17.0 context-floor reduction (−28..34% floor) implemented + reviewed, AT FIX-B1/B2 STAGE NOW.

## 9 · Completion criteria
v3.17.0 on origin/main, tag pushed, CI green, spec DONE-flipped, local main ff'd, memory updated, operator told the measured floor delta (target ≥8k tokens/session; implementer measured PO −8.0k, AI-Dev −7.9k, Deploy −8.5k at B/4).
