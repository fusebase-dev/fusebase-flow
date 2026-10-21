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
# CATEGORIES (MAJOR 11; 6.0.0-m8 M6-6): every protected-paths category is digest-bound and single use, so every one
# is minted here: `fusebase_flow_internals` (the default), `ci_cd_config` (`.github/workflows/**`) and any other the
# policy declares (`deployment_config`, `migration_and_schema`, a project's own). The operation per category comes from
# path_policy.operation_for, so writer and verifier read ONE definition. FF_BOOTSTRAP_TTL_MIN may not pass
# path_policy.edit_cap (60 minutes), and the artifact records `minted_on`, the commit HEAD is at: the commit that lands
# on it spends it, so a copy of it never approves the same bytes again.
#
# GO-AHEAD FORM (`--paths`, any category but ci_cd_config): one operator go-ahead in chat lets the agent edit AND
# commit named Flow files, minted BEFORE the change exists. The artifact names those exact paths and binds the commit
# HEAD is at instead of a staged digest: path_policy then allows the Edit/Write of a named path and a commit whose
# staged paths are all named, until a commit lands on that HEAD (moving HEAD back does not revive it) or it expires (at
# most GO_AHEAD_MAX_MINUTES); each use is audited.
#
# Usage:
#   bash hooks/local/write-bootstrap-approval.sh                          # staged internals
#   bash hooks/local/write-bootstrap-approval.sh --category ci_cd_config  # staged workflows (or another category)
#   bash hooks/local/write-bootstrap-approval.sh --paths <path>...        # go-ahead: named paths, before the edit
#   bash hooks/local/write-bootstrap-approval.sh --consume [--category X] # delete artifact(s)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APPROVALS_DIR="$ROOT/state/approvals"
TTL_MIN="${FF_BOOTSTRAP_TTL_MIN:-15}"   # short-lived: covers the setup commit only

CATEGORY="fusebase_flow_internals"
SLUG=""
CONSUME=0
GO_PATHS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --consume) CONSUME=1; shift ;;
        --category) CATEGORY="${2:-}"; shift 2 ;;
        --slug) SLUG="${2:-}"; shift 2 ;;
        --paths) shift; while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do GO_PATHS+=("$1"); shift; done
                 [ "${#GO_PATHS[@]}" -gt 0 ] || { echo "[bootstrap-approval] --paths needs at least one path" >&2; exit 2; } ;;
        --help|-h) sed -n '2,36p' "$0"; exit 0 ;;
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
        *)                       SLUG="$(printf '%s' "$CATEGORY" | tr '_' '-')" ;;
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

# Python in the pre-commit's order: python3, then python, then py -3, each proved 3.10+ by the pre-commit's probe, so
# a python.org Windows host (python and py, no python3) can mint too; the Store stub fails the probe.
_ff_is_py3() { "$@" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 10) else 1)' >/dev/null 2>&1; }
FF_PY=""
for FF_TRY in python3 python "py -3"; do
    # shellcheck disable=SC2086  # "py -3" is two words
    if _ff_is_py3 $FF_TRY; then FF_PY="$FF_TRY"; break; fi
done
if [ -z "$FF_PY" ]; then
    echo "[bootstrap-approval] no Python 3.10+ found (tried: python3, python, py -3) — cannot mint the digest-bound approval." >&2
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
# shellcheck disable=SC2086
PYTHONPATH="$ROOT/hooks" $FF_PY - "$ROOT" "$ARTIFACT" "$CATEGORY" "$TTL_MIN" "$SLUG" ${GO_PATHS[@]+"${GO_PATHS[@]}"} <<'PY'
import datetime, json, subprocess, sys
from pathlib import Path

