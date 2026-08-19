#!/usr/bin/env bash
# Fusebase Flow — S3a: the stamp-time byte-compliance guard.
#
# The defect this phase pins: a manifest is a pure function of covered-file BYTES, and
# nothing checked those bytes were the canonical LF form before attesting them. Locally the
# stamper and the verifier read the same wrong worktree copy and AGREE; only a clean
# checkout disagrees, so CI goes red for a file that looks fine on every developer machine.
# Four occurrences in two days in this repo alone; most recently
# policies/module-size-baseline.txt (hashed CRLF, shipped LF, reddened CI twice).
#
# The contract is a GUARD, not a warning: emit the diagnostic, return NON-ZERO, and do NOT
# rewrite the manifest. A warning that still writes a knowingly non-canonical attestation is
# observability, not a guard — the wrong baseline still gets created.
#
# SCOPE (deliberate): the resolved `eol=lf` gitattribute, i.e. the proven CRLF subclass. This
# does NOT settle `stamper-hashes-worktree-not-artifact` (committed bytes vs worktree bytes),
# which stays open — so a CRLF file with no eol pin must still stamp.
#
# Output contract (parsed by run-tests.sh): "PASS: stamp-eol-guard <name>" /
# "FAIL: stamp-eol-guard <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MCM="$ROOT/hooks/local/lib/managed_content_manifest.py"
HKM="$ROOT/hooks/local/lib/hook_manifest.py"
GUARD="$ROOT/hooks/local/lib/eol_guard.py"
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: stamp-eol-guard $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: stamp-eol-guard $1 ($2)"; }
finish() { echo "[test-stamp-eol-guard] $pass/$((pass + fail)) PASS"; exit $fail; }

if [ ! -f "$GUARD" ]; then
  bad "guard-present" "missing $GUARD"; finish
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

###############################################################################
# Fixture: a minimal managed tree with this repo's own EOL pins.
###############################################################################
mkfix() {   # -> a fresh initialized fixture root
  local d; d="$(mktemp -d "$TMP/fxXXXXXX")"
  mkdir -p "$d/policies" "$d/hooks/local/lib" "$d/hooks/handlers" "$d/audit"
  printf '4.11.0\n' > "$d/VERSION"
  printf '* text=auto\n*.sh text eol=lf\n*.py text eol=lf\n*.txt text eol=lf\n*.png -text\n' > "$d/.gitattributes"
  # -c core.autocrlf=false: the fixture's bytes are the subject of the test; a host
  # autocrlf setting must never rewrite them out from under it.
  git -c init.defaultBranch=main init -q "$d" >/dev/null 2>&1
  git -C "$d" config core.autocrlf false
  printf '# baseline\n800 hooks/local/upgrade.sh\n' > "$d/policies/module-size-baseline.txt"
  printf '#!/usr/bin/env bash\necho hi\n' > "$d/hooks/local/lib/some-lib.sh"
  echo "$d"
}

crlf() { printf '%s' "$(cat "$1")" | sed 's/$/\r/' > "$1.crlf" && mv "$1.crlf" "$1"; }

stamp_mcm() { "$python_bin" "$MCM" stamp --root "$1" 2>&1; }
stamp_hkm() { "$python_bin" "$HKM" stamp --root "$1" 2>&1; }

###############################################################################
# Row 1 — THE reproduction: policies/module-size-baseline.txt holding CRLF under
# an `eol=lf` pin. The stamper must REFUSE and leave the manifest untouched.
###############################################################################
fx="$(mkfix)"
out="$(stamp_mcm "$fx")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "clean-tree-stamps"; else
  bad "clean-tree-stamps" "rc=$rc :: $out"; fi
before="$("$python_bin" -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$fx/audit/managed-content-manifest.json" 2>/dev/null)"

crlf "$fx/policies/module-size-baseline.txt"
out="$(stamp_mcm "$fx")"; rc=$?
if [ "$rc" -ne 0 ]; then ok "crlf-refuses-nonzero"; else
  bad "crlf-refuses-nonzero" "stamper returned 0 on CRLF-under-eol=lf :: $out"; fi

after="$("$python_bin" -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$fx/audit/managed-content-manifest.json" 2>/dev/null)"
if [ -n "$before" ] && [ "$before" = "$after" ]; then ok "crlf-does-not-rewrite-manifest"; else
  bad "crlf-does-not-rewrite-manifest" "manifest changed despite the refusal"; fi

