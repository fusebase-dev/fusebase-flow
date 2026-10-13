# secret-pattern-escaped-glue

**Status:** open — not scheduled. **Filed:** 2026-10-12 (T133 audit L3). **Severity:** low-medium (secret-detection recall). **Surface:** `policies/secret-patterns.yml` (FR-07 protected).

## Observed

T133 (option E) matches a key that starts at a word boundary, or one glued to preceding text whose body passes the glued-key test (a digit and an uppercase letter; for AKIA keys a digit only). A plain `=`, quote, colon or space is already a boundary, so a key after it is always caught (`secret-patterns.yml:21,42`). A key preceded by an ESCAPE SEQUENCE whose last character is alphanumeric counts as glued instead: a JSON newline escape (backslash-n), a JSON unicode escape (backslash-u003d), or URL percent-encoding (`%3D`, `%22`). Glued keys that fail the body test are missed — the T133 audit measured ≈3% of glued AKIA / glpat keys overall; the escape-glued subset was not measured separately.

## Ask

Treat a preceding escape sequence (backslash-n / backslash-t / backslash-r, `%XX`, backslash-uXXXX) as a boundary in the lookbehind or alternation, keep the bounded-lookahead performance rule (≤0.2 s/MB adversarial, linear), and extend the release-gated `secret-patterns` matrix with escaped contexts. Measure recall/precision vs the T133 baseline before deciding.

## Constraints

FR-07 protected → single-use approval; strictest audit (security).
