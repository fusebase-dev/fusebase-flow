# Workflow: live-user-verification

> **Style:** Mode-B-lite. The procedural workflow for testing on the operator's actual account using their session credentials, with explicit consent + ephemeral handling + cleanup.

## When to run

Some tickets benefit from testing on the operator's actual account rather than synthetic test data. The Product Owner proposes this option when:

- The bug is operator-account-specific (real config / real auth / real data shape)
- The feature exercises real-config edge cases that synthetic data won't reproduce
- Reproducing the issue requires real-auth state (cookies / OAuth tokens / session)

The operator can also request it explicitly ("test it on my account").

## When NOT to run

- Customer-facing workflows where credential exposure has any risk beyond the operator's own account.
- Any scenario where synthetic test data would surface the same behavior.
- When the operator is fatigued or distracted (consent-flow risk).
- Read-write tests against shared / production state that other operators depend on.

## Procedure

### Step 1 — PO proposes the option (CONSENT FLOW; exact text)

The PO copies this block verbatim into chat. Do not paraphrase — the exact phrasing matters because the operator decides based on it.

```
## Live-user verification option

I can verify this on your actual account (faster, more accurate diagnosis), OR
proceed with synthetic test data (safer, slower).

If you provide your session key:
- AI Developer runs smoke prompts against your live account
- Faster: real config, real auth, real edge cases visible
- Risk: if the implementer's session is compromised during testing, your account
  could be accessed during the testing window
- Mitigation: session expires per its TTL; you can sign out at end of work to
  invalidate immediately; key is never persisted to disk

If you decline:
- AI Developer uses synthetic test data + test accounts
- Slower: may not reproduce account-specific edge cases
- Safer: no credential exposure

Reply 'share key' or 'use synthetic'.
```

The operator has full agency. PO highlights risks AND benefits. Document the operator's choice in spec.md.

### Step 2 — Operator decides

| Reply | Next step |
|---|---|
| `share key` | proceed to Step 3 (consent recorded) |
| `use synthetic` | document in spec.md "Operator declined live-user verification; using synthetic test data"; skip the rest of this workflow; use synthetic in the implementer handoff |
| any other reply | re-prompt with the consent flow text; do not infer consent from ambiguous reply |

### Step 3 — Author the approval artifact

```bash
bash hooks/local/approve-local.sh session_key_or_cookie_use <slug> "live-user verification for ticket: <reason>"
```

Result: `state/approvals/session_key_or_cookie_use-<slug>-<YYYYMMDD>.json` with TTL = 30 minutes (per `policies/approval-policy.yml`).

The TTL is short by design. The session key is intended for the testing window only.

### Step 4 — PO drafts the implementer handoff with session-key authorization

In `docs/tmp/handoff/<date>-<slug>-implement.md`, include:

```markdown
## Live-user verification authorized

Operator has consented to live-user verification per `workflows/live-user-verification.md`.
Approval artifact: `state/approvals/session_key_or_cookie_use-<slug>-<YYYYMMDD>.json` (TTL 30 min).

The session key will be supplied by the operator via env var (NOT in this handoff text).
AI Developer must apply the session-key handling discipline (flow-skills/role-discipline/SKILL.md
section "AI Developer", item IM.7):
- mask in any output (never print the value)
- never persist to disk (no commits, no log files, no audit log)
- ephemeral — discard at end of testing window
- sanity-test before relying (curl + identity check, see Step 5)
- end-of-work cleanup (operator signs out OR cookie expires; document)
```

### Step 5 — Cookie sanity test (AI Developer side)

Before running smoke prompts, verify the session key is valid. The cookie / token must:

- Authenticate (HTTP 200 on a known authenticated endpoint).
- Match the operator's identity (response body contains expected operator-id / email).
- Not be expired (response includes a session-valid indicator if the API exposes one).

