# WP 2 grammar spec: the four documents and their parser

**Status:** DRAFT, revision 3. Revision 3: four post-cap changes after review round 2 of 2; not re-reviewed; each is a mandatory check in the wave-2 code review of flow_docs.py / the WP 7c validator / WP 8 flags (named fixture cases). Round 2 (`astra-wp2-grammar-r2.md`) said REWORK with majors R2-01 to R2-04; the "Revision 3 (post-cap, integrator) change log" at the end maps each one to the sections it changed. Revision 2 is kept as `wp2-grammar-spec.r2.md`. Round 1 (`astra-wp2-grammar-r1.md`) said FREEZE WITH CHANGES; its findings R1-01 to R1-12 are folded, and the "Revision 2 change log" maps them. Revision 1 is kept as `wp2-grammar-spec.r1.md`. No code is written against this spec until the frozen copy is committed (plan-wp2.md, task WP2-c). **Date:** 2026-10-16. **Work package:** WP 2, backlog slug `four-document-model`. **Flow tree read:** main at `4daa771c` (v5.11 plus T165, T166).

**Authority, in order.** (1) The owner's decisions: `owner-decisions-2026-10-16.md` (a), `owner-decisions-2026-10-16b.md` (b), `owner-decisions-2026-10-16c.md` (c, which makes the "owner decision" labels of `runner-conventions-wp7c-2026-10-16.md` binding). Where they differ, the later one wins. (2) The accepted reply `reply-to-owner-2026-10-16.md` (RPL). (3) File 1, the design (D), over the handoff (H), except D section 8. (4) The team analyses. (5) The tree.

**Citation keys.** D = `flow-minimal-core-2026-10-15.md`; H = `flow-handoff-2026-10-15-minimal-core.md`; LF = `flow-handoff-2026-10-15-lighter-flow.md`; RC = `runner-conventions-wp7c-2026-10-16.md`; RB = `rebuild-review-B-2026-10-15.md`; RPL = the reply; OWa/OWb/OWc = the three owner files; dec-1-4, dec-5-8, dec-9-11 = the team analyses. Tree paths are relative to the Flow repository root.

---

## 0. In one minute

- A project keeps **four documents** in one folder, `docs/flow/`: `backlog.md`, `phases.md`, one `evidence/<phase>.md` per phase, and `ledger.md`. Flow ships **four templates** for them under `templates/`. They replace all 25 of today's templates (section 9).
- **Ids:** items `B<n>`, owner answers `A<n>`, phases `P<n>`, slices `P<n>-S<k>`, tasks `T<n>` with an optional one-letter suffix (`T12a`). Task ids are unique across `phases.md`.
- **One field per line** in the backlog, so a diff can say which field of which item changed. D:99 needs that: "a change to an item's `risk` or `criterion` line inside its own slice window is a flag".
- **Nothing derivable is written by hand.** Task rows carry no status and no SHA. `committed` comes from the DONE check, `done` from the validator (D:21, H:78).
- **Evidence rows follow the owner's runner conventions** (OWc:13-17): a capture's path, sha256 and size, the run-log path, and for unit rows a `<file>::<test name>` id against a TAP log. Flow defines no capture folder.
- **The flags file keeps T166's TSV** (`flow-flags v1`, `hooks/local/lib/checks.py:31, 429-445`). This spec adds a `slice` mode, stable ids, and the ruling and note vocabularies.
- **One parser**, `hooks/local/lib/flow_docs.py`, stdlib only and safe under `python3 -S`. It never raises on bad content and never echoes document content: a problem carries only a fixed code, a line number, a fixed field name or a well-formed id. The slicer, the DONE check, the validator, the checks and `commit-msg` all call it (section 10).

---

## 1. The four documents

| Document | Path in a project | Purpose | Written by | Read by |
|---|---|---|---|---|
| Backlog | `docs/flow/backlog.md` | Feedback items (id, source, one criterion or test id, risk tag, status, inputs, cited answers) and the owner's answers | planner | slicer (WP 9), validator (WP 7c), checks (WP 8), plan step |
| Phases | `docs/flow/phases.md` | Phases, slices and tasks: task id, the item it serves, one line of what it does, globs, estimate in minutes and files; the reference project | planner | slicer, DONE check (WP 7b), checks, validator, `commit-msg` (WP 10), gate (WP 7d) |
| Evidence | `docs/flow/evidence/P<n>.md`, one per phase | One PASS or FAIL row per criterion of the phase, with its capture and run log | builder (claims), planner | validator, gate |
| Ledger | `docs/flow/ledger.md` | Pointer to the status line, the next step, the current handoff, and one-line records (verdicts, reviews, skeptics, alerts, closes, migration) | planner | gate (round counts), successor sessions, phase 7 counts, WP 12 report |

**Why one folder.** The DONE check, the validator and `commit-msg` need fixed paths. A fixed folder also makes "the four documents are never trivial-tier paths" (H:78, H:86) one prefix test. `docs/flow/` does not exist in the Flow repository today (checked 2026-10-16), and it is not one of the CLI-owned `docs/` paths H:88 lists (`docs/north-star.md`, `docs/audience.md`, `docs/product.md`, `docs/business-logic.md`). `docs/flow/` is the folder: the owner answered B5 yes on 2026-10-16 (`owner-decisions-2026-10-16d.md`).

**No `docs/flow/phases.md` means legacy mode.** WP 10's `commit-msg` keeps 5.11 behaviour when that file is absent at HEAD (RPL:93). The Flow repository itself stays in legacy mode.

**Templates.** Flow ships `templates/backlog.md`, `templates/phases.md`, `templates/evidence.md`, `templates/ledger.md` (RPL:275 counts 4 templates in the 54). The plan step copies them into `docs/flow/`. A template is a valid empty document: it parses with zero problems. Its one example lives inside an HTML comment that starts at column 0, which the parser ignores (section 2). No template carries a version string, because `hooks/local/sync-version-strings.sh:130-138` rewrites version tokens under `templates/`.

---

## 2. Rules shared by all four documents

