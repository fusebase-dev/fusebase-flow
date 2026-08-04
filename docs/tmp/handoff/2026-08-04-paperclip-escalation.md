# Escalation — the installed-engine upgrade path overwrites the consumer overlay, and the 4.7.0 approval default is now an **observed** fail-open

**To:** Fusebase Flow maintainers · **From:** paperclip+hermes-v1 (consumer) · **Date:** 2026-08-04
**Flow versions:** installed **4.6.1**, source clone **4.7.0** (`cbda87e`; was `85b97dd` in our 2026-07-30 report)
**Related (read these first — not restated here):**
`2026-07-28-approval-artifact-binding-and-upgrade-conflict-classification.md` (§ 3 → shipped as `af18431`)
`2026-07-30-bootstrap-upgrade-disarms-engine-seams-before-classification.md` (§ 5 predicted § 1 below)

## 0. Front-load

We ran `bash hooks/local/upgrade.sh --auto-yes` on a clean tree. It completed content + VERSION, then our
composed gate fired **RED on L2/L3/L4** and refused. We measured the cause, rolled back to 4.6.1, and
re-proved the restored gate refuses live.

Three findings, in descending value to you:

| # | Finding | Strength |
|---|---|---|
| 1 | The 4.7.0 approval default accepts a missing-`expires_at` artifact → `fusebase deploy` **allowed** on our tree | **OBSERVED** (was INFERRED in 07-30 § 5) |
| 2 | The post-upgrade **recovery hint routes a re-run into an engine with no gate invocation** | **OBSERVED** (grep counts, § 3) |
| 3 | A string-anchor substance sentinel cannot distinguish *lost* from *renamed-upstream* | **OBSERVED** (§ 4) |

**Our own error, stated first:** we ran the **installed 4.6.1** engine (blunt `refresh dir: hooks/` /
`refresh dir: policies/`) instead of the **4.7.0** engine's per-file classifier. 07-30 § 7 documents that
exact contrast, and we did not re-read our own filing before acting. `af18431` would have refused and
written nothing. **The overwrite is not a 4.7.0 defect.** Findings 1–3 stand independently of it.

## 1. The 07-30 § 5 inference is now a measurement

Both engines, same tree, same 98 artifacts in `state/approvals/`, evaluated out-of-tree against a
`git archive HEAD` copy so neither engine could see the other's files:

| Engine | `fusebase deploy` | `git push origin master` | Verdict field |
|---|---|---|---|
| 4.6.1 (our overlay) | **deny** — FR-12 | **deny** — FR-12 | no artifact accepted |
| 4.7.0 (refreshed) | **allow** | **allow** | `approval_verdict=MISSING_EXPIRY` |

Mechanism, exactly as you described it: `_ACCEPT_COMPAT = {VALID, MISSING_EXPIRY}` plus
`strict_approvals: false` (upstream `policies/approval-policy.yml:154`; the key does not exist in ours —
we deny unconditionally). We hold 98 active artifacts accumulated over months of deploys; several carry
no `action` and no `expires_at` at all. One of them satisfies `production_deploy` permanently.

**This is not a request to change your default** — 07-30 § 5 already conceded it is your compatibility
call, and we still concede it. What is new: on a real consumer tree with real accumulated history, the
default is not a latent permissiveness, it is a **live open deploy gate**, reached by the documented
upgrade path, in one command, with no warning from the framework itself.

Our overlay's substance, for context — none of it exists upstream under any name (0 hits each):
`schema: fusebase-flow/approval@2`, `call_id` binding, `shadow_allow`, positive-whitelist semantics.

## 2. Why the collision is structural, not incidental

4.7.0 independently rewrote the same layer we hardened: new `hooks/shared/approval_artifact.py`,
`command_rules.py`, `denial_message.py`; `command_policy.py` ~709 lines changed; `evaluate_command`
renamed `evaluate`. So the 12 `changed-by-both` files from 07-30 § 0 are not a merge — six of them are
two independent implementations of one contract, and the naive restore
(`git checkout <pre-upgrade-sha> -- <the 7 security files>`) yields a hybrid: our `command_policy.py`
beside upstream's new modules that nothing then imports.

We are not asking you to solve that. We are recording that **"consumer keeps their patch" is not
available as an outcome here** — only *keep ours whole*, *take yours whole*, or *port deliberately*.

## 3. New defect — the recovery hint points at a gate-less engine

Our composed gate is invoked from seam I5 inside `hooks/local/upgrade.sh` (07-30 § 2). Measured:

| Engine copy | `check-post-upgrade-gate` refs | `classif*` refs |
|---|---|---|
| installed 4.6.1 `hooks/local/upgrade.sh` | **1** (I5 present) | **0** |
| upstream 4.7.0 `hooks/local/upgrade.sh` | **0** | **13** |

What actually happened on our run: bash had already parsed the 4.6.1 engine into `main()`, so **I5 fired
from memory and caught the regression — after the on-disk file had been replaced by upstream's
gate-less copy.** We were saved by a parse-order accident.

