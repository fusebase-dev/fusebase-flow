#!/usr/bin/env bash
# Fusebase Flow — cli-flow-recovery: CLASSIFICATION module (sourced, never run).
# WHY-home: docs/specs/backlog-triage-execution/architecture-review.md § Q2 (step 4).
#
# TRIPWIRE — every scenario here builds its OWN tree and mutates only that tree. These used to
# be ten `cp -R "$PROJECT"` clones of a tree that four earlier scenarios had already mutated, so
# a reordering changed what was under test. Never derive one scenario's fixture from another's
# end state, and never hoist a tree out of a scenario to "save a build": the build is ~10 forks.
#
# TRIPWIRE — no recovery run belongs in this module. Each scenario asserts how a GIVEN state is
# classified by the read-only reporter; earning that state through post-fusebase-update.sh would
# re-test the E2E module at ~40s a scenario and prove nothing new.

ffcf_classify_run() {
  local d s names=()

  # U10 — an absent FLAG-GATED CLI provider skill is benign, not CLI_LAYER_DRIFT. The CLI deletes
  # flag-gated skills when their flag is off, so absence is by design; the remediation must name
  # `set-flag`, not the dead-end `fusebase update`.
  d="$TMP_BASE/u10-flaggated"; ffcf_conflict_tree "$d"
  rm -rf "$d/.claude/skills/managed-integrations" "$d/.agents/skills/managed-integrations"
  ffcf_conflicts "$d" "$TMP_BASE/u10.json"
  [ "$FFCF_RC" -ne 1 ] || { cat "$TMP_BASE/u10.json" >&2; fail "U10: absent flag-gated skill wrongly escalated to CLI_LAYER_DRIFT (exit 1)"; }
  ffcf_json_assert "$TMP_BASE/u10.json" "U10: absent flag-gated skill should be benign INFO, not drift" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "CLI_LAYER_DRIFT", f"flag-gated absence must not be CLI_LAYER_DRIFT, got {d['verdict']}"
bad = [f for f in d["findings"] if f["status"] == "MISSING" and "managed-integrations" in f["path"]]
assert not bad, f"flag-gated skill reported MISSING: {bad}"
info = [f for f in d["findings"] if f["status"] == "INFO" and "managed-integrations" in f["path"]]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and "flag" in txt and "set-flag" in txt, f"expected flag-aware benign INFO, got {info}"
PY
  pass "U10: absent flag-gated CLI skill is benign INFO (not CLI_LAYER_DRIFT); remediation names set-flag"

  # U11 — Flow hooks NOT wired (opt-in default) is benign, not SHARED_MERGE_DRIFT: settings.json
  # exists with CLI hooks but no Flow stop.py => deliberate hooks-off (F3), a benign INFO.
  d="$TMP_BASE/u11-hooksoff"; ffcf_conflict_tree "$d"; ffcf_settings_hooksoff "$d"
  ffcf_conflicts "$d" "$TMP_BASE/u11.json"
  ffcf_json_assert "$TMP_BASE/u11.json" "U11: hooks-off should be benign INFO, not SHARED_MERGE_DRIFT" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "SHARED_MERGE_DRIFT", f"deliberate hooks-off must not be SHARED_MERGE_DRIFT, got {d['verdict']}"
drift = [f for f in d["findings"] if f["path"] == ".claude/settings.json" and f["status"] in ("DRIFT", "MISSING")]
assert not drift, f"settings.json wrongly reported drift: {drift}"
info = [f for f in d["findings"] if f["path"] == ".claude/settings.json" and f["status"] == "INFO"]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and ("not wired" in txt or "opt-in" in txt), f"expected an opt-in INFO for unwired hooks, got {info}"
PY
  pass "U11: Flow hooks-off (opt-in) is benign INFO, not SHARED_MERGE_DRIFT"

  # U12 (v3.9.0) — deleting the canonical source (now flow-skills/) is flagged loudly: canonical
  # gone while mirrors remain => a recoverable FLOW_LAYER_DRIFT naming the restore path.
  d="$TMP_BASE/u12-skillsdeleted"; ffcf_conflict_tree "$d"
  rm -rf "$d/flow-skills"
  ffcf_conflicts "$d" "$TMP_BASE/u12.json"
  ffcf_json_assert "$TMP_BASE/u12.json" "U12: deleted canonical flow-skills/ should be flagged loudly with restore guidance" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
hits = [f for f in d["findings"] if f["path"] == "flow-skills/" and f["status"] == "MISSING"]
assert hits, "expected a loud MISSING finding for deleted canonical flow-skills/"
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in hits).lower()
assert "canonical" in txt, f"finding should name it canonical: {hits}"
assert "upgrade.sh" in txt or "git checkout" in txt, f"finding should name a restore path: {hits}"
assert d["verdict"] == "FLOW_LAYER_DRIFT", f"deleted canonical source should be FLOW_LAYER_DRIFT, got {d['verdict']}"
PY
  pass "U12: deleted canonical flow-skills/ is flagged FLOW_LAYER_DRIFT with restore guidance"

  # U19 (v3.9.0) — a legacy root skills/ left ALONGSIDE the new flow-skills/ is benign (the CLI's
  # "delete ./skills" warning is finally correct for Flow too): a one-line migration INFO.
  d="$TMP_BASE/u19-legacy-leftover"; ffcf_conflict_tree "$d"
  cp -R "$d/flow-skills" "$d/skills"
  ffcf_conflicts "$d" "$TMP_BASE/u19.json"
  [ "$FFCF_RC" -ne 1 ] || { cat "$TMP_BASE/u19.json" >&2; fail "U19: legacy skills/ leftover wrongly escalated to drift (exit 1)"; }
  ffcf_json_assert "$TMP_BASE/u19.json" "U19: legacy skills/ leftover should be a benign INFO, not drift" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", f"legacy leftover must stay HEALTHY, got {d['verdict']}"