Example sanity test (adapt to project's auth model):

```bash
# Operator supplies via env var; never paste the value into chat.
SESSION_TOKEN="${OPERATOR_SESSION_TOKEN:?must be set}"

# Sanity probe: GET a known authenticated endpoint
response=$(curl -s -o /tmp/sanity-response.json -w "%{http_code}" \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  "${API_BASE_URL}/me")

if [ "$response" != "200" ]; then
  echo "Sanity test FAIL: HTTP $response (expected 200). Aborting; do not proceed with smoke."
  exit 1
fi

# Verify identity matches expected operator
identity=$(jq -r '.email // .id // "unknown"' /tmp/sanity-response.json)
echo "Sanity test PASS: authenticated as $identity"

# Cleanup the temp response (don't leave session evidence on disk)
rm -f /tmp/sanity-response.json
```

If the sanity test fails: STOP. Do not run smoke prompts with an invalid token. Surface to operator.

### Step 6 — Run smoke prompts with masked output

Smoke prompts execute as normal per `workflows/smoke-verification.md`, with two modifications:

1. **Output masking:** wherever a command would print or log the session key, redact. Use `sed` / `awk` to strip the cookie value before piping to log:
   ```bash
   # Wrong: token may leak in log
   curl -H "Cookie: session=$TOKEN" "$URL" 2>&1 | tee log.txt

   # Right: redact in piped log
   curl -H "Cookie: session=$TOKEN" "$URL" 2>&1 \
     | sed "s|$TOKEN|<REDACTED>|g" \
     | tee log.txt
   ```

2. **Evidence persistence:** screenshots and response bodies that would normally land in `docs/tmp/handoff/<date>-<slug>-smoke/` must be screened for any leaked session value. If a screenshot would expose the cookie, take a different screenshot or crop.

### Step 7 — End-of-work cleanup (mandatory)

After smoke completes (PASS or FAIL), the cleanup step is non-optional:

1. **Operator action:** sign out of the account in the source-of-truth UI to invalidate the session immediately. This is the strongest cleanup; it doesn't wait for TTL.
2. **Or:** wait for the cookie's natural TTL to expire (often 60 min — 24 hours depending on system). The TTL of the approval artifact (30 min) is shorter than typical cookie TTLs; once the artifact expires, the workflow is effectively closed even if the cookie itself is still valid.
3. **Verify no persistence:**
   ```bash
   # Should return zero results (no places where the cookie value was written)
   grep -r "$TOKEN" docs/ state/ . 2>/dev/null | head
   ```
4. **Document in deploy report or ticket audit log:**
   ```
   Live-user verification cleanup:
   - Smoke completed at <timestamp>
   - Operator signed out at <timestamp> (or: cookie TTL expires at <timestamp>)
   - grep for token in repo: 0 matches (no persistence)
   - Approval artifact expired at <timestamp> (or: removed manually)
   ```

### Step 8 — Add cleanup_marker_present transcript line

For the `stop` hook to recognize that cleanup happened, include this exact phrase in the transcript / final response:

```
cleanup: operator can sign out OR cookie expires per TTL
```

The `stop` hook scans for this signal before allowing "smoke complete" / "deploy complete" claims when live-user verification was in play (per `policies/required-artifacts.yml: signal_definitions: cleanup_marker_present`).

## Outputs

| Artifact | Path | Mode |
|---|---|---|
| Approval artifact | `state/approvals/session_key_or_cookie_use-<slug>-<date>.json` | machine-readable |
| Consent record | `docs/specs/<slug>/spec.md` audit log | Mode B |
| Sanity-test result | chat output | Mode A |
| Smoke evidence (with redacted credentials) | `docs/tmp/handoff/<date>-<slug>-smoke/` | Mode B |
| Cleanup confirmation | deploy report or `docs/tmp/handoff/<date>-<slug>-deploy.md` | Mode B |

## Failure modes

| Failure | Recovery |
|---|---|
| Operator declines | use synthetic test data; document choice in spec.md; this workflow does not run |
| Sanity test FAIL (HTTP 401 / 403) | session is invalid; do NOT proceed with smoke; ask operator to provide a fresh token OR fall back to synthetic |
| Sanity test passes but identity doesn't match | wrong account; STOP; ask operator to verify |
| A smoke prompt fails AND a screenshot leaked the cookie value | redact the screenshot, OR delete and re-take; rotate the cookie; update spec.md audit log |
| Approval artifact expires mid-smoke | re-author the artifact (`approve-local.sh` again); if smoke is partially done, document the timing in deploy report |
| Cleanup step skipped | treat as production-incident-equivalent; operator signs out immediately; file `docs/problem-catalog/<date>-cleanup-bypass/problem.md` |

## Anti-patterns

- ❌ Paraphrase the consent flow text. The exact phrasing in Step 1 is the contract; modifying it changes the operator's risk understanding.
- ❌ Persist the session key to disk in any form (commit, log file, env file, audit log). Mask in all outputs.
- ❌ Skip the sanity test. An invalid token causes silent smoke failures that look like product bugs.
- ❌ Skip the cleanup step. The TTL is the safety net; the cleanup is the active protection.
- ❌ Bake the session-key value into the implementer handoff. Use env var NAMES; the value lives in the environment, supplied by the operator at runtime.
- ❌ Use this workflow for shared / multi-operator state. The risk model assumes the operator's own account; multi-operator scenarios need explicit additional approvals.

## Related

- `policies/approval-policy.yml: session_key_or_cookie_use` — TTL + enforcement
- `policies/secret-patterns.yml: cookie_session_value` — pattern detection (per-tool override blocks `pre_tool_use` writes)
- `flow-skills/role-discipline/SKILL.md` AI Developer section IM.7 — handling discipline summary
- `workflows/smoke-verification.md` — generic smoke procedure (this workflow extends it for live-user)
- `workflows/violation-recovery.md` FR-12 — recovery if session-key was used without an artifact
- `docs/operator-discipline.md` OD-3 — don't bypass the Product Owner (session-key proposals always go through PO)
