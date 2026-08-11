# Implement handoff — Phase C Slice 5: po-investigate.sh read-only hardening

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.6. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-10 (reproduce-before-fix), FR-22. **Synchronous; bound long runs; no runaways; STOP at gate; do NOT bump VERSION/push/tag/deploy.** ONE coherent commit stacked on the current HEAD (Phase C S4). `hooks/local/po-investigate.sh` is NOT a `fusebase_flow_internals` protected path — no bootstrap approval needed (verify against policies/protected-paths.yml first; if a protected file IS touched, use the sanctioned single-use approval flow). NEVER `--no-verify`.

## Finding (Phase C audit M2 — security-adjacent; detail in tasks/wecmxwyrx.output + slice-plan §Slice 5)
`hooks/local/po-investigate.sh` is the read-only allowlist wrapper that lets the Product Owner run investigation Bash (diff/log/show/status/grep/ls/cat...) WITHOUT the Edit/Write tools. Its "structural read-only guarantee" is BREACHED: through the allowlisted `git diff` / `git log` / `git show` subcommands, forwarded args can REDIRECT OUTPUT or invoke EXTERNAL PROGRAMS and thereby WRITE/OVERWRITE files the Edit/Write tool would deny — e.g. `git diff --output=<path>` (writes to path), `git diff --ext-diff` + `GIT_EXTERNAL_DIFF=<cmd>` / `-c diff.external=<cmd>`, and pager/`-c core.pager=<cmd>` escapes. So a PO session that is supposed to be read-only can create/clobber files.

## Scope — ONE commit (harden the wrapper; keep legit read-only investigation working)
1. **REPRODUCE-BEFORE-FIX (FR-10):** demonstrate the breach on the current HEAD — e.g. `bash hooks/local/po-investigate.sh git diff --output=/tmp/po-breach.txt HEAD~1 HEAD` writes /tmp/po-breach.txt (a write via a "read-only" wrapper). Try the `GIT_EXTERNAL_DIFF` / `-c diff.external` / `-c core.pager` variants too. Record which escapes work.
2. **FIX:** in the diff/log/show (and any other subcommand that forwards args) branches, REJECT forwarded args/flags that redirect output or invoke an external program. At minimum reject: `--output`/`-o` (and `--output=…`), `--ext-diff`, `--no-ext-diff` is fine (keep), `-c` / `--config-env` config overrides (or specifically `-c diff.external=…`, `-c core.pager=…`, `-c *.external`, `-c core.editor=…`), `--pager`/pager overrides, `-O`/`--output-indicator*` if they can write, and any `=<path>` output form. Also SCRUB the environment for `GIT_EXTERNAL_DIFF`, `GIT_PAGER`, `GIT_EDITOR`, `GIT_SEQUENCE_EDITOR`, `PAGER` before invoking git (unset them), and force `--no-pager` / `GIT_PAGER=cat` where appropriate. Prefer a DENYLIST of the dangerous flags PLUS an env scrub (robust); if the wrapper already has an allowlist model for flags, extend it. Fail CLOSED: an unrecognized/blocked flag ⇒ the wrapper refuses (nonzero + a clear message), never silently forwards.
3. Keep legit read-only investigation fully working: `git diff HEAD~1 HEAD`, `git log --oneline -20`, `git show <sha>:<path>`, `git status`, `git grep`, etc. must still succeed unchanged.

## Do NOT
Do NOT broaden what the wrapper ALLOWS (this is a tightening). Do NOT touch protected paths / pre-commit chain / hooks/handlers. Do NOT bump VERSION/push/tag. Do NOT `--no-verify`.

## Gate (scoped) — stop, report, HALT
FR-10 RED→GREEN: each breach vector (`--output`, `GIT_EXTERNAL_DIFF`, `-c diff.external`, `-c core.pager`) now REFUSED (no file written) on the fixed wrapper; RED baseline recorded. Legit read-only commands still work (a small allow-suite). If there is a po-investigate test suite, run it; else add one (`hooks/tests/test-po-investigate.sh` if a home exists) with the RED→GREEN breach cases + the legit-still-works cases, wired if a tag slot exists. `bash -n` the wrapper; preflight green; SINGLE mirror --check 0-drift; check-module-size --all exit 0. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: commit SHA; FR-10 evidence (each write-escape vector RED→GREEN: refused, no file written; legit read-only still works); the denylist + env-scrub applied; confirmation nothing legit was broken + nothing new allowed; any new test file + wiring; scoped-gate numbers; VERSION unchanged. Do NOT push/tag/deploy.
