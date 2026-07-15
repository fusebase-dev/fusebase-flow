# find-wasted-code — false-positive classes (with intentional bad examples)

This file is **excluded from the scan on purpose** (see `SCAN_EXCLUDE_EXACT` in
`hooks/local/find_wasted_code/constants.py`), so the intentionally broken example
paths and links below are never themselves reported. Each block shows what the
audit must NOT flag and why — these are the classes the golden fixtures lock.

## W1 — must NOT flag

- **Args to non-interpreters.** `touch hooks/shared/evil_extra.py` or
  `rm hooks/shared/gone.py` in a fenced block — the path is created/removed, not
  run. Only interpreter/`./`-prefixed execution counts.
- **cwd-ambiguous paths.** `cd hooks && python local/tool.py` — the base is not
  the repo root; the path resolves to Coverage, not a finding.
- **Placeholders.** `python hooks/local/${TOOL}.sh`, `bash hooks/local/<name>.sh`
  — a `$VAR`/`<…>`/`{…}` segment → Coverage.
- **Design-doc / historical mentions.** Anything under `docs/specs/`,
  `docs/backlog/`, `docs/release-notes/`, `/archive/`, `/problem-catalog/`, or
  `CHANGELOG.md` — these discuss hypothetical or retired paths and are excluded.
- **External executables.** `git`, `jq`, `codex` — cannot be verified from repo
  state; never `broken`.

## W2 — must NOT flag

- **External / scheme links.** `https://example.com/x.md`, `mailto:a@b.co`.
- **Line references on code.** `[src](../code.py#L20)` is valid GitHub navigation.
- **Valid duplicate-heading anchors.** two `## Setup` headings yield `setup` and
  `setup-1`; both anchors are valid.
- **Slug-ambiguous targets.** a link to a heading containing a code span, `&`
  entity, emphasis, raw HTML, or non-ASCII → `inconclusive`, never a false
  `broken` (e.g. `../README.md#health-check--recovery-v22`).
- **Directory links.** `[dir](../hooks/)` — directories count as existing.

## W3 — must NOT flag

- **Guarded/optional sources.** `[ -f .env ] && . .env`, or a source with a
  trailing `2>/dev/null` / `|| true`.
- **Dynamic source paths.** `source "$LIB_DIR/util.sh"`.
- **Ambiguous frontmatter fields.** a `related_workflows:` entry that is actually
  a repo-relative script path (`hooks/local/fusebase-flow-health-check.sh`) or a
  skill name — resolved across shapes; a miss is Coverage.

## W4 — must NOT flag

- **Existing handlers.** a settings hook wired to a handler that exists, even
  behind `"$CLAUDE_PROJECT_DIR"/…` quoting.
- **Non-path commands.** `npm run lint`, `node quality-check-apps.js` when the
  file exists.

## W5 — must NOT flag (baseline dismissals)

- **Diagnostic present.** `except Exception: logger.warning(...)` — the handler
  tells someone; not a silent swallow.
- **Explicit suppression.** `with contextlib.suppress(OSError): ...`.
- **Annotated intentional.** any swallow carrying
  `find-wasted-code: ignore W5 — <reason>` (e.g. best-effort cleanup, fail-closed
  wrappers).
- **Comments / heredocs.** a `2>/dev/null` inside a `#` comment or a `<<EOF`
  heredoc body does not inflate the shell baseline.
