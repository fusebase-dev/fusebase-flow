#!/usr/bin/env bash
# Fusebase Flow — deploy-approval receipt (schema fusebase-flow/deploy-approval-receipt/v1).
#
# WHY THIS EXISTS: state/approvals/* is gitignored, so a committed deploy report that cites
# `state/approvals/<action>-<slug>-<date>.json` as its authorization evidence dangles on every
# fresh clone. This emits a clone-durable RECEIPT that travels inside the committed report.
# Contract owner: docs/specs/consumer-escalation-v480/spec.md § "S2 closure C3 - LOCKED
# receipt contract" (AC10-AC13).
#
# EVIDENCE LIMITS — do not overclaim. The receipt shows that an approval artifact with the
# recorded digest was READ AND VALIDATED at `observed_at`, and what that artifact bound. It
# does NOT authenticate the operator (`approved_by` is unauthenticated audit metadata —
# decision K3) and cannot prove the artifact was not fabricated by whoever ran the deploy.
#
# THE GATE IS UNCHANGED. This emits evidence; it enforces nothing. The pre-deploy gate stays
# hooks/shared/command_policy.py + path_policy.py over the live, gitignored artifact.
#
# Usage:
#   bash hooks/local/lib/approval-receipt.sh emit <action> <slug> --deploy-hash <hash> \
#        [--command '<exact command>'] [--artifact <path>] [--format markdown|json]
#   bash hooks/local/lib/approval-receipt.sh verify <committed-report-file>
#   (also reachable as: bash hooks/local/approve-local.sh --receipt <same args>)
#
# emit exit: 0 receipt emitted and observed_verdict is VALID; 3 receipt emitted but the
#   artifact did NOT validate (the receipt still records the truthful verdict — never suppress
#   it); 2 bad usage / unverifiable input (NO receipt); 1 unreadable or non-object artifact.
# verify exit: 0 the report satisfies the v1 contract; 1 it does not; 2 bad usage.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

MODE="${1:-}"
[ "$#" -gt 0 ] && shift

case "$MODE" in
    emit|verify) ;;
    --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "[approval-receipt] usage: $0 emit <action> <slug> --deploy-hash <hash> ... | $0 verify <report>" >&2; exit 2 ;;
esac

ACTION=""; SLUG=""; DEPLOY_HASH=""; COMMAND_STR=""; ARTIFACT=""; FORMAT="markdown"
REPORT=""; COMMAND_GIVEN=0; positional=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --deploy-hash) DEPLOY_HASH="${2:-}"; shift 2 ;;
        --command) COMMAND_STR="${2:-}"; COMMAND_GIVEN=1; shift 2 ;;
        --artifact) ARTIFACT="${2:-}"; shift 2 ;;
        --format) FORMAT="${2:-}"; shift 2 ;;
        --*) echo "[approval-receipt] unknown option: $1" >&2; exit 2 ;;
        *)
            if [ "$MODE" = "verify" ]; then
                [ "$positional" -eq 0 ] || { echo "[approval-receipt] unexpected argument: $1" >&2; exit 2; }
                REPORT="$1"
            else
                case "$positional" in
                    0) ACTION="$1" ;;
                    1) SLUG="$1" ;;
                    *) echo "[approval-receipt] unexpected argument: $1" >&2; exit 2 ;;
                esac
            fi
            positional=$((positional + 1)); shift ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "[approval-receipt] python3 not on PATH — cannot read approval artifacts." >&2
    exit 1
fi

if [ "$MODE" = "emit" ] && { [ -z "$ACTION" ] || [ -z "$SLUG" ]; }; then
    echo "[approval-receipt] usage: $0 emit <action> <slug> --deploy-hash <hash> [--command '<exact command>']" >&2
    exit 2
fi
if [ "$MODE" = "verify" ] && [ -z "$REPORT" ]; then
    echo "[approval-receipt] usage: $0 verify <committed-report-file>" >&2
    exit 2
fi

MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - \
    "$MODE" "$ROOT" "$ACTION" "$SLUG" "$DEPLOY_HASH" "$COMMAND_STR" "$COMMAND_GIVEN" \
    "$ARTIFACT" "$FORMAT" "$REPORT" <<'PY'
import hashlib, json, re, sys
from datetime import timezone
from pathlib import Path

(mode, root, action, slug, deploy_hash, command_str, command_given,
 artifact_arg, fmt, report_arg) = sys.argv[1:11]