info = [f for f in d["findings"] if f["path"] == "skills/" and f["status"] == "INFO"]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and "flow-skills/" in txt and ("safe to delete" in txt or "upgrade.sh" in txt), f"expected benign migration INFO, got {info}"
bad = [f for f in d["findings"] if f["path"] == "skills/" and f["status"] == "MISSING"]
assert not bad, f"legacy leftover must not be MISSING: {bad}"
PY
  pass "U19: legacy root skills/ alongside flow-skills/ is a benign migration INFO (not drift)"

  # U13 (Issue 2) — CLI provider skills absent from the NON-authoritative .agents/ mirror is
  # benign: the CLI maintains them in .claude/skills only and Flow never writes CLI skill text,
  # so a partial .agents/ mirror must not drift and must not recommend `fusebase update`.
  d="$TMP_BASE/u13-agentsgap"; ffcf_conflict_tree "$d"
  names=(); for s in app-backend app-routing app-secrets app-sidecar app-ui-design; do names+=("$d/.agents/skills/$s"); done
  rm -rf "${names[@]}"
  ffcf_conflicts "$d" "$TMP_BASE/u13.json"
  [ "$FFCF_RC" -ne 1 ] || { cat "$TMP_BASE/u13.json" >&2; fail "U13: .agents CLI-provider gap wrongly escalated to CLI_LAYER_DRIFT (exit 1)"; }
  ffcf_json_assert "$TMP_BASE/u13.json" "U13: .agents CLI-provider gap should be benign, not drift" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "CLI_LAYER_DRIFT", f".agents CLI-provider gap must not be CLI_LAYER_DRIFT, got {d['verdict']}"
bad = [f for f in d["findings"] if f["status"] == "MISSING" and f["path"].startswith(".agents/skills/")]
assert not bad, f".agents CLI-provider skills wrongly reported MISSING: {bad}"
info = [f for f in d["findings"] if f["status"] == "INFO" and f["path"] == ".agents/skills"]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and ".claude/skills" in txt and "expected" in txt, f"expected a benign explanatory INFO for .agents mirror, got {info}"
PY
  pass "U13 (Issue 2): .agents CLI-provider mirror gap is benign INFO (not CLI_LAYER_DRIFT); points at .claude/skills, not fusebase update"

  # AC4: explicit known_names, no app-*.md glob. The two known CLI app-agents must be attributed
  # cli-owned BY NAME on the AUTHORITATIVE surface (.claude/agents); .codex/agents is a
  # non-authoritative mirror (Issue 2) reported as a benign summary, not per-agent.
  d="$TMP_BASE/ac4-knownnames"; ffcf_conflict_tree "$d"
  ffcf_conflicts "$d" "$TMP_BASE/conflict.json"
  ffcf_json_assert "$TMP_BASE/conflict.json" "known_names CLI app-agents not attributed cli-owned" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1], encoding="utf-8").read())
