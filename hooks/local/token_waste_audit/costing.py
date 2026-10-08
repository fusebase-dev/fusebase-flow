from collections import Counter
from datetime import datetime
from decimal import Decimal

from .common import Finding, LIVE, TOP_SINKS

RATE_DATE = "2026-10"
COST_LABEL = "list-price estimate (rates as of %s); subscription billing differs" % RATE_DATE
RATES = {model: tuple(map(Decimal, rates)) for model, rates in {
    "claude-opus-5-5": ("4", "20", "0.20"),
    "claude-opus-5": ("5", "25", "0.50"),
    "claude-sonnet-5": ("2", "10", "0.20"),
    "claude-fable-5-1": ("10", "50", "0.25"),
    "claude-haiku-4-5": ("1", "5", "0.10"),
}.items()}
CATEGORIES = ("cache read", "cache write 5m", "cache write 1h", "uncached input", "output")
MILLION = Decimal(1_000_000)


def requests(s, *, include_synthetic=True):
    return sorted((r for r in [*s["requests_by_id"].values(), *s["requests_no_id"]]
                   if include_synthetic or r.get("model") != "<synthetic>"),
                  key=lambda r: r.get("seq", 0))


def token_parts(request):
    u = request["usage"]
    split = u.get("cache_creation") or {}
    short = split.get("ephemeral_5m_input_tokens") or 0
    long = split.get("ephemeral_1h_input_tokens") or 0
    creation = max(u.get("cache_creation_input_tokens") or 0, short + long)
    return dict(zip(CATEGORIES, (u.get("cache_read_input_tokens") or 0,
        short + max(creation - short - long, 0), long,
        u.get("input_tokens") or 0, u.get("output_tokens") or 0)))


def rates_for(request):
    card = RATES.get(request.get("model"))
    if card is None:
        return None
    inp, out, read = card
    return dict(zip(CATEGORIES, (read, inp * Decimal("1.25"), inp * 2, inp, out)))


def request_costs(request):
    rates = rates_for(request)
    if rates is None:
        return None
    return {category: tokens * rates[category] / MILLION
            for category, tokens in token_parts(request).items()}


def context(request):
    parts = token_parts(request)
    return sum(parts[c] for c in CATEGORIES[:4])


def attribution(items):
    tokens = dict.fromkeys(CATEGORIES, 0)
    costs = dict.fromkeys(CATEGORIES, Decimal(0))
    unpriced = Counter()
    for s in items:
        for request in requests(s):
            for category, count in token_parts(request).items():
                tokens[category] += count
            priced = request_costs(request)
            if priced is None:
                unpriced[request.get("model") or "<missing>"] += 1
            else:
                for category, cost in priced.items():
                    costs[category] += cost
    return {"tokens": tokens, "costs": costs, "unpriced": unpriced,
            "total": sum(costs.values())}


def residency(s):
    reqs = requests(s, include_synthetic=False)
    contexts = [context(r) for r in reqs]
    return {"peak": max(contexts, default=0),
            "average": sum(contexts) / len(contexts) if contexts else 0,
            "requests": len(reqs), "compactions": s.get("compactions", 0),
            "cache_read_cost": attribution([s])["costs"]["cache read"]}


def residency_finding(session):
    stats = [residency(s) for s in [session, *session.get("subagents", [])]]
    total = sum(s["cache_read_cost"] for s in stats)
    large = [s for s in stats if s["peak"] >= 500_000]
    held = sum(s["cache_read_cost"] for s in large)
    if total and held / total >= Decimal("0.5"):
        return Finding("context-residency",
            "%d transcripts peaked ≥500k and hold %.1f%% of cache-read cost" % (
                len(large), 100 * held / total),
            "FR-26 TE-19 — bounded residency: fresh worker per task group / rotate at milestones (token-economy)",
            LIVE, "cost signal", "observed cache-read cost; not an avoidable-spend estimate",
            (), held)
    return None


def timestamp(raw):
    try:
        parsed = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        return parsed.timestamp() if parsed.tzinfo else None
    except (ValueError, TypeError, OverflowError, OSError):
        return None


def cache_rewrites(s):
    previous = None
    rows = []
    for request in requests(s, include_synthetic=False):
        start = timestamp(request.get("timestamp"))
        gap = start - previous if start is not None and previous is not None else None
        previous = start
        split = request["usage"].get("cache_creation") or {}
        ttl = (3600 if (split.get("ephemeral_1h_input_tokens") or 0) > 0
               else 300 if (split.get("ephemeral_5m_input_tokens") or 0) > 0 else None)
        parts = token_parts(request)
        creation = parts["cache write 5m"] + parts["cache write 1h"]
        if ttl is None or gap is None or gap <= ttl or creation < 100_000:
            continue
        priced = request_costs(request)
        cost = None if priced is None else priced["cache write 5m"] + priced["cache write 1h"]
        rows.append({"tokens": creation, "gap": gap, "ttl": ttl, "cost": cost})
    return rows


