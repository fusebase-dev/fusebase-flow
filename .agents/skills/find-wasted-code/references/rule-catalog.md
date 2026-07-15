# find-wasted-code — rule contract

The executable contract lives in `hooks/local/find_wasted_code/` and its golden
fixtures in `hooks/local/find_wasted_code/selftest.py` (run with `--selftest`).
This file is the human-readable companion. Concrete broken/OK examples for every
false-positive class live in `false-positive-examples.md` (that file is excluded
from the scan on purpose, so its intentional bad examples are never flagged).

## Confidence model

- **broken / confirmed** — provable from repository state: a referenced target is
  absent, an anchor no heading yields (on a slug-confident target), a settings
  hook wired to a missing handler.
- **candidate / inconclusive** — the signature holds but proof needs a human
  (e.g. a Markdown target with slug-ambiguous headings).
- **Coverage (unresolved)** — the reference could not be resolved to a provable
  claim (cwd-ambiguous path, placeholder, ambiguous frontmatter field). Listed so
  silence is auditable — never counted as a defect.

The whole tool is conservative by construction: when in doubt, Coverage, not a
finding. That is what keeps the audit from blocking or annoying the operator.

## Inventory + scope

- Inventory is `git ls-files` (tracked, exact-case, host-independent). Existence
  is checked against that exact set — never a case-insensitive filesystem probe —
  so a case-only mismatch is reported, not silently passed. In a git tree where
  `git ls-files` fails, the tool fails closed rather than walking the filesystem.
- **Existence universe** = every tracked path (mirrors, overlays, the report
  itself included) so a link *to* a mirror is never a false broken.
- **Scan set** excludes self-output (`docs/wasted-code/`), skill mirrors
  (`.claude/skills/`, `.agents/skills/` — the canonical `flow-skills/` is scanned
  instead), the overlay command copies, fixtures, historical records (CHANGELOG,
  release-notes, archives, problem-catalog), and design docs (`docs/specs/`,
  `docs/backlog/`) which discuss hypothetical paths.

## Rules

### W1 — dead-end tool/script references
North star: "dead-end tool calls." Confirms only an **execution-context** path:
an interpreter (`bash`/`sh`/`python`/`python3`/`py`, optional `sudo`/`env`/flags)
or `./` directly in front of a `.py`/`.sh` path, plus bare inline-code paths under
the runnable dirs (`hooks/`, `.claude/hooks/`). A known root-prefix var
(`$CLAUDE_PROJECT_DIR/`, `$ROOT/`, `$(git rev-parse --show-toplevel)/`, `./`) is
stripped first. A cwd-ambiguous path (e.g. after `cd somewhere &&`) or any
placeholder (`<…>`, `{…}`, `$VAR`, `*`) is Coverage, not a finding. Deliberately
does NOT flag paths that are arguments to `touch`/`rm`/`cat`/`ls` etc.
Known limitation: it cannot verify missing *external* executables or invalid
flags from repo state — those are out of scope, never `broken`.

### W2 — broken internal links
North star: "broken links." Resolves relative dests against the source document,
`/x` from repo root, `#x` against the current document; splits the raw dest on the
first literal `#` before percent-decoding. External schemes and placeholders are
skipped. A missing path is `broken` (directories count as existing). Anchor
validation runs only for Markdown targets — `code.py#L20` is a line ref, not a
heading. Slugs follow the GitHub algorithm (lowercase, strip markup keeping inner
text, decode entities, remove punctuation except `-`/`_`, spaces→`-`, dedupe
collisions with `-1`/`-2`; explicit HTML `id`/`name` anchors are case-sensitive).
When a target has a slug-ambiguous heading (code span, entity, emphasis, raw HTML,
non-ASCII), a non-matching anchor is `inconclusive`, never a false `broken`.

### W3 — missing helpers
North star: "missing helpers." Confirms a shell `source`/`.` of a **static,
root-explicit** script that is absent (a guarded/optional source such as
`[ -f x ] && . x`, or a `$VAR` path, is Coverage). Frontmatter
`related_workflows`/`hook_dependencies` entries are resolved against every known
shape (repo-relative, `workflows/<x>`, `flow-skills/<x>/SKILL.md`); because that
field is used inconsistently, a miss is Coverage, not a confirmed defect.

### W4 — footgun config
North star: "footgun configs." Parses `*settings*.json.example` (stdlib JSON,
duplicate-key aware) and confirms any hook `command` wired to a handler script
that does not exist — a hook that silently never fires (severity blocker).
Deduplicated against W1. Dead/undocumented policy keys are out of v1 (no stdlib
YAML, high false-positive) and noted as future work.

### W5 — silent push-through (baseline, not findings)
North star: "silently push through without telling anyone." Emitted as a measured
**baseline**, never confirmed findings: broad/trivial Python `except` handlers
(bare or `Exception`/`BaseException` with a `pass`/`…`/`return <const>`/`continue`
body and no diagnostic) via AST, and shell `2>/dev/null` / `|| true` /
`|| return 0` outside comments and heredocs. This repo intentionally fails
open/closed in many places, so generic swallow-detection cannot be low-FP; the
operator reviews the baseline and annotates intentional swallows with an inline
`find-wasted-code: ignore W5 — <reason>` directive. Precise
fail-open-on-a-trust-path detection is future work.

## Known limitations (by design — conservative)

This is a stdlib regex-based analyzer, not a full CommonMark/shell parser. Where a
construct cannot be parsed unambiguously, the tool routes to a false-negative or
Coverage, never a false `confirmed`. Documented residuals: a backtick code span
that spans multiple physical lines is masked only line-locally (a link inside such
a span could be read), and a `source` statement quoted across lines relies on a
heuristic quote/continuation tracker. These do not occur in the repo's own files
(the dogfooded run is false-positive-free); they are acceptable false-positive
risks only on adversarial input and are the reason `broken` findings are framed as
review candidates, not auto-fixes.

## Growth rule

A friction pattern that recurs across audits and matches no rule above → add a
rule module + its golden fixtures (known-bad fires, known-good silent) via
`skill-authoring`, keeping the confirmed-only-when-provable contract. Never widen
a signature in a way that trades a false negative for a false positive.
