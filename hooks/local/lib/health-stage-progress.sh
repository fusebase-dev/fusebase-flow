#!/usr/bin/env bash

ffhc_stage_start() {
  FFHC_STAGE_NAME="$1"
  FFHC_STAGE_BUDGET="${2:-none}"
  FFHC_STAGE_STARTED="$SECONDS"
  printf '[health-check] START stage=%s budget=%s\n' "$FFHC_STAGE_NAME" "$FFHC_STAGE_BUDGET" >&2
}

ffhc_stage_end() {
  local child_rc="${1:-none}"
  local rc_scope="${2:-}"
  local elapsed=$((SECONDS - FFHC_STAGE_STARTED))
  [ -z "$rc_scope" ] || rc_scope=" rc_scope=$rc_scope"
  printf '[health-check] END stage=%s elapsed=%ss child_rc=%s%s budget=%s\n' \
    "$FFHC_STAGE_NAME" "$elapsed" "$child_rc" "$rc_scope" "$FFHC_STAGE_BUDGET" >&2
}

ffhc_run_cli_version_stage() {
  local library="$1"
  if [ -f "$library" ]; then
    . "$library"
    ffhc_stage_start "cli-version" "${FFHC_CLI_VERSION_TIMEOUT}s"
    FFHC_LAST_RC="not-run"
    ffhc_cli_version_check
    ffhc_stage_end "$FFHC_LAST_RC"
  else
    ffhc_stage_start "cli-version" "10s"
    LOCAL_UNVERIFIED+=("CLI version check: UNVERIFIED — missing $library (re-clone or run 'bash hooks/local/upgrade.sh')")
    ffhc_stage_end "not-run"
  fi
}
