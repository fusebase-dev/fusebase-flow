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

PFU_SOURCE="$(awk '/^FF_BH_LIB=/{n=4} n{print; n--}' "$PFU")"
[ -f "$BH_LIB" ] || { bad setup-lib-writer "missing $BH_LIB"; finish; }
if [ "$PFU_SOURCE" = 'FF_BH_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/backup-hygiene.sh"
[ -f "$FF_BH_LIB" ] || FF_BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
# shellcheck source=lib/backup-hygiene.sh
if [ -f "$FF_BH_LIB" ]; then . "$FF_BH_LIB"; else ff_git_exclude_backups() { return 1; }; fi' ] \
   && ! grep -q '^ff_git_exclude_backups() {' "$PFU"; then
  ok "pfu-sources-lib-without-inline-writer"
else
  bad "pfu-sources-lib-without-inline-writer" "source block missing or inline writer present"; finish
fi
PFU_STEP="$TMP_BASE/pfu-step/post-fusebase-update.sh"
mkdir -p "$(dirname "$PFU_STEP")/lib"
cp "$BH_LIB" "$(dirname "$PFU_STEP")/lib/backup-hygiene.sh" \
  || { bad setup-pfu-step "could not copy lib"; finish; }
printf '%s\n' "$PFU_SOURCE" > "$PFU_STEP"
awk '/^ff_git_exclude_backups \|\|/{print; found=1} END{if (!found) exit 1}' "$PFU" >> "$PFU_STEP" \
  || { bad setup-pfu-step "exclude call site missing"; finish; }

MISSING_STEP="$TMP_BASE/missing-lib/post-fusebase-update.sh"
mkdir -p "$(dirname "$MISSING_STEP")"
cp "$PFU_STEP" "$MISSING_STEP"
R="$TMP_BASE/missing-lib-repo"; mkdir -p "$R" && ( cd "$R" && git init -q . ) >/dev/null 2>&1
cp "$R/.git/info/exclude" "$TMP_BASE/missing-lib-before"
if ( cd "$R" && bash "$MISSING_STEP" ) > "$TMP_BASE/missing-lib-output" 2>&1 \
   && grep -q 'note: could not update .git/info/exclude' "$TMP_BASE/missing-lib-output" \
   && cmp "$TMP_BASE/missing-lib-before" "$R/.git/info/exclude" >/dev/null 2>&1; then
  ok "pfu-missing-lib-notes-exclude-failure"
else
  bad "pfu-missing-lib-notes-exclude-failure" "missing-lib call did not warn without writing"
fi

run_writer() {
  ( cd "$2" || exit 97
    case "$1" in
      lib) . "$BH_LIB"; ff_git_exclude_backups ;;
      pfu) bash "$PFU_STEP" ;;
    esac )
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

POLICY_TPL="$TMP_BASE/policy-tpl"; cp -R "$TPL" "$POLICY_TPL"
mkdir -p "$POLICY_TPL/policies" "$POLICY_TPL/.claude/worktrees/x" \
  && ( cd "$POLICY_TPL" && echo local > policies/model-routing.local.yml \
       && cd .claude/worktrees/x && git init -q . && echo agent > agent.txt \
       && "${G[@]}" add agent.txt && "${G[@]}" commit -qm agent ) >/dev/null 2>&1 \
  || { bad setup-policy-worktree-fixture "could not build the local-policy/worktree fixture"; finish; }

C="$TMP_BASE/policy-control"; cp -R "$POLICY_TPL" "$C"
if add_all "$C" && grep -q 'policies/model-routing\.local\.yml$' "$C.ls" \
   && grep -qE '^160000 .*	\.claude/worktrees/x$' "$C.ls"; then
  ok "control-unexcluded-local-policy-and-worktree-staged"
else
  bad "control-unexcluded-local-policy-and-worktree-staged" "fixture does not reproduce the hazard: $(cat "$C.ls" 2>/dev/null)"
fi

for w in lib pfu; do
  R="$TMP_BASE/policy-writer-$w"; cp -R "$POLICY_TPL" "$R"
  if run_writer "$w" "$R"; then
    unstaged_row "$w-writer-keeps-local-policy-and-worktree-unstaged" "$R" 'policies/model-routing\.local\.yml|\.claude/worktrees/'
  else
    bad "$w-writer-keeps-local-policy-and-worktree-unstaged" "writer rc=$?"
  fi
done

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
  if [ "$rc1$rc2" = "00" ] && [ "$n1" -eq $((n0 + 4)) ] && [ "$n2" -eq "$n1" ] \
     && [ "$(tail -n 1 "$EX")" = "/.claude/worktrees/" ]; then
    ok "$w-writer-upgrades-v54-exclude-by-missing-lines-idempotently"
  else
    bad "$w-writer-upgrades-v54-exclude-by-missing-lines-idempotently" "rc=$rc1/$rc2 lines $n0->$n1->$n2: $(cat "$EX")"
  fi
done

for w in lib pfu; do
  R="$TMP_BASE/v58-$w"; mkdir -p "$R" && ( cd "$R" && git init -q . ) >/dev/null 2>&1
  EX="$R/.git/info/exclude"; mkdir -p "$(dirname "$EX")"
  printf '%s\n' "# Fusebase Flow upgrade/refresh backups (transient; keep until validated) — never stage them." \
    "*.pre-upgrade-$TSG" "*.pre-bootstrap-$TSG" "*.pre-refresh-$TSG" "/.fusebase-flow-source/" >> "$EX"
  n0="$(wc -l < "$EX")"
  run_writer "$w" "$R"; rc1=$?; n1="$(wc -l < "$EX")"
  run_writer "$w" "$R"; rc2=$?; n2="$(wc -l < "$EX")"
  if [ "$rc1$rc2" = "00" ] && [ "$n1" -eq $((n0 + 3)) ] && [ "$n2" -eq "$n1" ] \
     && [ "$(tail -n 1 "$EX")" = "/.claude/worktrees/" ]; then
    ok "$w-writer-upgrades-v58-exclude-by-three-lines"
  else
    bad "$w-writer-upgrades-v58-exclude-by-three-lines" "rc=$rc1/$rc2 lines $n0->$n1->$n2: $(cat "$EX")"
  fi
done

L="$TMP_BASE/parity-lib"; P="$TMP_BASE/parity-pfu"
mkdir -p "$L" "$P" \
  && ( cd "$L" && git init -q . ) >/dev/null 2>&1 \
  && ( cd "$P" && git init -q . ) >/dev/null 2>&1 \
  && run_writer lib "$L" && run_writer pfu "$P" \
  && cmp "$L/.git/info/exclude" "$P/.git/info/exclude" >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  ok "writers-emit-identical-lists"
else
  bad "writers-emit-identical-lists" "writer setup, execution or byte parity failed"
fi

finish
