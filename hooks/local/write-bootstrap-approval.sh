#!/usr/bin/env bash
# Fusebase Flow — write a SINGLE-USE bootstrap protected-path approval (WS1b).
#
# A fresh install and a self-upgrade both need to make the documented setup/upgrade
# commit through Flow's own just-installed pre-commit, which blocks unapproved edits
# to fusebase_flow_internals paths. This authors the SANCTIONED exception (the FR-07
# way — NOT a --no-verify bypass): a short-TTL artifact bound to the EXACT staged
# changeset (tree_digest via path_policy.compute_staged_tree_digest) and to the exact
# operation (flow-internals-bootstrap). Because the digest binds to the staged content
# and mode, the artifact authorizes ONLY this changeset — a later, unrelated
# protected-path edit produces a different digest and still DENIES (single-use).
#
# OPERATOR-DRIVEN, not auto-consumed: upgrade.sh / post-fusebase-update.sh PRINT the
# `mint -> git commit -> --consume` steps as recommended next actions; the operator
# runs them. Single-use holds even if `--consume` is skipped: a lingering post-commit
# artifact is digest-bound to the (now-committed) changeset, so it matches NO new
# staged changeset, and it self-expires (TTL, default 15 min; FF_BOOTSTRAP_TTL_MIN).
#
# Usage:
#   bash hooks/local/write-bootstrap-approval.sh              # mint for the staged internals
#   bash hooks/local/write-bootstrap-approval.sh --consume    # delete the bootstrap artifact(s)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APPROVALS_DIR="$ROOT/state/approvals"
OPERATION="flow-internals-bootstrap"
TTL_MIN="${FF_BOOTSTRAP_TTL_MIN:-15}"   # short-lived: covers the setup commit only

CONSUME=0
for arg in "$@"; do
    case "$arg" in
        --consume) CONSUME=1 ;;
        --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "[bootstrap-approval] unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# Consume path: remove any bootstrap artifact(s) once the setup commit has passed.
if [ "$CONSUME" -eq 1 ]; then
    removed=0
    for f in "$APPROVALS_DIR"/protected_path_edit-flow-bootstrap-*.json; do
        [ -f "$f" ] || continue
        rm -f "$f"; removed=$((removed + 1))
    done
    echo "[bootstrap-approval] consumed $removed bootstrap approval artifact(s)"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[bootstrap-approval] python3 not on PATH — cannot mint the digest-bound approval." >&2
    exit 1
fi

mkdir -p "$APPROVALS_DIR"
DATE_STAMP="$(date -u +%Y%m%d)"
ARTIFACT="$APPROVALS_DIR/protected_path_edit-flow-bootstrap-${DATE_STAMP}.json"

# Mint via the SAME path_policy the hook reads, so the tree_digest is computed by the
# exact code that later verifies it (no drift between writer and verifier). The script
# collects the staged protected-internals paths, computes the digest, and writes the
# artifact with the required protected-paths.yml fields + operation + tree_digest.
PYTHONPATH="$ROOT/hooks" python3 - "$ROOT" "$ARTIFACT" "$OPERATION" "$TTL_MIN" <<'PY'
import datetime, json, sys
from pathlib import Path

root, artifact, operation, ttl_min = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
sys.path.insert(0, str(Path(root) / "hooks"))
from shared.path_policy import (  # noqa: E402
    compute_staged_tree_digest, is_protected, staged_change_paths,
)

# Full staged change set (A/C/M + DELETES + rename src/dst) so a sanctioned delete or
# rename of a protected internals path can be approved via the SAME artifact — writer
# and verifier share staged_change_paths, so they never drift (T23).
staged = staged_change_paths(Path(root))
# Only the fusebase_flow_internals paths need the exception; scope it tight.
paths = [p for p in staged if is_protected(p)[1] == "fusebase_flow_internals"]
if not paths:
    print("[bootstrap-approval] no staged fusebase_flow_internals paths — nothing to approve")
    sys.exit(0)

digest = compute_staged_tree_digest(paths, Path(root))
expires = (datetime.datetime.utcnow() + datetime.timedelta(minutes=ttl_min)).strftime("%Y-%m-%dT%H:%M:%SZ")
data = {
    "approved_by": "flow-bootstrap",
    "scope": "flow-internals-bootstrap",
    "expires_at": expires,
    "reason": "install/upgrade setup commit — single-use, digest-bound (WS1b)",
    "action": "protected_path_edit",
    "operation": operation,
    "tree_digest": digest,
    "paths": paths,
}
Path(artifact).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"[bootstrap-approval] minted {artifact} (expires {expires}; {len(paths)} path(s); digest {digest[:12]}…)")
PY
