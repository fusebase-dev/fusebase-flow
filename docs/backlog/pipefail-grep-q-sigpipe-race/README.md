# pipefail-grep-q-sigpipe-race

**Status:** open — not scheduled. **Filed:** 2026-10-13 (v5.10 pre-tag hosted run 38342435289). **Severity:** medium (intermittent red release gates). **Surface:** shell scripts under `set -o pipefail` that pipe a separate writer into an early-exiting reader (`… | grep -q`, `grep -qx`, `head -n1`).

## Observed

`git-capture-guard gated-list-covers-the-commit-and-release-surface` failed once on hosted Windows (`list=8 files; pre-commit or the release phase is missing`) although `check-git-capture.sh --list` prints a static array containing both required paths. Mechanism: `grep -q` exits on its first match; if the writer still has output to write it takes SIGPIPE, and `pipefail` makes the pipeline false even though the match succeeded. The matched entry (`hooks/git/pre-commit`) is the FIRST line, the worst case. Pre-existing (test unchanged since 2026-09-10); fixed at that one site by T140 (capture once, match via here-string).

## Scope of the class

`rg '\|\s*grep\s+-[a-zA-Z]*q' hooks/` → 381 occurrences in 64 files (2026-10-13), including shipped hooks (`hooks/git/commit-msg`, `hooks/local/upgrade.sh`, `post-fusebase-update.sh`). A site is racy only when ALL hold: `pipefail` is active in that shell; the writer is a separate process (external command or `bash script`), or a builtin whose output can span several writes; output continues after the matched line. Single short `printf '%s' "$var" |` writes are usually safe but not guaranteed.

## Ask

Classify the 381 sites by those criteria, convert the racy ones to capture-then-match (here-string) or `grep … >/dev/null` without `-q`, and add a cheap static guard (like `check-git-capture.sh`) that rejects new `| grep -q` in pipefail scripts unless the writer is a here-string. Ship as its own outcome with a mutation proving the guard; touches `hooks/git/**` (FR-07 protected) — single-use approval for those files.
