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
| `bounded-run-msys-collateral-kill` | high | resolved (core) / v3.30.4 (hard) | MSYS `taskkill //T` over-killed (255 collateral: caller/harness/other sessions) and returned rc0-on-kill; ancestor-resolution + PID reuse |
| `health-check-false-broken-rc0-on-kill` | high | resolved | Healthy install read BROKEN on Ovation — rc0-on-kill hit the `rc0+no-PASS+no-FAIL⇒BROKEN` branch; fixed at root (true-124-on-kill), fail-closed guard preserved |
| `truncated-manifest-on-bound-hit` | medium | resolved | Self-mistake: release shipped a truncated skill-mirror manifest — bound-hit mid-write + `mirror-skills --check` (a non-existent flag) ran a concurrent full mirror |
| `inaccurate-consumer-prompt` | medium | resolved | Self-mistake: consumer apply-prompt claimed "the upgrade installs the fixed pre-commit" — false; asserted tool behavior without verifying it against source |
