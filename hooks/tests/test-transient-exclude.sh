#!/usr/bin/env bash
# Fusebase Flow — every git-exclude writer keeps Flow's transient artifacts out of `git add -A`.
# Outcome record: docs/changes/2026-09-30-ovation-escalation-f1-f4.md (F4).
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: transient-exclude <name>" / "FAIL: transient-exclude <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
PFU="$ROOT/hooks/local/post-fusebase-update.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: transient-exclude $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: transient-exclude $1 ($(printf '%s' "${2:-}" | tr '\n' '|' | cut -c1-400))"; }
finish() { echo "[test-transient-exclude] $pass/$((pass + fail)) PASS"; exit $fail; }

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/ff-transient-exclude.XXXXXX")" || { bad setup-tmpdir "mktemp -d failed"; finish; }
trap 'rm -rf "$TMP_BASE"' EXIT
G=(git -c user.name=flow-test -c user.email=flow-test@local -c core.autocrlf=false -c commit.gpgsign=false)
BACKUP="app.txt.pre-upgrade-20260101T000000Z"

extract_fn() { awk -v fn="$1" '$0 ~ ("^" fn "\\(\\) \\{"){p=1} p{print} p&&/^}/{exit}' "$2"; }
PFU_FN="$(extract_fn ff_git_exclude_backups "$PFU")"
[ -f "$BH_LIB" ] || { bad setup-lib-writer "missing $BH_LIB"; finish; }
[ -n "$PFU_FN" ] || { bad setup-pfu-writer "ff_git_exclude_backups not found in $PFU"; finish; }

run_writer() {
  ( cd "$2" || exit 97
    case "$1" in lib) . "$BH_LIB" ;; pfu) eval "$PFU_FN" ;; esac
    ff_git_exclude_backups )
}

# TRIPWIRE: the nested clone needs a commit — without one `git add -A` errors instead of staging a gitlink.
TPL="$TMP_BASE/tpl"
mkdir -p "$TPL/.fusebase-flow-source" \
  && ( cd "$TPL" && git init -q . && echo app > app.txt && echo old > "$BACKUP" \
       && cd .fusebase-flow-source && git init -q . && echo src > VERSION \
       && "${G[@]}" add VERSION && "${G[@]}" commit -qm src ) >/dev/null 2>&1 \
  || { bad setup-fixture "could not build the nested-clone fixture"; finish; }

# TRIPWIRE: git output goes to files, never $(git …) (docs/problem-catalog/msys-git-command-substitution-hang/problem.md).
add_all() {
  ( cd "$1" && "${G[@]}" add -A && git ls-files -s > "$1.ls" && git status --porcelain > "$1.st" ) >/dev/null 2>&1
}

C="$TMP_BASE/control"; cp -R "$TPL" "$C"
if add_all "$C" && grep -qE '^160000 .*	\.fusebase-flow-source$' "$C.ls"; then
  ok "control-unexcluded-clone-staged-as-gitlink"
else
  bad "control-unexcluded-clone-staged-as-gitlink" "fixture does not reproduce the hazard: $(cat "$C.ls" 2>/dev/null)"
fi

unstaged_row() {
  add_all "$2" || { bad "$1" "git add -A failed"; return; }
  grep -q '	app\.txt$' "$2.ls" || { bad "$1" "project file not staged, row proves nothing: $(cat "$2.ls")"; return; }
  if grep -qE "$3" "$2.ls" "$2.st"; then
    bad "$1" "transient artifact staged or listed: index=$(cat "$2.ls") status=$(cat "$2.st")"; return
  fi
  ok "$1"
}

for w in lib pfu; do
  R="$TMP_BASE/writer-$w"; cp -R "$TPL" "$R"
  if run_writer "$w" "$R"; then
    unstaged_row "$w-writer-keeps-clone-and-backup-unstaged" "$R" 'fusebase-flow-source|pre-upgrade-'
  else
    bad "$w-writer-keeps-clone-and-backup-unstaged" "writer rc=$?"
  fi
done

R="$TMP_BASE/gitignore"; cp -R "$TPL" "$R"; cp "$ROOT/.gitignore" "$R/.gitignore"
unstaged_row "shipped-gitignore-keeps-clone-unstaged" "$R" 'fusebase-flow-source'

# TRIPWIRE: these are the exact lines v5.4 consumers already hold; a writer that edits one re-appends it.
TSG='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
for w in lib pfu; do
  R="$TMP_BASE/v54-$w"; mkdir -p "$R" && ( cd "$R" && git init -q . ) >/dev/null 2>&1
  EX="$R/.git/info/exclude"; mkdir -p "$(dirname "$EX")"
  printf '%s\n' "# Fusebase Flow upgrade/refresh backups (transient; keep until validated) — never stage them." \
    "*.pre-upgrade-$TSG" "*.pre-bootstrap-$TSG" "*.pre-refresh-$TSG" >> "$EX"
  n0="$(wc -l < "$EX")"
  run_writer "$w" "$R"; rc1=$?; n1="$(wc -l < "$EX")"
  run_writer "$w" "$R"; rc2=$?; n2="$(wc -l < "$EX")"
  if [ "$rc1$rc2" = "00" ] && [ "$n1" -eq $((n0 + 1)) ] && [ "$n2" -eq "$n1" ] \
     && [ "$(tail -n 1 "$EX")" = "/.fusebase-flow-source/" ]; then
    ok "$w-writer-upgrades-v54-exclude-by-one-line-idempotently"
  else
    bad "$w-writer-upgrades-v54-exclude-by-one-line-idempotently" "rc=$rc1/$rc2 lines $n0->$n1->$n2: $(cat "$EX")"
  fi
done

finish