| Rule | Exact form | Why |
|---|---|---|
| Encoding | UTF-8. A leading BOM is accepted and dropped. CRLF is read as LF. Over 1,048,576 bytes is a `size` problem and nothing is parsed | Same cap as `MAX_BLOB_BYTES` in `checks.py:22` |
| Comments | A comment starts on a line whose first characters are `<!--`, outside the ledger's `## Next` and `## Handoff` sections, and ends at the first `-->`, on that line or a later one. Text after that `-->` on the same line is a `stray` problem. Everything inside is ignored. `<!--` anywhere else is literal text: inside a field value, a table cell, an answer body (its lines start with `>`), the ledger's `## Next` and `## Handoff` sections, or a record's text. An unclosed comment is a `comment` problem | Lets a template carry one example without creating an item, and never cuts text out of an answer, a handoff or a value (R1-08) |
| Blank lines | Ignored everywhere except inside an answer body and the ledger's `## Handoff` section | |
| Empty cell or value | `-`, `—`, or nothing (an empty cell, or nothing after `<key>:`). All three read as "none". A required field that reads as none is `field-missing`. One exception: `- inputs:` takes its value from the indented entries below it, and reads as none only when there are none | 5.11 templates use `—`; agents type `-` or leave it blank |
| Field line | `- <key>: <value>` at column 0. Keys are lowercase with `_`. One key per line. A key may appear once per block | Lets a diff name the field that changed (D:99). A repeated key is a `field-repeat` problem |
| Strictness | An unknown key is a `field` problem. A non-blank line in an item or phase block that is not a field line is a `stray` problem. Free prose is allowed only in declared payload fields: answer bodies, task `Does` cells, evidence `Note` cells, the ledger's `## Next` and `## Handoff`, and the text after `--` in a record | Free prose in an item would need a named reader (H:78), and it has none. This does not stop the documents from growing: RB 3.1 to 3.3 stay open for this release (section 13) |
| Markdown table header | The header row's cells, after `cells()` trims them, must equal the column names in order. Spacing around the pipes does not matter. The separator row is T144's `SEPARATOR_ROW` | A harmless spacing change is not a problem. Applies to Markdown tables only; the tab-separated files of sections 7 and 8 keep their exact column lines |
| Date | `YYYY-MM-DD` | |
| Timestamp | `YYYY-MM-DDTHH:MMZ` in the ledger; `YYYY-MM-DDTHH:MM:SSZ` in state files | UTC only |
| Repo path | Relative to the repository root, `/` separators, no leading `/`, no `..`, no `\`, no drive letter | Same shape the tier reader accepts (`hooks/local/lib/validator_tier.py:82-90`) |
| Glob | The FR-13 tier dialect: rules of `pattern_problem` (`validator_tier.py:73-93`: repo-relative, `**` only as a whole segment, no `\ [ ] { }`, a directory written `dir/**`) and the matcher `_glob_to_regex` (`hooks/shared/module_size.py:35-56`), always with `fullmatch` (`validator_tier.py:62-63`) | Over-matching is fail-open for both the DONE check and flag 1. That is why the tier reader refuses `path_policy`'s fnmatch matcher (`validator_tier.py:62`). The `--retro` tool's fnmatch + `**` matcher (`checks.py:52-68`) is the calibration tool's, not the core's |

### Id grammar

| Id | Pattern (full match) | Unique within | Example | Notes |
|---|---|---|---|---|
| Item | `B[1-9][0-9]*` | `backlog.md` | `B12` | Also the criterion id: one criterion per item (section 3) |
| Answer | `A[1-9][0-9]*` | `backlog.md` | `A3` | |
| Phase | `P[1-9][0-9]*` | `phases.md` | `P7` | Also the evidence file name |
| Slice | `P[1-9][0-9]*-S[1-9][0-9]*` | `phases.md` | `P7-S3` | The phase prefix equals the enclosing phase. Used as `<slice>` in every `state/` file name |
| Task | `T[1-9][0-9]*[a-z]?` | `phases.md`, all phases, table rows and `housekeeping` fields together | `T301`, `T301a` | `T301` and `T301a` are different ids. A suffix lets a planner split a task without renumbering. A housekeeping id is outside every table but still takes part in this uniqueness |
| Task token in a commit subject | `\bT\d+[a-z]?\b` | | | The scanning regex of `hooks/local/lib/checks_git.py:28`. A token that is not a valid task id (for example `T0`, `T012`) cannot resolve. Retro flags files keep such tokens as they are (section 7) |
| Flag, slice mode | `P[1-9][0-9]*-S[1-9][0-9]*-(F[1-4]\|R\|D\|E)-[0-9a-f]{8}` | the project (the slice prefix names the flags file) | `P7-S3-F1-3fa9c2d0` | Section 7. The slice prefix equals the file's slice |
| Flag, retro mode | `F[1-4]-[0-9a-f]{7}-[1-9][0-9]*` | one flags file | `F2-29f4979-1` | As `checks.py:443` writes it. Unchanged |
| Dispatch | `P[1-9][0-9]*-S[1-9][0-9]*-(V\|R)[1-9][0-9]*` | `ledger.md` | `P7-S3-V2` | Section 6. `V` is a verdict dispatch, `R` a review dispatch. The slice prefix equals the record's scope |

**A change WP 10 must make.** Today's `commit-msg` matches `\bT[0-9]+\b` (`hooks/git/commit-msg:41`). That regex does not match `T12a`, because there is no word boundary between `2` and `a`. The new `commit-msg` must use the task-token regex above, which `flow_docs.py` exports. Legacy mode keeps the 5.11 regex unchanged.

---

## 3. `docs/flow/backlog.md`

### Grammar

```
# Backlog                                   <- line 1 (after comments and blank lines), exactly

## B<n> <title>                             <- one block per item, in any order
- source: <slice id> | <flag id> | owner:<YYYY-MM-DD>
- criterion: <one line>                     <- exactly one of criterion / test
- test: <repo path>::<test name>
- risk: none | auth | data | prod
- status: open | done | dropped
- inputs:                                   <- optional; then one entry per line, indented two spaces
  - <entry>
- answers: <A id>, <A id>                   <- optional
- shares: <B id>                            <- optional; the root of this item's share group

## Answers                                  <- exactly once, after every item

### A<n> <question, one line>
- answered: <YYYY-MM-DD> | pending
> <verbatim answer text, one or more lines starting with "> ">
```

A title is the rest of the heading line after the id and one space. It must be non-empty.

### Item fields

| Key | Required | Values | Read by |
|---|---|---|---|
| `source` | yes | a slice id (feedback raised during that slice), a flag id (an upheld flag became an item), or `owner:<date>`. Slice ids and flag ids are told apart by full match (section 2); a slice-mode flag id's prefix names its flags file | plan step; `checks --precision` "acted-on share", which counts a flag id cited by a backlog item (dec-5-8 §6.3 point 5) |
| `criterion` | one of the two | one observable sentence | slicer; checks flag 2 (a dependency named in it counts as requested, OWc:15, RC §5; matched as in "Dependency names" below); validator item-edit flag |
| `test` | one of the two | `<repo path>::<test name>`, split at the first `::`. A `\|` inside the name is written `\|` | slicer; validator (the unit row's `Ref` must equal it); item-edit flag |
| `risk` | yes | `none`, `auth`, `data`, `prod` | validator (the tag may raise the minimum evidence class, never lower it, D:26); gate (rubric hold applies when risk is not `none`, D:83); verify step (loads the security checklist); slicer; item-edit flag |
| `status` | yes | `open`, `done`, `dropped` | plan step; WP 12 migration report |
| `inputs` | no | entries, below | slicer (prints them, `BLOCKED-AT-input`); checks flag 2 (`dep:`, `env:`, `cfg:` entries) |
| `answers` | no | answer ids, comma-separated; each must exist under `## Answers` | slicer prints each cited answer in full (H:85) |
| `shares` | no | one item id: the root of this item's share group. The root is another item that has no `shares` line itself, so there are no chains | validator: see "Share groups" below (D:99 "unless the criterion names a shared capture") |

**One criterion per item.** D:21 and H:78 say "acceptance criterion or test id", singular. The criterion id is the item id, so "every criterion id in the phase has exactly one row" (D:99) is "every item served by the phase has exactly one evidence row". An item that needs two criteria is two items. This is a review question (section 13).

**Status is only what no script derives.** `planned` is not a status: an item is planned when a task in `phases.md` cites it. `done` is set by the planner in the `ship:` commit, after a PASS verdict covering the item's row. `dropped` needs no reason field: the commit message carries it.

**Why one field per line.** A change to `risk:` or `criterion:` (or `test:`) inside the item's slice window must be a computed flag (D:99; RB 1.10). `changed_fields(old, new)` (section 10) compares the parsed fields and names the item and the field. A table row could be compared cell by cell too; one field per line is chosen because the line diff a reviewer sees then shows the field by name, and each field has its own line number.

**Share groups.** An item with `shares: B12` is a member of B12's group; B12 is its root and a member too. So B13, B14 and B15 can each declare `shares: B12`, and all four are one group. `check_refs` gives `ref` when `shares` names a missing item, the item itself, or an item that has its own `shares` line. The validator applies the rule to the whole digest group: for each digest cited by two or more `smoke` or `live` rows of the phase, every item citing it must belong to one share group. If not, every row citing that digest fails.

### Input entries

Each entry is one line under `- inputs:`, indented two spaces, starting with `- `.

| Entry | Form | Kind | What the slicer does (WP 9) |
|---|---|---|---|
| A file | `<repo path>` | `path` | Prints the path and its size |
| A section or row of a file | `<repo path>#<anchor>` | `anchor` | Prints the anchored heading section, or the table row whose first cell equals the anchor, inline under the slicer's byte cap (RPL:24, dec-1-4 §2) |
| A web page | `http://…` or `https://…` | `url` | Prints the reference; the kind `url` goes through the input-kind map |
| Anything a tool reads | `<kind>:<reference>`, kind matching `[a-z][a-z0-9-]{1,30}` and not reserved | `tool` | Looks up the kind in the `input_kinds` map of `policies/agent-tools.yml` (Flow declares the key, the project names the tools, RPL:24; shape in section 12). A kind whose tool is not in the agent's profile, or a kind the map does not list, prints `BLOCKED-AT-input` |
| A requested dependency | `dep:<package name>` or `dep:@<scope>/*` | `name` | Prints it under "requested"; no tool lookup. Any other form is a `value` problem |
| A requested environment variable | `env:<NAME>` | `name` | same |
| A requested config key | `cfg:<key path>` | `name` | same |

The reserved kinds `dep`, `env`, `cfg` are the owner's "place for the item to name dependencies" (OWc:15). Flag 2 reads them: a new runtime dependency, environment variable or config key is **named** when an item served by the commit's task lists it here. An environment variable or config key matches its entry exactly. A dependency is also named by the item's `criterion` line (RC §5: "the item's acceptance criterion or inputs name the package"). That fills the TSV column `named` with `yes` or `no` (section 7). Flow names no tool in this grammar: tool kinds are the project's words (H:62).

**Dependency names.** One matcher, `dep_named` (section 10), serves `dep:` entries and the criterion line alike.

| Part | Rule |
|---|---|
| Package name | `(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*`, the npm form |
| Pattern | an exact package name, or the scoped wildcard `@<scope>/*` that the owner used for AC27 (RC §5, OWc:19) |
| Exact match | the package equals the pattern, character for character |
| Wildcard match | the package starts with `@<scope>/` and the rest is one name with no `/`. `@dnd-kit/*` names `@dnd-kit/core` and `@dnd-kit/sortable`; it does not name `@dnd-kit-x/core` |
| Not supported | substring or prefix matching (`react` does not name `react-dom`), a bare scope (`@dnd-kit` names nothing), any other `*` (`react-*`, `@*/core`) |
| Patterns from `dep:` | each entry's value; it must be a package name or a scoped wildcard |
| Patterns from `criterion` | split the line at every character outside `[A-Za-z0-9@/._~*-]`; drop one trailing `.` from each piece (a sentence end); keep each piece that is a package name or a scoped wildcard. Backticks and commas therefore separate names. Ordinary words become patterns too; one matters only if a package with exactly that name is added. Matching is case-sensitive, as npm names are lowercase |

So a criterion like AC27, which names `react-router-dom` and `@dnd-kit/*` as exact pins (RC §5), names `react-router-dom`, `@dnd-kit/core`, `@dnd-kit/sortable` and `@dnd-kit/utilities`: the four packages T54 added.

### Answers

| Part | Rule | Read by |
|---|---|---|
| `### A<n> <question>` | Under `## Answers` only | slicer prints it with the body |
| `- answered:` | a date, or `pending` | slicer prints it. A cited `pending` answer is visible in the builder's slice; the role card says stop and ask (RPL:33) |
| Body | One or more lines starting with `> `, blank `>` lines allowed. The text is the line after its `> ` (or the empty line for `>`), kept byte for byte. Nothing inside it is a comment, so `<!-- component-slot -->` stays (section 2) | slicer prints the body in full (H:85) |

---

## 4. `docs/flow/phases.md`

### Grammar

```
# Phases                                    <- line 1, exactly
- reference: <label> | none                 <- file-level, required
- reference_manifest: <repo path> | none    <- file-level, required

## P<n> <title>
- base: <7-40 lowercase hex> | pending      <- required
- housekeeping: <T id>                      <- optional, at most one per phase
- reference: <label> | none                 <- optional override
- reference_manifest: <repo path> | none    <- optional override

### P<n>-S<k> <title>
- after: <slice id>, <slice id>             <- optional
| Task | Item | Does | Globs | Estimate |    <- exactly one table per slice; these header cells, trimmed, in this order
|---|---|---|---|---|
| T<n> | B<n> | <one line> | `<glob>`, `<glob>` | <minutes>m <files>f |
```

Phases appear in file order. Slices appear under their phase. Every task row belongs to exactly one slice. Cells are split with T144's `cells()` (`hooks/local/lib/gate_contract_check.py:47-51`), so `\|` is a literal pipe. The separator row is recognised with T144's `SEPARATOR_ROW` (`gate_contract_check.py:20`).

### Fields and cells

| Field or cell | Required | Values | Read by |
|---|---|---|---|
| `reference` | file: yes; phase: no | free label (a project name, a blueprint, a path) or `none` | slicer prints it; rubric R(b) uses it through the reviewer brief (D:83, D:87) |
| `reference_manifest` | file: yes; phase: no | a repo path to the reference project's `package.json`, or `none` | checks flag 2 "a dependency the reference project's manifest does not carry" (H:84). `none` makes that arm print "not run", as `--retro` does today (`checks.py:462`) |
| `base` | yes | the phase's base commit, or `pending` before the phase starts | DONE check (H:83: "from the phase's base SHA"); checks (slice window); validator (item-edit window); gate |
| `housekeeping` | no | a task id that appears in no table and in no other phase's `housekeeping` field (task-id uniqueness, section 2) | `commit-msg` resolves it; the DONE check and flags 1 and 4 skip it. Its globs are the trivial-tier lists of `policies/evidence-classes.yml` at HEAD (RPL:34 "a standing housekeeping task per phase"; dec-9-11 §2.3). **What it enforces:** a commit citing the housekeeping id must be trivial-tier (every staged path in the tier lists), because the task serves no item and rule 1 needs an item before code. The reverse is not enforced: a trivial-tier commit may cite any resolving id, since the DONE check ignores trivial-tier commits and citing a real task gains nothing |
| `after` | no | slice ids that must reach DONE first | build step dispatch order (WP 6). Carries T145's cross-slice order (carry-511 T145). `check_refs` checks that each id exists; WP 6 rejects a self-dependency or a cycle before dispatch |
| `Task` | yes | a task id, unique across the file | everyone |
| `Item` | yes | an item id that exists in `backlog.md` | slicer; validator (the phase's criteria are the items its tasks serve); checks flag 2 (`named`) |
| `Does` | yes | one line, non-empty | slicer |
| `Globs` | yes | one or more backticked globs, separated by `, ` | DONE check; flag 1; slicer prints breadth and matched-file counts (RB 1.11) |
| `Estimate` | yes | `<minutes>m <files>f`, minutes 1-9999, files 0-999 | flag 3 (D:81); slicer prints it. Test paths are budgeted separately by flag 3 from the tier's `test_paths`, not by a second estimate |

**No status, no SHA, no "depends on" per task.** `committed` and `done` are derived (D:21, H:78). 5.11's `SHA` and `Status` columns (`templates/tasks.md:12-18`) are exactly the hand-written facts the rebuild removes. Order inside a slice is row order.

**Closed phases stay.** Every phase stays in `phases.md` with all its rows. Reason: `commit-msg` resolves a task id in `phases.md` at HEAD, and judges a revert on its inner subject (RPL:34). If a closed phase were collapsed, a revert of one of its commits could not resolve. Agents do not read this file; they read slices. RB 3.3's collapse rule is a review question (section 13).

---

## 5. `docs/flow/evidence/P<n>.md`

### Grammar

```
# Evidence                                  <- line 1, exactly; the phase id is the file name

| Criterion | Status | Class | Ref | Capture | sha256 | Bytes | Log | SHA | Env | Note |
|---|---|---|---|---|---|---|---|---|---|---|
| B12 | PASS | live | S5 | docs/tmp/run-a3f9c1/S5/login.json | <64 hex> | 1834 | docs/tmp/run-a3f9c1/README.md | - | dev | - |
| B14 | PASS | unit | packages/core/test/auth.test.ts::magic link expires | - | - | - | test-results/run-7be210/unit.tap | 1a2b3c4 | - | - |
```

One table; its header cells, trimmed, are these eleven names in this order. One row per criterion. A second row for the same criterion is a `duplicate` problem.

### What a row needs depends on its status

| Status | Required cells | Other cells |
|---|---|---|
| `PASS` | every cell the row's class needs in the table below | `-` where the table says `-` |
| `FAIL` | `Criterion`, `Status`, `Class`, and a `Note` that says why (not `-`) | May be `-` when that evidence does not exist: the criterion could not run, no capture was made, or the run stopped before its log existed. A cell that is filled must still have its form, and the validator checks it as for PASS |

A runner's `BLOCKED-AT-<reason>`, or a run that hit its deadline (exit 124), is a FAIL row whose `Note` says so (RC §2; `templates/gate-report.md:133-137`). Missing evidence never makes a row PASS. A PASS row with a cell missing is `field-missing`; a FAIL row whose `Note` is `-` is `field-missing` with ident `Note`.

### Cells

| Cell | `unit` row | `smoke` or `live` row | Read by (WP 7c unless noted) |
|---|---|---|---|
| `Criterion` | item id | item id | every criterion of the phase needs exactly one row |
| `Status` | `PASS` or `FAIL` | same | the builder's claim. Only these two words, as T144 set them (`templates/gate-report.md:137`). FLAKY is the validator's output, reported as FAIL (D:99), never a row status |
| `Class` | `unit` | `smoke` or `live` | compared with the minimum class the validator derives from touched paths and the risk tag. Order: `unit` < `smoke` < `live` |
| `Ref` | the test id `<repo path>::<test name>`. If the item has `test:`, it must be equal | the runner's row id in the run log's `Row` column (RC §1: `\| Time (UTC) \| Row \| Record \|`), token `[A-Za-z0-9._-]{1,64}` | finds the row's lines in the run log; the finding scan and the FLAKY rule use it (run history, below) |
| `Capture` | `-` | repo path of the capture, where the test tool put it (RC §1, OWc:13: "Flow defines no capture folder") | exists; above the size floor; its digest may repeat only inside one share group (section 3, "Share groups") |
| `sha256` | `-` | 64 lowercase hex of the capture | the validator hashes the file in place and compares (OWc:13) |
| `Bytes` | `-` | the capture's size, an integer | compared with the file; size floor |
| `Log` | repo path of a TAP log: a file whose name ends in `.tap`, directly in an indexed run directory (RC §3) | repo path of the run log `README.md`, directly in an indexed run directory (RC §1) | an unrecognised log fails every row citing it (D:99, RC §2). The log's folder must equal the `dir` of exactly one run in `state/runs/<phase>/index.tsv`; that run is the row's run (section 8). A log in no indexed run fails the row |
| `SHA` | 7-40 hex: the commit the test ran at | `-` | unit: the test file exists at this SHA (D:99, RC §3) |
| `Env` | `-` | environment token `[a-z0-9-]{1,32}` | finds the latest line of `state/deploys/<env>.jsonl`; "capture postdates the deploy" compares the run log's first `Time (UTC)` cell with that line's `finished` (RC §4) |
| `Note` | free text or `-` (not `-` on a FAIL row) | same | a `repro:` token is the reproduction note that stops a pass-after-fail from being FLAKY (D:99). Read by the planner |

The digest-uniqueness rule applies to `smoke` and `live` rows only. A TAP log covers many tests, so unit rows have no capture and no digest. Captures may be untracked or ignored, as the test tool does it (RC §1); the validator reads them where they are.

### Run history (the FLAKY rule)

FLAKY needs every earlier result of the criterion in the phase (D:99). The owner's five-column runs index stays as it is (OWc:14). The grammar fixes four things on top of it.

1. **Which runs.** Every run in `state/runs/<phase>/index.tsv`, ordered by `started`. The verify step indexes every run whose log backs an evidence row: unit test runs that write a TAP log, as well as live runs.
2. **Where a run's results are.** A live or smoke result is a line of the run's `README.md` whose `Row` cell equals one of the criterion's `Ref`s. A unit result is a line of a `*.tap` file directly in the run directory, joined to the full `<file>::<test name>` identity of one of the criterion's `Ref`s, never to the test name alone (R2-04). No other file is read.
   - **What Node's TAP output carries.** When one `node --test --test-reporter=tap` command runs several files into one log (RC §3), the log is one flat list. There is no `# Subtest: <file>` line per file: Node removed that wrapper when it flattened `--test` output (nodejs/node PR #46440). A `# Subtest:` line names a test or a suite, never a file, so it is not read as one. A failing line `not ok <n> - <name>` is followed by a YAML block (`---` to `...`) that holds `location: '<path>:<line>:<column>'`. A passing line `ok <n> - <name>` carries no file. Checked 2026-10-16 by running Node 24.14.0 over two files in one log, and in the reporter source on Node's `main` (`lib/internal/test_runner/reporter/tap.js`: `test:fail` builds `location`, `test:pass` passes none). Node's documentation does not specify this format and says reporter output may change between versions. The per-file `# Subtest: <file>` nesting assumed when revision 3 was briefed does not hold for current Node.
   - **The join.** A `not ok` line, at any indent, whose name is the `Ref`'s test name is that `Ref`'s failure when its `location` path names the `Ref`'s file: with each run of `\` read as one `/`, and the trailing `:<line>:<column>` removed, the path equals `<file>` or ends with `/<file>`. A `location` naming another file makes it that file's test, not this `Ref`'s.
   - **No location: unresolved, never assigned.** A `not ok` line with the `Ref`'s test name and no readable `location` cannot be told apart from a same-named test in another file. The run's history is then unresolved (rule 4); the failure is neither assigned to the `Ref` nor dropped. This is also why the join fails closed if Node's output changes again: a failure that loses its file becomes unresolved, never clean.
   - **Passing lines are not history.** An `ok` line names no file, so it is never joined to a `Ref` by its name. The FLAKY rule needs earlier failures (a PASS after a FAIL, D:99); the row's own PASS is its claim.
   - **Path suffixes.** The join compares whole path segments from the end. A `Ref` file `test/a.test.ts` also matches a failure located at `…/packages/x/test/a.test.ts` with the same test name. That rare case can only add a failure, so it errs toward FLAKY, never toward a hidden failure.
   - **What WP 7c's fixture must prove.** That the `location` path of a failing line names the `.ts` test file given to the runner under `node --import tsx --test` (RC §3), on a TAP sample captured from that command. The 2026-10-16 check used `.mjs` files; the `.ts` path under `tsx` is an assumption until that sample exists (section 12, WP 7c).
3. **Which `Ref`s belong to a criterion, and with which log.** Within a phase, a criterion is known by its item id. Its history pairs are every (`Ref`, `Log`) its row had at any revision of `evidence/P<n>.md` from the phase `base` to the tip (`git log` on that file, then `read_at` and `parse_evidence` per revision, then `history_pairs`, section 10). Each historical `Ref` keeps, beside it, the `Log` that revision cited (R2-03). A revision whose row has `-` in `Ref` or in `Log` (allowed on a FAIL row) adds no pair. Changing a `Ref` or a `Log` therefore cannot hide an earlier failure.
4. **Missing history is unresolved, never clean.** An indexed run is unresolved when its directory is missing on this host, or holds neither a recognised `README.md` nor a `*.tap` file, or holds a `not ok` line that has the test name of a unit `Ref` of the phase and no readable `location` (rule 2). A history pair is unresolved when its `Log` is in no run of the index at the tip, is missing on this host, or no longer holds a line for its `Ref`: for a live or smoke `Ref`, a line of the recognised `README.md` table whose `Row` cell equals it; for a unit `Ref`, an `ok` or `not ok` line with its test name (a passing line names no file, so the name is all a TAP log can show). Directory-level existence is not enough: a run directory that still holds other logs does not resolve a cited log that is gone. The validator names each unresolved run and each unresolved pair, and reports every PASS row of the phase as FAIL, with the reason "history unresolved". It never counts a missing run or log as one without failures. So a project keeps its run directories, and every log an evidence revision cited, until the phase closes.

---

## 6. `docs/flow/ledger.md`

### Grammar

```
status: state/status.line                   <- line 1, byte for byte (H:78)

## Next
<exactly one line, or ->                    <- replaced in place, never appended

## Handoff
<free text for a successor, or ->           <- replaced in place

## Records
- <timestamp> <kind> <scope> <key>=<value> ... [-- <one line of free text>]
```

`<scope>` is a slice id, a phase id, or `-`, as the kind allows (table below). Values contain no space; a list value is comma-separated. Records are appended in time order, one line each.

### Record kinds

| Kind | Scope | Required keys | Optional keys | Read by |
|---|---|---|---|---|
| `dispatch` | the slice id that `gate <slice>` took | `id=<dispatch id>`, `agent=<agent id>` | | gate (WP 7d): the two round counters (below); build step: a dispatch with no completion names the agent to look for |
| `verdict` | the same slice id | `result=PASS\|FAIL`, `dispatch=<V dispatch id>` | | gate: the result of that verdict dispatch. Not counted again |
| `review` | the same slice id | `result=clean\|findings`, `dispatch=<R dispatch id>` | | gate and review step: the result of that review dispatch. Not counted again |
| `skeptic` | a slice id, a phase id, or `-` | `result=holds\|refuted`, `agent=<id>` | | verify step (two skeptics per phase gate, D:50: their two records name different agents); phase 7 counts (K8 measure) |
| `alert` | a slice id, a phase id, or `-` | `id=<reader alert id>`, `real=yes\|no` | | phase 7 count "alerts that were real against alerts raised" (H:146), joined by `id` with `state/reader/last.json` |
| `close` | a slice id | `by=owner\|unattended`; with `unattended`, also `auth=<A id>` | `carry=<B ids>` | gate: no further round for the scope; plan step: the carry-over list becomes items (RPL:25 (e)) |
| `migrate` | a slice id, a phase id, or `-` | `from=<version>`, `highest=<T id>` | `open=<T ids>`, `questions=<ids>` | WP 12: the migration report is the ledger's first records (H:88 step 8; RPL:30); plan step: new task ids start above `highest`, and the open ids and questions are re-planned |

`<agent id>` matches `[A-Za-z0-9._:-]{1,128}`. Timestamps are `YYYY-MM-DDTHH:MMZ`.

### Round counting (RPL:25 (a) to (e))

- **A round is a dispatch, not a result.** The planner appends the `dispatch` record just before it launches the agent (the build skill, WP 6, says so). A verdict dispatch comes only after `gate <slice>` exits 0, so a script failure writes no record and costs no round (RPL:25 (c)).
- **The dispatch id.** `<slice>-V<k>` for a verdict dispatch, `<slice>-R<k>` for a review dispatch. `<k>` is one more than the number of earlier `dispatch` records with the same scope and letter. A gap or a repeat is a `record` problem. So each id is unique in the ledger, and `<k>` is the count so far.
- **The two counters.** Both are kept per slice, the scope `gate <slice>` takes. `gate_rounds` counts the slice's `V` dispatches. The review counter counts its `R` dispatches, under the same limit (RPL:25 (d)). `verdict` and `review` records are never counted. A dispatch with no completion (the agent timed out, or returned no PASS or FAIL) still counts.
- **Completion records.** A `verdict` cites one earlier `V` dispatch of its scope, a `review` one earlier `R` dispatch, else `ref`. A second completion for one dispatch is `duplicate`.
- **At the limit.** The limit forbids further dispatches, never the completion of a dispatch already counted (R2-01). When a counter reaches the limit, no further `dispatch` of that letter is recorded for the scope; the gate refuses a new round (WP 7d). Each dispatch of the scope that has no completion yet may still get its one `verdict` or `review`, so the last round's PASS, FAIL or findings are recorded. A dispatch whose agent timed out simply never gets one; it still counts. The planner then drafts the numbered carry-over list and records `close`. After the scope's `close`, a `dispatch`, `verdict` or `review` record for that scope is a `record` problem: the parser checks this without knowing the limit. `close by=owner` is the default: the owner closes (RPL:25 (e)). `close by=unattended` must carry `auth=<A id>`: an owner answer in `backlog.md` that authorizes an unattended close, answered (not `pending`) on or before the close record's date. Without `auth` the record is `field-missing`. An answer that is missing, pending or dated after the close gives `ref` from `check_refs`.

The limit itself is `gate_rounds` in the approval policy. The parser reads no policy, so comparing a counter with the limit is the gate's job (WP 7d).

**What is not in the ledger, and why.**
- **No deploy records.** OWc:14 and RC §4 make `state/deploys/<env>.jsonl` the deploy record, written by the ship step and committed with the `ship:` commit. D:21 listed deploy records in the ledger; the later owner decision wins, and one fact keeps one home.
- **No hand-written done or open lists.** They are derived (D:21; D:48).
- **No reader alerts.** The reader writes `state/status.line`, never `ledger.md` (D:97). The ledger holds only the planner's ruling on an alert.
- **No handoff history.** `## Handoff` is replaced in place; git keeps the history (RB 3.2).

---

## 7. `state/flags/<slice>.tsv` (flow-flags v1)

T166 defined this format for `--retro` (`hooks/local/lib/checks.py:31, 392-393, 429-445`). This spec keeps it byte-compatible and adds the `slice` mode that WP 8 writes. Per OWb, the `--retro` tool moves to `maintainer/` under a new name; its output stays `flow-flags v1`, mode `retro`. `flow_docs.py` owns the column list from now on, and a fixture holds parity with the calibration tool (plan-wp2.md WP2-d).

### Layout

| Line | Form |
|---|---|
| 1 | `#flow-flags<TAB>v1` |
| Header lines | `#<key><TAB><value>`; `const` repeats as `#const<TAB><NAME><TAB><value><TAB><provenance>` |
| Column line | `id check kind level commit task path name lines named ruling note`, tab-separated, exactly (`checks.py:31`) |
| Rows | 12 tab-separated cells. `\` `TAB` `LF` `CR` are escaped as `\\` `\t` `\n` `\r` (`checks.py:392-393`) |

| Header keys | Mode `retro` (as `checks.py:431-437` writes) | Mode `slice` (WP 8) |
|---|---|---|
| keys, in order | `mode`, `range`, `tip`, `commits`, `merges_skipped`, `scanned`, `vendored`, `include`, `reference`, `const` (repeated), `skipped_blobs`, `unparsed_manifests` | `mode`, `slice`, `phase`, `base`, `tip`, `reference`, `const` (repeated) |

### Cells

| Cell | Values |
|---|---|
| `id` | retro: `F<check>-<sha7>-<k>` (ordinal, `checks.py:443`), unchanged. slice: `<slice>-F<check>-<h8>` for checks 1 to 4, `<slice>-R-<h8>` for the rubric, `<slice>-D-<h8>` for DONE rows, `<slice>-E-<h8>` for validator flags. `<h8>` and the rules for repeats and re-runs are under "Flag identity in slice mode" below. Unique in the file |
| `check` | retro: `2`, `4`. slice: `1`, `2`, `3`, `4`, `R`, `DONE`, `E` |
| `kind` | check 1: `outside` (changed file under no task glob), `new` (new file under no task glob). Check 2: `dep`, `dep-dev`, `cfg`, `env` (`checks.py:32`), `dep-ref`. Check 3: `minutes`, `files`, `no-commit-calls`, `before-work-calls`, `repeat`. Check 4: `dup`. `R`: `R-a`, `R-b`. `DONE`: `send-back`, `override`. `E`: `item-edit` |
| `level` | `flag` or `log` (`checks.py:382`). The owner's two flag-2 exemptions are `log` rows (OWb:21-24) |
| `commit` | 40 hex, or empty for slice-level rows |
| `task` | retro: any `TASK_TOKEN_RE` match, kept as written (so `T0` and `T012` stay valid), `multi`, or empty (`checks_git.py:152-153`; `hooks/git/commit-msg:41`). slice: a valid task id (`TASK_ID_RE`), `multi`, or empty |
| `path` | repo path or empty |
| `name` | dependency, key, variable or block name; escaped; or empty. Never code text (`checks.py:448`) |
| `lines` | integer, 0 when not a duplicate |
| `named` | `yes`, `no`, or `n/a`. Retro writes `n/a` (`checks.py:444`); slice mode fills it from the backlog (section 3) |
| `ruling` | empty (open), `upheld` or `rejected`. Written only by `checks --rule <id> upheld\|rejected --note "<reason>"`, one id per call (RPL:28; dec-5-8 §6.3 point 1) |
| `note` | empty, or `;`-separated `key=value` tokens. Keys: `line` (as retro writes, `checks.py:444`), `exempt` (`creates-file`, `test-only`), `reason` (required with a ruling), `est`, `actual`, `breadth`, `occ`, `ev` (both below). A bare value contains no `;`, `=`, `"`, TAB or newline; spaces are fine. Any other value is written in double quotes, with `\"` for a quote and `\\` for a backslash inside them, so `reason="kept; the = sign is literal"` is one token. The note is read in two steps: first the cell is unescaped as every cell is (Layout above), then the note is split into tokens |

### Validation by mode

**Retro mode** checks the layout only: the magic line, the header keys in order, the column line, 12 cells per row, valid escapes, the retro id pattern (section 2), `commit` as 40 hex, and the vocabularies of `check`, `kind`, `level` and `named`. It keeps every cell as written, applies no id resolution and no repo-path rule to `task`, `path` or `name`, and `parse_flags` then `format_flags` gives the same bytes back. That keeps every file T166 writes valid (R1-09).

**Slice mode** adds the rules that need resolution: the `#slice` header equals the file name's slice; every id has that slice as its prefix; `task` is a valid task id; `commit` is 40 hex or empty.

### Flag identity in slice mode

- **The anchor.** A row's anchor is seven values: `slice`, `check`, `kind`, `task`, `path`, `name` and `occ`. `<h8>` is the first 8 hex of sha256 over the seven values, UTF-8, joined by `0x1f` (dec-5-8 §6.3 point 2). `commit` is not in the anchor, so a rebase or amend that keeps the change keeps the id.
- **One finding per anchor.** The same anchor raised again by a later commit of the slice window is the same finding: one row. For the event kinds below, "the same anchor" means the same six other values and the same event key `ev`. Its `commit` is the earliest commit, in topological order, that raised it; its `lines` and `note` come from that commit.
- **Separate events, and their key.** Rows that differ only in `occ` are separate events: two call spans of check 3 (`no-commit-calls`, `before-work-calls`, `repeat`), or two duplicated blocks with one name in one file (check 4). The writer (WP 8) gives each event a key, written in the note as `ev=<16 hex>`: for check 4, the first 16 hex of sha256 over the duplicated block's normalized lines (normalized as check 4 compares them), joined by LF; for check 3, the first 16 hex of sha256 over the timestamp and the call id of the span's first tool call, as the transcript records them, joined by `0x1f` (WP 8 confirms that each transcript format it reads carries a call id). The key holds no commit. A rebase or an amend rewrites commit ids, and the anchor already leaves `commit` out so that such a rewrite keeps the id; an unchanged block or span keeps its key the same way. The trade: a rebase keeps an event's ruling, while an edited block, or a span whose first call moves, is a different event.
- **Occurrence numbers are kept, never recomputed (R2-02).** `occ` is a number given to an event once and kept in its row, not a rank over the current history: a rank changes when an earlier event is removed or the events are reordered, and the next event would then take a removed event's id and ruling. `merge_flags` (section 10) gives each new event its `occ`, in event order (first commit, topological, then line, then the time of the first tool call):
  - **Match.** The event's candidates are the rows of the file with the same six other values and the same `ev`. Exactly one candidate, wanted by no other new event: the event takes that row's `occ`, so its id, `ruling` and `reason`.
  - **New.** No candidate: a new row whose `occ` is one above the highest `occ` of any row in the file with the same six other values. No row is ever removed (below), so an `occ` once given, including one whose event no longer occurs, is never given again.
  - **Ambiguous.** More than one candidate, or one candidate wanted by two new events (only a hand edit or a 64-bit key collision makes either): no ruling transfers. The event takes the lowest-`occ` candidate that has no ruling and is not yet taken, or a new row when none is left. An open row carries no ruling, so taking it transfers nothing; taking it, rather than always opening a new row, keeps a re-run from adding one more row each time the ambiguity is met.
  - The note carries `occ=<n>` when `n` is 2 or more; no `occ` token means 1. A row without `ev` (every kind not named above) always has `occ` 1.
  So removing or reordering earlier events moves no id and no ruling to another event.
- **Rulings survive re-runs.** Each writer (section 8) touches only the rows of the checks it computes, through `merge_flags` (section 10). A new row whose id is already in the file keeps the old `ruling` and the old note's `reason`. A row whose id no longer occurs is kept as it was, ruled or open: a ruled one still counts for `--precision`, and an open one may already be cited by a commit body, which is the acted-on count (dec-5-8 §6.3 point 5). An open row at phase end is listed as a finding, as dec-5-8 says. Rows of other writers are left alone. So a re-run never removes a row.
- **A collision is never merged.** If two different anchors give one id, the writer stops with an error and writes nothing.
- **Retro ids are unchanged.** Retro mode keeps `F<check>-<sha7>-<k>` exactly as `checks.py:443` writes it. Retro rulings are the calibration tool's concern.

---

## 8. Other state files the grammar names

| File | Owner of the format | Writer | Committed | Grammar |
|---|---|---|---|---|
| `state/deploys/<env>.jsonl` | the owner (RC §4, OWc:14) | ship step (WP 6) | yes, with the `ship:` commit | One JSON object per line with exactly the owner's eleven keys `env`, `command`, `started`, `finished`, `rc`, `head`, `env_file_sha256`, `version_id`, `deploy_id`, `readiness`, `approval`. Their types are under "Deploy records" below. `flow_docs.parse_deploys` checks keys and types |
| `state/runs/<phase>/index.tsv` | this spec, from OWc:14 ("one line per run: run id, phase, directory, started, exit code") | the verify step, by the command WP 7c provides | yes, in the same commit as the evidence rows it backs | Line 1 `#flow-runs<TAB>v1`; column line `run phase dir started rc`; rows: run id `[A-Za-z0-9._-]{1,64}`, unique in the file; phase id, equal to the folder's `<phase>`; repo path of the run directory, unique in the file; `YYYY-MM-DDTHH:MM:SSZ`; integer. Every run whose log backs an evidence row is indexed, unit (TAP) runs too. An evidence row's `Log` joins its run through `dir` (section 5, "Run history"). Captures stay where the tool puts them; this index is the only thing under `state/runs/` (RC §1) |
| `state/flags/<slice>.tsv` | this spec (section 7) | `checks` (WP 8: checks 1 to 4, and `R` rows through `--rubric`), the DONE check (WP 7b: `DONE` rows), the validator (WP 7c: `E` rows). Each writes through `merge_flags` and `format_flags` | yes, with a `plan:` or `ship:` commit (RPL:28) | section 7 |
| `state/gate/<slice>.txt` | WP 7d | `gate <slice>` | yes, with a `plan:` or `ship:` commit (RPL:28) | not this spec |
| `state/returns/<slice>.json`, `<slice>-<role>.json` | WP 6, 7b, 4 (D:98; RPL:31) | builder; `codex exec` reader | WP 7b decides | not this spec |
| `state/status.line`, `state/reader/last.json` | WP 7a | reader | WP 7a decides | not this spec |
| `state/slices/<task>.start` | WP 9 (dec-1-4 §2; RB 1.12) | slicer | WP 9 decides | not this spec |

`.gitignore` ignores only named `state/` paths (`.gitignore:1-16`), so the committed files above are tracked by default.

### Deploy records (`state/deploys/<env>.jsonl`)

The key set is the owner's and does not change (RC §4, OWc:14). This table fixes what each value may be, so every writer produces the same shape and the validator can compare dates.

| Key | JSON type | Rule |
|---|---|---|
| `env` | string | environment token `[a-z0-9-]{1,32}`, equal to the file name's `<env>` |
| `command` | string | the exact deploy command, one line, non-empty. The ship step writes no secret value into it (H:65); the parser never echoes it |
| `started` | string | `YYYY-MM-DDTHH:MM:SSZ`, a real UTC date and time (`2026-02-30T…` fails) |
| `finished` | string | same form; not earlier than `started`. Never null: a failed or timed-out deploy also finishes |
| `rc` | integer | 0 to 255. JSON `true` or `false` is not an integer here |
| `head` | string | the deployed commit: 40 lowercase hex, or 64 in a SHA-256 repository |
| `env_file_sha256` | string or null | 64 lowercase hex of the environment file the deploy read; null when it read none |
| `version_id`, `deploy_id` | string or null | `[A-Za-z0-9._:-]{1,128}`, as the deploy tool printed them; null when it printed none, for example a deploy that failed first |
| `readiness` | object or null | exactly `probe` (string: method and path, for example `GET /api/health`), `status` (integer HTTP status, or null when nothing answered), `ms` (integer latency, or null), `ok` (boolean). Null when no probe ran |
| `approval` | object or null | exactly `artifact` (string `[A-Za-z0-9._-]{1,128}`: the approval file's name) and `consumed` (timestamp as `started` when the single-use approval was deleted, or null if the deploy failed before it was used). Null when the environment needs no approval |

- **Failed deploys are recorded.** A failed deploy is a line like any other, with `rc` not 0. The fields it never reached are null where the table allows null.
- **Order and "latest".** Lines are appended in order of `finished`. A line whose `finished` is earlier than the line before it is a `row` problem. The latest line is the last one, whatever its `rc`: a capture made before a failed deploy may no longer show what is deployed (RC §4: "the latest line for the row's environment").
- **Strict JSON.** One object per line; no blank lines; a repeated key in one object is a `row` problem (read with `object_pairs_hook`); a missing key is `field-missing`; an extra key is `field`; a value that breaks its rule in the table is `value`. Each carries the line number and, when the key is one of the eleven, the key as ident. An extra key's name is document content, so its ident is empty (section 10).

---

## 9. What replaces each of the 25 templates

Today: 22 files in `templates/` and 3 in `templates/references/`, 108,480 bytes, 2,293 lines (measured 2026-10-16). All 25 leave `templates/`; the 4 new files take their place. Destination folders for "optional pack" and "upstream" are WP 1a's.

| Template (bytes) | Fate | Where its live content goes |
|---|---|---|
| `spec.md` (2,493) | dropped | Criterion, risk and inputs become backlog item fields. Problem, scope and wire-format prose has no reader |
| `decisions.md` (1,560) | dropped | The owner's answers live under `## Answers` in `backlog.md` (D:21) |
| `tasks.md` (3,038) | dropped | Task rows in `phases.md`. `Inputs:` (`tasks.md:29`, T152) becomes the item's `inputs`. `SHA` and `Status` (`tasks.md:12`) become derived |
| `verification-gate.md` (7,434) | dropped | Criterion rows become `evidence/P<n>.md`. The minimum class comes from `policies/evidence-classes.yml` (WP 11). The smoke-prompt columns (`verification-gate.md:55-59`) and rollback text go to the verify and ship skills (WP 6) |
| `gate-report.md` (8,467) | dropped | `state/gate/<slice>.txt` (WP 7d) and a `verdict` record. The PASS/FAIL row rule of T144 (`gate-report.md:131-137`) becomes the evidence row. The operator relay block goes (FR-16 retires) |
| `handoff.md` (3,672) | dropped | The ledger's `## Next` and `## Handoff` |
| `handoff-implement.md` (14,529) | dropped | The slice (WP 9) and the builder card (WP 5). **Blocked by a kept fixture:** see section 12 and owner question 1 |
| `handoff-deploy.md` (14,302) | dropped | The ship skill (WP 6) and `state/deploys/<env>.jsonl` |
| `deploy-report.md` (10,619) | dropped | `state/deploys/<env>.jsonl` (RC §4). Section 1a receipts go with ask 5 (RPL:63) |
| `change-note.md` (3,077) | dropped | With the lightweight lane (WP 3). A trivial-tier commit needs no document |
| `smoke-test-playwright.md` (9,001) | dropped | About 10 tool-neutral lines go into verify; Playwright setup is CLI-owned (RPL:48). The T143 line "do not commit screenshots or raw run output" goes with them (carry-511 T143) |
| `references/deploy-report-checklist.md` (1,382) | dropped | The ship skill |
| `references/gate-report-checklist.md` (1,646) | dropped | The validator |
| `architect-response.md` (7,673) | optional pack | With `workflows/architect-escalation.md` (LF:119); WP 3 and WP 6 decide that workflow's fate |
| `references/architect-response-checklist.md` (1,087) | optional pack | Folds into `architect-response.md` (LF:118) |
| `audience.md`, `north-star.md`, `product.md`, `business-logic.md`, `business-logic-index.md` (1,090 + 1,246 + 1,293 + 2,091 + 1,823) | optional pack | Onboarding and product-doc tasks (LF:120). One line about `docs/north-star.md` folds into the plan skill (RPL:29) |
| `clarify-conversation.md`, `problem-catalog-entry.md`, `backlog-ticket-README.md`, `handoff-folder-README.md` (1,470 + 1,905 + 1,086 + 1,869) | optional pack | LF:120 |
| `skill-template.md` (4,627) | upstream (maintainer) | LF:121 |

Count: 13 dropped, 11 to the optional pack, 1 upstream. 25 in total.

---

## 10. Parser contract: `hooks/local/lib/flow_docs.py`

### Constraints

| Constraint | Source |
|---|---|
| Python 3.10+ standard library only; no PyYAML; no import from other Flow modules except loading `hooks/shared/module_size.py` by path for the glob matcher | Non-negotiable 7 (H:63). `commit-msg`'s helper runs as `python3 -S` with `PYTHONNOUSERSITE=1`, as the tier reader does (`validator_tier.py:97`). RPL:188 lists the parser as reading no policy |
| Reads no policy and holds no threshold. Byte caps, ceilings and the input-kind map belong to the consumers | RPL:188; every threshold is a named constant with provenance in its consumer (RPL:90) |
| Pure parse functions take `str` and do no I/O. Two small loaders read a working-tree file or a file at a git revision | `commit-msg` resolves ids "in `phases.md` at HEAD" (RPL:34). The HEAD reader copies the `ls-tree` + `cat-file` pattern (`validator_tier.py:174-191`) and inherits the hook's environment, including `GIT_INDEX_FILE` (`validator_tier.py:168-170`) |
| Never raises on document content. Returns a result with a tuple of `Problem`s. Raises `TypeError` only for a wrong argument type | A malformed document must not crash a hook |
| Never prints. A `Problem` carries only a fixed code, a line number and a safe ident (see `Problem` below), never other document content, whatever position it came from | Non-negotiable 9 (H:65): any field, valid or malformed, can carry a credential. Cutting a token short does not remove a credential (R1-01) |
| Deterministic: mappings keep file order | Stable output for fixtures and flag ids |
| Line ceiling 650 (expected about 550). Revision 2 adds the deploy types, the dependency matcher, `merge_flags`, the note quoting and the dispatch rules, about 100 lines. Revision 3 adds the occurrence matching in `merge_flags`, `history_pairs` and the after-`close` record rule, about 30 lines. File 1 gives the parser no estimate (D:89, D:97-99 estimate only the reader, DONE, validator and checks) | OWa asks for a stated ceiling per new file |

### Constants

| Name | Value |
|---|---|
| `SCHEMA` | `1` |
| `DOCS_DIR`, `BACKLOG_PATH`, `PHASES_PATH`, `LEDGER_PATH`, `EVIDENCE_DIR` | `docs/flow`, `docs/flow/backlog.md`, `docs/flow/phases.md`, `docs/flow/ledger.md`, `docs/flow/evidence` |
| `RECORD_GLOBS` | `state/flags/*.tsv`, `state/gate/*.txt`, `state/deploys/*.jsonl`, `state/runs/*/index.tsv`: the committed record files (section 8). WP 10 decides which commit subject may stage which |
| `MAX_DOC_BYTES` | `1048576`, provenance "definition 2026-10-16, same cap as `checks.py` `MAX_BLOB_BYTES`" |
| `TASK_TOKEN_RE` | `\bT\d+[a-z]?\b` (`checks_git.py:28`) |
| `TASK_ID_RE`, `ITEM_ID_RE`, `ANSWER_ID_RE`, `PHASE_ID_RE`, `SLICE_ID_RE`, `FLAG_ID_SLICE_RE`, `FLAG_ID_RETRO_RE`, `DISPATCH_ID_RE` | section 2 |
| `DEP_NAME_RE`, `DEP_WILDCARD_RE` | section 3, "Dependency names" |
| `RISKS`, `ITEM_STATUSES`, `CLASSES`, `ROW_STATUSES`, `RECORD_KINDS`, `FLAG_CHECKS`, `FLAG_KINDS`, `RULINGS`, `NOTE_KEYS` | the vocabularies of sections 3 to 7 |
| `FLAGS_COLUMNS` | `("id", "check", "kind", "level", "commit", "task", "path", "name", "lines", "named", "ruling", "note")`, equal to `checks.py:31` |
| `EVIDENCE_COLUMNS`, `TASK_COLUMNS`, `RUNS_COLUMNS`, `DEPLOY_KEYS`, `READINESS_KEYS`, `APPROVAL_KEYS` | sections 4, 5 and 8 |

### Return shapes (frozen dataclasses)

| Type | Fields |
|---|---|
| `Problem` | `code: str` (a fixed code, below), `line: int` (1-based, 0 for the whole file), `ident: str`. `ident` is one of three things and nothing else: (1) an id that full-matches its section 2 pattern (item, answer, phase, slice, task, flag or dispatch id); (2) a key, cell, column or header name from this grammar's fixed lists, for example `risk`, `Globs`, `Estimate`, `Note`, `finished`; (3) empty. It never carries an offending value, a glob, an estimate, a path, a hash, an unknown key, a malformed id, an agent id, a run id, an environment token or any free text, not even cut short. The line number is how the planner finds the fault |
| `Input` | `raw`, `kind` (`path`, `anchor`, `url`, `tool`, `name`), `path`, `anchor`, `tool_kind`, `name_kind` (`dep`, `env`, `cfg`), `value`, `line` |
| `Item` | `id`, `title`, `source`, `criterion`, `test`, `risk`, `status`, `inputs: tuple[Input]`, `answers: tuple[str]`, `shares`, `line`, `field_lines: dict[str, int]` |
| `Answer` | `id`, `question`, `answered`, `text`, `line` |
| `Backlog` | `items: dict[str, Item]`, `answers: dict[str, Answer]`, `problems: tuple[Problem]` |
| `Task` | `id`, `phase`, `slice`, `item`, `does`, `globs: tuple[str]`, `minutes`, `files`, `housekeeping: bool`, `line` |
| `Slice` | `id`, `phase`, `title`, `after: tuple[str]`, `tasks: tuple[str]`, `line` |
| `Phase` | `id`, `title`, `base`, `housekeeping`, `reference`, `reference_manifest`, `slices: tuple[str]`, `line` |
| `Phases` | `reference`, `reference_manifest`, `phases: dict`, `slices: dict`, `tasks: dict`, `problems` |
| `EvidenceRow` | `criterion`, `status`, `cls`, `ref`, `capture`, `sha256`, `bytes`, `log`, `sha`, `env`, `note`, `line` |
| `Evidence` | `phase`, `rows: tuple[EvidenceRow]`, `problems` |
| `Record` | `ts`, `kind`, `scope`, `fields: dict[str, str]`, `text`, `line` |
| `Ledger` | `next`, `handoff`, `records: tuple[Record]`, `problems` |
| `Flags` | `header: tuple[tuple[str, str]]`, `rows: tuple[dict[str, str]]`, `problems` |
| `Run`, `Deploy` | the columns and keys of section 8, plus `line` |

A field that is absent or `-` is `None`. A task that is the phase's `housekeeping` task has `item=None`, `globs=()`, `minutes=files=None`, `slice=None`.

### Functions

| Function | Returns | Notes |
|---|---|---|
| `decode(blob: bytes)` | `(text or None, Problem or None)` | `utf-8-sig`, CRLF to LF, size cap |
| `read_worktree(root, relpath)` | `bytes or None` | |
| `read_at(root, rev, relpath)` | `(bytes or None, reason: str)` | `ls-tree -z <rev> -- <path>`, then `cat-file blob <oid>`; a non-regular file is refused (`validator_tier.py:174-191`) |
| `parse_backlog(text)` | `Backlog` | |
| `parse_phases(text)` | `Phases` | Checks every glob with `glob_problem` |
| `parse_evidence(text, phase=None)` | `Evidence` | `phase` comes from the file name |
| `parse_ledger(text)` | `Ledger` | |
| `parse_flags(text, slice=None)` | `Flags` | Both modes, validated as section 7 "Validation by mode" says. `slice` comes from the file name |
| `format_flags(header, rows)` | `str` | The only writer of the flags file. Escapes as `checks.py:392-393` |
| `merge_flags(old: Flags, new_rows, checks)` | `tuple[dict]` | Section 7 "Occurrence numbers are kept" and "Rulings survive re-runs". `new_rows` arrive without `id`; `merge_flags` gives each its `occ` (match by the six other anchor values and `ev`; a new `occ` above every `occ` used; no ruling through an ambiguous match) and computes its `id` with `flag_id`. A row without `ev` has `occ` 1, so the DONE check (`DONE` rows) and the validator (`E` rows) pass rows exactly as before, minus the `id`. Touches only the rows whose `check` is in `checks`; carries `ruling` and `reason` by id; keeps every row that no longer occurs; refuses an id collision |
| `history_pairs(revisions)` | `dict[str, tuple[tuple[str, str]]]` | Section 5 "Run history", rule 3. `revisions` are the `Evidence` of each revision of one evidence file, oldest first. Per criterion, the distinct (`Ref`, `Log`) pairs in first-seen order, from rows whose `Ref` and `Log` are both filled. Pure; the validator checks each pair's log on disk |
| `note_tokens(note)`, `format_note(tokens)` | `dict[str, str] or None`, `str` | Split and write a note cell, with the quoting of section 7. `None` for a malformed note |
| `format_record(ts, kind, scope, fields, text=None)` | `str` | Used by WP 7d, WP 8 and WP 12 to append a ledger record |
| `parse_runs(text, phase=None)`, `parse_deploys(text, env=None)` | `(tuple[Run or Deploy], tuple[Problem])` | Section 8. `phase` and `env` come from the path; a row or line that disagrees is `value` |
| `run_of(runs, log_path)` | `Run or None` | The indexed run whose `dir` is the folder of `log_path` (section 5, "Run history") |
| `dep_named(package, item)` | `bool` | Section 3, "Dependency names": the item's `dep:` entries and criterion tokens, exact or scoped-wildcard match |
| `check_refs(backlog, phases, ledger=None)` | `tuple[Problem]` | Cross-document: every task's item exists; every cited answer exists; every `shares` id exists, is not the item itself, and names a root with no `shares` line; every `after` id exists; no housekeeping id in a table, and none repeated across phases. With `ledger`: every `dispatch`, `verdict`, `review` and `close` scope is a slice in `phases.md`; every `close auth` names an answered owner answer dated on or before the close |
| `phase_criteria(phases, phase_id)` | `set[str]` | Items served by the phase's non-housekeeping tasks |
| `changed_fields(old: Backlog, new: Backlog, fields=("risk", "criterion", "test"))` | `list[tuple[item_id, field]]` | For the item-edit flag (D:99) |
| `task_tokens(subject: str)` | `list[str]` | All `TASK_TOKEN_RE` matches, in order |
| `is_flow_document(path: str)` | `bool` | True for the three fixed paths and `docs/flow/evidence/P<n>.md` |
| `glob_problem(pattern)` | `str` | Empty when valid. Same rules and messages as `validator_tier.pattern_problem` (`:73-93`); a fixture holds the parity. Copied, not imported, because WP 10 will make `validator_tier.py` import this module |
| `load_glob(root)` | callable | Loads `_glob_to_regex` from `hooks/shared/module_size.py` by path, as `validator_tier.load_glob` does (`:61-70`) |
| `cells(row)` | `list[str]` | Verbatim T144 (`gate_contract_check.py:47-51`) |
| `md_section(text, anchor)` | `str or None` | For `path#anchor` inputs in project files. The first heading whose text, after the `#`s and an optional `<n>[a-z]?.` number, equals the anchor ignoring case; it ends at the next heading of the same or a higher level (T144's `section_table` rule, `gate_contract_check.py:54-70`). A whole-text match, not T144's prefix match (`:28-29` ends in `\b`) |
| `md_table_row(text, first_cell)` | `(header cells, row cells) or None` | The first table row anywhere whose first cell equals the anchor exactly |
| `flag_id(slice, check, kind, task, path, name, occ=1)` | `str` | Section 7 slice-mode ids, with the slice prefix |
| `main(argv)` | exit code | `flow_docs.py check <path>...`: prints `<path>:<line>: <code> <ident>` per problem; exit 0 clean, 1 problems, 2 usage. For the plan step and the commit hook's warn-only evidence line (RPL:28) |

