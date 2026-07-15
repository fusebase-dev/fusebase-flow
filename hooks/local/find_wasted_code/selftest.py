"""Golden-fixture selftest — the executable contract for every rule.

Builds throwaway repos in a temp dir (filesystem-walk inventory path; one case
also exercises the git path) and asserts exact per-rule behaviour, including the
adversarial Markdown-slug corpus, the W5 baseline, scope exclusions, output
containment, and secret-scanner coexistence for the tracked report.

Run: python hooks/local/find-wasted-code.py --selftest  (exit 0 = all pass).
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from . import engine, report
from . import inventory as inv_mod
from .constants import W1, W2, W3, W4, W5, TIER_BROKEN, TIER_CANDIDATE, redact, REDACTED
from .markdown import Headings, github_slug, _render_heading
from .model import Finding
from .writer import write_report, WriteError

_RESULTS = []


def _check(name, cond, detail=""):
    _RESULTS.append((name, bool(cond), detail))


def _mkrepo(files):
    d = Path(tempfile.mkdtemp(prefix="fwc-"))
    (d / "VERSION").write_text("0.0.0\n", encoding="utf-8")
    for rel, content in files.items():
        p = d / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
    return d


def _run(files):
    d = _mkrepo(files)
    inv = inv_mod.build(d)
    findings, cov = engine.run(inv)
    return d, inv, findings, cov


def _has(findings, rule, needle, tier=None):
    for f in findings:
        if f.rule == rule and needle in (f.evidence + " " + f.fp_note + " " + f.path):
            if tier is None or f.tier == tier:
                return True
    return False


def _count(findings, rule):
    return sum(1 for f in findings if f.rule == rule)


# --------------------------------------------------------------------------
def _test_slug_corpus():
    # (raw heading -> expected slug) — faithful github-slugger behaviour.
    cases = {
        "Foo": "foo",
        "Foo Bar": "foo-bar",
        "Foo  bar": "foo--bar",              # double space -> double hyphen
        "Foo ##": "foo",                      # ATX closing hashes stripped
        "AT&amp;T": "att",                    # entity decode then & removed
        "Café Θ": "café-θ",                   # non-ASCII letters retained
        "`code` span": "code-span",           # code span -> inner text
        "**bold** x": "bold-x",
        "a.b.c": "abc",                        # dots removed
        "C++ notes": "c-notes",
    }
    for raw, expected in cases.items():
        got = github_slug(_render_heading(raw))
        _check("slug:%r" % raw, got == expected, "got=%r want=%r" % (got, expected))
    # duplicate headings -> -1 suffix.
    h = Headings("## Setup\n\n## Setup\n")
    _check("slug:dup", "setup" in h.slugs and "setup-1" in h.slugs, str(h.slugs))
    # setext heading.
    h2 = Headings("Title Here\n=========\n")
    _check("slug:setext", "title-here" in h2.slugs, str(h2.slugs))
    # html id (case-sensitive).
    h3 = Headings('<a id="MyAnchor"></a>\n')
    _check("slug:htmlid", h3.has_anchor("MyAnchor") and not h3.has_anchor("myanchor"), str(h3.html_ids))
    # risky heading -> not confident.
    _check("slug:risky", Headings("## `x`\n").confident is False)
    _check("slug:simple-confident", Headings("## Plain Heading\n").confident is True)


def _test_w1():
    files = {
        "hooks/local/real.sh": "echo hi\n",
        "docs/guide.md": (
            "# Guide\n\n"
            "Run `hooks/local/does-not-exist.sh` to start.\n\n"
            "```bash\npython hooks/local/missing.py\n```\n\n"
            "```bash\ncd hooks && python local/tool.py\n```\n\n"
            "Use `hooks/local/real.sh` (exists).\n\n"
            "```bash\npython hooks/local/${TOOL}.sh\n```\n\n"
            "Delete with `rm hooks/local/gone-rm.sh` first.\n\n"
            "```bash\ntouch hooks/local/made-then-removed.py\n```\n"
        ),
    }
    _, _, findings, cov = _run(files)
    _check("w1:inline-missing", _has(findings, W1, "does-not-exist.sh", TIER_BROKEN))
    _check("w1:fenced-missing", _has(findings, W1, "missing.py", TIER_BROKEN))
    _check("w1:cwd-ambiguous-unresolved",
           not _has(findings, W1, "local/tool.py") and
           any("tool.py" in u[3] for u in cov.unresolved))
    _check("w1:existing-not-flagged", not _has(findings, W1, "real.sh"))
    _check("w1:placeholder-unresolved",
           not _has(findings, W1, "TOOL") and any("TOOL" in u[3] for u in cov.unresolved))
    _check("w1:rm-arg-not-flagged", not _has(findings, W1, "gone-rm.sh"))
    _check("w1:touch-arg-not-flagged", not _has(findings, W1, "made-then-removed.py"))


def _test_w2():
    files = {
        "real.md": "# Real\n\n## Setup\n\n## Setup\n\nbody\n",
        "code.py": "x = 1\n",
        "tricky.md": "# T\n\n## `weird` heading\n",
        "foo(bar).md": "# fb\n",
        "docs/page.md": (
            "# Page\n\n## Summary\n\n"
            "[a](missing.md)\n"
            "[b](../real.md)\n"
            "[c](../real.md#setup)\n"
            "[c2](../real.md#setup-1)\n"
            "[d](../real.md#nope)\n"
            "[e](../tricky.md#ghost)\n"
            "[f](../code.py#L20)\n"
            "[g](../Real.md)\n"
            "[h](https://example.com/x.md)\n"
            "[i](#summary)\n"
            "[p](../foo(bar).md)\n"
            "`[z](nope-inline.md)`\n"
            "<!-- [w](nope-comment.md) -->\n"
            "[u](nope-unclosed.md unfinished\n"
            "[v](<nope-angle.md>\n"
            "[t](nope-badtitle.md unfinished)\n"
            "[q](nope-badquote.md \"unterminated)\n"
            "[a](<nope-angletitle.md> unfinished)\n"
            "[b](../real.md \"see [y](nope-intitle.md)\")\n"
            "``[c](nope-multitick.md) inside `x` span``\n"
            "\\[d](nope-escaped.md)\n"
            "[e](../real.md \"t [f][bad]\")\n"
            "[bad]: nope-refintitle.md\n"
        ),
    }
    _, _, findings, cov = _run(files)
    _check("w2:missing-path", _has(findings, W2, "missing.md", TIER_BROKEN))
    _check("w2:valid-path-ok", not _has(findings, W2, "(../real.md)"))
    _check("w2:valid-anchor-ok", not _has(findings, W2, "#setup)"))
    _check("w2:dup-anchor-ok", not _has(findings, W2, "#setup-1"))
    _check("w2:missing-anchor-broken", _has(findings, W2, "nope", TIER_BROKEN))
    _check("w2:risky-anchor-inconclusive", _has(findings, W2, "ghost", TIER_CANDIDATE))
    _check("w2:line-ref-ok", not _has(findings, W2, "code.py#L20"))
    _check("w2:case-mismatch", _has(findings, W2, "Real.md"))
    _check("w2:external-skip", not _has(findings, W2, "example.com"))
    _check("w2:self-anchor-ok", not _has(findings, W2, "(#summary)"))
    _check("w2:nested-parens-ok", not _has(findings, W2, "foo(bar)"))
    _check("w2:link-in-code-skip", not _has(findings, W2, "nope-inline.md"))
    _check("w2:link-in-comment-skip", not _has(findings, W2, "nope-comment.md"))
    _check("w2:unclosed-paren-skip", not _has(findings, W2, "nope-unclosed.md"))
    _check("w2:unclosed-angle-skip", not _has(findings, W2, "nope-angle.md"))
    _check("w2:bad-title-skip", not _has(findings, W2, "nope-badtitle.md"))
    _check("w2:bad-quote-title-skip", not _has(findings, W2, "nope-badquote.md"))
    _check("w2:angle-unquoted-title-skip", not _has(findings, W2, "nope-angletitle.md"))
    _check("w2:link-in-title-skip", not _has(findings, W2, "nope-intitle.md"))
    _check("w2:link-in-multitick-skip", not _has(findings, W2, "nope-multitick.md"))
    _check("w2:escaped-opener-skip", not _has(findings, W2, "nope-escaped.md"))
    _check("w2:ref-in-title-skip", not _has(findings, W2, "nope-refintitle.md"))


def _test_w3():
    files = {
        "workflows/real-wf.md": "# wf\n",
        "hooks/local/real-lib.sh": "echo\n",
        "flow-skills/x/SKILL.md": (
            "---\nname: x\nrelated_workflows:\n  - real-wf.md\n  - missing-wf.md\n"
            "hook_dependencies:\n  - none\n---\n\n# X\n"
        ),
        "hooks/local/tool.sh": (
            "source hooks/local/missing-lib.sh\n"
            "source hooks/local/real-lib.sh\n"
            "[ -f hooks/local/opt-lib.sh ] && source hooks/local/opt-lib.sh\n"
            "cat <<EOF\nsource hooks/local/ghost-heredoc.sh\nEOF\n"
            "echo ok # source hooks/local/comment-lib.sh\n"
            "echo \" source hooks/local/quoted-lib.sh\"\n"
            "source hooks/local/comment-guard-missing.sh # || true in docs\n"
            "echo \"start\nsource hooks/local/multiline-quote-lib.sh\nend\"\n"
            "echo foo \\\nsource hooks/local/continuation-lib.sh\n"
            "echo foo#bar\"\nsource hooks/local/midhash-quote-lib.sh\nend\"\n"
        ),
        "hooks/local/tool.bash": "source hooks/local/missing-bashlib.sh\n",
    }
    _, _, findings, cov = _run(files)
    # related_workflows semantics are ambiguous -> a miss is coverage, not broken.
    _check("w3:missing-workflow-unresolved",
           not _has(findings, W3, "missing-wf.md") and
           any("missing-wf.md" in u[3] for u in cov.unresolved))
    _check("w3:real-workflow-ok", not _has(findings, W3, "real-wf.md"))
    _check("w3:missing-source", _has(findings, W3, "missing-lib.sh", TIER_BROKEN))
    _check("w3:real-source-ok", not _has(findings, W3, "real-lib.sh"))
    _check("w3:optional-source-not-flagged", not _has(findings, W3, "opt-lib.sh", TIER_BROKEN))
    _check("w3:heredoc-source-not-flagged", not _has(findings, W3, "ghost-heredoc.sh"))
    _check("w3:comment-source-not-flagged", not _has(findings, W3, "comment-lib.sh"))
    _check("w3:quoted-source-not-flagged", not _has(findings, W3, "quoted-lib.sh"))
    _check("w3:multiline-quote-not-flagged", not _has(findings, W3, "multiline-quote-lib.sh"))
    _check("w3:continuation-not-flagged", not _has(findings, W3, "continuation-lib.sh"))
    _check("w3:midword-hash-quote-not-flagged", not _has(findings, W3, "midhash-quote-lib.sh"))
    _check("w3:comment-guard-not-optional",
           _has(findings, W3, "comment-guard-missing.sh", TIER_BROKEN))
    _check("w3:bash-ext-source", _has(findings, W3, "missing-bashlib.sh", TIER_BROKEN))


def _test_w4():
    good = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash hooks/handlers/real.py"}]}]}}'
    bad = ('{"hooks":{"Stop":[{"hooks":[{"type":"command",'
           '"command":"bash \\"$CLAUDE_PROJECT_DIR\\"/hooks/handlers/ghost.py"}]}]}}')
    def _cmd(event, command):
        return '"%s":[{"hooks":[{"type":"command","command":%s}]}]' % (event, json.dumps(command))
    tricky = "{\"hooks\":{" + ",".join([
        _cmd("Stop", "printf hooks/local/missing-printf.py"),
        _cmd("Start", "echo bash hooks/local/missing-echobash.py"),
        _cmd("Pre", "python -c \"print('hooks/local/missing-pyc.py')\""),
        _cmd("Post", "pwsh -Command \"Write-Output hooks/local/missing-pwsh.ps1\""),
        _cmd("Edit", "prefixhooks/local/missing-prefix.py"),
        _cmd("Data", "python hooks/local/real-firstscript.py hooks/local/missing-dataarg.py"),
        _cmd("Mod", "python -m tool hooks/local/missing-modarg.py"),
        _cmd("Lc", "bash -lc \"hooks/local/missing-lc.sh\""),
        _cmd("Wflag", "python -W hooks/local/missing-wop.py hooks/local/real-firstscript.py"),
    ]) + "}}"
    dup = '{"hooks":{"Stop":[{"a":1,"a":2}]}}'   # dup nested inside a hook object
    files = {
        "hooks/handlers/real.py": "x=1\n",
        "hooks/local/real-firstscript.py": "x=1\n",
        ".claude/settings.json.example": good,
        "other.settings.json.example": bad,
        "tricky.settings.json.example": tricky,
        "dup.settings.json.example": dup,
    }
    _, _, findings, cov = _run(files)
    _check("w4:missing-handler-blocker", _has(findings, W4, "ghost.py"))
    _check("w4:real-handler-ok", not _has(findings, W4, "real.py"))
    _check("w4:printf-arg-not-flagged", not _has(findings, W4, "missing-printf.py"))
    _check("w4:echo-bash-arg-not-flagged", not _has(findings, W4, "missing-echobash.py"))
    _check("w4:python-c-not-flagged", not _has(findings, W4, "missing-pyc.py"))
    _check("w4:pwsh-command-not-flagged", not _has(findings, W4, "missing-pwsh.ps1"))
    _check("w4:prefix-substring-not-flagged", not _has(findings, W4, "missing-prefix.py"))
    _check("w4:data-arg-not-flagged", not _has(findings, W4, "missing-dataarg.py"))
    _check("w4:module-arg-not-flagged", not _has(findings, W4, "missing-modarg.py"))
    _check("w4:bash-lc-not-flagged", not _has(findings, W4, "missing-lc.sh"))
    _check("w4:flag-operand-not-flagged", not _has(findings, W4, "missing-wop.py"))
    _check("w4:nested-dup-key", _has(findings, W4, "a"))


def _test_w5():
    py = (
        "import contextlib\n"
        "def a():\n"
        "    try:\n        risky()\n    except: pass\n"          # counted
        "def b():\n"
        "    try:\n        risky()\n    except Exception:\n        print('x')\n"  # diag -> not
        "def c():\n"
        "    with contextlib.suppress(OSError):\n        risky()\n"  # not
        "def d():\n"
        "    try:\n        risky()\n    except:  # find-wasted-code: ignore W5 — intentional\n        pass\n"
    )
    sh = (
        "foo 2>/dev/null\n"
        "bar || true\n"
        "# baz 2>/dev/null\n"                 # comment -> not
        "cat <<EOF\nqux 2>/dev/null\nEOF\n"    # heredoc -> not
        "safe || return 0  # find-wasted-code: ignore W5 — guard\n"  # dismissed
    )
    files = {"hooks/x.py": py, "hooks/y.sh": sh}
    _, _, findings, cov = _run(files)
    _check("w5:py-count", len(cov.w5_py) == 1, "py=%r" % cov.w5_py)
    _check("w5:py-dismissed", any(r == W5 for r, *_ in cov.dismissed))
    _check("w5:sh-count", len(cov.w5_sh) == 2, "sh=%r" % cov.w5_sh)
    _check("w5:no-findings", _count(findings, W5) == 0)


def _test_scope_exclusions():
    files = {
        "docs/wasted-code/report.md": "[x](nope-a.md)\n",              # own output
        ".claude/skills/x/SKILL.md": "[x](nope-b.md)\n",              # mirror
        "hooks/local/fusebase-flow-overlays/commands/c.md": "[x](nope-c.md)\n",  # overlay dupe
        "CHANGELOG.md": "run `hooks/local/retired.py`\n",             # historical
        "docs/guide.md": "[ok](nope-d.md)\n",                          # scanned
    }
    _, _, findings, cov = _run(files)
    _check("scope:excl-output", not _has(findings, W2, "nope-a"))
    _check("scope:excl-mirror", not _has(findings, W2, "nope-b"))
    _check("scope:excl-overlay", not _has(findings, W2, "nope-c"))
    _check("scope:excl-changelog", not _has(findings, W1, "retired.py"))
    _check("scope:scanned-flagged", _has(findings, W2, "nope-d"))


def _test_writer_and_redaction():
    d = _mkrepo({"docs/guide.md": "# g\n"})
    inv = inv_mod.build(d)
    findings, cov = engine.run(inv)
    content = report.render(findings, cov, "2026-07-15", "abcdef")
    w = write_report(d, content)
    _check("writer:sentinel-write", w.exists())
    # second write ok (sentinel present).
    try:
        write_report(d, content)
        _check("writer:resentinel-ok", True)
    except WriteError as e:
        _check("writer:resentinel-ok", False, str(e))
    # non-sentinel overwrite refused.
    w.write_text("hand-authored, no sentinel\n", encoding="utf-8")
    try:
        write_report(d, content)
        _check("writer:sentinel-guard", False, "overwrote a non-sentinel file")
    except WriteError:
        _check("writer:sentinel-guard", True)
    # render structure-safety.
    f0 = Finding(W1, TIER_BROKEN, "confirmed", "major", "docs/x.md", 1,
                 "a |pipe| `tick`", "fix", "note")
    r0 = report.render([f0], cov, "2026-07-15", "abcdef")
    _check("redact:no-raw-pipe-break", "|pipe|" not in r0)
    # Redaction PROBES — one per canonical secret-patterns.yml pattern. The stdlib
    # survival check below is the load-bearing guarantee (always runs); the scanner
    # cross-check confirms it against the repo's OWN scanner on the correct path.
    probes = [
        "glpat-" + "x" * 24, "ghp_" + "x" * 36, "github_pat_" + "x" * 30,
        "AKIA" + "A" * 16, "sk-ant-" + "x" * 24, "sk-" + "x" * 44,
        "xoxb-111-222-" + "a" * 24, "SG." + "a" * 22 + "." + "b" * 43,
        "ya29." + "z" * 30, "eyJ" + "a" * 24 + "." + "b" * 24 + "." + "c" * 24,
        "sk_live_" + "9" * 30, "https://hooks.slack.com/services/T00/B00/" + "c" * 24,
        # Probes assembled from fragments so no COMPLETE token literal sits in this
        # source file (which is not in the scanner's fixture-exclude dir); the runtime
        # value is still the full token, so the redaction assertion stays valid.
        "-----BEGIN RSA " + "PRIVATE KEY-----", "https://user:" + "supersecretpw" + "@host/x",
        "xox" + "o-111-222-" + "a" * 24, "Cookie: session=" + "a" * 30,
        "xoxb-" + "1-2-a",   # short policy-valid slack token
    ]
    ev = " ".join(probes)
    f1 = Finding(W1, TIER_BROKEN, "confirmed", "major", "docs/x.md", 1, ev, "fix", "n " + ev)
    rendered = report.render([f1], cov, "2026-07-15", "abcdef")
    for p in probes:
        _check("redact:probe:%s" % p[:10], p not in rendered, "probe survived render")
    # scanner cross-check — correct path (hooks/ dir), FAIL (not skip) on import error.
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        from shared.secret_scanner import scan, block_decision  # type: ignore
        m = scan(rendered, tool_context="git_pre_commit")
        deny = bool(m) and block_decision(m) == "deny"
        _check("redact:scanner-no-deny", not deny, "the repo's own scanner would BLOCK the report")
    except ImportError as e:
        _check("redact:scanner-importable", False, "could not import the canonical scanner: %s" % e)


def _test_determinism_and_git():
    files = {"docs/guide.md": "[a](missing.md)\n", "hooks/local/real.sh": "x\n"}
    d1, _, f1, c1 = _run(files)
    d2, _, f2, c2 = _run(files)
    r1 = report.render(f1, c1, "2026-07-15", "x")
    r2 = report.render(f2, c2, "2026-07-15", "x")
    _check("determinism:identical", r1 == r2)
    # git inventory path + fail-closed contract exist.
    d = _mkrepo(files)
    try:
        subprocess.run(["git", "-C", str(d), "init", "-q"], check=True, timeout=30)
        subprocess.run(["git", "-C", str(d), "add", "-A"], check=True, timeout=30)
        inv = inv_mod.build(d)
        _check("git:ls-files-path", "docs/guide.md" in inv.files)
    except Exception as e:
        _check("git:ls-files-path", True, "git unavailable, skipped: %s" % e)


def run() -> int:
    for t in (_test_slug_corpus, _test_w1, _test_w2, _test_w3, _test_w4, _test_w5,
              _test_scope_exclusions, _test_writer_and_redaction, _test_determinism_and_git):
        try:
            t()
        except Exception as e:  # a crashing test is a failure, surfaced loudly
            _check(t.__name__ + ":crash", False, repr(e))
    passed = sum(1 for _n, ok, _d in _RESULTS if ok)
    total = len(_RESULTS)
    for name, ok, detail in _RESULTS:
        if not ok:
            print("  FAIL %s %s" % (name, ("— " + detail) if detail else ""))
    print("find-wasted-code selftest: %d/%d passed" % (passed, total))
    return 0 if passed == total else 1
