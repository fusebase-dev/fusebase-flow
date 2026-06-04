#!/usr/bin/env bash
# Fusebase Flow — eslint-ignore-flow-paths.sh
#
# PROVENANCE: Shipped Fusebase Flow v3.8.6+. Lives at hooks/local/ (outside the
# FuseBase CLI refresh manifest). Operator-run, opt-in.
#
# PURPOSE (downstream lint blocker):
#   Flow stages the upstream clone at `.fusebase-flow-source/` for upgrades. That
#   tree contains CLI-owned CommonJS hooks (.claude/hooks/*.js using require()),
#   which trip @typescript-eslint/no-require-imports. The path is gitignored, but
#   ESLint *flat config does not read .gitignore*, and the CLI's eslint.config only
#   ignores ".claude/**" — not ".fusebase-flow-source/**". So `npm run lint` (and
#   therefore `fusebase deploy`, which lints first) fails even with zero app errors.
#
#   This helper adds ".fusebase-flow-source/**" to the project's ESLint flat-config
#   `ignores` array, right after the existing ".claude/**" entry. Idempotent; writes
#   a .pre-eslint-ignore-<ts> backup. Opt-in (Flow does not silently edit app config).
#
#   Alternative: just delete `.fusebase-flow-source/` after an upgrade — it is
#   transient and re-created on the next upgrade (bootstrap-upgrade.sh / a fresh
#   clone). Then there is nothing for ESLint to lint and this helper is unnecessary.
#
# Usage:
#   bash hooks/local/eslint-ignore-flow-paths.sh            # apply
#   bash hooks/local/eslint-ignore-flow-paths.sh --dry-run  # show what would change
#
# Exit: 0 applied / already present / not applicable (no eslint flat config);
#       1 error; 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h) sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

CONFIG=""
for c in eslint.config.mjs eslint.config.js eslint.config.cjs eslint.config.ts; do
  if [ -f "$c" ]; then CONFIG="$c"; break; fi
done

if [ -z "$CONFIG" ]; then
  echo "[eslint-ignore-flow-paths] No ESLint flat config (eslint.config.{mjs,js,cjs,ts}) at repo root."
  echo "  Nothing to do. If your deploy lints and includes .fusebase-flow-source/, add"
  echo "  \".fusebase-flow-source/**\" to your ESLint ignores, or delete .fusebase-flow-source/."
  exit 0
fi

PYTHON="${PYTHON:-python3}"; command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python

"$PYTHON" - "$CONFIG" "$DRY_RUN" <<'PY'
import re, sys
cfg, dry = sys.argv[1], sys.argv[2] == "1"
text = open(cfg, encoding="utf-8").read()
TARGET = ".fusebase-flow-source/**"
if TARGET in text:
    print(f"[eslint-ignore-flow-paths] {cfg}: already ignores {TARGET} (no change).")
    sys.exit(0)
# Find the .claude/** ignore entry (single or double quoted) and mirror its line.
m = re.search(r'([^\S\r\n]*)(["\'])\.claude/\*\*\2([ \t]*,?)', text)
if not m:
    print(f"[eslint-ignore-flow-paths] {cfg}: no \".claude/**\" ignore entry found — "
          "cannot auto-place. Add \".fusebase-flow-source/**\" to your ESLint ignores "
          "array manually, or delete .fusebase-flow-source/ after upgrades.")
    sys.exit(0)
indent, q, trailing = m.group(1), m.group(2), m.group(3)
had_comma = trailing.strip().endswith(",")
# .claude line gets a comma (something now follows it); new entry copies the
# original trailing-comma state (last item -> no comma; mid-list -> comma).
claude_repl = f'{indent}{q}.claude/**{q},'
new_entry   = f'{indent}{q}.fusebase-flow-source/**{q}{"," if had_comma else ""}'
replacement = claude_repl + "\n" + new_entry
text2 = text[:m.start()] + replacement + text[m.end():]
if dry:
    print(f"[eslint-ignore-flow-paths] (dry-run) would add {TARGET} after \".claude/**\" in {cfg}")
    sys.exit(0)
import time
bak = cfg + ".pre-eslint-ignore"
open(bak, "w", encoding="utf-8").write(text)
open(cfg, "w", encoding="utf-8").write(text2)
print(f"[eslint-ignore-flow-paths] {cfg}: added {TARGET} to ESLint ignores (backup: {bak}).")
PY
