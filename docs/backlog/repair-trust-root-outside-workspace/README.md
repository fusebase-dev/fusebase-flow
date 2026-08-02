# repair-trust-root-outside-workspace

**Status:** parked
**Filed:** 2026-08-02
**Source:** decision M17 (`docs/specs/upgrade-source-integrity-and-observability/decisions.md`) — the option (b) it rejected for that ticket, filed so the rejection is a deferral and not a silent drop.
**Severity:** medium — a bounded, disclosed weakness, not a live fail-open. `--repair-managed` is honest about what it proves today.

## The case this covers

`--repair-managed` binds the layer set it must confirm from the **verified source tree** (M16). That anchor is outside the **repaired tree's** control — nothing the consumer root can delete shrinks the bound set — but it is **not** outside the *workspace's* control:

- `.fusebase-flow-source` is reused when present (`hooks/local/bootstrap-upgrade.sh`, Step 1).
- Ref resolution prefers the caller-controlled local ref, then `origin/<ref>`, then `HEAD` (`hooks/local/lib/materialize-managed-source.sh`).
- The tree is verified against **its own** shipped manifest with **its own** verifier.

So a party who can commit into that staging repository and move its ref can author a self-consistent tree that declares **fewer layers**, and obtain `FF_SOURCE_STATE=VERIFIED` over it. `git archive <oid>` defeats worktree tampering; it is not upstream provenance.

M17 locks the same-principal threat model: that party is, by assumption, the same principal who could edit `bootstrap-upgrade.sh` itself, so the attack buys nothing. **This ticket is the case where that assumption does not hold** — a root-owned or read-only hop over a user-writable staging directory, a group-writable/CI/shared runner, a container bind-mount, any co-tenant workspace.

## What closing it requires (both need a trust root Flow does not have today)

| Option | Shape | Cost |
|---|---|---|
| Remote fetch at repair time | Repair ignores the staging directory and materializes the version's tree from `--repo` / a tag over the network, per run | Network dependency on a path that exists to fix a broken install; offline repair regresses; still trusts TLS + the remote, not a signature |
| Signature verification | The release ships a detached signature over the manifest (or over the tree); repair verifies it before reading coverage | Flow has **no signing seam** (K3) — key custody, rotation, distribution to consumers, and a verification path that itself cannot be replaced by the tree it judges |

Either is a **new capability with its own spec, decisions and adversarial review**. Neither is a patch on the upgrade ticket, which is why M17 refused to take it inline.

## Explicitly NOT in scope

- Re-opening M16. The upstream-declared bound set is correct and stays; this ticket strengthens what "verified source" means, it does not move membership back to the consumer tree.
- Any claim that identity is enforced. K3 stands: the agent and the operator write as one OS principal, `approved_by` is audit metadata, Flow verifies schema/expiry/binding and never identity. A repair guarantee stricter than the approval gate that authorizes it would be worse than the accurate weaker one.
- Closing the pre-boundary TOCTOU window by replacing the operator's staging directory — separately rejected in M13/M17 and disclosed in `docs/release-notes/v4.7.0.md` § Known limitation (pre-boundary route).

## Where the current, honest boundary is written down

- `docs/specs/upgrade-source-integrity-and-observability/decisions.md` M16 (anchor + its threat-model line) and M17 (the decision itself)
- `docs/specs/approval-binding-and-upgrade-classification/decisions.md` K3 (same-principal trust model; no signing seam)
- `docs/release-notes/v4.7.0.md` § Known limitation (pre-boundary route) and § What a plain `--source` directory proves
- `docs/backlog/provenance-and-single-seam-guarantees/` L1 — the same class stated cross-product: a guarantee pinned to an identity the system cannot distinguish

## First move if this is picked up

Enumerate every reader of `$SOURCE_TREE` and every path by which a tree becomes `VERIFIED` **before** choosing an option — per L2 of `provenance-and-single-seam-guarantees`, a guarantee pinned to one seam without a carrier census is how the last three rounds of this ticket went wrong.
