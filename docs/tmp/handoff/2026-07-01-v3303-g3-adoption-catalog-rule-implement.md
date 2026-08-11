# Implement handoff — v3.30.3 Group 3: WS1 (secret-scan + single-use protected-path exception + safe hook install) · WS7 (problem catalog) · WS8 (zero-trust liveness rule)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.2. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03, FR-05, FR-07 (this group EDITS a protected path — see note), FR-12 (secrets), FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated); no runaways; stop at the gate; do NOT bump VERSION/push/tag.**

## PROTECTED-PATH NOTE (FR-07 — sanctioned, not a bypass)
T7 edits `hooks/shared/path_policy.py` (a `fusebase_flow_internals` protected path). If the installed pre-commit blocks the commit, author the **sanctioned** `state/approvals/protected_path_edit-<slug>.json` approval artifact FIRST (the FR-07 way), then commit. **NEVER `--no-verify`.** T6/WS7/WS8 files are not protected.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `docs/specs/windows-msys-hardening/roadmap.md` — the **"Codex doc-review — FOLDED"** block is AUTHORITATIVE: WS1(a) keep excludes NARROW + runtime-construct tokens + negative test; WS1(b) exception must be **genuinely single-use** (staged-tree/path-digest-bound + short-TTL + exact-op + consume/cleanup); WS1(c) don't clobber custom `.git/hooks`; no `git add -A` in ACs; **WS1 review has a SECURITY dimension**. WS7/WS8 sections + §4 self-mistakes.
2. `hooks/tests/test-secret-scan-staged.sh` (`:22`, `:54` literal tokens), `hooks/shared/staged_secret_scan.py` (`_EXCLUDE_PATHSPECS`), `hooks/git/pre-commit`, `hooks/shared/path_policy.py` (`has_active_exception :62-80`, `evaluate`), `policies/protected-paths.yml` (`fusebase_flow_internals`, `on_unapproved_edit`), `hooks/local/install-git-hooks.sh`, `hooks/local/install.sh`, `hooks/local/upgrade.sh`, `hooks/local/post-fusebase-update.sh`.
3. `FLOW_RULES.md` FR-27 row (`:36`) + `flow-skills/liveness-discipline/SKILL.md` + role-discipline § Write-time discipline digest (FR-24 channel). `docs/backlog/` (for the catalog's sibling convention).

## Scope — one task = one commit.

- **T6 (WS1a) — secret-scan: runtime tokens, NARROW excludes, negative test, release-gate self-test.**
  - In `hooks/tests/test-secret-scan-staged.sh:22,54` **construct the designed tokens at runtime** (e.g. `SECRET="ghp_$(printf 'x%.0s' $(seq 1 36))"`; build both `sed` tokens the same way) so **no literal PAT is a committed `+` line**. Keep `_EXCLUDE_PATHSPECS` NARROW — do NOT `:(exclude)hooks/tests/`; the runtime-token approach means nothing new needs excluding (leave the 3 existing designed-token excludes as-is).
  - **Negative test:** a real hard-coded secret in a DIFFERENT `hooks/tests/*.sh` (non-designed) still BLOCKS the scan (proves the narrow-exclude didn't blind the scanner).
  - **Release-gate self-test:** stage the entire release tree through the fixed pre-commit and assert exit 0 — via a **temp clone or an explicit path-staging list** (NO `git add -A`). Wire into run-tests.
- **T7 (WS1b/c) — single-use protected-path exception + safe hook install.**
  - **Single-use exception:** the approval artifact `install.sh`/`upgrade.sh --wire-hooks` writes for the setup/upgrade commit must be **bound to the staged tree/path digest** (of exactly the Flow-internal changeset), **short-TTL**, **exact-operation**, and **consumed/cleaned after the commit passes**. Extend `path_policy.has_active_exception` so a plain path+TTL artifact is NOT sufficient (the digest+op binding is required for the internals-bootstrap category). **AC:** after the setup commit, a *second, unrelated* protected-path edit still DENIES.
  - **Bootstrap writer:** `install.sh` (fresh) + `upgrade.sh`/`post-fusebase-update.sh --wire-hooks` write the artifact for their own changeset so the documented `git add <paths> && git commit` passes WITHOUT `--no-verify`.
  - **Safe hook (re)install:** `install-git-hooks.sh` / the upgrade path must **detect a Flow-managed marker/hash** on `.git/hooks/pre-commit`, and **back up or warn** on a custom hook (require explicit opt-in to overwrite) — never silent clobber. `upgrade.sh`/`post-fusebase-update.sh` (re)install/refresh the Flow hook (fixing the "upgrade doesn't wire the fixed pre-commit" gap). Correct the release-note/consumer-guidance wording accordingly.
  - **Tests:** fresh-install + upgrade setup commit passes through the wired hook (no `--no-verify`); reuse-denial (2nd unrelated protected-path edit denies); a pre-existing custom `.git/hooks/pre-commit` is preserved/backed-up.
- **T8 (WS7) — internal problem catalog.** Create `docs/problem-catalog/` with one entry per issue (**problem → root cause → resolution → guardrail**): this batch's field issues + the **two self-mistakes** (roadmap §4: non-existent `mirror-skills --check` → manifest truncation; the inaccurate "upgrade installs the fixed pre-commit" consumer prompt). Add an index. Wire a pointer into the session/ticket-start routine (role-discipline § digest / FR-24 channel + `hooks/handlers/session_start.py` if appropriate) so it's read before future work. Pointer-style (FR-23) — no restatement.
- **T9 (WS8) — mandatory zero-trust subagent-liveness rule.** Extend the FR-27 row + `flow-skills/liveness-discipline/SKILL.md`: *never trust or passively wait on a subagent/Codex completion ping; proactively poll its liveness often (git-progress/process, not the 0-byte transcript); on transient rate-limit/stall, re-dispatch or SendMessage-resume (wait ~60s, retry until it starts); verify final git state (clean linear history, 0 mirror drift) before trusting it.* Add the FR-24 write-time digest line so it's present-by-construction. **FR-07:** the FR-27 rule ROW may be extended (this is an intentional FR change — allowed for a rule improvement, not a version-attestation-only edit) — keep it minimal + do NOT alter other FR rows / the 3 deploy-policy semantics / ratchet.

## FR-07 / hard rules
No diff to OTHER FR rows / the 3 deploy-policy rule semantics / ratchet-governance.yml (T9 extends ONLY the FR-27 row + liveness skill). The secret scanner must still block real secrets (narrow excludes). The single-use exception must NOT become a standing bypass. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ secret scanner still blocks real secrets  ☐ exception single-use (reuse-denies)  ☐ custom .git/hooks preserved  ☐ no --no-verify
☐ only FR-27 row extended (T9); other FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n`/`py_compile` changed files · run-tests PASS incl. new tests (negative-secret-blocks · release-gate-self-test · reuse-denial · custom-hook-preserved · fresh/upgrade-commit-passes) (bounded; per-phase 0-FAIL) · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** · FR-07 clean (only FR-27 extended). Emit the FR-22 marker; produce the gate report; HALT. A FuseBase security-aware + Codex adversarial review runs after the v3.30.3 groups.

## Return
Gate report: per-task SHAs (T6-T9), AC evidence (T6 runtime-tokens + negative-secret-blocks + release-gate-self-test; T7 fresh+upgrade-commit-passes-no-noverify + reuse-denial + custom-hook-preserved; T8 catalog populated + wired; T9 FR-27 extended + digest), no-regression, gate numbers, FR-07 (only FR-27 row extended), + note the protected-path approval artifact used (if any). Do NOT push/tag.
