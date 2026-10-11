#!/usr/bin/env python3
from pathlib import Path
import re
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "hooks"))
from shared import policy_loader, secret_scanner

passed = failed = 0


def check(name, good):
    global passed, failed
    passed += bool(good)
    failed += not good
    print(("PASS: " if good else "FAIL: ") + "secret-patterns " + name)


# Construct tokens and slug probes at runtime; HEAD's old policy scans this upgrade (T133).
body = "aB3c" * 40
url_body = "aB3_" * 40
shapes = {
    "openai_api_key": {
        "legacy": "sk-" + body[:48],
        "proj": "sk-" + "proj-" + url_body[:156],
        "svcacct": "sk-" + "svcacct-" + url_body[:140],
        "admin": "sk-" + "admin-" + url_body[:120],
        "None": "sk-" + "None-" + url_body[:120],
    },
    "anthropic_api_key": {
        "api03": "sk-" + "ant-api03-" + url_body[:93] + "-" + body[:6] + "AA",
        "admin01": "sk-" + "ant-admin01-" + url_body[:93] + "AA",
        "oat01": "sk-" + "ant-oat01-" + url_body[:93] + "AA",
    },
    "github_personal_access_token": {
        "ghp": "gh" + "p_" + body[:36],
        "ghs": "gh" + "s_" + body[:36],
    },
    "gitlab_personal_access_token": {"glpat": "gl" + "pat-" + url_body[:20]},
    "aws_access_key_id": {
        "akia": "AK" + "IA" + "ABCD2345" * 2,
        "doc-example": "AK" + "IA" + "IOSFODNN7" + "EXAMPLE",
    },
    "google_oauth_token": {"ya29": "ya" + "29." + url_body},
}
contexts = {
    "line-start": "{k}",
    "env-equals": "API_KEY={k}",
    "env-quoted": 'API_KEY="{k}"',
    "json": '{{"apiKey": "{k}"}}',
    "yaml": "api_key: {k}",
    "bearer": "Authorization: Bearer {k}",
    "single-quote": "key='{k}'",
    "backtick": "`{k}`",
    "query": "https://x.io/v1?key={k}",
    "path-segment": "https://x.io/keys/{k}",
    "cli-flag": "--api-key {k}",
    "cli-flag-equals": "--api-key={k}",
    "paren": "f({k})",
    "tab": "\t{k}",
    "comma": "a,{k}",
    "glued-underscore": "KEY_{k}",
    "glued-hyphen": "x-{k}",
}
slugs = {
    "reproducer": "".join(("https://help.example.com/e-signature-ta", "sk-", "action-",
                            "automate-your-document-signing-process")),
    "help-desk": "".join(("/blog/help-de", "sk-", "software-comparison-",
                           "for-small-teams-in-2026-guide")),
    "risk-assessment": "".join(("ri", "sk-", "assessment-framework-",
                                 "for-enterprise-vendors-and-partners-v2")),
    "ask-confirmation": "".join(("a", "sk-", "the-user-for-confirmation-",
                                  "before-running-the-destructive-step")),
    "product-catalogue": "".join(("product-", "sk-", "catalogue-entry-",
                                   "with-a-very-long-descriptive-tail-x")),
    "ant-colony": "".join(("/docs/ta", "sk-", "ant-",
                            "colony-optimisation-walkthrough-for-beginners")),
    "highs-and-lows": "".join(("hi", "ghs_", "and_lows_of_the_quarterly_",
                               "budget_review_meeting_notes")),
    "glpat-word": "big" + "gl" + "pat-" + "x" * 22,
    "akia-word": "QUERY" + "AK" + "IA" + "ABCDEFGHIJKLMNOP",
    "papaya-body": "/papa" + "ya" + "29." + "x" * 24,
    "papaya-recipe": "papa" + "ya" + "29." + "recipe-with-mango-and-lime-juice",
}
reproducer = slugs["reproducer"]

# Load the shipped policy directly so per-clone overrides cannot blind the release oracle.
policy = policy_loader._load_yaml(ROOT / "policies/secret-patterns.yml")
patterns = policy.get("patterns", [])
compile_errors = []
for entry in patterns:
    try:
        re.compile(entry["pattern"])
    except re.error:
        compile_errors.append(entry["id"])
check("every-pattern-compiles", bool(patterns) and not compile_errors)
unbounded = [entry["id"] for entry in patterns
             if any("*" in body or "+" in body
                    for body in re.findall(r"\(\?[=!](.*?)\)", entry["pattern"]))]
check("no-unbounded-lookahead", not unbounded)

tp_total = tp_passed = fp_total = fp_passed = 0
with patch.object(secret_scanner, "get_policy", return_value=policy):
    for pattern_id, variants in shapes.items():
        for shape, key in variants.items():
            good = True
            for context in contexts.values():
                matches = secret_scanner.scan(context.format(k=key), tool_context="git_pre_commit")
                caught = any(match.pattern_id == pattern_id and match.action == "block"
                             for match in matches)
                tp_total += 1
                tp_passed += caught
                good = good and caught
            check("tp-%s-%s-all-17-contexts" % (pattern_id, shape), good)
    for name, slug in slugs.items():
        matches = secret_scanner.scan(slug, tool_context="git_pre_commit")
        clean = not any(match.action == "block" for match in matches)
        fp_total += 1
        fp_passed += clean
        check("fp-%s" % name, clean)
    matches = secret_scanner.scan("docs: " + reproducer + "\n", tool_context="git_pre_commit")
    check("reproducer-line-clean", not any(match.action == "block" for match in matches))

old_openai = "sk-" + r"[A-Za-z0-9_-]{40,}"
check("fp-arm-bites", re.search(old_openai, reproducer) is not None)
print("[secret-patterns-matrix] %d/%d PASS; TP %d/%d; FP %d/%d" % (
    passed, passed + failed, tp_passed, tp_total, fp_passed, fp_total))
sys.exit(failed)