### Problem codes

`size`, `encoding`, `comment`, `title`, `heading`, `id`, `duplicate`, `field`, `field-repeat`, `field-missing`, `value`, `stray`, `section`, `table`, `cells`, `glob`, `estimate`, `ref`, `first-line`, `record`, `magic`, `header`, `columns`, `row`. One code per kind of fault; the fixture names each.

### Who calls what

| Consumer | Calls |
|---|---|
| `slice.py` (WP 9) | `parse_backlog`, `parse_phases`, `check_refs`, `md_section`, `md_table_row`, `load_glob` (breadth), `parse_flags` (`--brief`) |
| `gate.py` DONE check (WP 7b) | `parse_phases`, `task_tokens`, `load_glob`; `parse_flags`, `flag_id`, `merge_flags`, `format_flags` (`DONE` rows) |
| `gate.py` validator (WP 7c) | `parse_evidence`, `parse_phases`, `phase_criteria`, `parse_backlog`, `check_refs` (share groups), `read_at` + `changed_fields`, `read_at` and `parse_evidence` per evidence revision, then `history_pairs` (run history), `parse_runs`, `run_of`, `parse_deploys`; `parse_flags`, `flag_id`, `merge_flags`, `format_flags` (`E` rows) |
| `gate.py` gate (WP 7d) | `parse_ledger` (counts `V` and `R` `dispatch` records per slice; `close`), `check_refs` with the ledger (`close auth`), `format_record` |
| `checks.py` core (WP 8) | `parse_phases`, `parse_backlog`, `dep_named`, `parse_flags`, `flag_id`, `merge_flags`, `note_tokens`, `format_note`, `format_flags`, `load_glob` |
| `commit-msg` helper (WP 10) | `read_at(HEAD, PHASES_PATH)`, `decode`, `parse_phases`, `task_tokens`, `TASK_ID_RE`, `is_flow_document`, `RECORD_GLOBS` |
| pre-commit warn-only evidence line (WP 7c) | `parse_evidence` via `main check` |
| `flow migrate` (WP 12) | `format_record` (`migrate`) |
| `reader.py` (WP 7a) | none |

