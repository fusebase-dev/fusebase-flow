# N5 — `upgrade.sh` reports success while installing nothing

**Status:** SPECIFIED — design ratified by the operator; §1/§2 apply LOCKED decisions unchanged, §3 is the one new rule.
**Opened:** 2026-08-15
**Severity:** HIGH
**Trigger:** consumer report against `v4.10.1`, verified mechanically here.
**Class:** the release cannot reach the population it was written for.

## Verdict

**HALF-IMPLEMENTED DECISION, not a wrong one.** K13a (LOCKED) states the invariant unconditionally — *"a consumer with no `audit/managed-content-manifest.json` does not get a tree full of `unknown-base`"* — and names `bootstrap-upgrade.sh` only as the mechanism in scope at the time. Synthesis was never ported to `upgrade.sh`, which is the path most consumers take. The fix **completes** K13a; it amends nothing.

## Established — verified locally, not taken on trust

| Fact | Evidence |
|---|---|
| `unknown-base` is silently kept on the ordinary path | `upgrade.sh:388` `MCM_DECISIONS="…,unknown-base=keep,changed-by-both=abort"` |
| `upgrade.sh` contains ZERO synthesis calls | `ff_synthesize_base` exists only in `bootstrap-upgrade.sh` (defined `:698`, called `:761`) |
| VERSION advances regardless of what was delivered | `upgrade.sh:644-648`, an unconditional CRITICAL step gated only on `VERSION_CHANGE` |
| The repo already documented this exact failure | `bootstrap-upgrade.sh:685-694`: *"the upgrade reports success while installing NOTHING. The classifier release could not deliver its own content."* |
| The run already counts what it applied | `upgrade.sh:524,537,549` — `ff_applied` / `ff_removed` / `ff_preserved` |

### Consumer reproduction (the oracle)

Same trees, one variable — the presence of `audit/managed-content-manifest.json`:

| `--base` | upstream-only (refreshed) | unknown-base (silently kept) | consumer-only |
|---|---:|---:|---:|
| absent | 0 | **26** | 0 |
| present | **24** | 0 | **2** |

24 upstream changes silently dropped. The 2 genuinely consumer-edited files also lose their `consumer-only` protection into the same bucket, so the report cannot even tell the consumer which files are theirs.

### Why HIGH, not theoretical

The exposed population is exactly the F1/N1 one: installs whose last upgrade ran a pre-4.7.0 engine, which never delivered a base manifest. `v4.10.1` exists to bring adopters current with CLI 0.29.8; those adopters' upgrades will quietly decline to deliver it. It was caught only by hand-grepping for three known fixes.

## Slices

### S1 — port K13a synthesis to the ordinary upgrade path

Extract `ff_synthesize_base` into a shared lib sourced by **both** engines. **Extract, never copy** (K14's one-home principle): two copies drift, and the function's M1 line-ending block explicitly says not to simplify it — that block is the difference between a correct base and whole-tree misclassification.

Parameterise only what differs between the two callers: log prefix, base path, module source, source repo, and the isolated python runner (`ff_boot_py` / `ff_up_py`). Behaviour must not change for `bootstrap-upgrade.sh`.

### S2 — `unknown-base` still never aborts (K9 unchanged)

The consumer's preferred fix — abort like `changed-by-both` — is a **rejected alternative** (`decisions.md:193`, *"unusable first adoption"*). It also punishes the forked consumer least able to recover. Not adopted. Nothing in this ticket changes a per-path verdict.

### S3 — a run that delivered nothing must not claim it did

Per-path verdicts are K9's domain; this is a **run-level** rule and does not touch them. `upgrade.sh:12` already claims *"VERSION as the LAST step — so VERSION can never advance ahead of content"* — an **ordering** guarantee that N5 proves insufficient: with every path kept, VERSION advances ahead of content semantically while satisfying the ordering.

**Trigger — all three clauses required:**

```
VERSION would change   AND   ff_applied == 0 AND ff_removed == 0   AND   >=1 path classified unknown-base
```

The third clause separates *"nothing to do"* from *"couldn't tell what to do"*: a current tree has a base and classifies `current`; a docs-only release touches no managed path. Neither trips.

**On trigger:**

1. Refuse the VERSION bump.
2. **Exit non-zero**, with a verdict distinguishable from both a clean run and a `changed-by-both` abort — this is *"delivered nothing"*, not *"conflict needs a human"*, not *"success"*.
3. Name the recovery concretely: `docs/release-fingerprints.md` identifies the tag to seed from, and `bootstrap-upgrade.sh` synthesizes the base.
4. The **dry run** must surface the same condition — the consumer specifically noted the dry run showed no conflicts.

Not warn-only. `preflight.sh:301` already warns on a missing base and did not stop this, partly because preflight is maintainer-side and the consumer never runs it. A second advisory would be the third soft signal on one failure.

**Cannot strand the forked consumer** — the refusal keys on zero-refreshed, not on synthesis failing:

| Synthesis | Refreshed | Outcome |
|---|---|---|
| resolves | any | normal refresh, VERSION advances |
| fails (forked) | >0 | VERSION advances — unchanged from today |
| fails (forked) | 0, all `unknown-base` | refuse, exit non-zero, name the recovery |

## Acceptance criteria

- **AC1** — base absent + resolvable tag ⇒ synthesis runs on the `upgrade.sh` path; the consumer matrix becomes `24 upstream-only refreshed / 2 consumer-only preserved / 0 unknown-base`.
- **AC2** — base present ⇒ behaviour byte-identical to today (synthesis is a no-op).
- **AC3** — forked/unreleased VERSION + files still refreshed ⇒ proceeds, VERSION advances, no abort (K9 honoured).
- **AC4** — trigger fires ⇒ non-zero exit, VERSION unchanged on disk, message names `release-fingerprints.md` + `bootstrap-upgrade.sh`, verdict distinguishable from `changed-by-both`.
- **AC5** — dry run surfaces the same condition rather than reporting no conflicts.
- **AC6** — `bootstrap-upgrade.sh` behaviour unchanged by the extraction.

## Explicitly NOT doing

| Not doing | Why |
|---|---|
| Abort on `unknown-base` | K9 LOCKED; rejected alternative (`decisions.md:193`) |
| Restamp a base from the consumer's current tree | K13b: records their edits as "upstream base"; the next upstream change then overwrites them — the original incident, through the machinery built to prevent it |
| Warn-only on the S3 trigger | would be the third soft signal on the same failure |
| F2 (hasher normalization) | evidence attached to `stamper-hashes-worktree-not-artifact`; not this ticket |
| N4 (ownership-scoping vs `name: fusebase-flow`) | recorded separately; not in the N5 commit |