The engine then printed, as its failure recovery:

```
[upgrade] Recover by re-running (idempotent — the refreshed engine finishes the rest):
    bash hooks/local/upgrade.sh
```

That re-run executes **upstream's** engine. It would classify (good — it should refuse and write
nothing), but it emits **no gate verdict at all**. The instruction issued at the exact moment a consumer
has just been told their security substance is gone hands them the one engine that cannot tell them so
again. A consumer who re-runs and sees a clean exit has no way to distinguish "classifier protected me"
from "gate no longer exists".

**Suggested fix (cheap):** when the run that failed invoked a consumer gate that the refreshed engine
does not invoke, say so in the recovery block — e.g. *"note: the refreshed engine does not invoke
`<gate>`; re-run it directly after the upgrade."* One line, no mechanism change.

## 4. A string-anchor sentinel cannot classify substance

Our L4 sentinel reports `SUBSTANCE LOST` by checking for literal anchors. It fired correctly here — but
it fires **identically** when upstream re-implements the same guarantee under a different name, which is
precisely what 4.7.0 did for expiry/binding. Its wording ("treat as an incident") is therefore not
evidence on its own.

What separated the cases was **executing both engines against real artifacts** (§ 1). We are changing our
own procedure to require that measurement before acting on the sentinel, and we flag the general lesson:
any anchor-based substance check in a framework that permits upstream refactors will produce
indistinguishable true and false positives. Ours is consumer-owned; we are not asking you to ship one.

## 5. What we did — rollback, and live proof of the restored state

Tree was clean before the upgrade, so rollback was total:

1. move the 20 upgrade-created untracked files aside (kept, not deleted)
2. `git restore .`
3. `bash hooks/local/install-git-hooks.sh` — re-pin `.git/hooks` to the 4.6.1 drivers, avoiding the
   new-driver/old-HEAD scanner skew we hit on the 3.30.4→4.2.0 hop
4. re-probe the real handler

End state: `HEAD 5898d229` (unchanged, **no commits made**), `VERSION 4.6.1`, 0 dirty files.

Live proof — the real `hooks/handlers/pre_tool_use.py`, post-rollback. It also refused an interactive
probe of ours mid-session, i.e. observed refusing, not inferred:

```
fusebase deploy         -> deny   FR-12
git push origin master  -> deny   FR-12
git status              -> allow
npm run lint            -> allow
```

## 6. What we are NOT claiming

- Not claiming 4.7.0 caused the overwrite. **We ran the wrong engine** (§ 0). `af18431` works; 07-30 § 0
  measured it working on this same tree.
- Not claiming the approval default is a defect. It is your documented compatibility choice. We claim
  only that its consequence on an aged consumer tree is now observed rather than reasoned.
- Not claiming § 3 causes silent corruption — upstream's classifier should still refuse to write. The
  defect is the **missing signal**, not a missing protection.
- Not re-litigating 07-28 or 07-30. Both stand; this extends them.

## 7. Reproduction

1. Consumer tree with a security overlay on the approval path and ≥1 artifact lacking `expires_at`.
2. `git archive HEAD hooks policies | tar -x -C <tmp>`; `git init` it; copy `state/approvals/` in.
3. Evaluate `fusebase deploy` under that engine → deny.
4. Repeat with the 4.7.0 files in place → allow, `approval_verdict=MISSING_EXPIRY`.
5. `grep -c check-post-upgrade-gate` on both `upgrade.sh` copies → 1 vs 0 (§ 3).

Steps 3–4 need nothing applied to the live tree.

## 8. Our standing decision, unchanged from 07-30 § 6

We have **not** adopted 4.7.0. The keep-vs-adopt call on the 12 `changed-by-both` files is still open,
now with § 1 as evidence rather than inference. Three routes on our side:

| Route | Cost | What we give up |
|---|---|---|
| Stay 4.6.1, relay this report | lowest | 4.7.0's classifier, source-boundary work, backup cleanup |
| Port our overlay onto 4.7.0's modules | Full-lane ticket, adversarial plan review | time on the most safety-critical files |
| Adopt 4.7.0 + purge the 98 legacy artifacts | cheapest adoption | `call_id` / `shadow_allow`; `MISSING_EXPIRY` acceptance remains standing |

Unrelated local item recorded so it is not mistaken for upgrade fallout:
`audit/hook-layer-manifest.json` was last stamped `fca22db8` (2026-07-28) while 9 hook files changed in
`24fd1277` / `f944da00` after it, so `/fusebase-health` reports `FLOW_LAYER_DRIFT` deterministically until
re-stamped. Predates this session; unaffected by the upgrade or the rollback.

## Contact

Filed by the paperclip+hermes-v1 consumer; third in the chain after 2026-07-28 and 2026-07-30. Both
engines and the source clone remain staged with a baseline of record, so re-running any measurement here
against a proposed fix is cheap for us.