---

## 11. Field inventory (H:78: "no template field exists that no script or phase step reads")

Every field, record key, header key and state-file cell is listed. Storing a value in the parser does not count as reading it.

| Document | Field | Script reader | Phase-step reader |
|---|---|---|---|
| backlog | item id and title | slicer, validator (criterion id), checks (`named`), `check_refs` | plan |
| backlog | `source` | `checks --precision` (flag ids) | plan |
| backlog | `criterion` | slicer, checks flag 2 (`dep_named`), validator `E` | verify |
| backlog | `test` | slicer, validator | verify |
| backlog | `risk` | validator, gate (rubric hold), slicer | verify (security checklist) |
| backlog | `status` | WP 12 report | plan, ship |
| backlog | `inputs`: path, anchor, url and tool entries | slicer | |
| backlog | `inputs`: `dep:`, `env:`, `cfg:` entries | slicer, checks flag 2 | |
| backlog | `answers` | slicer | |
| backlog | `shares` | validator (share groups), `check_refs` | |
| backlog | answer id and question | slicer, `check_refs` | plan |
| backlog | answer `answered`, body | slicer; gate (`close auth` date) | plan |
| phases | `reference` (file and phase) | slicer (`--brief`, rubric R(b)) | plan |
| phases | `reference_manifest` (file and phase) | checks flag 2 `dep-ref` | |
| phases | phase id and title, slice id and title | slicer, DONE check, checks, validator, gate, `commit-msg` | plan |
| phases | `base` | DONE check, checks, validator, gate | |
| phases | `housekeeping` | `commit-msg`, DONE check, checks | |
| phases | `after` | `check_refs` (ids exist) | build (dispatch order) |
| phases | `Task`, `Item`, `Does`, `Globs`, `Estimate` | slicer, DONE check, checks, validator, `commit-msg` | |
| evidence | all eleven cells | validator | verify (`Note`) |
| ledger | line 1 | | every session (points at the status line) |
| ledger | `## Next`, `## Handoff` | | build, successor |
| ledger | record timestamp | gate (order; `close auth` date) | |
| ledger | `dispatch` `id` | gate (both counters; completion links) | |
| ledger | `dispatch` `agent` | | build (a dispatch with no completion names the agent to look for) |
| ledger | `verdict` `result`, `dispatch` | gate | |
| ledger | `review` `result`, `dispatch` | gate | review |
| ledger | `skeptic` `result` | | verify; phase 7 counts (K8) |
| ledger | `skeptic` `agent` | | verify (the two skeptics of a phase gate are different agents) |
| ledger | `alert` `id`, `real` | | phase 7 count (H:146), joined with `state/reader/last.json` |
| ledger | `close` `by`, `auth` | gate, `check_refs` | |
| ledger | `close` `carry` | | plan (the carry-over list becomes items) |
| ledger | `migrate` `from`, `highest`, `open`, `questions` | WP 12 report | plan (new ids above `highest`; re-plan `open` and `questions`) |
| ledger | record text after `--` | | successor |
| flags | header `mode`, slice-mode `slice`, `phase` | `parse_flags` (mode and file agreement), `checks --precision` (per phase) | |
| flags | slice-mode `base`, `tip`, `reference`, `const` | slicer `--brief` (the window, the reference, the constants with provenance, D:75) | review |
| flags | retro header keys | | maintainer calibration (the calibration tool's own output) |
| flags | `id` | `checks --rule`, `merge_flags`, `checks --precision` (acted-on: cited by a backlog `source` or a commit body) | |
| flags | `check`, `kind`, `level`, `named` | `checks --precision`, slicer `--brief` | review |
| flags | `commit`, `task`, `path`, `name`, `lines` | slicer `--brief`, `flag_id` (`task`, `path`, `name`) | review |
| flags | `ruling` | gate (holds: the rubric on a risk-tagged item, the DONE send-back), `checks --precision`, `merge_flags` | |
| flags | `note`: `reason`, `exempt` | `checks --precision` (`exempt` rows are `log`), `merge_flags` (`reason`) | plan |
| flags | `note`: `line`, `est`, `actual`, `breadth`, `occ` | slicer `--brief`; `flag_id` (`occ`) | review |
| flags | `note`: `ev` | `merge_flags` (occurrence matching, section 7) | |
| runs index | `run`, `dir`, `started` | validator (`run_of`; history order; names an unresolved run) | |
| runs index | `phase` | `parse_runs` (equals the folder), validator | |
| runs index | `rc` | | verify (exit 124: cleanup did not run, so the run's identities are listed by run id, RC §2) |
| deploys | `env`, `finished` | validator (deploy dating, RC §4) | |
| deploys | `started` | `parse_deploys` (not after `finished`) | ship, successor |
| deploys | `head`, `rc`, `env_file_sha256`, `command` | | ship (preflight of the next deploy: the last `head` is the rollback target, `rc` says whether the last deploy failed, `env_file_sha256` shows whether the environment file changed, `command` is what to repeat); successor |
| deploys | `version_id`, `deploy_id`, `readiness`, `approval` | | successor (what is live, whether it answered its probe, which approval allowed it); ship (the next deploy's approval) |

Fields read by a phase step alone: `after` (for order), the ledger's two sections and record text, `dispatch agent`, `skeptic` keys, `alert` keys, `close carry`, the runs index's `rc`, and the deploy fields other than `env`, `started` and `finished`. Each row names its step. `review n=` is removed: no script or step read it (R1-12).

---

## 12. Consequences for other work packages

| WP | What this grammar fixes for it |
|---|---|
| WP 10 `commit-msg` | Use `TASK_TOKEN_RE`; resolve with `parse_phases` on the HEAD blob; legacy mode when `docs/flow/phases.md` is absent at HEAD. The commits that carry records must have a legal subject: decision 6 admits `state/flags/*.tsv` and `state/gate/*.txt` in `plan:` and `ship:` (RPL:28); OWc:14 adds `state/deploys/*.jsonl` to `ship:`; this spec adds `state/runs/*/index.tsv` beside an evidence commit. A commit citing the phase's `housekeeping` id must be trivial-tier (section 4). A revert is judged on its inner subject (RPL:34); a revert of a `plan:` or `ship:` commit is therefore judged as a `plan:` or `ship:` commit, on its own staged paths. Add `hooks/local/lib/flow_docs.py` to `TIER_INPUTS` (`validator_tier.py:23-29`) once the tier decision imports it, so a staged parser edit cannot qualify itself |
| WP 7b DONE | Task globs and the phase base come from `phases.md`; the housekeeping task is skipped; `DONE` rows go through `merge_flags` |
| WP 7c validator | The row cells of section 5, conditional on status; the run history rules of section 5 (history pairs with their logs, the TAP join on `<file>::<test name>`); share groups (section 3); the runs index and deploys file of section 8; the item-edit flag as check `E`, through `merge_flags`. The TAP pass marker and the runner exit codes are constants in WP 7c's code (interface table below). Its fixture carries the review-round-2 cases below |
| WP 7d gate | Counts the `V` and `R` `dispatch` records per slice against `gate_rounds`. At the limit it refuses a further dispatch of that letter, while each dispatch already counted may still record its one completion before the `close` (R2-01); `close by=unattended` needs its `auth` answer (section 6) |
| WP 8 checks | Slice mode of section 7, with its ids, the event key `ev` (check 3 spans, check 4 blocks), the kept `occ` and `merge_flags`; `named` from the backlog through `dep_named`; `dep-ref` from `reference_manifest`; glob dialect of section 2 (not the calibration tool's fnmatch matcher, `checks.py:52-68`). Its fixture carries the review-round-2 case below |
| WP 9 slicer | Input kinds and `path#anchor` resolution of section 3; the `input_kinds` map (interface table below) |
| WP 11 | The two policy key sets in the interface table below; this grammar holds the class names `unit`, `smoke`, `live` |
| WP 6 | The plan skill teaches the grammar in short form; the build skill appends the `dispatch` record before each verdict or review dispatch (section 6); the ship skill writes the deploy line with the types of section 8; the verify skill writes the runs index line for every run, unit runs included, and tells the project to keep every indexed run directory, and every log an evidence revision cited, until the phase closes (a missing one makes the phase's PASS rows unresolved, section 5). A tool that clears its output folder on each run needs a separate output folder per run |
| WP 12 | Writes `migrate` records; never converts 5.x documents (H:88) |
| WP 2 wave 3 | Removing `templates/handoff-implement.md` reddens `liveness`, a release tag (`hooks/tests/run-tests.sh:98`). Case `ac4-liveness-in-hard-invariants` and `ac4-hard-region-bounded` read that template (`hooks/tests/test-liveness-bounded-run.sh:288-316`) and run in `--core-only` mode too (only the dependency at `:262-263` is skipped). That is a fourth fixture departure, which needs the owner (plan-wp2.md, owner question 1) |

### Fixture cases from review round 2 (post-cap; checked in the wave-2 code review)

Revision 3 was not re-reviewed, so each change is held by named cases. The parser's cases are in plan-wp2.md (L06, F03, F05, E08). The cases below belong to the consumers' fixtures; their plans name them under these names.

| Case | Fixture | Finding | Proves |
|---|---|---|---|
| `history-partial-loss` | WP 7c validator | R2-03 | One indexed run holds `auth.tap`, with B12's failure (`not ok`, located in B12's file), and `other.tap`, with unrelated tests. Evidence revision 1 cites `auth.tap` for B12; revision 2 cites a newer run in which B12 passes. With `auth.tap` deleted and `other.tap` kept, every PASS row of the phase is FAIL with "history unresolved", and B12's pair is named. The same when `auth.tap` stays but its B12 line is gone, and when the run's index row is gone. With `auth.tap` intact, B12 is FLAKY and nothing is unresolved |
| `tap-same-name-different-file` | WP 7c validator | R2-04 | One run's log holds `not ok … - rejects invalid input` located in `auth.test.ts` and `ok … - rejects invalid input` from `profile.test.ts`, as Node prints two files into one log. A PASS row for `profile.test.ts::rejects invalid input` finds no earlier failure (not FLAKY); a later PASS row for `auth.test.ts::rejects invalid input` finds that failure |
| `tap-unlocated-failure` | WP 7c validator | R2-04 | The same log with the failing line's `location` removed: history unresolved for the phase; the failure is assigned to neither test |
| `tap-node-sample` | WP 7c validator | R2-04 | The logs of the two cases above are captured from `node --import tsx --test --test-reporter=tap` over two `.ts` files (paths replaced), so the join is proved on what that command prints, `.ts` location paths included (section 5, rule 2) |
| `ev-stable-across-rebase` | WP 8 checks | R2-02 | A duplicated block keeps its `ev` when its commit is rebased or amended, and gets a new `ev` when one of its lines is edited; a check-3 span keeps its `ev` when commits are rewritten and its first tool call stays the same |

### Interface with WP 11: the two policy key sets (confirmed by review round 1, R1-10)

| Policy | Key | Shape | Rule |
|---|---|---|---|
| `policies/evidence-classes.yml` | the closed key set | exactly these eight keys: `schema_version`, `validator_free_paths`, `test_paths`, `copy_paths`, `vendored_paths`, `classes`, `finding_marker`, `row_status_pattern` | An unknown key is rejected (`plan-wp11.md:132`). No other key is added unless the key set is deliberately extended in a later grammar commit |
| `policies/evidence-classes.yml` | `finding_marker` | the owner's constant | A Record cell beginning `FINDING <id>:` (the word, a space, an id, a colon; RC §2, OWc:16) |
| `policies/evidence-classes.yml` | `row_status_pattern` | the owner's constant | `^(PASS\|FAIL: .+\|BLOCKED-AT-[a-z0-9-]+.*)$` (RC §2, OWc:16) |
| `policies/agent-tools.yml` | `input_kinds` | `input_kinds: {<kind>: [<tool>, ...]}` | `<kind>` matches `[a-z][a-z0-9-]{1,30}` and is not one of the reserved kinds `dep`, `env`, `cfg`. Tools follow the profile's tool rules (WP 11, `plan-wp11.md:174-178`). The slicer reads it (section 3) |
| WP 7c code (no policy key) | TAP pass marker | constant with provenance "owner runner conventions 2026-10-16 (RC §3, OWc:16)" | `ok <n> - <name>` with no `# SKIP` or `# TODO` suffix |
| WP 7c code (no policy key) | runner exit codes | constant with the same provenance | `0` pass; `1` error; `3` findings were recorded; `124` deadline reached, cleanup did not run (RC §2) |

The TAP pass marker and the exit codes live in WP 7c's code because the eight-key set has no key for them. Moving them into the policy would mean extending that set on purpose, in a grammar commit.

---

## 13. Open points for the review, with the default this spec takes

| # | Question | Default here | Why |
|---|---|---|---|
| 1 | One criterion per item, with criterion id = item id? | yes (round 1 agreed) | D:21, H:78 singular; keeps the validator's "exactly one row" simple. One observable criterion, not a reason for artificial commits. Shared evidence uses share groups (section 3) |
| 2 | Folder `docs/flow/`? | yes (round 1 agreed; owner answered B5 yes, 2026-10-16) | One prefix test; no collision with CLI-owned docs paths |
| 3 | Closed phases and done items stay in their files? | yes (round 1 agreed, for this release) | Revert resolution at HEAD (RPL:34); RB 3.1 and 3.3 propose collapsing. The cost is planner reading and parse time. Growth stays open: the 1 MiB cap is a late rejection, not growth control, and the strict grammar does not solve it |
| 4 | No deploy records in the ledger? | none | OWc:14 makes the jsonl the record |
| 5 | Is `after` worth a field read only by the build step? | keep (round 1 agreed) | T145 cross-slice order needs a home. WP 6 rejects self-dependencies and cycles before dispatch |
| 6 | Runs index committed with the evidence commit? | yes (round 1 agreed, with R1-05) | Otherwise the FLAKY rule lives on one host, the same reason decision 6 commits the flags file (dec-5-8 §6.4). The index does not bring ignored logs to another host: a missing run stays unresolved (section 5) |
| 7 | Flag ids hashed in slice mode, ordinal in retro mode? | yes, with the slice in the id and an occurrence number (R1-04), kept per event across re-runs (R2-02) | Retro output is already on file with ordinal ids (OWb); slice rulings must survive re-runs (section 7, "Flag identity in slice mode") |
| 8 | Should `commit-msg` also require a trivial-tier commit to cite the housekeeping id? | no; only the reverse (a housekeeping citation must be trivial-tier) | Either id is ignored by the DONE check; requiring the housekeeping id adds a reject and protects nothing |

---

## Revision 2 change log

Round 1 review: `astra-wp2-grammar-r1.md`, verdict FREEZE WITH CHANGES, findings R1-01 to R1-12. Each fix follows the review's "Smallest change" column. Revision 1 is kept as `wp2-grammar-spec.r1.md`.

| Finding | What changed | Sections |
|---|---|---|
| R1-01 (blocker) | A `Problem` carries only a fixed code, a line number and a safe ident: a well-formed id, a fixed field name, or nothing. The 80-character offending token is gone, for every position: values, globs, estimates, unknown keys, malformed ids, record values, flag cells and deploy lines | 0, 8 (deploy problems), 10 (constraints, `Problem`) |
| R1-02 (blocker) | New `dispatch` record, written before launch, with a unique self-counting id (`<slice>-V<k>`, `<slice>-R<k>`). Both counters count dispatches per slice; `verdict` and `review` link to their dispatch and are not counted again. A dispatch with no result still counts. `close by=unattended` must cite `auth=<A id>`, an owner answer dated on or before the close. `agent` moved from `verdict` and `review` to `dispatch`, its one home | 2 (dispatch id), 6 (record kinds, round counting), 10 (`check_refs`, who calls what), 11, 12 (WP 6, WP 7d) |
| R1-03 (blocker) | One dependency matcher, `dep_named`: exact npm names plus the owner's scoped wildcard `@<scope>/*`, for `dep:` entries and criterion tokens alike. No substring or prefix matching | 3 (input entries, "Dependency names"), 10 (constants, functions), 11 |
| R1-04 (major) | Slice-mode ids now start with the slice (`P7-S3-F1-3fa9c2d0`), so a backlog `source` finds its file. The hash covers slice, check, kind, task, path, name and an occurrence number `occ`, not the commit. One finding per anchor across commits; separate events get `occ`. `merge_flags` keeps rulings across re-runs, per writer, and never removes a row, so an open flag cited by a commit body still counts as acted on. Retro ids unchanged | 2 (flag ids), 3 (`source`), 7 (cells, "Flag identity in slice mode"), 8 (flags writers), 10, 12, 13 (point 7) |
| R1-05 (major) | The five-column index stays. Added: the `Log` to run join through `dir`; TAP logs are `*.tap` files directly in a run directory; every run is indexed, unit runs too; a criterion's history covers every `Ref` its row had in the phase; a missing indexed run is unresolved and fails PASS rows, never counts as clean. The verify skill (WP 6) tells the project to keep run directories until the phase closes | 5 (`Log` cell, "Run history"), 8 (runs index), 10 (`parse_runs`, `run_of`), 11, 12 (WP 6, WP 7c), 13 (point 6) |
| R1-06 (major) | Evidence requirements depend on status. PASS needs every cell of its class. FAIL needs only `Criterion`, `Status`, `Class` and an explaining `Note`; other cells may be `-`, and any filled cell is still checked. `BLOCKED-AT-*` and exit 124 are FAIL rows | 5 ("What a row needs depends on its status", `Note` cell) |
| R1-07 (major) | Types for all eleven deploy keys: timestamps, `rc`, SHA forms, nullable fields, the shapes of `readiness` and `approval`, environment and file agreement, append order, failed deploys. The key set is unchanged. The review says "twelve keys"; the owner's list (OWc:14, RC §4) and this spec both have eleven, so the owner's eleven stand | 8 ("Deploy records"), 10 (constants, `parse_deploys`), 11 |
| R1-08 (major) | A comment starts only on a line beginning `<!--`, outside the ledger's `## Next` and `## Handoff`. Everywhere else `<!--` is literal, so answer bodies, `## Next`, `## Handoff`, values and cells keep it. An answer body is its lines after the `> ` prefix, byte for byte | 1 (templates), 2 (comments), 3 (answer body) |
| R1-09 (major) | Retro mode checks layout only and keeps every cell as written, so `T0` and `T012` stay valid. Id validity and file agreement apply in slice mode only | 2 (task token note), 7 (`task` cell, "Validation by mode") |
| R1-10 (major) | Interface table with the eight `evidence-classes.yml` keys exactly as the review confirmed, `finding_marker` and `row_status_pattern` with the owner's constants, and `agent-tools.yml` `input_kinds: {<kind>: [<tool>, ...]}` with kind regex `[a-z][a-z0-9-]{1,30}` and `dep`, `env`, `cfg` reserved. The TAP pass marker and exit codes 0, 1, 3, 124 are WP 7c code constants, since the key set is not extended. The input table now names `input_kinds` | 3 (input entries), 12 (WP 7c, WP 9, WP 11 rows; "Interface with WP 11") |
| R1-11 (major) | `shares` names the root of a share group; the root has no `shares` line. All members of one group may cite one digest. For each repeated digest, every citing item must be in one group, else every row citing it fails | 3 (grammar, `shares` row, "Share groups"), 5 (`Capture` cell), 10 (`check_refs`) |
| R1-12 (minor) | The inventory now lists record keys, flags header keys and cells, runs index cells and deploy keys, each with a script or phase-step reader. `review n=` is removed: nothing read it. The deploy fields other than `env` and `finished` name the ship preflight and successor sessions as readers | 6 (`review` keys), 11 |

**Review notes applied (outside the numbered findings, stated in the review's text).**

| Note | What changed | Sections |
|---|---|---|
| "Unattributable" was wrong | Table cells can be compared too; the reason for one field per line is now readability and line numbers | 3 ("Why one field per line") |
| Do not claim strictness controls growth | The strictness reason no longer says it stops accumulation; growth stays open | 2 (strictness), 13 (point 3) |
| Housekeeping ids share task-id uniqueness | Stated, and checked by `check_refs` | 2 (task id), 4 (`housekeeping`), 10 |
| `after` cycles | WP 6 rejects self-dependencies and cycles before dispatch | 4 (`after`), 13 (point 5) |
| Section 13 answers | The review's agreements are recorded; point 2 names owner answer B5 as pending | 1, 13 |

**Cheaper forms adopted (review, last section).** All four keep their contracts.

| Form | What changed | Sections |
|---|---|---|
| Compare header cells after trimming | Markdown table headers compare trimmed cells. The TSV column lines stay exact, for T166 byte compatibility | 2 (Markdown table header), 4, 5 |
| Blank and `-` are the same empty value | An empty value or cell reads as none, like `-` and `—`; `- inputs:` still takes its indented entries | 2 (empty value) |
| Quoted note values | A flags note value may be double-quoted, so a reason can hold `;`, `=` or `"`. The cell is unescaped first, then split | 7 (`note` cell) |
| Prose only in declared payload fields | Already the rule; the payload fields are listed and the reason (no reader for item prose) is stated | 2 (strictness) |

**Consequences the fixes need.** The parser's stated ceiling rises from 550 to 650 lines (expected about 520), for the added rules (section 10). The status line marks this as revision 2.

**Kept as owner decisions.** The deploy key set (eleven keys, above). The five-column runs index (OWc:14). `docs/flow/` is confirmed by the owner (B5, 2026-10-16). No finding conflicted with an owner decision in any other way.

---

## Revision 3 (post-cap, integrator) change log

Round 2 review: `astra-wp2-grammar-r2.md`, verdict REWORK, majors R2-01 to R2-04. R1-01, R1-03 and R1-06 to R1-12 are closed; R1-02, R1-04 and R1-05 stayed open through R2-01 (R1-02), R2-02 (R1-04), R2-03 and R2-04 (R1-05). Round 2 of 2 was the last; no further round runs. The integrator applied each finding's "Smallest change" after the cap. Revision 3 is not re-reviewed: each change is a mandatory check in the wave-2 code review of `flow_docs.py`, the WP 7c validator or WP 8's flags, through the named fixture cases below. Revision 2 is kept as `wp2-grammar-spec.r2.md`.

| Finding | What changed | Sections | Fixture cases |
|---|---|---|---|
| R2-01 (major): the final permitted dispatch could not record its result | "The next record is `close`" and "only a `close` follows" are gone. The limit forbids further dispatches of that letter, never the completion of a dispatch already counted: each outstanding dispatch may get its one `verdict` or `review` before the `close`. **Addition beyond the review's words:** a `dispatch`, `verdict` or `review` after the scope's `close` is a `record` problem, the limit-free half of "before closure" that the parser can check | 6 ("At the limit"); 10 (line ceiling); 12 (WP 7d) | L06: final-round PASS and final-round timeout, both counters, records after the `close` (plan-wp2.md) |
| R2-02 (major): occurrence renumbering transferred a ruling | `occ` is kept per event, never recomputed from current history. A re-run matches an event to the row with the same six other anchor values and the same event key `ev` (in the note): the duplicated block's content hash for check 4; the first tool call's transcript timestamp and call id for check 3. **Decision 1:** `ev` holds no first-seen commit, the integrator's other offered key part. The anchor already leaves `commit` out so that a rebase or amend keeps the id; a commit in `ev` would drop the ruling of every multi-event row on each rebase. The trade: an edited block, or a span whose first call moves, is a new event. A new event takes `occ` one above every `occ` used for its six values, so a retired `occ` is never reused. **Decision 2, a departure from the brief's literal wording** ("where correspondence is ambiguous, no ruling transfers and the row is new"): no ruling transfers, as asked, but the event takes an open candidate row before it opens a new one. Taken literally, an ambiguity that persists would add one more row on every re-run; an open row has no ruling, so taking it transfers nothing. Ambiguity needs a hand edit or a 64-bit key collision. `merge_flags` now assigns `occ` and the id; a row without `ev` has `occ` 1, so the DONE and `E` writers are unchanged apart from passing rows without `id`. The false claim "commits and transcripts only grow" is removed | 7 (`note` cell; "One finding per anchor"; "Separate events, and their key"; "Occurrence numbers are kept"); 10 (`merge_flags`, line ceiling); 11 (`ev`); 12 (WP 8; case table); 13 (point 7) | F03 and F05: removal and reordering of earlier events, no reuse of a retired `occ`, the ambiguous case (plan-wp2.md); `ev-stable-across-rebase` (WP 8) |
| R2-03 (major): losing one historical log could erase a failure | Each historical `Ref` keeps the `Log` its revision cited (`history_pairs`, new, pure). A pair is unresolved when its log is in no indexed run, is missing, or no longer holds a line for its `Ref`; directory-level existence is not enough. An unresolved pair fails every PASS row of the phase with "history unresolved", as an unresolved run does. The verify skill (WP 6) tells the project to keep every cited log until the phase closes | 5 (rules 3 and 4); 10 (`history_pairs`, who calls what, line ceiling); 12 (WP 6, WP 7c; case table) | E08: the pairing half (plan-wp2.md); `history-partial-loss` (WP 7c) |
| R2-04 (major): historical TAP matching discarded the file | A unit result joins the full `<file>::<test name>`. **The brief's mechanism does not hold:** current Node prints no per-file `# Subtest: <file>` wrapper (removed in nodejs/node PR #46440). Checked on 2026-10-16 by a local run of Node 24.14.0 over two files into one log, and in `lib/internal/test_runner/reporter/tap.js` on Node's `main`; Node's documentation does not specify the TAP layout and says reporter output may change between versions. The join therefore uses the `location:` path that Node prints in the YAML block of a failing line only. A failing line with the test name and no readable `location` makes the run's history unresolved, never assigned; passing lines name no file and are not history. Whether `location` names the `.ts` file under `node --import tsx --test` is stated as an assumption that WP 7c's fixture must prove on a captured sample | 5 (rule 2; rule 4, unjoinable failure); 12 (WP 7c; case table) | `tap-same-name-different-file`, `tap-unlocated-failure`, `tap-node-sample` (WP 7c) |

**Not changed, and open.**
- **The row's own pass marker stays a name match.** WP 7c's pass marker (`ok <n> - <name>` without `# SKIP` or `# TODO`, RC §3) is checked by name on the row's own log. Node prints no file on a passing line, so a same-named test in another file can satisfy it. Round 2 did not raise this, and closing it would mean a new validator rule. It is left to the integrator.
- **Hours.** plan-wp2.md's estimate for WP2-d is not re-estimated for about 30 more parser lines.
- **R1 findings.** Nothing closed in round 2 is reopened.
