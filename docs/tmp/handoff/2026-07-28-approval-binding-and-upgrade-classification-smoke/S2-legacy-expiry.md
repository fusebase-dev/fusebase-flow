```text
##### S2 step 1: --inventory (4.7.0) #####
file                                    action             schema  expiry-state      binding-state  verdict(strict)        
--------------------------------------  -----------------  ------  ----------------  -------------  -----------------------
production_deploy-legacy-20260728.json  production_deploy  legacy  legacy-no-expiry  none           REJECT (MISSING_EXPIRY)

[approve-local] 1 artifact(s); 1 would be REJECTED under strict_approvals: true.
[approve-local] Reissue each with: bash hooks/local/approve-local.sh <action> <slug> '<reason>' --command '<exact command>'
EXIT=0

##### S2 step 2: deploy payload, strict_approvals=false (compat) #####
{"decision": "allow", "reason": "no rule matched", "rule_id": null, "hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "no rule matched"}}EXIT=0

##### S2 step 3: flip strict_approvals=true, same payload #####
154:strict_approvals: true
file                                    action             schema  expiry-state      binding-state  verdict(strict)        
--------------------------------------  -----------------  ------  ----------------  -------------  -----------------------
production_deploy-legacy-20260728.json  production_deploy  legacy  legacy-no-expiry  none           REJECT (MISSING_EXPIRY)

[approve-local] 1 artifact(s); 1 would be REJECTED under strict_approvals: true.
[approve-local] Reissue each with: bash hooks/local/approve-local.sh <action> <slug> '<reason>' --command '<exact command>'
INVENTORY-EXIT=0
[fusebase-flow] DENY: BLOCKED (FR-12): fusebase deploy
Requires approval: production_deploy [MISSING_EXPIRY]
  production_deploy: MISSING_EXPIRY - artifact has no expires_at (legacy; rejected once strict_approvals is on)
Fix - on your chat go-ahead the agent runs this; you type no command:
  bash hooks/local/approve-local.sh production_deploy <slug> --command 'fusebase deploy'
{"decision": "deny", "reason": "BLOCKED (FR-12): fusebase deploy\nRequires approval: production_deploy [MISSING_EXPIRY]\n  production_deploy: MISSING_EXPIRY - artifact has no expires_at (legacy; rejected once strict_approvals is on)\nFix - on your chat go-ahead the agent runs this; you type no command:\n  bash hooks/local/approve-local.sh production_deploy <slug> --command 'fusebase deploy'", "rule_id": "FR-12", "hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "BLOCKED (FR-12): fusebase deploy\nRequires approval: production_deploy [MISSING_EXPIRY]\n  production_deploy: MISSING_EXPIRY - artifact has no expires_at (legacy; rejected once strict_approvals is on)\nFix - on your chat go-ahead the agent runs this; you type no command:\n  bash hooks/local/approve-local.sh production_deploy <slug> --command 'fusebase deploy'"}}EXIT=2

----- ground-truth: state/audit.log.jsonl (both decisions) -----
{"ts":"2026-07-29T00:33:32Z","event_id":"a0ba8c8d1c34496687408f6e5e375e58","event":"approval_legacy_accepted","decision":"allow","reason":"K7 compat [command_policy]: production_deploy-legacy-20260728.json has no parseable expires_at and was accepted. Strict mode (strict_approvals: true) will REJECT it — reissue with `bash hooks/local/approve-local.sh production_deploy <slug> --command '<exact command>'`.","rule_id":"FR-12","session_id":null,"host_tool":null,"artifact":"production_deploy-legacy-20260728.json","action":"production_deploy","carrier":"command_policy","approval_verdict":"MISSING_EXPIRY"}
{"ts":"2026-07-29T00:33:32Z","event_id":"2bae0221c3e042bd98a91b272f3ece5f","event":"pre_tool_use","decision":"allow","reason":"no rule matched","rule_id":null,"session_id":null,"host_tool":null,"tool_name":"Bash"}
{"ts":"2026-07-29T00:33:33Z","event_id":"3fb46949e1564218a0eed7fe733a6b2b","event":"pre_tool_use","decision":"deny","reason":"BLOCKED (FR-12): fusebase deploy\nRequires approval: production_deploy [MISSING_EXPIRY]\n  production_deploy: MISSING_EXPIRY - artifact has no expires_at (legacy; rejected once strict_approvals is on)\nFix - on your chat go-ahead the agent runs this; you type no command:\n  bash hooks/local/approve-local.sh production_deploy <slug> --command 'fusebase deploy'","rule_id":"FR-12","session_id":null,"host_tool":null,"tool_name":"Bash","matched_pattern":"\\bfusebase\\s+deploy\\b","approval_action":"production_deploy","approval_verdict":"MISSING_EXPIRY","required_actions":["production_deploy"],"all_required_actions":["production_deploy"],"action_verdicts":{"production_deploy":"MISSING_EXPIRY"}}
```
