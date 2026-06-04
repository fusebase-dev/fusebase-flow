change_tier: lightweight
ticket: u14-wire-hooks-stop-mis-wire

Problem:   post-fusebase-update.sh --wire-hooks, on a project whose .claude/settings.json
           already had CLI Stop hooks, produced a Stop entry LABELED as the Flow hook but
           carrying the CLI run-typecheck-apps.js command — so stop.py was never wired
           (Flow end-of-turn enforcement silently off; CLI typecheck ran twice). Reproduced.
Root cause: settings-json-merge.py discover_flow_config_from_upstream() used handlers[0].command
           per event. The upstream example's shared Stop chain lists CLI hooks before stop.py
           ([run-typecheck-apps.js, quality-check-apps.js, stop.py]), so handlers[0] was a CLI
           command — discovered as the "Stop" Flow command. (Existing test missed it: it runs
           without .fusebase-flow-source, so discovery fell back to the correct hardcoded default.)
Change:    discovery now picks the FLOW handler in each event's chain (command under
           hooks/handlers/), falling back to handlers[0] only if none match. Stop now resolves
           to stop.py regardless of CLI-hook ordering.
Verified:  reproduced the mis-wire, then confirmed fix wires stop.py + preserves CLI typecheck
           once. recovery sim +U14 (wire onto existing CLI Stop chain WITH upstream example
           present → Flow entry is stop.py). 25/25 sim; run-tests 16/16; preflight 0/0; health
           HEALTHY; merge script syntax valid.
Rollback:  git revert <SHA>
Commit:    d227837
Deploy:    plain operator go-ahead -> v3.8.5 (tag + GitHub release).
