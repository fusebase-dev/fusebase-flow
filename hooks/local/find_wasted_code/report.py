"""Render the tracked report. All evidence flows through code_escape (redaction
+ structure-safety) so the report can never trip the staged secret scanner or
break its own Markdown table."""
from __future__ import annotations

from .constants import (
    SCHEMA_VERSION, SENTINEL, RULE_TITLES, code_escape,
    W1, W2, W3, W4, W5, SEV_BLOCKER, SEV_MAJOR, SEV_MINOR,
)

_SEV_ORDER = {SEV_BLOCKER: 0, SEV_MAJOR: 1, SEV_MINOR: 2}
_RULES = (W1, W2, W3, W4, W5)


def _summary_table(findings):
    rows = []
    counts = {}
    for f in findings:
        counts.setdefault(f.rule, {SEV_BLOCKER: 0, SEV_MAJOR: 0, SEV_MINOR: 0})
        counts[f.rule][f.severity] += 1
    lines = ["| Rule | Title | blocker | major | minor |",
             "|---|---|--:|--:|--:|"]
    for r in _RULES:
        c = counts.get(r, {SEV_BLOCKER: 0, SEV_MAJOR: 0, SEV_MINOR: 0})
        lines.append("| %s | %s | %d | %d | %d |"
                     % (r, RULE_TITLES[r], c[SEV_BLOCKER], c[SEV_MAJOR], c[SEV_MINOR]))
    return "\n".join(lines)


def render(findings, cov, date_str, index_id):
    findings = sorted(findings, key=lambda f: (f.rule, _SEV_ORDER.get(f.severity, 9),
                                               f.path, f.line))
    out = [SENTINEL,
           "",
           "# find-wasted-code report",
           "",
           "> Generated %s · schema %d · index %s" % (date_str, SCHEMA_VERSION, index_id),
           "",
           "Static friction-footgun audit (dead-end tool calls, broken links, missing "
           "helpers, footgun configs, silent push-through). **Every row is a review "
           "candidate, not an auto-fix — the operator/PO decides.** `broken` = the "
           "referenced target is provably absent; `candidate` = needs human judgment. "
           "Ambiguous references are listed under Coverage, never as defects.",
           "",
           "## Summary",
           "",
           _summary_table(findings),
           "",
           "- Files scanned: **%d** · findings: **%d** · unresolved (coverage): **%d** · "
           "dismissed by directive: **%d**"
           % (cov.scanned, len(findings), len(cov.unresolved), len(cov.dismissed)),
           ""]

    for r in _RULES:
        rfind = [f for f in findings if f.rule == r]
        if not rfind:
            continue
        out += ["## %s — %s" % (r, RULE_TITLES[r]), "",
                "| id | sev | tier/verdict | location | evidence | note |",
                "|---|---|---|---|---|---|"]
        for f in rfind:
            out.append("| `%s` | %s | %s/%s | `%s:%d` | `%s` | %s |" % (
                f.id, f.severity, f.tier, f.verdict,
                code_escape(f.path), f.line, code_escape(f.evidence), code_escape(f.fp_note)))
        out.append("")
        # suggested fixes (deduped by rule).
        fixes = []
        for f in rfind:
            if f.fix not in fixes:
                fixes.append(f.fix)
        out += ["_Suggested fixes:_ " + " ".join("• " + code_escape(x) for x in fixes), ""]

    # --- coverage -----------------------------------------------------------
    out += ["## Coverage (silence is auditable)", ""]
    out.append("Rules evaluated: %s." % ", ".join(sorted(cov.rules_run)) if cov.rules_run
               else "No rules ran.")
    out.append("")
    if cov.w5_py or cov.w5_sh:
        out += ["### W5 swallowed-error baseline (NOT findings — review candidates)", "",
                "- Python broad/trivial handlers: **%d**" % len(cov.w5_py),
                "- Shell `2>/dev/null` / `|| true` / `|| return 0`: **%d**" % len(cov.w5_sh),
                "",
                "_Intentional swallows can be annotated `find-wasted-code: ignore W5 — <reason>`._",
                ""]
        sample = (cov.w5_py + cov.w5_sh)[:20]
        if sample:
            out.append("<details><summary>sample (first %d)</summary>" % len(sample))
            out.append("")
            for p, ln in sample:
                out.append("- `%s:%d`" % (code_escape(p), ln))
            out += ["", "</details>", ""]
    if cov.unresolved:
        out += ["### Unresolved references (could not prove — not defects)", ""]
        for rule, p, ln, why in sorted(cov.unresolved)[:60]:
            out.append("- %s `%s:%d` — %s" % (rule, code_escape(p), ln, code_escape(why)))
        if len(cov.unresolved) > 60:
            out.append("- … and %d more" % (len(cov.unresolved) - 60))
        out.append("")
    if cov.dismissed:
        out += ["### Dismissed by `ignore` directive: %d" % len(cov.dismissed), ""]
    if cov.skipped:
        by_reason = {}
        for p, reason in cov.skipped:
            by_reason.setdefault(reason, 0)
            by_reason[reason] += 1
        out += ["### Skipped inputs", "",
                ", ".join("%s: %d" % (k, v) for k, v in sorted(by_reason.items())), ""]
    return "\n".join(out).rstrip() + "\n"
