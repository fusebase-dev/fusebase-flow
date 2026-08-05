# Phase C — Fable whole-system audit: findings triaged into fix slices

Independent Fable audit of shipped FuseBase Flow v3.30.6 (HEAD 676f4b1), 9-subsystem fan-out. **40 real findings, 0 clean subsystems.** Full per-finding detail (evidence + fix_direction) in the workflow result: `tasks/wecmxwyrx.output`. Fable audited; **Opus 4.8 implements every fix**. Findings verified before slicing (esp. the S1 cluster — confirmed by direct code inspection).

## Severity roll-up: 4 HIGH · 14 MEDIUM · 22 LOW

## Fix slices (grouped by theme for coherent one-commit-per-slice fixes; ranked by value)

### SLICE 1 — Hook host-compatibility (CRITICAL — the enforcement is inert live) [H1,H2,H3,M4,M5,L7]
**VERIFIED REAL.** The Flow hooks read Flow-schema keys the Claude Code runtime never sends, and the promised normalization shim does not exist, so live enforcement is inert (tests pass only on synthetic fixtures).
- H1: `user_prompt_submit.py:84` reads `event.get("user_prompt")`; Claude Code sends `prompt`. → FR-12 secret warn, bypass/impl-without-spec detection, /product-owner reminder all inert live.
- H2: `stop.py:145` runs CLAIM_PATTERNS against `agent_message` only (Claude Code's Stop has no `agent_message`). → FR-04/05/14 done/deploy deny gate + FR-22 recommended-warn never fire live. (stop.py DOES read transcript_path at :125 but only for the PO-activation warn + signal detection, NOT for claim detection.)
- H3: no shim exists; settings.json.example invokes handlers directly; README/schema falsely claim a normalizer.
- FIX: make handlers host-tolerant — `user_prompt = event.get("user_prompt") or event.get("prompt") or ""`; in stop.py, when `agent_message` is absent, derive the final assistant message from the TAIL of `transcript_path` (last assistant-role JSONL entry) and run CLAIM_PATTERNS against that (precise — not the whole transcript, to avoid over-trigger). Surface warns/denies via stderr AND hookSpecificOutput.additionalContext (exit-0 JSON stdout does not reach the model). Relax `_PO_INVOCATION_RE` anchoring for real transcript JSONL. Add NATIVE-shape fixtures (prompt-key; transcript-only Stop with no agent_message) asserting the warn/deny still fire — closes the synthetic-only coverage gap. Correct docs/hook-coverage.md + rail-mapping.md + FR-12 enforcement column (L7) to the true per-host coverage. **DO NOT weaken any gate; this makes inert gates actually fire.**

### SLICE 2 — Release-doc + version-propagation backfill [H4,M8,M12,M9,L15,L17,L18,L20]
- H4/M8/M12: no CHANGELOG entries + no docs/release-notes/ for v3.30.3–v3.30.6; README badge stale at 3.30.2. FIX: backfill CHANGELOG + docs/release-notes/v3.30.{3,4,5,6}.md (content reconstructable from the release commits + deploy handoffs); bump README badge to 3.30.6.
- M9: `.claude-plugin/marketplace.json` advertises **3.10.0** (20 minor versions stale, no guard). FIX: bump to VERSION + extend preflight §8 parity-check to it.
- L15: sync-version-strings.sh re-mirror swallows failures + prints success. FIX: propagate mirror rc, loud error + exit 1 on failure.
- L17/L18/L20: PUBLISHING.md / compatibility.md stale expected outputs (24/24 tests, 78 mirror files). FIX: self-derived expectations (N/N PASS; mirror==manifest count) or pointer, not hardcoded counts.

### SLICE 3 — Stale `skills/` → `flow-skills/` path sweep [L1,L5,L16,M13]
Mechanical: the v3.9.0 skills/→flow-skills/ rename left dead `skills/<slug>/SKILL.md` refs in role don't-lists (references/{product-owner,ai-developer,deploy}.md), skill-authoring (canonical home + destination table), and DP.10 mandatory-read pointer. FIX: one-pass `s|skills/|flow-skills/|` across the identified carriers + re-mirror. (M13 makes a framework skill authored per skill-authoring orphaned from the mirror pipeline — real operations impact.)

### SLICE 4 — Fail-closed + robustness in tooling [M6,L12,L13]
- M6: preflight.sh skill-frontmatter + orphaned-approval checks can never fail the exit code (`|| true` swallows rc before `$?`). → false-clean for CI + health engine. FIX: test the heredoc python rc directly.
- L12: health engine misreports a completed run-tests with visible INCONCLUSIVE rows as BROKEN "crashed, no parsable result". FIX: detect `^INCONCLUSIVE:` / a present summary line → route to LOCAL_UNVERIFIED, not BROKEN.
- L13: verify-gate.sh crashes (Python traceback) from any subdirectory (reads policy CWD-relative). FIX: `cd "$ROOT"` after computing ROOT.

### SLICE 5 — po-investigate.sh read-only hardening [M2]
The PO "structural read-only guarantee" is breached: `git --output`/`--ext-diff`/`GIT_EXTERNAL_DIFF`/pager escapes through allowlisted diff/log/show let the PO write/overwrite files the Edit/Write tool denies. FIX: reject forwarded args that redirect output or invoke external programs in the diff/log/show branches. (Security-adjacent — the PO read-only sandbox.)

### SLICE 6 — Doc/rule-consistency corrections [M1,M3,M7,M10,M11,M14,L2,L3,L4,L6,L8,L9,L10,L11,L14,L19,L21,L22]
The long tail of doc-vs-code contradictions (evidence-backed, mostly LOW): spec status LOCKED vs DRAFT convention (M1); FR-01 pre_tool_use claim with no tool-time check (M3); lightweight-lane deploy stamp vs actual gate (M7); AGENTS.md catalog omits liveness-discipline while claiming 32 (M10); codename 'headroom' in 13 tracked files vs release-notes "=0" claim (M11 — reword to avoid spelling the codename); Architect-deliverables contradiction (M14); + L2/L3/L4/L6/L8/L9/L10/L11/L14/L19/L21/L22 (invocation-marker claim, ledger contradiction, handoff-dir scope, FR-04 stop claim, stale Status line v0.28, workflow-vs-skill labels, secret-precedence comment, PO-Bash-gated wording, fixture-count docs, template version strings, dangling FR-DP-4/HR-PO-15 IDs). FIX: mechanical doc/rule-text corrections (may split into 6a docs + 6b FR/rail-mapping if large). NONE weaken enforcement.

## Sequencing
S1 (critical, enforcement-live) → S2 (release-doc/version) → S4 (fail-closed tooling) → S3 (path sweep) → S5 (po-investigate) → S6 (doc cleanup, batchable last). Each slice = one Opus fix commit → scoped gate → (S1/S4/S5 get adversarial review; S2/S3/S6 lighter) → batch-deploy as v3.30.7 (or per-slice if warranted). S1 is the priority.
