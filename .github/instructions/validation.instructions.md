---
applyTo: "docs/specs/*/verification-gate.md, docs/handoff/*-smoke/**, **/test/**, **/__tests__/**"
---

# Fusebase Flow — validation & QA instructions for GitHub Copilot / VS Code

Apply when running gate checks, reviewing diffs against the gate contract, or verifying smoke prompts.

## Gate report (AI Developer-side)

Required fields per `policies/gate-contracts.yml`:

- Implementation summary (1–3 sentences)
- Per-task SHAs (`T<n>: <sha> <subject>`)
- Test counts (before / after / delta per layer)
- Lint status (clean / warnings / errors)
- Typecheck status (clean / errors)
- Worker-undisturbed git diff confirmation
- Manifest version (if applicable)
- Deviations from architect / PO plan
- Self-attestation phrase

If any field is missing, redirect: "Gate report missing <field>. Per FR-05, complete reports only. Re-run."

## Reproducibility before fix (FR-10)

When the operator describes a single observed failure:

1. Don't draft a fix immediately.
2. Reproduce 3 times under the same conditions.
3. Outcomes:
   - 3/3 reproduce → systemic; draft fix.
   - 1/3 or 2/3 → likely model variance / non-determinism; document and recommend no-op close.
   - 0/3 → close as no-op-needed.

## Smoke prompts (post-deploy)

When `verification-gate.md` defines numbered S1..Sn:

- Persist evidence to `docs/handoff/<date>-<slug>-smoke/`.
- Compute pass ratio against the gate contract threshold.
- If below threshold, do NOT mark spec DONE; surface failure with concrete `S<n> observed Y, expected Z`.

## What this scope does NOT do

- Approve deploy (that's the `release-deploy-reporting` skill)
- Auto-fix lint / typecheck errors — surface them
- Skip reproducibility-before-fix (FR-10)
