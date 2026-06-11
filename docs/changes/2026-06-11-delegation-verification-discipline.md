change_tier: lightweight
ticket: delegation-verification-discipline

Problem:   Downstream proposal (paperclip+hermes-v1 autonomous run, operator-
           relayed), two framework gaps hit repeatedly: (1) 3 delegated
           sessions ended turns "watching in background — I'll resume when it
           completes" — delegated sessions cannot self-resume; orchestrator
           had to detect false completions from ground truth each time.
           (2) Verification skills define WHAT counts as evidence but not HOW
           to obtain it economically — default agent behavior is to WATCH
           (re-read state every cycle): ~150-280k tokens/watcher session,
           linear with wall-clock; same evidence available ~10x cheaper by
           reading durable records after the run.
Change:    1) task-delegation: binding Turn-completion rule (deliverable
           complete in-turn; bounded in-turn polling or record-then-read;
           never "I'll resume when…"; one-sentence push into delegating
           prompts). Pushed also into templates/handoff-implement.md
           delegation line + workflows/greenlight-deploy.md probe step.
           2) smoke-testing § Verification cost discipline: record-then-read
           default (durable evidence surfaces read once post-run); missing
           evidence surface = observability-gap finding; sole exception =
           first live drive of fresh code hunting unknown failure modes
           (bounded); plans state their mode; delegated-session tie-in.
           validation-and-qa: § Verification cost cross-ref.
Verified:  preflight 0/0; run-tests 24/24; --all 0; mirrors re-run clean.
Rollback:  git revert <SHA>
Commit:    2c017b7
Deploy:    operator-relayed proposal = the request -> v3.19.1 tag + GitHub
           Release, push origin main --follow-tags.