root, artifact, category, ttl_min, slug = (
    sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
go_paths = sys.argv[6:]
sys.path.insert(0, str(Path(root) / "hooks"))
from shared.path_policy import (  # noqa: E402
    GO_AHEAD_MAX_MINUTES, _load_categories, compute_staged_tree_digest, edit_cap, is_protected, operation_for,
    staged_change_paths,
)

# TRIPWIRE: minting for a category the policy does not declare would produce an artifact no path can use.
known = sorted(_load_categories())
operation = operation_for(category) if category in known else None
if operation is None:
    print(f"[bootstrap-approval] '{category}' is not a category of policies/protected-paths.yml "
          f"(known: {', '.join(known)}) — refusing to mint.", file=sys.stderr)
    sys.exit(2)
cap = edit_cap(Path(root))
if not go_paths and not 1 <= ttl_min <= cap:
    print(f"[bootstrap-approval] refused: FF_BOOTSTRAP_TTL_MIN={ttl_min}: an approval lives 1 to {cap} minutes "
          "(approval-policy.yml, protected_path_edit)", file=sys.stderr)
    sys.exit(2)
head = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD^{commit}"], capture_output=True, text=True,
                      cwd=root).stdout.strip()

if go_paths:
    # TRIPWIRE: the go-ahead names exact repo-relative paths of THIS category, never a glob, and binds HEAD; a path
    # outside the category, or a longer life, would widen what one chat go-ahead lets an agent change.
    def problem(p: str) -> str:
        if p.startswith("/") or "\\" in p or ":" in p or any(s in ("", ".", "..") for s in p.split("/")):
            return "not a repo-relative path written with / (no leading /, no . or .. segment)"
        if any(ch in p for ch in "*?["):
            return "a glob; name each file"
        return "" if is_protected(p)[1] == category else f"not a {category} path"
    bad = [f"{p}: {why}" for p in go_paths if (why := problem(p))]
    if category == "ci_cd_config":  # a CI workflow stays digest-bound: minted after staging, never before the edit
        bad.insert(0, "--paths with --category ci_cd_config: a CI workflow is approved after staging, never by a go-ahead")
    if bad or ttl_min > GO_AHEAD_MAX_MINUTES or ttl_min < 1:
        for line in bad + ([f"FF_BOOTSTRAP_TTL_MIN={ttl_min}: a go-ahead lives 1 to {GO_AHEAD_MAX_MINUTES} minutes"]
                           if ttl_min > GO_AHEAD_MAX_MINUTES or ttl_min < 1 else []):
            print(f"[bootstrap-approval] refused: {line}", file=sys.stderr)
        sys.exit(2)
    if not head:
        print("[bootstrap-approval] refused: no commit yet; a go-ahead binds the commit HEAD is at", file=sys.stderr)
        sys.exit(2)
    from shared.approval_artifact import compute_repo_id  # noqa: E402
    from shared.audit_logger import emit  # noqa: E402
    paths, now = sorted(set(go_paths)), datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    expires = (now + datetime.timedelta(minutes=ttl_min)).strftime("%Y-%m-%dT%H:%M:%SZ")
    data = {
        "approved_by": slug, "scope": operation, "expires_at": expires,
        "created_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "reason": f"the operator's go-ahead in chat: edit and commit exactly these {category} paths",
        "action": "protected_path_edit", "operation": operation, "head_at_mint": head,
        "repo_id": compute_repo_id(Path(root)), "paths": paths,
    }
    Path(artifact).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    emit("approval_go_ahead_minted", decision="allow", rule_id="FR-07", root=Path(root),
         reason=f"FR-07: go-ahead {Path(artifact).name} minted for {len(paths)} {category} path(s), until {expires}",
         extra={"artifact": Path(artifact).name, "paths": paths, "head_at_mint": head})
    print(f"[bootstrap-approval] minted {artifact} (expires {expires}; the go-ahead for {len(paths)} named path(s): "
          f"{', '.join(paths)}; edit them and commit exactly them while HEAD stays at {head[:12]}; that commit spends it)")
    sys.exit(0)

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
from shared.approval_artifact import compute_repo_id  # noqa: E402
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
    "minted_on": head,                                    # the commit that lands on it spends it (M6-6)
    "repo_id": compute_repo_id(Path(root)),               # it never approves the same bytes in another checkout
    "paths": paths,
}
Path(artifact).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"[bootstrap-approval] minted {artifact} (expires {expires}; {len(paths)} path(s); digest {digest[:12]}…)")
PY
