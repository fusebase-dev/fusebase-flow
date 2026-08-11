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
# AGENT-EXECUTED on the operator's chat approval, NOT an operator terminal ritual: when the
# operator OKs the protected-path change in chat, the AGENT runs `mint -> git commit -> --consume`
# on their behalf (upgrade.sh / post-fusebase-update.sh print them; operator runs nothing; minting
# with no operator approval = self-approval, forbidden). Single-use holds even if `--consume` is
# skipped: the artifact is digest-bound to the committed changeset and self-expires (TTL 15 min).
#
# CATEGORIES (MAJOR 11): every protected-paths category that path_policy enforces as
# digest-bound is mintable here — currently `fusebase_flow_internals` (the default, byte-for-
# byte the previous behaviour) and `ci_cd_config` (`.github/workflows/**`). Before this, the
# published protocol told the agent to mint a digest-bound approval for a workflow edit and
# NO shipped writer could: this script collected internals paths only, and approve-local.sh
# emitted no `paths` at all. The operation string per category comes from path_policy's
# _DIGEST_BOUND_OPERATIONS, so writer and verifier read ONE definition.
#
# Usage:
#   bash hooks/local/write-bootstrap-approval.sh                          # staged internals
#   bash hooks/local/write-bootstrap-approval.sh --category ci_cd_config  # staged workflows
#   bash hooks/local/write-bootstrap-approval.sh --consume [--category X] # delete artifact(s)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APPROVALS_DIR="$ROOT/state/approvals"
TTL_MIN="${FF_BOOTSTRAP_TTL_MIN:-15}"   # short-lived: covers the setup commit only

CATEGORY="fusebase_flow_internals"
SLUG=""
CONSUME=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --consume) CONSUME=1; shift ;;
        --category) CATEGORY="${2:-}"; shift 2 ;;
        --slug) SLUG="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "[bootstrap-approval] unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Filename slug per category. The default keeps the historical `flow-bootstrap` name, so an
# existing `--consume` caller (upgrade.sh, post-fusebase-update.sh, check-module-size.sh)
# removes exactly what it removed before.
if [ -z "$SLUG" ]; then
    case "$CATEGORY" in
        fusebase_flow_internals) SLUG="flow-bootstrap" ;;
        ci_cd_config)            SLUG="ci-workflow" ;;
        *) echo "[bootstrap-approval] no default slug for category '$CATEGORY' — pass --slug" >&2; exit 2 ;;
    esac
fi
case "$SLUG" in
    *[!A-Za-z0-9._-]*|"") echo "[bootstrap-approval] unsafe slug: '$SLUG'" >&2; exit 2 ;;
esac

# Consume path: remove the artifact(s) for THIS slug once the setup commit has passed.
if [ "$CONSUME" -eq 1 ]; then
    removed=0
    for f in "$APPROVALS_DIR"/protected_path_edit-"$SLUG"-*.json; do
        [ -f "$f" ] || continue
        rm -f "$f"; removed=$((removed + 1))
    done
    echo "[bootstrap-approval] consumed $removed '$SLUG' approval artifact(s)"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[bootstrap-approval] python3 not on PATH — cannot mint the digest-bound approval." >&2
    exit 1
fi

mkdir -p "$APPROVALS_DIR"
DATE_STAMP="$(date -u +%Y%m%d)"
ARTIFACT="$APPROVALS_DIR/protected_path_edit-${SLUG}-${DATE_STAMP}.json"

# Mint via the SAME path_policy the hook reads, so the tree_digest AND the per-category
# operation string are produced by the exact code that later verifies them (no drift between
# writer and verifier). The script collects the staged paths of the requested category,
# computes the digest, and writes the artifact with the required protected-paths.yml fields
# + operation + tree_digest.
PYTHONPATH="$ROOT/hooks" python3 - "$ROOT" "$ARTIFACT" "$CATEGORY" "$TTL_MIN" "$SLUG" <<'PY'
import datetime, json, sys
from pathlib import Path

root, artifact, category, ttl_min, slug = (
    sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
sys.path.insert(0, str(Path(root) / "hooks"))
from shared.path_policy import (  # noqa: E402
    _DIGEST_BOUND_OPERATIONS, compute_staged_tree_digest, is_protected, staged_change_paths,
)

# TRIPWIRE: minting for a category the VERIFIER does not treat as digest-bound would produce
# an artifact whose single-use property is decoration. Refuse rather than mislead.
operation = _DIGEST_BOUND_OPERATIONS.get(category)
if operation is None:
    print(f"[bootstrap-approval] '{category}' is not a digest-bound category "
          f"(known: {', '.join(sorted(_DIGEST_BOUND_OPERATIONS))}) — refusing to mint an "
          "artifact the gate would not enforce as single-use.", file=sys.stderr)
    sys.exit(2)

# Full staged change set (A/C/M + DELETES + rename src/dst) so a sanctioned delete or
# rename of a protected path can be approved via the SAME artifact — writer
# and verifier share staged_change_paths, so they never drift (T23).
staged = staged_change_paths(Path(root))
# Only the requested category's paths need the exception; scope it tight.
paths = [p for p in staged if is_protected(p)[1] == category]
if not paths:
    print(f"[bootstrap-approval] no staged {category} paths — nothing to approve")
    sys.exit(0)

digest = compute_staged_tree_digest(paths, Path(root))
now = datetime.datetime.utcnow()
expires = (now + datetime.timedelta(minutes=ttl_min)).strftime("%Y-%m-%dT%H:%M:%SZ")
data = {
    "approved_by": slug,
    "scope": operation,
    "expires_at": expires,
    "created_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),   # additive (M9); age, never authority
    "reason": f"sanctioned {category} changeset — single-use, digest-bound (WS1b)",
    "action": "protected_path_edit",
    "operation": operation,
    "tree_digest": digest,
    "paths": paths,
}
Path(artifact).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"[bootstrap-approval] minted {artifact} (expires {expires}; {len(paths)} path(s); digest {digest[:12]}…)")
PY
