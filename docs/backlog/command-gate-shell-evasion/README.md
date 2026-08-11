# command-gate-shell-evasion

**Status:** corpus LANDED (T5) · implementation BLOCKED on decisions D1 + D2 below — `NO IMPLEMENTABLE DECISION` until both are locked
**Found:** 2026-07-28 adversarial review of `approval-binding-and-upgrade-classification` (false negatives) · 2026-07-30 prerelease consumer report (false positives)
**Surface:** `policies/command-policy.yml` + `hooks/shared/command_policy.py` (`rule_matches`)
**Severity:** medium — both halves are pre-existing properties of regex-on-raw-command, not regressions
**Decisions of record:** K21 (`docs/specs/approval-binding-and-upgrade-classification/decisions.md`) — document, do not half-fix · M8 (`docs/specs/upgrade-source-integrity-and-observability/decisions.md`) — parser project, not a patch
**Sources:** `docs/tmp/handoff/2026-07-30-workhub-upstream-report.md` F7 · `docs/release-notes/v4.7.0.md` § "Known limitation … (F7)"

## Defect — one root cause, two directions

Rule matching is `re.search(pattern, command)` over the **raw** command string. Structure was intended; text is what is matched. Both failure directions follow:

| Dir | Class | Example | Executes | Matches a rule | Outcome |
|---|---|---|---|---|---|
| FN | Quote fragmentation | `fusebase de'pl'oy` | yes | no | gated command runs ungated |
| FN | Quote fragmentation | `npx prisma mi"grate" deploy` | yes | no | gated command runs ungated |
| FN | Dynamic construction | `CMD='fusebase deploy'; eval "$CMD"` | yes | no | gated command runs ungated |
| FN | Dynamic construction | `$(printf 'fusebase deploy')` | yes | no | gated command runs ungated |
| FP | Quoted message payload | `git commit -m "…denied by FR-06's <recursive force delete> guard"` | no destructive op | yes (deny) | honest commit message impossible via Bash |
| FP | Heredoc body | `python - <<'EOF'` writing docs that quote the pattern | no destructive op | yes (deny) | doc/report authoring impossible via Bash |

**Fixing one direction without structure makes the other worse.** That is the whole reason this is one ticket.

## MUST NOT be attempted (each is a false-negative hole traded for a false-positive fix)

Every narrowing proposed by the FP report is unsafe. Do not implement any of these, and do not accept a PR that does. The last column names the corpus rows that go RED if it is attempted.

| # | Proposal | Why it must not be attempted | Corpus red arm |
|---|---|---|---|
| N1 | Anchor destructive patterns to the **start** of the command string | `safe_thing && rm -rf /data` never matches. Compound lists (`&&`, `;`, `\|\|`, `\|`, newline) put executed commands anywhere in the string; "command position" is a *parse* property, not a string offset. K8's all-match semantics exist precisely because the second half of a compound line is real | `CP-01`..`CP-06`, `WS-06` |
| N2 | Strip / ignore the `-m` payload before matching | `git commit -m "$(rm -rf /)"` — the command substitution is expanded by the shell **before** `git` is ever invoked, so the `rm` executes regardless of what git does with the message. Text inside `-m` is not inert; only *single*-quoted text with no expansion is, and deciding that requires quote-state parsing | `PC-03` (must stay gated), `PC-01` (must stop gating) |
| N3 | Strip / ignore the `-F <file>` payload | Same class as N2 once the argument is anything other than a literal path (`-F "$(…)"`), and `-F` is *already* the sanctioned path — nothing needs stripping | `PC-04` (must stay gated), `PC-02` (must stay open) |
| N4 | Ignore heredoc bodies | `bash <<EOF … EOF` and `sh <<'EOF' … EOF` **execute** the body. A heredoc is data-only when its *consumer* is data-only (`cat > f`, `python -` writing a file), which again is a parse property. Blanket-ignoring bodies makes the heredoc the universal bypass | `CH-02`, `CH-03` (must stay gated) vs `CH-04`..`CH-06` (must stop gating) |
| N5 | Split argv and inspect tokens | **Worsens** the K21 quote-fragmentation FN class: `de'pl'oy` reassembles to `deploy` only if you implement shell quote removal correctly, and a naive `shlex`/whitespace split produces tokens that match neither the raw pattern nor the resolved command. Two evasion classes for the price of one | `QS-01`..`QS-12`, `DC-15` |
| N6 | Ship "phase 1 = FP fix, phase 2 = parser" | Phase 1 *is* one of N1–N5. Under release pressure phase 2 does not arrive, and the gate is left both evadable and obstructive — the exact outcome K3 and M8 reject | (process; no single row) |

