# `docs/problem-catalog/` — persistent record of significant problems

Problems that took non-trivial diagnosis effort, or that recur across tickets, get filed here so future sessions don't re-discover them.

```
docs/problem-catalog/
├── README.md                           ← this file (index)
└── <slug>/
    └── problem.md                      ← per-problem details (use templates/problem-catalog-entry.md)
```

## index format

```markdown
# Problem Catalog Index

| Slug | Severity | Status | One-line summary |
|---|---|---|---|
```

## When to file

Triggers (per FR-15 + `workflows/knowledge-curation.md`):

- Ticket required > 30 minutes of non-obvious diagnosis
- Same symptom seen in 2+ recent tickets
- Vendor or platform quirk surfaced
- Workaround applied for a platform constraint

The Product Owner proposes filing; the operator confirms. `Capture` files the entry; `skip` notes the decision in the current ticket's `decisions.md`.

## Skill vs problem-catalog

| Pattern | Where | Why |
|---|---|---|
| One specific incident with a specific cause | problem-catalog | Concrete, dated, reference-able |
| General expertise area that recurs across 3+ tickets | `docs/skills/<slug>/SKILL.md` (project-internal skill, distinct from `flow-skills/`) | Reusable knowledge, not incident-bound |

## Style

Mode B (full). Use `templates/problem-catalog-entry.md` as substrate.

## Index

Read this before starting a ticket that touches MSYS/Windows tooling, the install/upgrade
path, the secret scanner, or FR-07 protected-paths — future sessions should recognize a
known problem instead of re-diagnosing it.

