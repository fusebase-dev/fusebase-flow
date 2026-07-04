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