findings = data["findings"]
def owned(path):
    return [f for f in findings if f["path"] == path and f["layer"] == "cli"]
for name in ("app-architect", "app-create-checker"):
    p = f".claude/agents/{name}.md"
    if not owned(p):
        print(f"missing cli-owned finding for {p}", file=sys.stderr)
        sys.exit(1)
PY
  pass "CLI app-agents attributed cli-owned by explicit known_names (authoritative .claude/agents)"

  # A non-listed app-*.md agent must NOT be scooped up as cli-owned (no glob). Drop a synthetic
  # app-foo.md into the CLI agent dirs that is absent from known_names.
  d="$TMP_BASE/ac4-globretired"; ffcf_conflict_tree "$d"
  printf 'SYNTHETIC FLOW-NAMED AGENT app-foo\n' > "$d/.claude/agents/app-foo.md"
  printf 'SYNTHETIC FLOW-NAMED AGENT app-foo\n' > "$d/.codex/agents/app-foo.md"
  ffcf_conflicts "$d" "$TMP_BASE/conflict2.json"
  ffcf_json_assert "$TMP_BASE/conflict2.json" "synthetic app-foo.md was misattributed cli-owned (glob still active)" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1], encoding="utf-8").read())
findings = data["findings"]
bad = [f for f in findings if f["layer"] == "cli" and f["path"].endswith("app-foo.md")]
if bad:
    print(f"app-foo.md wrongly attributed cli-owned: {bad}", file=sys.stderr)
    sys.exit(1)
PY
  pass "non-listed app-foo.md agent not misattributed cli-owned (glob retired)"

  # B3 / AC2 + AC3 — provenance drift advisory + CUSTOM:SKILL scan. Four independent trees, each
  # stamped fresh: (1) clean, (2) mutated present skill, (3) CUSTOM block, (4) missing skill.
  # TRIPWIRE: (1)-(3) must stay exit 0 / HEALTHY — an advisory that flips the verdict is a
  # release blocker for every consumer who ever edited a vendored CLI skill.
  d="$TMP_BASE/prov-clean"; ffcf_conflict_tree "$d"
  ( cd "$d" && bash hooks/local/stamp-cli-provenance.sh > "$TMP_BASE/stamp.out" )
  test -f "$d/audit/cli-vendor-manifest.json" || fail "provenance manifest not generated"
  ffcf_conflicts "$d" "$TMP_BASE/prov-clean.json"
  [ "$FFCF_RC" -eq 0 ] || fail "clean provenance reporter should exit 0, got $FFCF_RC"
  ffcf_json_assert "$TMP_BASE/prov-clean.json" "clean provenance state should report 0 advisories and HEALTHY" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", d["verdict"]
assert d["summary"]["cli_snapshot_stale"] == 0, d["summary"]
assert d["summary"]["cli_custom_at_risk"] == 0, d["summary"]
PY
  pass "provenance stamped; clean state has 0 advisories and HEALTHY verdict"

  d="$TMP_BASE/prov-stale"; ffcf_conflict_tree "$d"
  ( cd "$d" && bash hooks/local/stamp-cli-provenance.sh >/dev/null )
  printf '\nLOCAL EDIT THAT DIFFERS FROM BUNDLED SNAPSHOT\n' >> "$d/.claude/skills/fusebase-cli/SKILL.md"
  ffcf_conflicts "$d" "$TMP_BASE/prov-stale.json"
  [ "$FFCF_RC" -eq 0 ] || fail "CLI_SNAPSHOT_STALE is advisory; reporter must still exit 0, got $FFCF_RC"
  ffcf_json_assert "$TMP_BASE/prov-stale.json" "mutated CLI skill should produce CLI_SNAPSHOT_STALE advisory while staying HEALTHY" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", f"advisory stale must not flip verdict: {d['verdict']}"