| Slug | Severity | Status | One-line summary |
|---|---|---|---|
| `install-upgrade-commit-self-blocked` | high | resolved | Fresh install / self-upgrade couldn't make its own documented setup commit through Flow's gates (secret self-trip + FR-07 + fixed pre-commit not re-installed) |
| `run-tests-never-completes-msys` | high | resolved | `run-tests.sh` never reached exit 0 on any MINGW64 box — harness didn't reuse the bounded-run reap; `$(...)` capture held open by a native grandchild |
| `bounded-run-msys-collateral-kill` | high | resolved (core v3.30.3; opt-in hard fence v3.30.4, Cummings-class reliability consumer-gated) | MSYS `taskkill //T` over-killed (255 collateral: caller/harness/other sessions) and returned rc0-on-kill; ancestor-resolution + PID reuse |
| `health-check-false-broken-rc0-on-kill` | high | resolved | Healthy install read BROKEN on Ovation — rc0-on-kill hit the `rc0+no-PASS+no-FAIL⇒BROKEN` branch; fixed at root (true-124-on-kill), fail-closed guard preserved |
| `truncated-manifest-on-bound-hit` | medium | resolved | Self-mistake: release shipped a truncated skill-mirror manifest — bound-hit mid-write + `mirror-skills --check` (a non-existent flag) ran a concurrent full mirror |
| `inaccurate-consumer-prompt` | medium | resolved | Self-mistake: consumer apply-prompt claimed "the upgrade installs the fixed pre-commit" — false; asserted tool behavior without verifying it against source |
| `tests-ran-without-set-e` | medium | resolved | A real WS5 optional-step abort bug passed the suite GREEN — the test sourced the lib without `set -e`, so the `set -e`-sensitive abort path was never reproduced; caught only by adversarial review (v3.30.4) |
| `security-check-fail-open-class` | high | resolved | Pre-commit security checks (FR-07 §3 + FR-12 §2) had MULTIPLE reachable fail-opens (delete/rename skipped, import/enum/SystemExit silent-pass, missing policy total-disable) — each closed to FAIL CLOSED (v3.30.5) |
| `mutable-python-load-point` | high | resolved | A security check loading working-tree code/patterns/config can be neutralized by tampering that copy (even unstaged, or via startup files / PYTHONPATH); fix = run from the trusted committed HEAD copy under scrubbed `-S`, git-decided fallback (v3.30.5) |
| `cwd-on-syspath-under-dash-S` | high | resolved | `python3 -S -` (stdin) leaves CWD on sys.path — an unstaged repo-root `pathlib.py`/`yaml.py` shadowed a stdlib import inside the trusted wrapper and forced a pass (real AWS key slipped, verified); fix = trusted file-script from a temp dir + `PYTHONSAFEPATH=1` (v3.30.5) |
| `adversarial-review-convergence` | medium | resolved | v3.30.5 took TEN convergence rounds — real convergence (each round closed a DISTINCT named load-point on a finite ladder; last two independent reviewers both SHIP with RED→GREEN PoCs), not an infinite loop |
| `msys-git-command-substitution-hang` | medium | resolved | `$(git ls-tree …)` inside the hook intermittently HANGS under MSYS (a native git grandchild holds the substitution pipe open past exit → rc=124); fix = file-redirect capture (v3.30.5) |
| `transient-subagent-retry-discipline` | medium | resolved | Server-side rate-limit/529/drop mid-task is a SERVER issue — retry immediately (then ~1 min backoff), resume from intact WIP via SendMessage, poll liveness, verify final git state before trusting the agent |
| `gate-loop-wall-time-saturated-host` | medium | resolved (mitigated) | Full gate is ~90% of session wall-time on a saturated MSYS host; fix = `FF_ONLY` scoped inner-loop gates (release gate stays full/fail-closed) + batched preflight mirror-hashing (~6.7×) (v3.30.6) |
| `live-enforcement-inertness` | critical | resolved | Hook handlers read a Flow-schema event field (`user_prompt`/`agent_message`) the host never sends (`prompt`/`transcript_path`) — enforcement was INERT live while schema-shaped fixtures stayed green; fix = read the host's native event shape + native-shape fixtures (v3.30.7, Phase C S1/S1b) |
| `ci-red-invisible-no-release-gate` | high | resolved | The framework's own CI was RED at the hook-tests step for ~3 releases (v3.31.0/v4.1.0/v4.2.0) and published anyway — no in-repo release gate, the suite never completed on MSYS, and CI was never watched; fix = release `publish` job `needs: verify` (red suite ⇒ no Release) + watch-CI-via-API discipline (v4.2.0) |
| `ci-linux-msys-test-divergence` | high | resolved | Tests green on MSYS-local FAILED on Linux CI (invisible until the suite finally reached those steps): shallow-checkout `HEAD~1` rc128, a python-mask that collaterally removed git, `chmod +x` dirtying 644 `.sh`, and a new health-critical needing a manifest in fixtures — fixed `fetch-depth: 0` / git-preserving mask / `core.fileMode false` / fixture stamp (v4.2.0) |
| `fr25-upgrade-adoption-collision` | high | resolved | Enabling FR-25 on an existing repo hard-blocked the first monolith touch (shipped non-empty baseline defeats the warn-only grace), and the "re-key baseline" remedy self-collided with FR-07 (baseline is protected) — fixed delta-aware change gate (pre-existing over-ceiling may be touched/shrunk, not grown) + `--write-baseline` auto-mints the FR-07 approval (v4.3.0) |
| `deploy-approval-terminal-friction` | high | resolved | Agent forced the operator to run `approve-local.sh` terminal commands even after the operator typed the DP.6 phrase + said "you run it" — conflated self-approval (forbidden) with transcribing the operator's explicit authorization (routine); enforcement never checked the author anyway. Fixed: after DP.6, the Deploy session authors every required approval artifact on the operator's behalf, all tickets; authoring without the phrase stays forbidden (v4.3.0) |
| `gate-command-operator-friction` | high | resolved | The deploy-only fix above was never generalized, so FR-07 bootstrap approval and FR-25 baseline adoption still printed "operator-run / never agent-initiated" terminal rituals from hook stderr. Fixed: one governing **Operator Gate Protocol** (`role-discipline` shared) — operator authorizes in chat, the agent runs every command (mint/adopt/commit/consume/deploy); reworded all FR-07/FR-25/FR-12 carriers; enforcement backstops (protected-path block, secret scan, `--no-verify` deny) unchanged (v4.3.2) |
| `upgrade-backups-trip-secret-scan` | high | resolved | Flow's `hooks.pre-upgrade-<ts>/` + `policies.pre-upgrade-<ts>/` upgrade backups carry the OLD secret-scan test fixtures / secret-patterns (dummy `ghp_`/`sk-ant-`/cookie literals; `.pre-bootstrap`/`.pre-refresh` backups don't); a wholesale `git add -A` (FuseBase CLI `fusebase update`'s pre-update checkpoint) false-blocked on Flow's own backups, with misleading "rotate credential" advice, then left the blobs staged (`AD`) blocking every later commit. Fixed: scanner excludes ONLY the exact root-anchored fixture/policy backup twins (`hooks.pre-upgrade-<ts>/tests/fixtures/**`, `policies.pre-upgrade-<ts>/secret-patterns*.yml`, `<ts>`=`[0-9]{8}T[0-9]{6}Z` — NOT `*.pre-*` NOR loose `*T*Z`; Codex-xHigh caught both as scanner bypasses) + `upgrade.sh`/`bootstrap-upgrade.sh`/`post-fusebase-update.sh` git-exclude backups via `.git/info/exclude` (exact-ts, worktree-correct, newline-safe) so `git add -A` never stages them + accurate `hooks/git/pre-commit` block message (v4.4.1) |