## The semantic corpus (delivered, T5)

| Item | Value |
|---|---|
| File | `hooks/tests/fixtures/corpus/command-gate-semantic-corpus.json` |
| Driver | `hooks/tests/test-command-policy.sh` § T5 reporting matrix (`FF_ONLY=command-policy`) |
| Cases | 132 — 91 `should_gate: true`, 41 `should_gate: false` |
| Per case | raw command · `should_gate` (semantic verdict) · `expected_rule` · `expected_actions` · `evasion_class` · `red_arm` (N1..N6) · `source` · `why` |
| Gate behaviour | **reporting only.** Asserts the corpus parses, every case carries the contract fields + a unique id + a declared class, every case produced a recorded verdict, and the six mandated classes + four mandated true negatives are still present. It does **not** assert `should_gate == observed` |
| Why not red | Reddening today's misses forces a narrow patch under gate pressure — i.e. one of N1..N5, or the N6 trap. P8 authorizes corpus + decision only |
| Placement | `fixtures/corpus/`, not `fixtures/` — `run_hook_tests.py:124` globs `fixtures/*.json` and FAILs any file without `_handler`. Covered by the managed-content manifest (same tier as `hooks/tests/lib/*`) |

Coverage against the shape this ticket demanded before implementation:

| Required row class | Corpus ids |
|---|---|
| Real gated commands, plain | `TP-01`..`TP-23` |
| Real gated commands in compound position (N1) | `CP-01`..`CP-06` |
| Quote-fragmented gated commands | `QS-01`..`QS-12` |
| Dynamically constructed gated commands | `DC-01`..`DC-15` |
| Expansion inside a message payload (N2/N3) | `PC-03`, `PC-04` |
| Inert prose quoting a pattern | `PC-01`, `PC-05`..`PC-09`, `CH-01`, `CH-07`, `CH-08` |
| Executing heredoc (N4) | `CH-02`, `CH-03` |
| Data-only heredoc | `CH-04`..`CH-06` |
| Ordinary developer lines (FP baseline, real not invented) | `TN-11`..`TN-23` — verbatim from `workflows/git-discipline.md` and `README.md`, each row citing `file:line` |

Three classes were added beyond the six named in the brief, because true negatives, the FP direction and rule-coverage gaps had no home among them: `plain`, `payload-context`, `alternate-binary`.

## Measured state of the shipped rules

Measured 2026-08-06 against `policies/command-policy.yml` @ `957bcb6` and `hooks/shared/command_policy.py` @ `308f11b` (both unchanged by T5), no approval artifacts present, so "gated" means "could not simply run".

| Evasion class | n | want-gate: caught | want-gate: MISSED | want-open: OVER-FIRED | want-open: ok |
|---|---|---|---|---|---|
| plain | 55 | 29 | 0 | 5 | 21 |
| quote-splitting | 12 | 3 | 9 | 0 | 0 |
| dynamic-construction | 15 | 4 | 11 | 0 | 0 |
| whitespace | 8 | 5 | 2 | 1 | 0 |
| path-form | 11 | 10 | 1 | 0 | 0 |
| comment-heredoc | 8 | 2 | 0 | 6 | 0 |
| encoding | 6 | 0 | 6 | 0 | 0 |
| payload-context | 10 | 2 | 0 | 6 | 2 |
| alternate-binary | 7 | 0 | 7 | 0 | 0 |
| **TOTAL** | **132** | **55** | **36** | **18** | **23** |