root_path = Path(root)
sys.path.insert(0, str(root_path / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    compute_command_digest, compute_repo_id, evaluate_artifact, now_utc, parse_expiry,
)

RECEIPT_SCHEMA = "fusebase-flow/deploy-approval-receipt/v1"
STAMP = "%Y-%m-%dT%H:%M:%SZ"

# TRIPWIRE: this ordered list IS the LOCKED C3 surface (spec.md § "S2 closure C3 - LOCKED
# receipt contract"). Adding, renaming or dropping an entry is a NEW DECISION, never an
# implementation detail — and `verify` below reads the same list, so a local edit silently
# redefines what every committed report is checked against.
IDENTITY = ["receipt_schema", "approval_artifact_schema", "approval_artifact_digest"]
COPIED = ["action", "repo_id", "command_digest", "scope", "created_at", "expires_at",
          "approved_by", "reason"]
COMPUTED = ["observed_at", "observed_verdict", "remaining_ttl_seconds"]
BINDING = ["deploy_hash"]
FIELDS = IDENTITY + COPIED + COMPUTED + BINDING

# Field names the artifact does NOT have. A receipt (or report) carrying one of these is
# asserting a stored field that no writer ever wrote — hooks/local/approve-local.sh stores
# `created_at`, and neither a `ttl` nor a `verdict`.
FORBIDDEN = ["approved_at", "ttl", "verdict"]

SOURCE_LABEL = {
    "receipt_schema": "receipt identity",
    "approval_artifact_schema": "stored (approval artifact)",
    "approval_artifact_digest": "computed - sha256 of the exact validated artifact bytes",
    "observed_at": "computed at validation",
    "observed_verdict": "computed at validation - NOT a stored field",
    "remaining_ttl_seconds": "computed at validation (`expires_at` - `observed_at`) - NOT a stored `ttl`",
    "deploy_hash": "deployment binding",
}
for _f in COPIED:
    SOURCE_LABEL[_f] = "stored (copied verbatim from the approval artifact)"

LIMITS = (
    "Evidence limits: this receipt records that an approval artifact with the digest above "
    "was read and validated at `observed_at`, and what it bound. It does NOT authenticate "
    "the operator (`approved_by` is unauthenticated audit metadata - decision K3) and cannot "
    "prove the artifact was not fabricated by whoever ran the deploy. The live artifact stays "
    "gitignored and mandatory; the pre-deploy gate is unchanged."
)
MARKER = f"<!-- {RECEIPT_SCHEMA} -->"

PLACEHOLDERS = {"tbd", "see commit", "see-commit", "seecommit", "pending", "n/a", "na",
                "none", "unknown", "hash", "deploy hash"}


def fail(msg: str, code: int) -> None:
    print(f"[approval-receipt] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def cell(value) -> str:
    """One table cell. `|` and newlines are ESCAPED, never dropped — `reason` is free text
    (approve-local.sh round-trips quotes/newlines/unicode) and an unescaped one would break
    the table the verifier parses. The `json` format is the byte-faithful one."""
    if value is None:
        return "(absent)"
    text = str(value).replace("\\", "\\\\").replace("|", "\\|")
    text = text.replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n")
    return f"`{text}`"


def render_markdown(receipt: dict) -> str:
    rows = ["| Field | Value | Source |", "|---|---|---|"]
    for f in FIELDS:
        rows.append(f"| `{f}` | {cell(receipt[f])} | {SOURCE_LABEL[f]} |")
    return "\n".join([MARKER, ""] + rows + ["", LIMITS])


def do_emit() -> None:
    dh = deploy_hash.strip()
    if not dh or dh.lower() in PLACEHOLDERS or re.search(r"\s", dh) or "<" in dh or ">" in dh:
        fail("--deploy-hash must be the real captured hash (DP.3: no 'TBD' / 'see commit' / "
             "'<hash>' placeholder, no spaces).", 2)

    if artifact_arg.strip():
        path = Path(artifact_arg)
    else:
        approvals = root_path / "state" / "approvals"
        today = now_utc().strftime("%Y%m%d")
        path = approvals / f"{action}-{slug}-{today}.json"
        if not path.is_file():
            found = sorted(approvals.glob(f"{action}-{slug}-*.json"))
            if len(found) == 1:
                path = found[0]
            elif not found:
                fail(f"no approval artifact for action={action!r} slug={slug!r}; "
                     "author it first (hooks/local/approve-local.sh) or pass --artifact.", 1)
            else:
                fail(f"{len(found)} artifacts match {action}-{slug}-*.json; "
                     "disambiguate with --artifact <path>.", 2)

    # TRIPWIRE (AC11): ONE read. The digest and the verdict below are both derived from THIS
    # byte string, so the receipt can never attest a digest for bytes other than the ones that
    # were validated. Never re-open the file to hash it.
    try:
        raw = path.read_bytes()
    except OSError as e:
        fail(f"approval artifact unreadable ({e}); no receipt emitted.", 1)
    digest = "sha256:" + hashlib.sha256(raw).hexdigest()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as e:
        fail(f"approval artifact is not UTF-8 JSON ({e}); no receipt emitted.", 1)
    if not isinstance(data, dict):
        fail("approval artifact is not a JSON object; no receipt emitted.", 1)

    # Fail-closed: a command-bound artifact whose binding cannot be checked would produce a
    # BINDING_MISMATCH that is an artifact of MISSING INPUT, not of the approval. Refuse to
    # emit rather than publish a misleading verdict.
    if isinstance(data.get("command_digest"), str) and data["command_digest"].strip() \
            and command_given != "1":
        fail("this artifact is command-bound; pass --command '<exact command>' so the "
             "binding is actually verified before a receipt claims a verdict.", 2)

    # TRIPWIRE: truncate to whole seconds BEFORE both the stamp and the arithmetic. The stamp
    # format has second resolution, so a sub-second `observed` makes the published
    # `remaining_ttl_seconds` disagree with `expires_at - observed_at` as printed.
    observed = now_utc().replace(microsecond=0)
    verdict = evaluate_artifact(
        data, expected_action=action,
        command_digest=compute_command_digest(command_str) if command_given == "1" else None,
        repo_id=compute_repo_id(root_path), now=observed)

    expires = parse_expiry(data.get("expires_at"))
    remaining = int((expires.astimezone(timezone.utc) - observed).total_seconds()) \
        if expires else None

    receipt = {f: None for f in FIELDS}
    receipt["receipt_schema"] = RECEIPT_SCHEMA
    receipt["approval_artifact_schema"] = data.get("schema_version")
    receipt["approval_artifact_digest"] = digest
    for f in COPIED:
        receipt[f] = data.get(f)
    receipt["observed_at"] = observed.strftime(STAMP)
    receipt["observed_verdict"] = verdict.value
    receipt["remaining_ttl_seconds"] = remaining
    receipt["deploy_hash"] = dh

    if fmt == "json":
        print(json.dumps(receipt, indent=2, ensure_ascii=False))
    elif fmt == "markdown":
        print(render_markdown(receipt))
    else:
        fail(f"unknown --format {fmt!r} (markdown|json).", 2)

    # Diagnostics go to STDERR so the emitted evidence carries no local path (AC12).
    print(f"[approval-receipt] read+validated: {path} (verdict {verdict.value})", file=sys.stderr)
    if verdict.value != "VALID":
        print(f"[approval-receipt] WARNING: observed_verdict is {verdict.value}, not VALID. The "
              "receipt records that truthfully. Do not present it as a clean authorization.",
              file=sys.stderr)
        sys.exit(3)


def receipt_block(text: str) -> str | None:
    """The receipt region only — the forbidden-token rules must not read report prose."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if MARKER in ln), None)
    if start is None:
        return None
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## ") or re.match(r"^-{3,}\s*$", lines[i]):
            end = i
            break
    return "\n".join(lines[start:end])


def do_verify() -> None:
    path = Path(report_arg)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        fail(f"report unreadable ({e}).", 2)

    fails = []
    block = receipt_block(text)
    if block is None:
        fails.append(f"R1 no {RECEIPT_SCHEMA} receipt in the report (assertion-only shape: a "
                     "committed report must carry the receipt, not a claim about one)")
    else:
        missing = [f for f in FIELDS if f"`{f}`" not in block]
        if missing:
            fails.append(f"R2 receipt is missing field(s): {', '.join(missing)}")

        m = re.search(r"`approval_artifact_digest`[^\n]*?`(sha256:[0-9a-f]{64})`", block)
        if not m:
            fails.append("R3 approval_artifact_digest is absent or not `sha256:<64 lowercase hex>`")

        m = re.search(r"`deploy_hash`\s*\|\s*`([^`]+)`", block)
        if not m:
            fails.append("R4 deploy_hash carries no value")
        elif m.group(1).strip().lower() in PLACEHOLDERS or "<" in m.group(1):
            fails.append(f"R4 deploy_hash is a placeholder ({m.group(1)!r}) — DP.3 requires the "
                         "captured hash")

        # R5 reads the FIELD-NAME column only. The source labels legitimately mention `ttl`
        # while disclaiming it ("NOT a stored `ttl`"); a block-wide token scan would reject
        # every conforming receipt for saying the true thing.
        names = re.findall(r"^\|\s*`([^`]+)`\s*\|", block, re.M)
        for tok in FORBIDDEN:
            if tok in names:
                fails.append(f"R5 receipt carries a `{tok}` field, which the approval artifact "
                             "does not store (stored: `created_at`; computed: "
                             "`observed_verdict`, `remaining_ttl_seconds`)")
        if re.search(r"(?<![\w-])approved_at(?![\w-])", block):
            fails.append("R5 receipt mentions `approved_at`; the stored field is `created_at`")
        for f in COMPUTED:
            row = re.search(rf"`{f}`\s*\|[^|\n]*\|([^\n]*)", block)
            if row and "computed" not in row.group(1).lower():
                fails.append(f"R6 `{f}` is not labelled as computed at validation")

    if "state/approvals" in text:
        fails.append("R7 the report cites a `state/approvals/...` local path — gitignored, so "
                     "it dangles on a fresh clone (AC12)")

    if fails:
        for f in fails:
            print(f"RECEIPT-VERIFY: FAIL {f}")
        sys.exit(1)
    print(f"RECEIPT-VERIFY: PASS {path} carries a conforming {RECEIPT_SCHEMA} receipt")


do_emit() if mode == "emit" else do_verify()
PY