def cache_rewrite_findings(s):
    return [Finding("cache-rewrite", "Cache creation %d tokens after %.1f min gap (TTL %s)" % (
        row["tokens"], row["gap"] / 60, "1h" if row["ttl"] == 3600 else "5m"),
        "FR-26 — wait under cache TTL / record-then-read (token-economy)", LIVE,
        "cost signal", "start-to-start gap exceeded this request's explicit creation TTL",
        (row["cost"] is None, -(row["cost"] or 0), -row["tokens"]), row["cost"])
        for row in cache_rewrites(s)]


def request_index(s):
    return {r.get("key", r.get("request_id")): r for r in requests(s)}


def payload_cost(s, index, seq, tokens, category="uncached input"):
    request = index.get(s.get("tool_requests", {}).get(seq))
    rates = rates_for(request) if request else None
    return Decimal(str(tokens)) * rates[category] / MILLION if rates else None


def sum_known(costs):
    known = [cost for cost in costs if cost is not None]
    return sum(known, Decimal(0)) if known else None


def polling_cost(s, command):
    index = request_index(s)
    wakes = [index[key] for key in s.get("bash_requests", {}).get(command, ()) if key in index]
    costs = [context(r) * rates_for(r)["cache read"] / MILLION
             for r in wakes if rates_for(r) is not None]
    return len(wakes), sum(context(r) for r in wakes), sum(costs) if costs else None


def cost_order(item):
    f = item[1]
    return f.cost is None, -(f.cost or 0)


def money(cost):
    return "unpriced" if cost is None else "$%.6f" % cost


def cost_section(sessions):
    lines = ["## Cost attribution", "", COST_LABEL, ""]
    for session in sessions:
        scopes = [("main", [session])]
        if not session.get("main_only"):
            scopes.append(("sub-agents", session.get("subagents", [])))
        data = [(scope, attribution(items)) for scope, items in scopes]
        total = sum(a["total"] for _, a in data)
        lines += ["### %s" % session["file"], "",
            "| Scope | Category | Tokens (including unpriced) | Estimated USD | Share of session priced cost |",
            "|---|---|---|---|---|"]
        rows = [(scope, c, a["tokens"][c], a["costs"][c]) for scope, a in data for c in CATEGORIES]
        for scope, c, tokens, cost in sorted(rows, key=lambda r: -r[3]):
            lines.append("| %s | %s | %d | %s | %.1f%% |" % (
                scope, c, tokens, money(cost), 100 * cost / total if total else 0))
        for scope, a in data:
            lines.append("%s: %s (%.1f%% of priced session cost)" % (
                scope, money(a["total"]), 100 * a["total"] / total if total else 0))
        lines += ["Session total: %s" % money(total)]
        unknown = Counter()
        for _, a in data:
            unknown.update(a["unpriced"])
        for model, count in sorted(unknown.items()):
            lines.append("%d requests unpriced (model %s) — tokens only; excluded from USD" % (count, model))
        if session.get("main_only"):
            lines.append("Sub-agents: not parsed (--main-only)")
        lines.append("")
    return lines


def context_section(sessions):
    lines = ["## Context residency", "",
        "Context = cache read + cache creation + uncached input. Compactions count compact_boundary events only.",
        "Top-10 transcripts per session by priced cache-read cost; unknown-model costs excluded."]
    for session in sessions:
        rows = [(s, residency(s)) for s in [session, *session.get("subagents", [])]]
        lines += ["", "### %s" % session["file"], "",
            "| Transcript | Cache-read USD | Peak context | Average context | Requests | Compactions |",
            "|---|---|---|---|---|---|"]
        for s, stats in sorted(rows, key=lambda r: -r[1]["cache_read_cost"])[:TOP_SINKS]:
            lines.append("| %s | %s | %d | %.1f | %d | %d |" % (
                s.get("label", s["file"]), money(stats["cache_read_cost"]), stats["peak"],
                stats["average"], stats["requests"], stats["compactions"]))
    lines += ["", "## Cache rewrite after expiry", "",
        "Counts and cost cover all matches before the session row cap; explicit TTL only. These are cost signals.",
        "| Session | Scope | Rewrites | Cache creation tokens | Estimated USD | Unpriced rewrites |",
        "|---|---|---|---|---|---|"]
    for session in sessions:
        scopes = [("main", [session])]
        if not session.get("main_only"):
            scopes.append(("sub-agents", session.get("subagents", [])))
        for scope, items in scopes:
            rows = [row for s in items for row in cache_rewrites(s)]
            lines.append("| %s | %s | %d | %d | %s | %d |" % (
                session["file"], scope, len(rows), sum(r["tokens"] for r in rows),
                money(sum_known([r["cost"] for r in rows]) if rows else Decimal(0)),
                sum(r["cost"] is None for r in rows)))
    return lines
