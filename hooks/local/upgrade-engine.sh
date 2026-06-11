#!/usr/bin/env bash
# Fusebase Flow — upgrade-engine.sh (DEPRECATED v3.18.0)
# Superseded by hooks/local/upgrade.sh, which covers the engine + recovery
# scripts and everything else. This shim forwards all arguments.
echo "[upgrade-engine] DEPRECATED: use 'bash hooks/local/upgrade.sh' (forwarding now)..." >&2
exec bash "$(dirname "$0")/upgrade.sh" "$@"
