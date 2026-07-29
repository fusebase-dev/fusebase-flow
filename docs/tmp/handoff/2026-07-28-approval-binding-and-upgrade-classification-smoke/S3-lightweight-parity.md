```text
NOTE (deviation, recorded): verification-gate S3 step 1 shows 'approve-local.sh lightweight_deploy smoke-ll ship it' WITHOUT --command.
Under K19/AC22 shipped by THIS ticket, --command is mandatory for command-gated actions, so the literal line now exits 2.
Executed with --command 'fusebase deploy' (the correct post-K19 invocation). Exit-2 of the literal line is demonstrated first.

##### S3 case 0: the gate's literal (no --command) must now exit 2 #####
[approve-local] ERROR: 'lightweight_deploy' is command-gated, so --command is required. An artifact without it authorizes every matching command in this repo (K19).
[approve-local] Re-run with the exact command, e.g.:
  bash hooks/local/approve-local.sh lightweight_deploy smoke-ll --command '<exact command>'
EXIT=2
0

##### S3 case A: lightweight_deploy artifact present #####
[approve-local] artifact written + re-verified: C:\tmp\ff470\s3\state\approvals\lightweight_deploy-smoke-ll-20260729.json (schema v2; expires 2026-10-27T00:33:57Z; repo-bound command-bound)
[approve-local] hooks honor this until it expires. Delete the file to revoke.
-- pre_tool_use:
  decision= allow
-- permission_request:
  decision= allow

##### S3 case B: artifact deleted #####
0
-- pre_tool_use:
  decision= deny
-- permission_request:
  decision= deny

##### S3 case C: production_deploy artifact instead #####
[approve-local] artifact written + re-verified: C:\tmp\ff470\s3\state\approvals\production_deploy-smoke-ll-20260729.json (schema v2; expires 2026-10-27T00:34:01Z; repo-bound command-bound)
[approve-local] hooks honor this until it expires. Delete the file to revoke.
-- pre_tool_use:
  decision= allow
-- permission_request:
  decision= allow

----- ground-truth: state/audit.log.jsonl -----
{"ts":"2026-07-29T00:33:57Z","event_id":"3fbcd993a4ca4bae888ec4207791f365","event":"pre_tool_use","decision":"allow","reason":"no rule matched","rule_id":null,"session_id":null,"host_tool":null,"tool_name":"Bash"}
{"ts":"2026-07-29T00:33:58Z","event_id":"da567d1b4e7d4d13bec577dd82565543","event":"permission_request","decision":"allow","reason":"require_approval matched (production_deploy); artifact(s) present.","rule_id":"FR-12","session_id":null,"host_tool":null,"tool_name":"Bash","matched_pattern":"\\bfusebase\\s+deploy\\b","approval_action":"production_deploy","approval_verdict":"VALID","required_actions":["production_deploy"],"all_required_actions":["production_deploy"],"action_verdicts":{"production_deploy":"VALID","lightweight_deploy":"VALID"}}
{"ts":"2026-07-29T00:33:59Z","event_id":"c23ae0e5dcee491481fd3442bc61a8f6","event":"pre_tool_use","decision":"deny","reason":"BLOCKED (FR-12): fusebase deploy\nRequires approval: production_deploy [NO_ARTIFACT]\n  production_deploy: NO_ARTIFACT - no approval artifact in state/approvals/\nFix - on your chat go-ahead the agent runs this; you type no command:\n  bash hooks/local/approve-local.sh production_deploy <slug> --command 'fusebase deploy'","rule_id":"FR-12","session_id":null,"host_tool":null,"tool_name":"Bash","matched_pattern":"\\bfusebase\\s+deploy\\b","approval_action":"production_deploy","approval_verdict":"NO_ARTIFACT","required_actions":["production_deploy"],"all_required_actions":["production_deploy"],"action_verdicts":{"production_deploy":"NO_ARTIFACT"}}
{"ts":"2026-07-29T00:34:00Z","event_id":"beac8e6967874a8b87266ba485bb7313","event":"permission_request","decision":"deny","reason":"BLOCKED (FR-12): fusebase deploy\nRequires approval: production_deploy [NO_ARTIFACT]\n  production_deploy: NO_ARTIFACT - no approval artifact in state/approvals/\nFix - on your chat go-ahead the agent runs this; you type no command:\n  bash hooks/local/approve-local.sh production_deploy <slug> --command 'fusebase deploy'","rule_id":"FR-12","session_id":null,"host_tool":null,"tool_name":"Bash","matched_pattern":"\\bfusebase\\s+deploy\\b","approval_action":"production_deploy","approval_verdict":"NO_ARTIFACT","required_actions":["production_deploy"],"all_required_actions":["production_deploy"],"action_verdicts":{"production_deploy":"NO_ARTIFACT"}}
{"ts":"2026-07-29T00:34:02Z","event_id":"4158148c70ec4d82b9c4ff1fc2a4b7eb","event":"pre_tool_use","decision":"allow","reason":"no rule matched","rule_id":null,"session_id":null,"host_tool":null,"tool_name":"Bash"}
{"ts":"2026-07-29T00:34:02Z","event_id":"b021986b0eb849ebbcdf529dd5138f03","event":"permission_request","decision":"allow","reason":"require_approval matched (production_deploy); artifact(s) present.","rule_id":"FR-12","session_id":null,"host_tool":null,"tool_name":"Bash","matched_pattern":"\\bfusebase\\s+deploy\\b","approval_action":"production_deploy","approval_verdict":"VALID","required_actions":["production_deploy"],"all_required_actions":["production_deploy"],"action_verdicts":{"production_deploy":"VALID"}}
```
