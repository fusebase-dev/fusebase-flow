#!/usr/bin/env bash
# Fusebase Flow — structured mutation discriminator for the A2 git-context classifier (T2/S2b).
# Evidence contract: docs/specs/pre-commit-trusted-tool-contract/verification-gate.md
#                    § Mutation evidence contract (AC7).
#
# A named RED is NOT proof, and neither is `row=PASS|FAIL`. This harness PREDECLARES one unique
# mutation target and its expected observable delta, then compares FULL STRUCTURED SNAPSHOTS of a
# baseline and a mutant run — structured rc, normalized stdout/stderr, worktree artifact manifest
# (path|type|size|hash), index/HEAD state, timeout class + budget, temp residue, and the tracked
# hook hash. Only the predeclared observables may differ; an unmutated copy presented as the mutant
# must be REJECTED.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: git-context-mutation <name>" / "FAIL: git-context-mutation <name>"; exit = fail count.
#
# TRIPWIRE — production hooks/git/pre-commit is COPIED and mutated only inside this run's temp
# state; it is byte-compared at the end and must never be written to.
# TRIPWIRE — declared nondeterminism is limited to two substitutions (the run's private TMPDIR and
# the scenario path). Widening that normalization would let a real diagnostic delta hide.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOK="$ROOT/hooks/git/pre-commit"
DIAG="git resolved no worktree here"
TARGET_ROW="G1-normal-repo-broken-git-blocks"
DECLARED_KEYS="rc stderr_sha"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: git-context-mutation $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: git-context-mutation $1 (${2:-})"; }
finish() { echo "[test-pre-commit-git-context-mutation] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$HOOK" ] || { bad "hook-present" "missing $HOOK"; finish; }
command -v sha256sum >/dev/null 2>&1 || { bad "sha256sum-present" "no sha256sum; the artifact manifest cannot be hashed"; finish; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffgcm-mutation.XXXXXX")"
cleanup() { case "$TMP" in "${TMPDIR:-/tmp}"/ffgcm-mutation.*) rm -rf -- "$TMP" ;; esac; }
trap cleanup EXIT
TMPP="$(cd "$TMP" && pwd -P)"   # physical: the ceiling is compared against the hook's `pwd -P`
cp "$HOOK" "$TMP/production-at-start"
TRACKED_HOOK_SHA="$(sha256sum "$HOOK" | cut -d' ' -f1)"

# ---- 1. Unique target: the ONE `exit 1` between the A2 BLOCK diagnostic and its closing `fi`. ----
diag_hits="$(grep -cF "$DIAG" "$HOOK")"
if [ "${diag_hits:-0}" -eq 1 ]; then ok "mutation-diagnostic-unique"
else bad "mutation-diagnostic-unique" "expected exactly 1 A2 BLOCK diagnostic, found ${diag_hits:-0}"; finish; fi

diag_line="$(grep -nF "$DIAG" "$HOOK" | cut -d: -f1)"
end_line="$(awk -v d="$diag_line" 'NR>d && /^[[:space:]]*fi[[:space:]]*$/ {print NR; exit}' "$HOOK")"
targets="$(awk -v d="$diag_line" -v f="${end_line:-0}" 'NR>d && NR<f && /^[[:space:]]*exit 1[[:space:]]*$/ {print NR}' "$HOOK")"
target_n="$(printf '%s' "$targets" | grep -c . || true)"
if [ "${target_n:-0}" -eq 1 ]; then ok "mutation-target-unique"
else bad "mutation-target-unique" "expected exactly 1 'exit 1' in lines $((diag_line + 1))..$((${end_line:-0} - 1)), found ${target_n:-0}"; finish; fi
TARGET_LINE="$targets"

# ---- 2. PREDECLARATION (before any run) ---------------------------------------------------------
{
  echo "[git-context-mutation] PREDECLARED MUTATION RECORD"
  echo "  id                 : A2-M1"
  echo "  target             : hooks/git/pre-commit:$TARGET_LINE (the single 'exit 1' of the A2 fail-closed BLOCK)"
  echo "  occurrence_count   : 1 (asserted above)"
  echo "  named_row          : $TARGET_ROW"
  echo "  scenario           : a real repo with staged content, invoked with a git shim that exits 128"
  echo "  expected_delta     : rc 1 -> 0; stderr KEEPS the '$DIAG' line but execution no longer"
  echo "                       stops, so it gains 'not in a git repo; skipping' — the exact fail-open"
  echo "                       (unusable git inside a repository treated as outside-repo execution)"
  echo "                       that A2 exists to close."
  echo "  declared_observables: rc, stderr_sha"
  echo "  expected_identical : stdout_sha, artifact_manifest_sha, artifact_count, index_state_sha,"
  echo "                       head_unchanged, temp_residue, timeout_class, budget_ok, tracked_hook_sha"
  echo "  negative_control   : an UNMUTATED copy presented as the mutant must be REJECTED"
} >&2
ok "mutation-predeclared-record-emitted"

