#!/usr/bin/env bash
# Fusebase Flow — po-investigate
# Allowlisted, read-only investigation wrapper for the Product Owner sub-agent.
# Provides a structurally enforced "read-only" guarantee that the sub-agent's
# system prompt cannot police via LLM judgment alone.
#
# Usage:
#   bash hooks/local/po-investigate.sh <subcommand> [args]
#
# Subcommands (read-only only):
#   status                — git status --short
#   diff [args]           — git diff [args]
#   log [args]            — git log [args]
#   show [args]           — git show [args]
#   blame <path>          — git blame <path>
#   ls [path]             — ls -la [path]
#   cat <path>            — cat <path>
#   head <path>           — head -200 <path>
#   tail <path>           — tail -200 <path>
#   find <name-pattern>   — find . -name <name-pattern> -type f
#
# Anything else exits non-zero. Mutating commands (git stash, git commit, npm install,
# node -e ..., python -c ..., bash -c ..., etc.) are not reachable through this wrapper
# because they aren't subcommand keys — the case statement falls through to the error
# branch.
#
# Why this exists:
#   The PO sub-agent's tool surface includes Bash (for legitimate read-only
#   investigation: git history, file listing, diffing). Free-form Bash plus a
#   prompt-level "use only for read-only investigation" instruction asks the LLM
#   to police a fuzzy boundary on every shell call (git stash mutates; npm view
#   makes network calls; node -e "fs.readFileSync(...)" is one keystroke from
#   writeFileSync). This wrapper makes the boundary structural: PO can run
#   `bash hooks/local/po-investigate.sh <subcommand>` and nothing else;
#   non-allowlisted subcommands get a non-zero exit.
#
# Architect-escalation note:
#   AR.4 migration-constraint-check needs to read docs/constitution.md and
#   policies/protected-paths.yml. Both are reachable via `cat <path>` here, and
#   the PO sub-agent also has the Read tool which serves the same purpose.

set -euo pipefail

SUB="${1:-}"
shift || true

case "$SUB" in
    status)
        git status --short ;;
    diff)
        git diff "$@" ;;
    log)
        git log "$@" ;;
    show)
        git show "$@" ;;
    blame)
        if [ -z "${1:-}" ]; then
            echo "usage: po-investigate blame <path>" >&2
            exit 2
        fi
        git blame "$1" ;;
    ls)
        ls -la "$@" ;;
    cat)
        if [ -z "${1:-}" ]; then
            echo "usage: po-investigate cat <path>" >&2
            exit 2
        fi
        cat "$1" ;;
    head)
        if [ -z "${1:-}" ]; then
            echo "usage: po-investigate head <path>" >&2
            exit 2
        fi
        head -200 "$1" ;;
    tail)
        if [ -z "${1:-}" ]; then
            echo "usage: po-investigate tail <path>" >&2
            exit 2
        fi
        tail -200 "$1" ;;
    find)
        if [ -z "${1:-}" ]; then
            echo "usage: po-investigate find <name-pattern>" >&2
            exit 2
        fi
        # Single positional name pattern; no -exec, no -delete forwarding.
        find . -name "$1" -type f ;;
    -h|--help|"")
        sed -n '2,32p' "$0" ;;
    *)
        echo "po-investigate: unknown or non-allowlisted subcommand '$SUB'" >&2
        echo "Allowed: status, diff, log, show, blame, ls, cat, head, tail, find" >&2
        echo "Run with --help for usage." >&2
        exit 2 ;;
esac