False-negative rate 36/91 (40%). False-positive rate 18/41 (44%). On the ordinary-developer sample taken verbatim from shipped docs (`TN-11`..`TN-23`, n=13) the FP rate is **0/13** — the shipped FPs are payload- and heredoc-shaped, not universal.

**What the current rules already catch** — all 23 plain gated commands (`TP-*`), all 6 compound-position rows (`CP-*`, so N1 is already unnecessary as well as unsafe), 10 of 11 path-form rows (`/bin/rm`, `env`, `command`, `busybox`, `\rm`, `~/bin/…`, `./node_modules/.bin/…`, `find -exec rm`), the executing heredocs (`CH-02`, `CH-03`), the `-m`/`-F` substitution rows (`PC-03`, `PC-04`), repeated-space and tab separators (`WS-01`..`WS-03`, `WS-06`, `WS-08`), and 4 dynamic-construction rows (`DC-01`, `DC-03`, `DC-06`, `DC-13`) **by accident** — the literal survives inside the assignment or substitution text; the same command with the literal split (`DC-04`) is missed.

Findings not previously recorded on this ticket:

| # | Finding | Rows |
|---|---|---|
| F1 | **A hard deny silently degrades to an approvable action.** Quote fragmentation and refspec form drop the command out of the `deny` stage but still hit `require_approval`, so an existing artifact permits it | `QS-05` (`rm -r''f /tmp/x` → `destructive_file_delete`), `QS-08` (→ `production_deploy`), `PF-11` (→ `production_deploy`) |
| F2 | **`git -C <dir> push --force origin main` matches nothing at all** — no quoting trick involved. Both git rules require `push` adjacent to `git`; a global option between them defeats them | `PF-09` |
| F3 | **`git push origin +main` is a force push with no `--force` token.** A flag-shaped pattern cannot see a `+` refspec | `PF-11` |
| F4 | **The FP direction is not only prose.** `fusebase<U+00A0>deploy` does not execute (U+00A0 is not a shell separator) but Python's `\s` matches it, so the gate fires on a string that cannot run | `WS-07` |
| F5 | **Two of the brief's own required true negatives are FPs today.** `docker run --rm image` and `charm` are correctly open; `npm rm pkg` and `git rm x` are denied as `destructive_file_delete` | `TN-02`, `TN-05` ok · `TN-03`, `TN-04` FP · `TN-24`..`TN-26` same shape, marked CONTESTED |
| F6 | **13 of 36 misses are outside any command-string parser's reach**: 6 runtime-decoding rows and 7 alternate-binary rows where no shipped rule names the binary at all | `EN-01`..`EN-03`, `EN-05`, `EN-06`, `AB-01`..`AB-07` |

## What each direction can actually close (measured, not projected)

Partition of the 36 misses by the smallest mechanism that closes them:

| Mechanism | Closes | Rows |
|---|---|---|
| A — shell-aware tokenization (quote removal, ANSI-C quoting, line continuation, `${IFS}`, in-string assignment tracking, recursion into `sh -c` string args, match against resolved argv) | **15 of 36** | `QS-01`..`QS-04`, `QS-06`, `QS-07`, `QS-09`..`QS-11`, `DC-05`, `DC-15`, `WS-04`, `WS-05`, `PF-09`, `EN-04` |
| B — conservative deny of commands whose expansion/decode could reach a gated token | **+14** | `DC-02`, `DC-04`, `DC-07`..`DC-12`, `DC-14`, `EN-01`..`EN-03`, `EN-05`, `EN-06` |
| New rules (neither A nor B; a coverage gap, not a parsing gap) | **+7** | `AB-01`..`AB-07` (`unlink`, `truncate -s 0`, `shutil.rmtree`, `fs.rmSync`, `perl unlink`, `gh workflow run`, `terraform apply`) |