# ---- 3. Copies: baseline, mutant, negative control ----------------------------------------------
cp "$HOOK" "$TMP/baseline"
cp "$HOOK" "$TMP/negative"
sed "${TARGET_LINE}d" "$HOOK" > "$TMP/mutant"
removed="$(diff "$TMP/baseline" "$TMP/mutant" | grep -c '^<' || true)"
added="$(diff "$TMP/baseline" "$TMP/mutant" | grep -c '^>' || true)"
if [ "${removed:-0}" -eq 1 ] && [ "${added:-0}" -eq 0 ]; then ok "mutation-is-single-line-deletion"
else bad "mutation-is-single-line-deletion" "expected exactly one removed line and none added (removed=${removed:-0} added=${added:-0})"; finish; fi
if cmp -s "$TMP/baseline" "$TMP/negative"; then ok "mutation-negative-control-is-unmutated"
else bad "mutation-negative-control-is-unmutated" "the negative control differs from the unmutated hook"; finish; fi

# ---- 4. Scenario + structured snapshot ----------------------------------------------------------
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nexit 128\n' > "$TMP/bin/git"; chmod +x "$TMP/bin/git"

# snapshot <hook-copy> <label>: build a PRISTINE scenario repo, run the hook once, write
# $TMP/<label>.snap (key=value) plus the normalized streams.
snapshot() {
  # TRIPWIRE: separate statements — a single `local` expands every word before it runs, so
  # `d="$TMP/$label…"` would read the OUTER (unset) label under `set -u`.
  local hook="$1" label="$2" t0 el rc
  local d="$TMP/$label.repo" td="$TMP/$label.tmpdir"
  rm -rf "$d" "$td"; mkdir -p "$d" "$td"
  ( cd "$d" && git init -q && git config user.email t@example.com && git config user.name t \
      && git config core.autocrlf false ) >/dev/null 2>&1
  printf '# note\nhello\n' > "$d/note.md"
  ( cd "$d" && git add -- note.md >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
  printf '# second\nworld\n' > "$d/second.md"
  ( cd "$d" && git add -- second.md >/dev/null 2>&1 )
  local head_before; head_before="$(git -C "$d" rev-parse HEAD 2>/dev/null)"
  # The classifier reports `pwd -P`, so the PHYSICAL scenario path has to normalize too — otherwise
  # the label leaks into stderr, stderr_sha differs for every run, and the negative control passes
  # for the wrong reason.
  local dp tdp; dp="$(cd "$d" && pwd -P)"; tdp="$(cd "$td" && pwd -P)"

  t0="$(date +%s)"
  ( cd "$d" && PATH="$TMP/bin:$PATH" TMPDIR="$td" GIT_CEILING_DIRECTORIES="$TMPP" bash "$hook" ) \
      >"$TMP/$label.out.raw" 2>"$TMP/$label.err.raw"; rc=$?
  el=$(( $(date +%s) - t0 ))

  # Declared nondeterminism: ONLY the private TMPDIR and the scenario repo path (both spellings).
  sed -e "s#$tdp#<TMPDIR>#g" -e "s#$td#<TMPDIR>#g" -e "s#$dp#<REPO>#g" -e "s#$d#<REPO>#g" "$TMP/$label.err.raw" > "$TMP/$label.err"
  sed -e "s#$tdp#<TMPDIR>#g" -e "s#$td#<TMPDIR>#g" -e "s#$dp#<REPO>#g" -e "s#$d#<REPO>#g" "$TMP/$label.out.raw" > "$TMP/$label.out"

  # Artifact manifest: every worktree file the run could have touched, as path|type|size|hash.
  ( cd "$d" && find . -path ./.git -prune -o -type f -print 2>/dev/null | LC_ALL=C sort \
      | while IFS= read -r f; do
          printf '%s|file|%s|%s\n' "$f" "$(wc -c < "$f" 2>/dev/null | tr -d ' ')" \
                                   "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)"
        done ) > "$TMP/$label.manifest"

  local tclass=none
  grep -q 'TIMEOUT@' "$TMP/$label.err" && tclass=bounded-hit
  {
    echo "rc=$rc"
    echo "stdout_sha=$(sha256sum "$TMP/$label.out" | cut -d' ' -f1)"
    echo "stderr_sha=$(sha256sum "$TMP/$label.err" | cut -d' ' -f1)"
    echo "artifact_manifest_sha=$(sha256sum "$TMP/$label.manifest" | cut -d' ' -f1)"
    echo "artifact_count=$(grep -c . "$TMP/$label.manifest" || true)"
    echo "index_state_sha=$( { git -C "$d" status --porcelain; git -C "$d" diff --cached --name-only; } 2>/dev/null | sha256sum | cut -d' ' -f1)"
    echo "head_unchanged=$([ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" = "$head_before" ] && echo yes || echo no)"
    echo "temp_residue=$(ls -A "$td" 2>/dev/null | grep -c . || true)"
    echo "timeout_class=$tclass"
    echo "budget_ok=$([ "$el" -le 30 ] && echo yes || echo no)"
    echo "tracked_hook_sha=$(sha256sum "$HOOK" | cut -d' ' -f1)"
  } | LC_ALL=C sort > "$TMP/$label.snap"
  SNAP_RC=$rc
}

