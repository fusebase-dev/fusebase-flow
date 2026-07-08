# Roadmap — cli-0.25.16-vendor-refresh (one page)

Ticket: track FuseBase CLI 0.25.16 from vendored 0.25.9. Review verdict: 0 BREAK / 6 FRESHNESS / 5 COSMETIC — all authorized. Target v3.32.0.

```
P0 DONE   Adversarial compat review (Opus + Fable, Codex-vetted)  -> correction list FR-A..FR-E + CO-1..CO-5
P1        PO planning (THIS)   spec DRAFT + decisions LOCKED + tasks + gate + implement handoff
   |
   v            [review gate: adversarial Codex review of these planning docs]
P2        AI-Developer implement (handoff 2026-07-07-cli-0.25.16-vendor-refresh-implement.md)
   T1 FR-A  ATOMIC re-vendor: 18 files x2 mirrors + del 2x2 + add 1x2 + re-stamp (132->130)   [1 commit]
   T2 FR-B/C/D  4 doc corrections (C2 = atomic doc-pair in BOTH docs)                          [1 commit]
   T3 FR-E  5 live strings 0.25.9->0.25.16 + dated 0.25.16 line   REQUIRES T1                  [1 commit]
   T4 CO-1..CO-5  cosmetics (filenames KEPT; CO-1/CO-2 REQUIRE T1)                             [1 commit]
   T5 docs/changes guidance-shift note (auth-flow + SDK); NO problem-catalog entry             [1 commit]
   |
   v            [verification gate G1-G13: preflight 0/0 · byte-identity · mirror parity ·
                 manifest 130 · health self-run HEALTHY/0-stale · run-tests N/N 0 FAIL ·
                 sync-allowlist 5/5 · scope containment — implementer HALTS here]
P3        Post-gate adversarial review (Codex) of the implemented diff
   |
   v            [operator go/no-go]
P4 DEPLOY Operator-executed: DP.1 approval artifact + DP.6 magic phrase -> FR-07
          write-bootstrap-approval -> VERSION 3.32.0 + sync-version-strings.sh +
          plugin.json/marketplace.json parity -> preflight 0/0 -> single FR-14 release
          commit -> tag v3.32.0 -> release notes (release-deploy-reporting)
```

## Dependency edges (hard)

| Edge | Why |
|---|---|
| FR-A → re-stamp (inside T1, same commit) | Partial FR-A is the only way to create a break (manifest/tree/mirror inconsistency) |
| T1 → T3 (FR-E) | Bumping strings first falsely claims 0.25.16 over a 0.25.9 snapshot |
| T1 → T4 (CO-1, CO-2) | Relabels assert "unchanged through 0.25.16" — only true once the snapshot IS 0.25.16 |
| Gate → P3 review → P4 | FR-05 stop-at-gate; deploy only after adversarial review + operator confirm |
| Version bump LAST (P4 only) | Touches FR-07-protected FLOW_RULES.md banner → write-bootstrap-approval flow; role boundary (Deploy phase, not AI Developer) |

Order-flexible: T2 and T5 have no dependency on T1 but stay in the linear chain (one session, one review).

## Slice inventory

| Slice | Class | Files touched | Owner |
|---|---|---|---|
| FR-A | FRESHNESS, BREAK-if-partial | 42 vendored path changes (36 modified + 4 deleted + 2 added) + audit/cli-vendor-manifest.json | AI Developer (T1) |
| FR-B/C/D | FRESHNESS docs | fusebase-cli-edition.md, CLI-CONFLICT-ANALYSIS.md | AI Developer (T2) |
| FR-E | FRESHNESS strings (tail of FR-A) | README, compatibility.md, cli-edition, audit/README | AI Developer (T3) |
| CO-1..5 | COSMETIC | stamp header, 3 test files + merge-py labels, ARCHITECTURE.md, .gitattributes | AI Developer (T4) |
| Changes note | docs | docs/changes/2026-07-07-cli-0.25.16-guidance-shift.md | AI Developer (T5) |
| VERSION 3.32.0 | release | VERSION, FLOW_RULES/AGENTS/CLAUDE banners, plugin+marketplace.json | Operator @ Deploy |

Full details: `spec.md` (scope + 3 mandatory evaluations) · `decisions.md` (D1–D12, LOCKED) · `tasks.md` (commands) · `verification-gate.md` (G1–G13) · handoff `docs/tmp/handoff/2026-07-07-cli-0.25.16-vendor-refresh-implement.md`.
