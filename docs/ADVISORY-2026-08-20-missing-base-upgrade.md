# ADVISORY — do not run `upgrade.sh` without a base manifest

**Issued:** 2026-08-20 · **Affects:** v4.11.0, v4.12.0 (and any earlier release taken from this state)
**Severity:** HIGH · **Status:** advisory issued ahead of the fix — read this before upgrading

## Who is affected

You are affected **only if all three hold**:

1. `audit/managed-content-manifest.json` is **missing** from your install, and
2. the engine that would execute (`hooks/local/upgrade.sh` in *your* tree) does not successfully
   synthesize one — true for every install last upgraded by a pre-4.11.0 engine, and
3. at least one pre-existing managed file in your tree differs from what upstream ships.

Typically this is an install whose last upgrade ran a **pre-4.7.0** engine, which never delivered a
base manifest.

**If `audit/managed-content-manifest.json` exists and verifies, you are not in this group.** Check:

```bash
ls audit/managed-content-manifest.json && bash hooks/local/verify-managed-content-manifest.sh
```

## What goes wrong

With no base manifest, the upgrade cannot tell your edits from upstream's changes, so it preserves
the ambiguous files — including `hooks/local/upgrade.sh` itself. New files still arrive. **The result
is a half-apply: the fix lands without the code that calls it, and `VERSION` advances anyway.**

The run then writes upstream's current manifest in as your base. On the next run, your (unchanged,
stale) files differ from that base, so the upgrade reports them as **your own edits** and preserves
them permanently. Across a release boundary the same paths become conflicts and the run **aborts**.

The tree is then frozen under the ordinary upgrade path, and the report presents the freeze as your
choice.

## What to do

### State A — base missing, you have NOT yet run `upgrade.sh`

**Do not run `hooks/local/upgrade.sh`.**

Use the bootstrap path, which stages the new engine first — but **only** while your `VERSION` still
truthfully identifies the baseline you actually have installed:

```bash
git clone --depth 1 --branch <target-tag> <repo> .fusebase-flow-source
bash .fusebase-flow-source/hooks/local/bootstrap-upgrade.sh -- --auto-yes
```

### State B — base missing, and you ALREADY ran `upgrade.sh`

Your `VERSION` has advanced while your content did not. **Stop, and do not attempt a self-repair.**

- **Do not** re-run `upgrade.sh`.
- **Do not** delete, copy, or re-stamp `audit/managed-content-manifest.json`. Deleting it and
  bootstrapping does **not** recover you — synthesis would key off the now-advanced `VERSION` and
  reconstruct the same wrong base.
- **Do not** run `bootstrap-upgrade.sh` blindly. It trusts an existing base without validating it,
  and hands the wrong one straight through.

**Preserve everything**, then wait for the recovery path shipping in the next release:

- `*.pre-upgrade-*` backups
- your `.fusebase-flow-source/` clone
- `VERSION` backups
- upgrade output/logs

This state is frozen under the ordinary upgrade path. It is **not** unrecoverable — backups and a
purpose-built repair can restore it, which is precisely what the next release will provide.

## Why the fix cannot simply ship

The repair belongs in `hooks/local/upgrade.sh`, and that file is exactly the one an affected install
never receives. A fix placed in the engine cannot rescue a consumer whose engine will not be
replaced. That is why this advisory exists as a document rather than as a patch note — and why any
future release carrying an engine-side upgrade fix must repeat it.

## Credit

Reported by the WorkHub Managed consumer with a three-run sandbox reproduction across two release
boundaries. Their forensic proof that the base was *copied* rather than derived — the poisoned base
hashing byte-identical to this project's own published v4.11.0 fingerprint row — is what made the
mechanism unambiguous.