if printf '%s' "$out" | grep -qi "CRLF" && printf '%s' "$out" | grep -q "policies/module-size-baseline.txt"; then
  ok "crlf-names-file-and-cause"
else
  bad "crlf-names-file-and-cause" "diagnostic did not name the file + CRLF :: $out"
fi

###############################################################################
# Row 2 — NO MANIFEST YET + CRLF: the wrong baseline must never be CREATED
# either. ("Do not rewrite" and "do not create" are the same requirement.)
###############################################################################
fx="$(mkfix)"
crlf "$fx/policies/module-size-baseline.txt"
out="$(stamp_mcm "$fx")"; rc=$?
if [ "$rc" -ne 0 ] && [ ! -f "$fx/audit/managed-content-manifest.json" ]; then
  ok "crlf-does-not-create-manifest"
else
  bad "crlf-does-not-create-manifest" "rc=$rc, manifest exists=$([ -f "$fx/audit/managed-content-manifest.json" ] && echo yes || echo no)"
fi

###############################################################################
# Row 3 — the hook-layer stamper carries the SAME guard. One guarded stamper and
# one unguarded one is the same hole with a smaller surface.
###############################################################################
fx="$(mkfix)"
out="$(stamp_hkm "$fx")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "hook-manifest-clean-stamps"; else
  bad "hook-manifest-clean-stamps" "rc=$rc :: $out"; fi
crlf "$fx/hooks/local/lib/some-lib.sh"
out="$(stamp_hkm "$fx")"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "hooks/local/lib/some-lib.sh"; then
  ok "hook-manifest-crlf-refuses"
else
  bad "hook-manifest-crlf-refuses" "rc=$rc :: $out"
fi

###############################################################################
# Row 4 — SCOPE: CRLF with no resolved `eol=lf` pin is NOT this guard's business.
# Widening to "any CRLF anywhere" would start deciding
# stamper-hashes-worktree-not-artifact by accident.
###############################################################################
fx="$(mkfix)"
printf 'plain text, no pin\n' > "$fx/policies/unpinned.dat"
printf '*.dat -text\n' >> "$fx/.gitattributes"
crlf "$fx/policies/unpinned.dat"
out="$(stamp_mcm "$fx")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "unpinned-crlf-allowed"; else
  bad "unpinned-crlf-allowed" "guard fired on a file with no eol=lf pin :: $out"; fi

###############################################################################
# Row 5 — DEGRADE OPEN off git: attributes cannot be resolved in a non-Git tree,
# and a stamper that refuses to run there would break a legitimate workflow the
# guard was never scoped to.
###############################################################################
fx="$(mkfix)"
rm -rf "$fx/.git"
crlf "$fx/policies/module-size-baseline.txt"
out="$(stamp_mcm "$fx")"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$fx/audit/managed-content-manifest.json" ]; then
  ok "non-git-degrades-open"
else
  bad "non-git-degrades-open" "rc=$rc :: $out"
fi
if printf '%s' "$out" | grep -qi "not verified\|could not resolve\|skipped"; then
  ok "non-git-says-so"
else
  bad "non-git-says-so" "silent skip — a guard that quietly does not run is the original defect :: $out"
fi

###############################################################################
# Row 6 — THIS repo, right now: every covered path already satisfies its pin.
# A guard that goes red on the tree that ships it is not adoptable.
###############################################################################
out="$("$python_bin" "$GUARD" --root "$ROOT" --manifest managed-content 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "this-repo-is-clean"; else
  bad "this-repo-is-clean" "rc=$rc :: $out"; fi

###############################################################################
# Row 7 — the wiring assertions: a guard nobody calls is not a guard.
###############################################################################
if grep -q "eol_guard" "$MCM"; then ok "managed-content-wires-guard"; else
  bad "managed-content-wires-guard" "no eol_guard reference in managed_content_manifest.py"; fi
if grep -q "eol_guard" "$HKM"; then ok "hook-manifest-wires-guard"; else
  bad "hook-manifest-wires-guard" "no eol_guard reference in hook_manifest.py"; fi
if grep -q "eol_guard" "$ROOT/hooks/local/stamp-cli-provenance.sh"; then ok "cli-provenance-wires-guard"; else
  bad "cli-provenance-wires-guard" "no eol_guard reference in stamp-cli-provenance.sh"; fi

finish
