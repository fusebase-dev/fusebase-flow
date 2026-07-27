```
change_tier: lightweight
ticket: rule-inventory-version-literal-noise
Problem:      rule-inventory.sh captured the version-bearing attestation verbatim, so every
              release bump left the rule-loss tripwire stale by exactly one `c` row — recurring
              benign noise that trains its reader to skim the diff (observed twice on v4.6.0:
              43c052d re-baselined, ef7793e's sync sweep forced a second re-baseline in 4323b23).
Change:       hooks/local/rule-inventory.sh — norm() lowercases first, then normalizes any
              v<major>.<minor>.<patch> literal to the token `vX.Y.Z` before a row is emitted
              (uppercase on purpose: nothing else in the output is, so it can never collide with
              real rule text). Semantics do not change across a bump, so the row must not either.
              hooks/tests/test-rule-inventory.sh — 5 new assertions (both arms + invariants).
              docs/specs/token-floor-remediation/rule-inventory-baseline.txt re-baselined.
Verified:     AC1 (green, real bump not a hand-edit): scratch tree + `git init`, VERSION 4.6.1 →
              99.98.97, SHIPPED hooks/local/sync-version-strings.sh run, attestation rewritten
              (old literal 0 lines, new literal 1 line) → inventory diff EMPTY. Control on the
              SAME fixture with the gsub line deleted → NON-EMPTY (`BOOT.attestation` v4.6.1 →
              v99.98.97), so the arm has teeth. Shipped as `version-bump-perturbs-source` +
              `version-bump-green`.
              AC2 (red): `reword-attestation` rewords the attestation sentence with no version
              touched ("Mode A on chat output" → "Mode A to whichever surface I like") → diff
              NON-EMPTY. Normalization did not blind the row.
              AC3: rows 170 → 170; ID, source-path and residency columns byte-identical;
              `sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/vX.Y.Z/g' <before> | diff - <after>` is EMPTY,
              i.e. the ONLY emitted-text delta repo-wide is the version-literal substitution
              (3 rows: BOOT.attestation + the historical provenance markers in IM.11 and PO.10).
              Suites: test-rule-inventory 30/30; full hooks/tests/run-tests.sh 625/625;
              test-sync-allowlist 8/8; preflight 0 errors.
Rollback:     git revert <SHA>  (instrument-only; no runtime/product surface)
Commit:       44ac492
Deploy:       not deployed — operator withheld publication (no push, no tag); FR-07 check: clean
              (staged set touches no protected path: hooks/local/**, hooks/tests/**, docs/**)
```
