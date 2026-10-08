# Token-waste audit v2 (consumer escalations 2026-10-07/08)

**Outcome:** `/token-waste-audit` reports where a Claude Code run's cost actually went — main session AND sub-agents — instead of ranking image false positives. **Inputs:** three consumer reports (WorkHub Managed, Service Business, FuseBase onboarding); adversarial review + measurements `c:/tmp/twa-review-2026-10-08/review.md` (local, not shipped). **Authorization:** operator, maintainer chat 2026-10-08: implement Outcome A; implementer GPT-6.1 Sol High (Codex 0.160.0, `windows.sandbox="unelevated"`), audit Opus 5.5 High. Outcomes B (guidance rows) and C (rule amendments) were authorized separately later the same day → `docs/changes/2026-10-08-token-cost-process.md`. **Review round cap:** 2 audit rounds per outcome; exhaustion returns to the operator, never extended by the orchestrator. **Status:** A1 `2aa5910` (audit r1 FIX-THEN-SHIP → r2 SHIP). A2 audit r1 FIX-THEN-SHIP (`<synthetic>` entries broke the gap chain) → r2 SHIP (`c:/tmp/twa-review-2026-10-08/audit-A2-r2.md`). Not pushed; no release. **Open optional (audit, not findings):** polling "wakes" counts every issue of the command; a request's start could use the preceding tool_result line (+4 sub rows live); mark observed vs estimated $ in ranking.

| Item | Outcome | Boundary | Success / failure example | Result |
|---|---|---|---|---|
| A1 · T120 | Audit correctness: sub-agent + workflow-agent transcripts parsed (`journal.jsonl` excluded); images counted as images, never as base64 text; identical-image re-reads detected; path snippets keep the tail; only model-visible content counted; per-session flood cap kept; FR-25 seam split | `hooks/local/token-waste-audit.py` (thin entry) → package `hooks/local/token_waste_audit/`; `hooks/tests/test-token-waste-classify.sh` + `hooks/tests/fixtures/token_waste_a1.py`; command body + twin; `token-economy` § Measure it + mirrors | Failure: WorkHub run — 10/10 `large-output` rows were PNG screenshots (5,336,782 base64 chars ≈ 43.7k real tokens) and 86% of cache reads (sub-agents) were never parsed. Success: same run → 220 agents / 52 workflows parsed, 25 images ≈ 43,757 estimated tokens, 0 image-driven `large-output`, 10 text rows + "860 more suppressed (session cap)" | IMPLEMENTED; audit r1 F1-F5 resolved (F1 session cap, F2 this record, F3 `sys.path` bootstrap, F4 `--main-only` label, F5 image table) |
| A2 · T121 | Cost attribution: price-weighted category header first; per-agent context residency; cache-rewrite-after-TTL class; polling weighted by context; findings ordered by estimated cost | audit package; same test + fixtures; command body; `token-economy` § Measure it | Failure: terminal "candidates found" pointed at <1% of cost while agents peaking >500k held 42% and post-TTL rewrites 12.7%. Success: header ranks sub-agent cache reads first; a 70-min gap on a 1h-TTL request with a 500k write yields one rewrite row; a 20-min gap yields none | IMPLEMENTED; new `costing.py`; live WorkHub `cbae7144`: sub-agents 84.0% of $, sub-agent cache reads the top category, 156 transcripts ≥500k hold 92.7% of cache-read $, `cache-rewrite` 36 main / 89 sub, report 23 KB / 162 lines; `<synthetic>` entries excluded from gap/residency chains, kept unpriced (`fbcc4f6e` 26 → 27); A1 carry-overs done (capped-path fixtures, cap documented, `round1-` prefix dropped) |

## Checks

Host: Windows 11, Git Bash (MSYS2), native Python 3.12.10. Linux not run locally; maintainer/release CI owns it. Logs: `c:/tmp/twa-review-2026-10-08/chk-A1-*.log`. Bash ran outside the Codex sandbox (sandbox denies Bash startup); the implementer's native harnesses are `state/audit/twa-a1-*.py` (gitignored).

| Item | Command | Result |
|---|---|---|
| A1 | `bash hooks/tests/test-token-waste-classify.sh` | 101/101 PASS, 53 s |
| A1 | `FF_ONLY=token-waste-classify,supersede-primitive bash hooks/tests/run-tests.sh` | 122/122 PASS, 63 s |
| A1 | `bash hooks/local/preflight.sh` | 0 errors, 0 warnings; registry 82 / 45 release / 7 opt-in / 4 unreviewed |
| A1 | `check-module-size.sh --worktree`; `git diff --check` | rc 0; rc 0 |
| A1 | `mirror-skills.sh --check`; command twin `cmp` | 0 drift (34 skills / 100 files); byte-identical |
| A1 | stamp + verify both manifests | hook-layer MATCH 228; managed-content MATCH 404 |
| A1 | live `python hooks/local/token-waste-audit.py --last 1 --dir <WorkHub transcripts>` | 220 agents (65 direct + 155 workflow), 52 workflows, journals ignored; 25 images ≈ 43,757 est. tokens; 0 image-driven `large-output`; 10 rows + 860 suppressed; 1 `image-reread` |
| A2 | `bash hooks/tests/test-token-waste-classify.sh` | 215/215 PASS, 58 s |
| A2 | `FF_ONLY=token-waste-classify,supersede-primitive bash hooks/tests/run-tests.sh` | 236/236 PASS, 84 s |
| A2 | preflight; module-size `--worktree`; `git diff --check`; mirror `--check`; twin `cmp` | 0/0; rc 0; rc 0; 0 drift; identical |
| A2 | stamp + verify both manifests | hook-layer MATCH 229; managed-content MATCH 406 |
| A2 | audit r1+r2 (Opus 5.5 High) independent $ recount | main $501.62 exact; sub-agents within live growth; 18/18 + 4/4 mutations red |
| A1 | audit r1 (Opus 5.5 High) independent recount | main totals exact; sub-agent totals match within live growth; privacy grep 0 base64 runs ≥200 chars; 13/15 mutations red (2 green judged harmless) |
