"""W4 — footgun config: a settings hook wired to a handler that does not exist.

Scope is the precise, stdlib-JSON sub-case only: parse `*settings*.json.example`,
walk every hook `command`, extract the handler script path(s) UNDER a real hook
dir, and confirm each exists. A hook wired to a missing handler silently never
fires — a real footgun, severity blocker. Duplicate JSON keys (last-wins is a
footgun) are collected across every nested object, not just the root.
The fuzzy dead-policy-key analysis is deliberately out of v1 (no stdlib YAML,
high false-positive) and noted as future in the rule catalog.
"""
from __future__ import annotations

import json
import re

from .constants import W4, TIER_BROKEN, CONFIRMED, SEV_BLOCKER, SEV_MINOR, strip_root_prefix
from .model import Finding

# A token is a handler ONLY when the whole token (quotes + root-prefix removed) IS a
# path under a real hook dir — anchored, so `prefixhooks/local/x.py` or a path buried
# inside `print('hooks/local/x.py')` never matches.
_HANDLER_FULL = re.compile(
    r"(?:hooks/handlers|hooks/local|hooks/shared|hooks/git|\.claude/hooks|\.agents/hooks)"
    r"/[\w./-]+\.(?:py|sh|js|ps1|cmd)")
_INTERP = {"bash", "sh", "python", "python3", "py", "node", "pwsh", "powershell"}
_ENV_PREFIX = {"sudo", "env", "exec", "command"}
_ENVVAR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _token_handler(tok):
    t = tok.replace('"', "").replace("'", "")
    stripped, _ = strip_root_prefix(t)
    return _HANDLER_FULL.fullmatch(stripped)


def _unbalanced_quote(tok):
    return tok.count('"') % 2 == 1 or tok.count("'") % 2 == 1


def _wired_handlers(cmd):
    """Handler paths ONLY for the pristine, unambiguous Flow shapes: after skipping
    sudo/env/exec + VAR=val, either the head IS a handler script, or the head is an
    interpreter with NO flags whose FIRST argument is the script (its remaining args
    are data). ANY flag (`-c`/`-W`/`-m`/`-lc`/…) or a token with an unbalanced quote
    (a space-containing quoted path split apart) is ambiguous → bail with NO
    handlers. Conservative by design: ambiguity is a false negative, never a false
    confirm. The one Flow wrapper that forwards a handler, `run-handler.sh <handler>`,
    is honoured."""
    toks = cmd.split()
    if any(_unbalanced_quote(t) for t in toks):
        return []                         # a quoted path with spaces was split — unparseable.
    i = 0
    while i < len(toks) and (toks[i].strip("\"'") in _ENV_PREFIX
                             or _ENVVAR_RE.match(toks[i].strip("\"'"))):
        i += 1
    if i >= len(toks):
        return []
    head = toks[i].strip("\"'")
    args = toks[i + 1:]
    if head not in _INTERP:
        m = _token_handler(toks[i])       # the command IS a handler script.
        return [m.group(0)] if m else []
    if any(a.strip("\"'").startswith("-") for a in args):
        return []                         # any flag may take an operand — ambiguous, bail.
    if not args:
        return []
    m = _token_handler(args[0])           # first arg is the script; the rest are data.
    if not m:
        return []
    out = [m.group(0)]
    if m.group(0).endswith("run-handler.sh") and len(args) > 1:
        mh = _token_handler(args[1])      # the wrapper forwards its next arg as the handler.
        if mh:
            out.append(mh.group(0))
    return out


def _parse_with_dups(text):
    """json.loads that also returns every duplicate key seen in ANY nested object."""
    dups = []

    def hook(pairs):
        seen = set()
        d = {}
        for k, v in pairs:
            if k in seen:
                dups.append(k)
            seen.add(k)
            d[k] = v
        return d

    return json.loads(text, object_pairs_hook=hook), dups


def _iter_commands(obj):
    hooks = obj.get("hooks") if isinstance(obj, dict) else None
    if not isinstance(hooks, dict):
        return
    for _event, entries in hooks.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            inner = entry.get("hooks")
            if not isinstance(inner, list):
                continue
            for h in inner:
                if isinstance(h, dict) and isinstance(h.get("command"), str):
                    yield h["command"]


def scan_w4(inv, cov, path, text):
    cov.rules_run.add(W4)
    try:
        obj, dups = _parse_with_dups(text)
    except (json.JSONDecodeError, ValueError) as e:
        cov.unresolve(W4, path, 1, "settings JSON did not parse: %s" % e)
        return
    if dups:
        yield Finding(W4, TIER_BROKEN, CONFIRMED, SEV_MINOR, path, 1,
                      ", ".join(sorted(set(dups))),
                      "Remove duplicate JSON keys (last value silently wins).",
                      "duplicate keys in settings JSON")
    seen = set()
    for cmd in _iter_commands(obj):
        for norm in _wired_handlers(cmd):
            if norm in seen:
                continue
            seen.add(norm)
            if inv.exists(norm):
                continue
            real = inv.case_mismatch(norm)
            note = ("case-mismatch: tracked as %s" % real) if real else \
                "settings wires a hook to a handler that does not exist (hook silently never fires)"
            yield Finding(W4, TIER_BROKEN, CONFIRMED, SEV_BLOCKER, path, 1,
                          norm, "Restore the handler or fix the command path.", note)
