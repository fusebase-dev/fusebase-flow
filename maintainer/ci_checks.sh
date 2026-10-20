#!/usr/bin/env bash
# Fusebase Flow 6.0 core: the done checks a hosted runner can run (Linux and Git Bash/MSYS).
# Milestone 1 checks 1, 3 and 4: install into an empty folder, the three git hooks fire with
# their own text, a re-install changes nothing, and the builder boot stays under 6,000 bytes.
# Check 2 (a real 5.x consumer) needs a private repository and stays a local check.
# Output: TAP lines "ok <n> - <name>" / "not ok <n> - <name>"; exit status = failures.
set -uo pipefail

CORE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-python3}"
# The installed file count (core files + provider mirrors) is a deliberate ratchet: change it in
# the same commit that changes the core's file set, and say why in the body.
EXPECT_FILES="${EXPECT_FILES:-82}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/flow-ci.XXXXXX")" || { echo "not ok 1 - temp dir"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

n=0; fail=0
ok()  { n=$((n + 1)); echo "ok $n - $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/#   /'; }
has() { printf '%s' "$1" | grep -F -q -- "$2"; }

P="$WORK/project"; R="$WORK/remote.git"
git init -q -b main "$P" && git init -q --bare "$R" || { bad "git init"; exit 1; }
git -C "$P" config user.name "flow-ci"; git -C "$P" config user.email "flow-ci@example.invalid"
git -C "$P" config commit.gpgsign false
git -C "$P" commit -q --allow-empty -m "init" && git -C "$P" remote add origin "$R"

# --- check 1: install into an empty folder, two providers, no hook wiring
out="$("$PY" "$CORE/maintainer/flow.py" install --target "$P" --providers claude,codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "install exits 0" || bad "install exits 0 (rc=$rc)" "$out"
has "$out" "manifest: audit/flow-install.json ($EXPECT_FILES files)" \
  && ok "install manifest lists $EXPECT_FILES files" \
  || bad "install manifest lists $EXPECT_FILES files" "$(printf '%s\n' "$out" | grep -E 'manifest:|added:|refused:')"
has "$out" "refused: 0" && ok "install refuses nothing" || bad "install refuses nothing" "$out"
if [ ! -e "$P/.claude/settings.json" ] && [ ! -e "$P/.codex/hooks.json" ]; then
  ok "no provider hook wiring without --wire-hooks"
else
  bad "no provider hook wiring without --wire-hooks"
fi
for h in pre-commit commit-msg pre-push; do
  hp="$(git -C "$P" rev-parse --git-path "hooks/$h")"; case "$hp" in /*|?:*) ;; *) hp="$P/$hp" ;; esac
  if [ -f "$hp" ] && cmp -s "$hp" "$CORE/hooks/git/$h"; then ok "git hook $h installed byte-identical"
  else bad "git hook $h installed byte-identical" "$hp"; fi
done

# --- the Flow .gitignore block (O-4): one block; approvals, the audit folder and bytecode ignored, .gitkeep kept
probes="$(printf 'state/approvals/probe.yml\nstate/audit/probe.log\nhooks/shared/__pycache__/probe.pyc\nstate/approvals/.gitkeep\n' \
  | git -C "$P" check-ignore --stdin 2>&1)"
if [ "$(grep -c '^# FLOW:BEGIN ignore' "$P/.gitignore" 2>/dev/null)" = 1 ] \
  && [ "$(printf '%s\n' "$probes" | grep -c .)" = 3 ] && ! has "$probes" ".gitkeep"; then
  ok "install writes the Flow .gitignore block once"
else
  bad "install writes the Flow .gitignore block once" "$(cat "$P/.gitignore" 2>&1; printf '%s\n' "$probes")"
fi
ignore_before="$(git hash-object "$P/.gitignore" 2>&1)"

# --- check 3: the three hooks fire with their own text
# The probe key is assembled at run time so the core's own pre-commit never sees the literal.
key="AKIA""IOSFODNN7EXAMPLE"
printf 'aws_access_key_id = %s\n' "$key" > "$P/probe-secret.txt"
git -C "$P" add probe-secret.txt
out="$(git -C "$P" commit -m "docs(probe): T1 secret scan probe" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "secret pattern" && has "$out" "aws_access_key_id"; then
  ok "pre-commit blocks a secret with its own text"
else
  bad "pre-commit blocks a secret with its own text (rc=$rc)" "$out"
fi
git -C "$P" rm -q --cached probe-secret.txt >/dev/null 2>&1; rm -f "$P/probe-secret.txt"

printf 'first note\n' > "$P/notes.md"; git -C "$P" add notes.md
out="$(git -C "$P" commit -m "update the notes" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "must cite a T-number"; then ok "commit-msg rejects a subject without a T-number"
else bad "commit-msg rejects a subject without a T-number (rc=$rc)" "$out"; fi

out="$(git -C "$P" commit -m "docs(notes): T1 add the first project note" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a valid commit passes the hooks" || bad "a valid commit passes the hooks (rc=$rc)" "$out"

out="$(git -C "$P" push origin main 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "BLOCKED (FR-12 pre-push)"; then ok "pre-push blocks an unapproved push to main"
else bad "pre-push blocks an unapproved push to main (rc=$rc)" "$out"; fi
[ -z "$(git -C "$R" for-each-ref)" ] && ok "the remote received nothing" || bad "the remote received nothing"

# --- re-install is the upgrade within 6.0: nothing to do on an unchanged tree
out="$("$PY" "$CORE/maintainer/flow.py" install --target "$P" --providers claude,codex 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && has "$out" "added: 0" && has "$out" "replaced: 0" && has "$out" "refused: 0"; then
  ok "a second install changes nothing"
else
  bad "a second install changes nothing (rc=$rc)" "$(printf '%s\n' "$out" | grep -E 'added:|replaced:|refused:|kept:')"
fi
[ "$(git hash-object "$P/.gitignore" 2>&1)" = "$ignore_before" ] && has "$out" ".gitignore (block current)" \
  && ok "a second install leaves the .gitignore block" \
  || bad "a second install leaves the .gitignore block" "$(grep -F '.gitignore' <<<"$out")"

# --- check 4: the builder boot stays under 6,000 bytes
last="$("$PY" "$CORE/maintainer/measure_boot.py" 2>&1 | tail -n 1 | tr -d '\r ')"
case "$last" in
  ''|*[!0-9]*) bad "builder boot is a number" "$last" ;;
  *) [ "$last" -lt 6000 ] && ok "builder boot $last bytes (< 6,000)" || bad "builder boot $last bytes (< 6,000)" ;;
esac

echo "# ci_checks: $((n - fail))/$n passed"
exit "$fail"