snapshot "$TMP/baseline" baseline; base_rc=$SNAP_RC
snapshot "$TMP/mutant"   mutant;   mut_rc=$SNAP_RC
snapshot "$TMP/negative" negative

if [ "$base_rc" -ne 0 ] && grep -qF "$DIAG" "$TMP/baseline.err"; then ok "mutation-baseline-blocks-as-declared"
else bad "mutation-baseline-blocks-as-declared" "the UNMUTATED hook did not BLOCK an unusable git inside a repository (rc=$base_rc) — no mutant verdict can be trusted"; finish; fi

# compare <baseline.snap> <candidate.snap>: 0 ONLY when every DECLARED key differs and every other
# key is identical. CMP_NOTE carries the clause-level reason.
compare() {
  local b="$1" c="$2" k v_b v_c line
  CMP_DECLARED=1; CMP_UNDECLARED=1; CMP_NOTE=""
  if ! diff <(cut -d= -f1 "$b") <(cut -d= -f1 "$c") >/dev/null 2>&1; then
    CMP_UNDECLARED=0; CMP_NOTE="snapshot key sets differ"; return 1
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    k="${line%%=*}"; v_b="${line#*=}"
    v_c="$(sed -n "s/^$k=//p" "$c")"
    case " $DECLARED_KEYS " in
      *" $k "*)
        if [ "$v_b" = "$v_c" ]; then
          CMP_DECLARED=0; CMP_NOTE="$CMP_NOTE declared observable '$k' did NOT change ($v_b);"
        fi ;;
      *)
        if [ "$v_b" != "$v_c" ]; then
          CMP_UNDECLARED=0; CMP_NOTE="$CMP_NOTE undeclared observable '$k' changed ($v_b -> $v_c);"
        fi ;;
    esac
  done < "$b"
  [ "$CMP_DECLARED" -eq 1 ] && [ "$CMP_UNDECLARED" -eq 1 ]
}

compare "$TMP/baseline.snap" "$TMP/mutant.snap"; mut_verdict=$?
mut_declared=$CMP_DECLARED; mut_undeclared=$CMP_UNDECLARED; mut_note="$CMP_NOTE"

if [ "$mut_declared" -eq 1 ] && [ "$mut_rc" -eq 0 ]; then ok "mutation-mutant-flips-declared-observables"
else bad "mutation-mutant-flips-declared-observables" "expected rc 1->0 and a changed stderr; got rc=$mut_rc.${mut_note:+ $mut_note}"; fi
if [ "$mut_undeclared" -eq 1 ]; then ok "mutation-undeclared-observables-identical"
else bad "mutation-undeclared-observables-identical" "an observable outside the predeclared delta moved:${mut_note:-}"; fi
if grep -q "not in a git repo; skipping" "$TMP/mutant.err" && ! grep -q "not in a git repo; skipping" "$TMP/baseline.err"; then
  ok "mutation-mutant-shows-the-fail-open"
else bad "mutation-mutant-shows-the-fail-open" "the mutant did not fall through to the outside-repo skip (or the baseline already did) — the deleted line is not what fails closed"; fi

# ---- 5. Negative control: an UNMUTATED copy presented as the mutant must be REJECTED -------------
compare "$TMP/baseline.snap" "$TMP/negative.snap"; neg_verdict=$?
neg_note="$CMP_NOTE"
if [ "$neg_verdict" -ne 0 ]; then ok "mutation-negative-control-rejected"
else bad "mutation-negative-control-rejected" "the comparator ACCEPTED an unmutated copy as a detected mutation — an undetected mutation would pass this gate"; fi

# ---- 6. Production integrity --------------------------------------------------------------------
if cmp -s "$HOOK" "$TMP/production-at-start" && [ "$TRACKED_HOOK_SHA" = "$(sha256sum "$HOOK" | cut -d' ' -f1)" ]; then
  ok "mutation-production-hook-unchanged"
else bad "mutation-production-hook-unchanged" "hooks/git/pre-commit changed during this run"; fi

# Evidence for the gate report's mutation record (stderr: the ^PASS:/^FAIL: parse stays clean).
{
  echo "[git-context-mutation] tracked_hook_sha=$TRACKED_HOOK_SHA"
  echo "[git-context-mutation] BASELINE snapshot:"; sed 's/^/    /' "$TMP/baseline.snap"
  echo "[git-context-mutation] MUTANT snapshot:";   sed 's/^/    /' "$TMP/mutant.snap"
  echo "[git-context-mutation] snapshot delta (baseline -> mutant):"
  diff "$TMP/baseline.snap" "$TMP/mutant.snap" || true
  echo "[git-context-mutation] stderr delta (baseline -> mutant):"
  diff "$TMP/baseline.err" "$TMP/mutant.err" || true
  echo "[git-context-mutation] negative-control verdict rc=$neg_verdict (nonzero = correctly rejected)${neg_note:+ — $neg_note}"
  echo "[git-context-mutation] mutant verdict rc=$mut_verdict"
} >&2

finish