**Consequence for scope: option A alone leaves 58% of the measured false negatives open.** A closes the entire quote-splitting class and the whole FP direction; it cannot reach indirection (`npm run deploy:prod`, `make deploy`, `source`), runtime variables (`git push origin "$BRANCH"`), or runtime decoding. `PF-09` is a *pattern* defect, not a parser defect, and is independently fixable — but only as part of a change that does not reintroduce N1..N5.

**Accepted residual under any option:** DC-08..DC-12 and DC-14 are unreachable in principle from a command string (the gated text lives in a file, a package script, or a runtime variable). Process discipline (FR-05/FR-12/FR-19) remains the control there; the hook is defence in depth. This is unchanged from the header of `policies/command-policy.yml` and must stay stated there.

**Platform assumption of the corpus:** POSIX `sh`/`bash` semantics, as executed by MSYS bash on Windows and by any Linux host. PowerShell and `cmd.exe` hosts quote and escape differently (backtick escape, no `$(…)`, different word splitting), so a bash-shaped parser would misjudge them; no PowerShell rows are present. Any implementation must state which host shell it claims to model, and `command-policy.yml` is shell-agnostic today.

## Decisions the operator must lock before implementation

Both are open. Until both are answered this ticket records **`NO IMPLEMENTABLE DECISION`** — the corpus is complete, the direction is not lockable.

**D1 — false-positive tolerance.** What FP rate is acceptable to ship?

| Option | Meaning | Measured consequence |
|---|---|---|
| D1a — zero FP | No command that executes nothing gated may be denied | All 18 over-fired rows must flip. Requires full quote-state + heredoc-consumer parsing (option A), including `CH-04`..`CH-06` where consumer identity alone is not sufficient |
| D1b — bounded FP with a sanctioned escape | Payload/heredoc FPs are accepted while `git commit -F <file>` remains documented | The prerelease complaint stands as-is. 12 of the 18 FP rows are prose/heredoc rows an agent hits while authoring docs or grepping the guard itself (`CH-*`, `PC-01`, `PC-05`..`PC-09`) |
| D1c — FP-free on ordinary usage only | Only the ordinary-developer sample must stay clean | **Already met (0/13).** Choosing this means shipping no FP work at all — state that plainly rather than implying an improvement |

**D2 — is a conservative deny acceptable?** May the gate deny a command merely because an `eval`/substitution/variable/decode pipe *could* reach a gated token?

| Option | Meaning | Measured consequence |
|---|---|---|
| D2-yes | Deny on the possibility | Closes 14 further misses (the whole `encoding` class plus dynamic indirection). Cost is **not measurable from this corpus**: the ordinary sample (n=13) contains no substitutions, so the FP cost of D2-yes on real usage is `UNKNOWN` — locking D2-yes requires a larger real command sample first |
| D2-no | Only structurally resolvable commands are gated | Caps the fix at option A: 15 of 36 misses closed, 21 accepted and documented, including all 6 `encoding` rows |

**Dependency:** D1 and D2 interact. D2-yes raises the FP rate, so a D1a + D2-yes lock is self-contradictory unless "FP" is redefined to exclude deliberate-evasion shapes. Lock D2 first.

**Recommendation (not a lock — Architect + test author; operator/PO decides):** option A plus explicit new rules for the `alternate-binary` gap, with B available as an operator-selectable strictness overlay rather than a default. Do not start any of it until D1 and D2 are recorded here, and do not begin with the FP half alone (N6).

**Before any implementation lands:** each of N1..N5 must be observably RED against the corpus rows named in the MUST NOT table, and the T5 reporting matrix must be converted to an expectation gate in the same change — not later.

## Related

- `docs/backlog/rm-rule-pattern-single-space-gap/` — a narrow pattern gap in the same file, **closed** in the corrections round (T28)
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` — the carrier-enumeration lesson
- `policies/command-policy.yml` header — the truthful statement of both directions + the sanctioned `git commit -F` path
- `docs/hook-coverage.md` — same statement on the coverage surface
- `docs/specs/backlog-triage-execution/execution-plan.md` §3 P8, §4 S4, §7 G4 — the authority for corpus-and-decision-only scope