assert d["summary"]["cli_snapshot_stale"] >= 1, d["summary"]
stale = [f for f in d["findings"] if f["status"] == "CLI_SNAPSHOT_STALE" and f["path"].endswith("fusebase-cli/SKILL.md")]
assert stale, "expected CLI_SNAPSHOT_STALE for the mutated skill"
PY
  pass "mutated CLI skill -> CLI_SNAPSHOT_STALE advisory (non-failing, verdict stays HEALTHY)"

  # Inject on the AUTHORITATIVE surface (.claude/skills) — that is the one the CLI refreshes, so
  # it is where a CUSTOM block is genuinely at risk (Issue 2: .agents is not CLI-touched).
  d="$TMP_BASE/prov-custom"; ffcf_conflict_tree "$d"
  ( cd "$d" && bash hooks/local/stamp-cli-provenance.sh >/dev/null )
  printf '\n<!-- CUSTOM:SKILL:BEGIN -->\nuser customization\n<!-- CUSTOM:SKILL:END -->\n' >> "$d/.claude/skills/app-backend/SKILL.md"
  ffcf_conflicts "$d" "$TMP_BASE/prov-custom.json"
  [ "$FFCF_RC" -eq 0 ] || fail "CLI_CUSTOM_AT_RISK is advisory; reporter must still exit 0, got $FFCF_RC"
  ffcf_json_assert "$TMP_BASE/prov-custom.json" "CUSTOM:SKILL block should be reported at-risk" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", f"advisory custom must not flip verdict: {d['verdict']}"
assert d["summary"]["cli_custom_at_risk"] >= 1, d["summary"]
risk = [f for f in d["findings"] if f["status"] == "CLI_CUSTOM_AT_RISK" and f["path"].endswith("app-backend/SKILL.md")]
assert risk, "expected CLI_CUSTOM_AT_RISK for the skill carrying a CUSTOM:SKILL block"
PY
  pass "CUSTOM:SKILL block -> CLI_CUSTOM_AT_RISK advisory (at-risk on next refresh)"

  # A MISSING CLI skill still escalates to CLI_LAYER_DRIFT (exit 1) — the advisory work must not
  # weaken missing-vs-stale semantics. fusebase-cli is NOT flag-gated, so this is a partial install.
  d="$TMP_BASE/prov-missing"; ffcf_conflict_tree "$d"
  ( cd "$d" && bash hooks/local/stamp-cli-provenance.sh >/dev/null )
  rm -f "$d/.claude/skills/fusebase-cli/SKILL.md"
  ffcf_conflicts "$d" "$TMP_BASE/prov-missing.json"
  [ "$FFCF_RC" -eq 1 ] || fail "MISSING CLI skill must still exit 1 (CLI_LAYER_DRIFT), got $FFCF_RC"
  ffcf_json_assert "$TMP_BASE/prov-missing.json" "MISSING CLI skill should still be CLI_LAYER_DRIFT" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "CLI_LAYER_DRIFT", d["verdict"]
PY
  pass "MISSING CLI skill still escalates to CLI_LAYER_DRIFT (missing-vs-stale semantics intact)"

  # F4 — single-provider benign absence. A Claude-only / Flow-only project that NEVER installed
  # the CLI provider skills (0 of N present) must NOT be CLI_LAYER_DRIFT: one benign INFO instead
  # of per-skill MISSING. Partial install stays drift (the prov-missing case above).
  d="$TMP_BASE/claude-only"; ffcf_conflict_tree "$d"
  names=(); for s in "${FFCF_PROVIDERS[@]}"; do names+=("$d/.claude/skills/$s" "$d/.agents/skills/$s"); done
  for s in "${FFCF_CLI_AGENTS[@]}"; do names+=("$d/.claude/agents/$s.md" "$d/.codex/agents/$s.md"); done
  rm -rf "${names[@]}"
  ffcf_conflicts "$d" "$TMP_BASE/claude-only.json"
  [ "$FFCF_RC" -ne 1 ] || { cat "$TMP_BASE/claude-only.json" >&2; fail "F4: 0-present CLI provider surface wrongly escalated to CLI_LAYER_DRIFT (exit 1)"; }
  ffcf_json_assert "$TMP_BASE/claude-only.json" "F4: 0-present provider surface should be benign (INFO, not CLI_LAYER_DRIFT)" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "CLI_LAYER_DRIFT", f"0-present must not be CLI_LAYER_DRIFT, got {d['verdict']}"
missing = [f for f in d["findings"] if f["status"] == "MISSING" and f["layer"] == "cli"]
assert not missing, f"0-present provider surface produced per-item MISSING: {missing}"
def text(f): return (f.get("action", "") + " " + f.get("detail", "")).lower()
info = [f for f in d["findings"] if f["status"] == "INFO" and "not installed" in text(f)]
assert info, "expected a benign INFO about provider skills not being installed"
PY
  pass "F4: 0-present CLI provider surface is benign (single INFO, never CLI_LAYER_DRIFT)"
  ffcp_substep classify check-cli-flow-conflicts.sh "12 isolated classification fixtures"
}
