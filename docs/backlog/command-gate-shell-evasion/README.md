# command-gate-shell-evasion

**Status:** promoted — ready to spec as its own Full-lane ticket (own review cycle)
**Found:** 2026-07-28 adversarial review of `approval-binding-and-upgrade-classification` (false negatives) · 2026-07-30 prerelease consumer report (false positives)
**Surface:** `policies/command-policy.yml` + `hooks/shared/command_rules.py` (`rule_matches`)
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

FN cases verified in-process by the review; `hooks/tests/test-command-policy.sh` carries the first two as **documented-limitation** cases asserting today's `allow`, so the future fix flips them rather than being written against no baseline. FP cases were hit by the prerelease reporter while committing the report that describes them; the sanctioned path today is `git commit -F <file>`, stated in `policies/command-policy.yml`'s header.

**Fixing one direction without structure makes the other worse.** That is the whole reason this is one ticket.

## MUST NOT be attempted (each is a false-negative hole traded for a false-positive fix)

Every narrowing proposed by the FP report is unsafe. Do not implement any of these, and do not accept a PR that does:

| # | Proposal | Why it must not be attempted |
|---|---|---|
| N1 | Anchor destructive patterns to the **start** of the command string | `safe_thing && rm -rf /data` never matches. Compound lists (`&&`, `;`, `\|\|`, `\|`, newline) put executed commands anywhere in the string; "command position" is a *parse* property, not a string offset. K8's all-match semantics exist precisely because the second half of a compound line is real |
| N2 | Strip / ignore the `-m` payload before matching | `git commit -m "$(rm -rf /)"` — the command substitution is expanded by the shell **before** `git` is ever invoked, so the `rm` executes regardless of what git does with the message. Text inside `-m` is not inert; only *single*-quoted text with no expansion is, and deciding that requires quote-state parsing |
| N3 | Strip / ignore the `-F <file>` payload | Same class as N2 once the argument is anything other than a literal path (`-F "$(…)"`), and `-F` is *already* the sanctioned path — nothing needs stripping |
| N4 | Ignore heredoc bodies | `bash <<EOF … EOF` and `sh <<'EOF' … EOF` **execute** the body. A heredoc is data-only when its *consumer* is data-only (`cat > f`, `python -` writing a file), which again is a parse property. Blanket-ignoring bodies makes the heredoc the universal bypass |
| N5 | Split argv and inspect tokens | **Worsens** the K21 quote-fragmentation FN class: `de'pl'oy` reassembles to `deploy` only if you implement shell quote removal correctly, and a naive `shlex`/whitespace split produces tokens that match neither the raw pattern nor the resolved command. Two evasion classes for the price of one |
| N6 | Ship "phase 1 = FP fix, phase 2 = parser" | Phase 1 *is* one of N1–N5. Under release pressure phase 2 does not arrive, and the gate is left both evadable and obstructive — the exact outcome K3 and M8 reject |

## Shape of the real fix

Parse **execution structure**: distinguish executed command nodes, compound lists and expansions/substitutions from single-quoted literals and data-only heredoc bodies. Match rules against resolved command nodes, not the raw string.

| Option | Sketch | Main risk |
|---|---|---|
| A — shell-aware tokenization | Real shell grammar; match against *resolved* argv per command node | Parser divergence from the executing shell; MSYS/PowerShell variance |
| B — conservative deny | Deny any command whose `eval`/substitution/variable expansion could reach a gated token | False positives on ordinary usage; pushes users toward workarounds |
| C — post-hoc | Gate at process level (audit executed argv) instead of the command string | Not preventive; needs a host capability Flow does not have |

A closes both directions; B closes only FN and worsens FP; C closes neither at the hook.

## Prerequisite — the semantic corpus (blocks any implementation)

No option ships without it. The corpus is the measurement instrument: it is what makes "did we fix FP without opening FN" an observation rather than a claim. Required shape — every row is `command string → expected verdict → why`, and both directions are represented:

| Class | Rows required | Expected verdict |
|---|---|---|
| Real gated commands, plain | `fusebase deploy`, `npx prisma migrate deploy`, `rm -rf build/` | require the action(s) |
| Real gated commands in compound position | `lint && fusebase deploy`, `a; rm -rf x`, `a \|\| rm -rf x` | require the action(s) — **N1's red arm** |
| Quote-fragmented gated commands | `fusebase de'pl'oy`, `npx prisma mi"grate" deploy` | require the action(s) — today `allow`; the flip is the FN fix |
| Dynamically constructed gated commands | `eval "$CMD"`, `$(printf 'fusebase deploy')`, alias/variable forms | deny or require, per the ticket's explicit decision |
| Expansion inside a message payload | `git commit -m "$(rm -rf /)"` | require `destructive_file_delete` — **N2's red arm** |
| Inert prose quoting a pattern | `git commit -m "documents the rm -rf guard"`, `git commit -F msg.txt` | allow — the FP fix |
| Executing heredoc | `bash <<EOF` / `sh <<'EOF'` with a gated body | require the action(s) — **N4's red arm** |
| Data-only heredoc | `cat > notes.md <<'EOF'` quoting a pattern | allow |
| Ordinary developer lines (false-positive rate baseline) | a real sample, not invented lines | allow |

Two decisions the ticket must take before implementation, both currently open:

1. Should a detected **evasion attempt** deny, or warn-and-require? (K21 left this open.)
2. What false-positive rate on the ordinary-usage sample is acceptable to ship?

Also required: an adversarial red-arm discipline — each of N1–N6, if implemented, must be observably RED against a named corpus row (the table above marks four of them), so the corpus proves the unsafe narrowings are unsafe rather than asserting it.

## Related

- `docs/backlog/rm-rule-pattern-single-space-gap/` — a narrow pattern gap in the same file, **closed** in the corrections round (T28)
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` — the carrier-enumeration lesson
- `policies/command-policy.yml` header — the truthful statement of both directions + the sanctioned `git commit -F` path
- `docs/hook-coverage.md` — same statement on the coverage surface
