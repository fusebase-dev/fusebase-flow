#!/usr/bin/env bash
# Fusebase Flow — FR-25 module-size ratchet (wrapper for hooks/shared/module_size.py).
#
# Usage:
#   bash hooks/local/check-module-size.sh                   # --staged (pre-commit default)
#   bash hooks/local/check-module-size.sh --worktree        # changes vs HEAD (Stop-hook use)
#   bash hooks/local/check-module-size.sh --all             # every tracked source file
#   bash hooks/local/check-module-size.sh --write-baseline  # (re)generate the committed
#                                                           # baseline — operator-run only
#   bash hooks/local/check-module-size.sh --write-baseline <path>  # re-key ONE row
#                                                           # (rename remedy; no global amnesty)
#
# Policy: policies/module-size.yml (+ optional gitignored module-size.local.yml).
# Exit 1 = ratchet violation under enforcement=block; warn-only while no baseline.
#
# ADOPTION (FR-07): the baseline is a protected path. --write-baseline stages the new
# baseline and mints a single-use FR-07 approval bound to that staged change, so the
# operator can commit the adoption the sanctioned way (NOT --no-verify). Non-write
# modes exec module_size.py directly (unchanged behavior).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
    python_bin="python"
fi
if ! command -v "$python_bin" >/dev/null 2>&1; then
    echo "[module-size] python not found; skipping FR-25 check" >&2
    exit 0
fi

is_write_baseline=0
for a in "$@"; do [ "$a" = "--write-baseline" ] && is_write_baseline=1; done

if [ "$is_write_baseline" -eq 1 ]; then
    "$python_bin" "$ROOT/hooks/shared/module_size.py" "$@"
    rc=$?
    [ "$rc" -ne 0 ] && exit "$rc"
    # Derive the baseline path from the COMMITTED policy (HEAD:policies/module-size.yml),
    # NOT the worktree copy — a worktree edit of the (protected) module-size.yml could
    # otherwise redirect the auto-mint at a DIFFERENT protected file (Fable review). Fall
    # back to the shipped default. Reading from HEAD means a redirect requires a COMMITTED
    # policy change, which itself hits FR-07.
    baseline_file="$(cd "$ROOT" && git show HEAD:policies/module-size.yml 2>/dev/null | "$python_bin" -c "import sys,yaml; d=(yaml.safe_load(sys.stdin.read()) or {}); print(d.get('baseline_file') or 'policies/module-size-baseline.txt')" 2>/dev/null)"
    [ -z "$baseline_file" ] && baseline_file="policies/module-size-baseline.txt"
    approval="$ROOT/hooks/local/write-bootstrap-approval.sh"
    if [ -f "$approval" ] && [ -f "$ROOT/$baseline_file" ] && ( cd "$ROOT" && git rev-parse --git-dir >/dev/null 2>&1 ); then
        ( cd "$ROOT" && git add -- "$baseline_file" 2>/dev/null )
        # Only proceed if the committed-baseline path ACTUALLY has a staged change. If a
        # worktree redirect made module_size.py write elsewhere, the real baseline is
        # unchanged -> nothing staged here -> do not mint.
        if ! ( cd "$ROOT" && git diff --cached --name-only -- "$baseline_file" | grep -Fqx "$baseline_file" ); then
            echo "[module-size] baseline unchanged (nothing to adopt, or a redirected write) — not minting." >&2
            exit 0
        fi
        # SAFETY (FR-07, FAIL-CLOSED): write-bootstrap-approval.sh mints a single-use approval
        # over the WHOLE staged protected set, not just the baseline. Auto-mint ONLY on an
        # AFFIRMATIVE verification that the baseline is the sole staged protected path. The
        # scope check passes the baseline path via ENV (never string-interpolated into -c
        # source -> no injection from a hostile module-size.yml, which is read from the
        # worktree), and prints "SCOPE_OK" as its first line ONLY on success. Any failure
        # (import error, SystemExit from policy_loader, empty output, nonzero rc, other
        # protected paths) yields no leading "SCOPE_OK" -> refuse to mint.
        scope_out="$(cd "$ROOT" && MSB_BASELINE="$baseline_file" "$python_bin" - <<'PY' 2>/dev/null
import os, sys
sys.path.insert(0, "hooks")
from pathlib import Path
from shared import path_policy
b = os.environ.get("MSB_BASELINE", "")
others = [p for p in path_policy.staged_change_paths(Path(".")) if p != b and path_policy.is_protected(p)[0]]
if others:
    print("OTHER_PROTECTED")
    for p in others:
        print(p)
else:
    print("SCOPE_OK")
PY
)"
        scope_rc=$?
        scope_first="$(printf '%s\n' "$scope_out" | head -n1)"
        if [ "$scope_rc" -eq 0 ] && [ "$scope_first" = "SCOPE_OK" ] && bash "$approval" >/dev/null 2>&1; then
            echo "[module-size] FR-07 approval minted (single-use, baseline-only) for the staged baseline change."
            echo "[module-size] Sanctioned adoption commit (baseline is a protected path; NOT --no-verify):"
            echo "    git commit -m 'chore(fr25): adopt module-size baseline' && bash hooks/local/write-bootstrap-approval.sh --consume"
        else
            echo "[module-size] NOT auto-minting (fail-closed): could not affirmatively verify the baseline is the ONLY staged protected path." >&2
            printf '%s\n' "$scope_out" | grep -vxE 'SCOPE_OK|OTHER_PROTECTED' | sed 's/^/      staged protected: /' >&2
            echo "[module-size] Adopt the baseline on its own — unstage any other protected path, then:" >&2
            echo "      git add -- $baseline_file && bash hooks/local/write-bootstrap-approval.sh && git commit -m 'chore(fr25): adopt module-size baseline' && bash hooks/local/write-bootstrap-approval.sh --consume" >&2
        fi
    fi
    exit 0
fi

# All args forwarded; a bare path is only valid after --write-baseline.
exec "$python_bin" "$ROOT/hooks/shared/module_size.py" "${@:---staged}"
