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


def advisor_iterations(s):
    return [{"usage": it, "model": it.get("model")}
            for its in s.get("advisor_by_request", {}).values() for it in its]


def advisor_by_model(items):
    rows = {}
    for s in items:
        for it in advisor_iterations(s):
            parts, priced = token_parts(it), request_costs(it)
            row = rows.setdefault(it["model"] or "<missing>", {
                "iterations": 0, "input": 0, "output": 0,
                "cost": None if priced is None else Decimal(0)})
            row["iterations"] += 1
            row["input"] += context(it)
            row["output"] += parts["output"]
            if priced is not None:
                row["cost"] += sum(priced.values())
    return rows


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
    # TRIPWIRE: never add advisor to CATEGORIES — token_parts/rates_for zip over it.
    advisor = advisor_by_model(items)
    advisor_cost = sum((r["cost"] for r in advisor.values() if r["cost"] is not None), Decimal(0))
    return {"tokens": tokens, "costs": costs, "unpriced": unpriced,
            "advisor_tokens": sum(r["input"] + r["output"] for r in advisor.values()),
            "advisor_cost": advisor_cost,
            "advisor_unpriced": Counter({m: r["iterations"] for m, r in advisor.items() if r["cost"] is None}),
            "total": sum(costs.values()) + advisor_cost}


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
            (), held, "", "observed")
    return None


def timestamp(raw):
    try:
        parsed = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        return parsed.timestamp() if parsed.tzinfo else None
    except (ValueError, TypeError, OverflowError, OSError):
        return None


def rewrite_requests(s):
    previous = prior = None
    for request in requests(s, include_synthetic=False):
        start = timestamp(request.get("timestamp"))
        gap = start - previous if start is not None and previous is not None else None
        previous, before = start, prior
        prior = request
        split = request["usage"].get("cache_creation") or {}
        ttl = (3600 if (split.get("ephemeral_1h_input_tokens") or 0) > 0
               else 300 if (split.get("ephemeral_5m_input_tokens") or 0) > 0 else None)
        parts = token_parts(request)
        creation = parts["cache write 5m"] + parts["cache write 1h"]
        if ttl is None or gap is None or gap <= ttl or creation < 100_000:
            continue
        priced = request_costs(request)
        cost = None if priced is None else priced["cache write 5m"] + priced["cache write 1h"]
        yield request, before, {"tokens": creation, "gap": gap, "ttl": ttl, "cost": cost}


def cache_rewrites(s):
    return [row for _request, _before, row in rewrite_requests(s)]


def reusable_prefix(request, before):
    # TRIPWIRE: cap at the prior request's cached prefix; new-turn tokens are written under 1h too.
    now, then = token_parts(request), token_parts(before)
    cached = then["cache read"] + then["cache write 5m"] + then["cache write 1h"]
    return max(0, min(now["cache write 5m"] + now["cache write 1h"], cached - now["cache read"]))


def rewrite_share(items):
    """Sub-agent 1h-TTL break-even inputs (decision F; premise review F12)."""
    out = {"written": 0, "rewritten": 0, "written_1h": 0, "models": set(), "unpriced": 0,
           "cost_5m": Decimal(0), "cost_1h": Decimal(0)}
    for s in items:
        hits = {id(request): reusable_prefix(request, before)
                for request, before, row in rewrite_requests(s) if row["ttl"] == 300 and row["gap"] <= 3600}
        for request in requests(s):
            parts = token_parts(request)
            written = parts["cache write 5m"] + parts["cache write 1h"]
            if not written:
                continue
            rewritten = hits.get(id(request), 0)
            out["written"] += written
            out["rewritten"] += rewritten
            out["written_1h"] += parts["cache write 1h"]
            card = RATES.get(request.get("model"))
            if card is None:
                out["unpriced"] += 1
                continue
            inp, _out, read = card
            out["models"].add(request["model"])
            out["cost_5m"] += written * inp * Decimal("1.25") / MILLION
            out["cost_1h"] += ((written - rewritten) * inp * 2 + rewritten * read) / MILLION
    return out


def break_even(model):
    inp, _out, read = RATES[model]
    return read / inp, Decimal("0.75") / (2 - read / inp)


def share_line(label, share):
    written, rewritten = share["written"], share["rewritten"]
    head = "Sub-agent rewrites at 5-60 min gaps (%s): %d of %d cache-write tokens" % (
        label, rewritten, written)
    if not written:
        return head + " (no sub-agent cache writes)"
    models = sorted(share["models"])
    if len(models) == 1:
        ratio, threshold = break_even(models[0])
        verdict = "a 1h TTL pays above %.1f%% at %s rates (0.75/(2 - r), r = cache-read/input = %g)%s" % (
            100 * threshold, models[0], ratio,
            "; share includes %d requests of unpriced models" % share["unpriced"] if share["unpriced"] else "")
    elif models:
        verdict = ("mixed models, cost-weighted over priced writes: 1h TTL %s vs 5m %s "
                   "(1h pays only when lower; %d unpriced requests excluded)" % (
                       money(share["cost_1h"]), money(share["cost_5m"]), share["unpriced"]))
    else:
        verdict = "break-even unpriced (unknown models)"
    bound = ("rewrites count only the prefix cached before the gap; "
             "lower bound: rewrites under 100k creation not counted")
    if share["written_1h"]:
        bound += "; 1h writes present, so rewrites they avoided are not counted either"
    return "%s (%.1f%%); %s; %s (token-economy § Measure it, operator-lever table)" % (
        head, 100 * Decimal(rewritten) / written, verdict, bound)


def cache_rewrite_findings(s):
    return [Finding("cache-rewrite", "Cache creation %d tokens after %.1f min gap (TTL %s)" % (
        row["tokens"], row["gap"] / 60, "1h" if row["ttl"] == 3600 else "5m"),
        "FR-26 TE-20 — wait under the cache TTL / record-then-read (token-economy)", LIVE,
        "cost signal", "start-to-start gap exceeded this request's explicit creation TTL",
        (row["cost"] is None, -(row["cost"] or 0), -row["tokens"]), row["cost"], "", "observed")
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
    # A wake is a repeat: the first request that issued the command is the original call, not a wake.
    issued = sorted((index[key] for key in s.get("bash_requests", {}).get(command, ()) if key in index),
                    key=lambda r: r.get("seq", 0))
    wakes = issued[1:]
    costs = [context(r) * rates_for(r)["cache read"] / MILLION
             for r in wakes if rates_for(r) is not None]
    return len(wakes), sum(context(r) for r in wakes), sum(costs) if costs else (None if wakes else Decimal(0))


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
        rows += [(scope, "advisor", a["advisor_tokens"], a["advisor_cost"]) for scope, a in data]
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
        unknown_advisor = Counter()
        for _, a in data:
            unknown_advisor.update(a["advisor_unpriced"])
        for model, count in sorted(unknown_advisor.items()):
            lines.append("%d advisor iterations unpriced (model %s) — tokens only; excluded from USD" % (
                count, model))
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
    for session in sessions:
        if not session.get("main_only"):
            lines += ["", share_line(session["file"], rewrite_share(session.get("subagents", [])))]
    return lines
