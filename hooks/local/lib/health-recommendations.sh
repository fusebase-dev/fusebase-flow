#!/usr/bin/env bash
# Fusebase Flow — health-check verdict -> operator guidance mapping.
#
# PROVENANCE:
#   Extracted verbatim from fusebase-flow-health-check.sh § Section 4 per FR-25
#   (the engine sat at 791 of the 800-line ceiling and the S1 CLI-version check
#   needed room). Lives at hooks/local/lib/ — outside the FuseBase CLI refresh
#   manifest. Sourced by the engine; never run standalone.
#
# SEAM: diagnosis (which verdict) stays in the engine; this file owns only the
#   "what do I tell the operator" mapping. One responsibility, one file.
#
# CONTRACT (the engine relies on these):
#   ffhc_build_recommendations -> appends to RECOMMENDATIONS in the CALLER's scope,
#                                 keyed on DRIFT_SIGNATURE. Reads LOCAL_DEFERRED,
#                                 CLI_VERSION_UNSUPPORTED and the FFHC_*_TIMEOUT
#                                 budgets. Emits nothing for an unknown signature.

ffhc_build_recommendations() {
  case "$DRIFT_SIGNATURE" in
    HEALTHY)
      RECOMMENDATIONS+=("No action required. Fusebase Flow overlay is intact.") ;;
    CLI_VERSION_UNSUPPORTED)
      # The lib composed the full three-fact text (version found / reviewed range /
      # next step) at detection time — replay it verbatim rather than paraphrasing.
      RECOMMENDATIONS+=("${CLI_VERSION_UNSUPPORTED[@]}")
      RECOMMENDATIONS+=("Only the CLI VERSION signal is verdict-affecting; CLI_SNAPSHOT_STALE / CLI_CUSTOM_AT_RISK / CLI_STOP_* remain advisory.") ;;
    PARTIAL_UPGRADE)
      RECOMMENDATIONS+=("PARTIAL UPGRADE — VERSION/content advanced but live attestation strings are STALE (an interrupted upgrade, or an adapter with no overlay-refresh path). The stale-fact items are listed above as 'PARTIAL_UPGRADE — …'.")
      RECOMMENDATIONS+=("Repair (re-syncs the derived strings + re-applies adapter overlays):")
      RECOMMENDATIONS+=("  bash hooks/local/sync-version-strings.sh")
      RECOMMENDATIONS+=("  bash hooks/local/post-fusebase-update.sh --refresh-overlays")
      RECOMMENDATIONS+=("Then re-run this health check (expect HEALTHY). If a re-run still reports the same surface, that adapter has no overlay-refresh path yet (e.g. GEMINI.md before the U6 follow-up) — sync-version-strings now covers it (U5).") ;;
    EXCEPTION_IN_EFFECT)
      if [ "${#LOCAL_DEFERRED[@]}" -gt 0 ]; then
        RECOMMENDATIONS+=("All non-OK items are operator-authored deferrals (active health_check_deferral-*.json artifact(s) in state/approvals/). This is engine v2.4.0+ acknowledging that the install brief or operator deliberately omitted parts of the canonical Fusebase Flow setup.")
        RECOMMENDATIONS+=("Recovery script CAN fix the underlying state if you decide to revisit any deferral — the script is additive + idempotent. Run: bash hooks/local/post-fusebase-update.sh")
        RECOMMENDATIONS+=("To clear the deferral artifact(s) themselves: delete the listed artifact file(s) or wait for their expires_at to pass.")
      else
        RECOMMENDATIONS+=("All drift is attributable to active approval artifact(s) in state/approvals/. This is the protected-paths exception mechanism working as designed.")
        RECOMMENDATIONS+=("Recovery script will NOT fix this — it doesn't touch state/approvals/.")
        RECOMMENDATIONS+=("To clear: when the protected work is done, delete the listed artifact(s) or wait for their expires_at to pass. Then re-run this health check.")
      fi ;;
    CLI_LAYER_DRIFT)
      RECOMMENDATIONS+=("CLI-owned agent assets are missing or structurally damaged.")
      RECOMMENDATIONS+=("Run the current FuseBase CLI refresh/update for this project first so the CLI restores its own files.")
      RECOMMENDATIONS+=("After CLI refresh, run: bash hooks/local/post-fusebase-update.sh") ;;
    SHARED_MERGE_DRIFT)
      RECOMMENDATIONS+=("Shared CLI/Flow files are missing Flow overlay or merge additions.")
      RECOMMENDATIONS+=("Run: bash hooks/local/post-fusebase-update.sh")
      RECOMMENDATIONS+=("The script restores Flow overlay blocks, Flow lifecycle settings, Flow skill/agent mirrors, and does not patch CLI hook helper files.") ;;
    FLOW_LAYER_DRIFT)
      RECOMMENDATIONS+=("Flow-owned overlay assets are missing or drifted.")
      RECOMMENDATIONS+=("Run: bash hooks/local/post-fusebase-update.sh")
      RECOMMENDATIONS+=("If CLI-owned assets are also damaged, refresh the current FuseBase CLI first, then rerun Flow recovery.") ;;
    BROKEN)
      RECOMMENDATIONS+=("Genuine failure detected (NOT attributable to an active approval artifact).")
      RECOMMENDATIONS+=("Inspect the LOCAL_BROKEN items above; address each manually.")
      RECOMMENDATIONS+=("After fixes, re-run this health check.") ;;
    PARTIAL_UNVERIFIED)
      RECOMMENDATIONS+=("PARTIAL — not a full health verdict. One or more CRITICAL checks did not run (timed out, skipped, or no timeout binary available); see the 'unverified' items above.")
      RECOMMENDATIONS+=("This is NOT a failure and NOT full health. Exit code 4. Nothing that DID run proved drift or breakage.")
      # WS4 DX: name the exact knob + current effective value (copy-ready re-run), + platform.
      if ffhc_is_msys; then FFHC_PLATFORM_NOTE="MSYS/Git-Bash (higher defaults auto-applied)"; else FFHC_PLATFORM_NOTE="POSIX"; fi
      RECOMMENDATIONS+=("Current effective timeout budgets ($FFHC_PLATFORM_NOTE): FFHC_PREFLIGHT_TIMEOUT=${FFHC_PREFLIGHT_TIMEOUT}s  FFHC_TESTS_TIMEOUT=${FFHC_TESTS_TIMEOUT}s  FFHC_FETCH_TIMEOUT=${FFHC_FETCH_TIMEOUT}s  FFHC_CONFLICT_TIMEOUT=${FFHC_CONFLICT_TIMEOUT}s. Raise the one named in the unverified item above (e.g. FFHC_TESTS_TIMEOUT=240) and re-run.")
      RECOMMENDATIONS+=("To get a full verdict: re-run on a host with more time/CPU, raise the relevant FFHC_*_TIMEOUT env knob (values above), or run the named check directly. If a timeout binary is missing, install coreutils (provides 'timeout'/'gtimeout') or opt into unbounded runs with FFHC_ALLOW_UNBOUNDED=1.") ;;
  esac
}
