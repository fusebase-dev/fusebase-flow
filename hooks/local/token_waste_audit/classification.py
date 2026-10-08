from .common import (LIVE, CLASSIFIED, FR10_TRIPLE, READ_REPEAT_MIN,
                     BASH_REPEAT_MIN, LARGE_TOOL_RESULT_CHARS, REPEAT_OUTPUT_MIN,
                     TOP_SINKS, PROBE_VERBS, PROBE_VERB_PAIRS, PROBE_FLAGS,
                     INTERPRETERS, VERB_SUFFIXES, SEGMENT_SPLIT, ENV_ASSIGN,
                     TEST_DIR_PREFIX, Finding, snippet, is_output_heavy)
import shlex
from .parsing import transcripts
from .costing import (request_index, payload_cost, sum_known, polling_cost,
                      cache_rewrite_findings, residency_finding, cost_order)

def monotonic_growth(sizes):
    return all(a <= b for a, b in zip(sizes, sizes[1:])) and sizes[-1] > sizes[0]


def contradictory_event(s, key, events):
    """A8 contradictory-event predicate. Returns the evidence string, or "" if none."""
    lo, hi = events[0][0], events[-1][0]
    # TRIPWIRE: both sides were canonicalized at ingest (canon_path) — compare them raw
    # here and the `C:/Repo` vs `c:\repo` alias false negative comes straight back.
    path = key[0]
    for wseq, wpath in s["write_events"]:
        if lo < wseq < hi and wpath == path:
            return "intervening write to the read path at event %d" % wseq
    for cseq in s["compaction_seqs"]:
        if lo < cseq < hi:
            return "context compaction between the reads at event %d" % cseq
    if any(e[3] for e in events):
        return "error-shaped tool_result for one of the reads"
    sizes = [e[1] for e in events]
    # TRIPWIRE: unreachable while the growth gate below requires ALL digests distinct
    # (identical digests already fail it). Kept because it is normative in A8 and becomes
    # load-bearing the moment "differing digests" is loosened to "not all identical".
    if any(b < a for a, b in zip(sizes, sizes[1:])) and len({e[2] for e in events}) == 1:
        return "non-monotonic size sequence with identical digests"
    return ""


def classify_re_read(s, key, n):
    """A8 growing-source-tail — CONJUNCTIVE: same full read key AND (monotonic growth OR
    differing digests) AND no contradictory event. Returns (status, evidence)."""
    events = s["read_events"].get(key, [])
    if len(events) != n:
        return LIVE, "result evidence for only %d of %d reads — not evaluable" % (len(events), n)
    sizes = [e[1] for e in events]
    digests = [e[2] for e in events]
    ndist = len(set(digests))
    grew = monotonic_growth(sizes)
    all_differ = ndist == len(digests)
    if not (grew or all_differ):
        return LIVE, ("sizes %s, %d distinct digest(s) — neither monotonic growth nor "
                      "all-differing digests (size difference alone is not sufficient)"
                      % (sizes, ndist))
    contra = contradictory_event(s, key, events)
    if contra:
        return LIVE, "growth signal present but contradicted — %s" % contra
    return CLASSIFIED, ("same full read key %s; %s (sizes %s, %d distinct digests); "
                        "no contradictory event"
                        % (snippet(str(key), keep_tail=True), "monotonic growth" if grew else "all digests differ",
                           sizes, ndist))


def tokenize(segment):
    try:
        return shlex.split(segment)
    except ValueError:
        return segment.split()


def command_verb(tokens):
    """(verb, argv) for one pipeline segment: leading env assignments and one interpreter
    wrapper stripped, verb reduced to its extension-less basename."""
    i = 0
    while i < len(tokens) and ENV_ASSIGN.match(tokens[i]):
        i += 1
    if i < len(tokens) and basename_verb(tokens[i]) in INTERPRETERS and i + 1 < len(tokens):
        i += 1
        while i < len(tokens) and tokens[i] in ("-m", "-u", "-l", "-c"):
            i += 1
    if i >= len(tokens):
        return "", []
    return basename_verb(tokens[i]), tokens[i:]


def basename_verb(token):
    base = token.replace("\\", "/").rsplit("/", 1)[-1]
    for suf in VERB_SUFFIXES:
        if base.lower().endswith(suf):
            return base[: -len(suf)]
    return base


def segment_probe_label(segment):
    """A8 probe shape for ONE pipeline segment — verb position or a known exact form."""
    tokens = tokenize(segment)
    if not tokens:
        return ""
    verb, argv = command_verb(tokens)
    label = PROBE_VERBS.get(verb.lower())
    if label:
        return label
    if len(argv) >= 2:
        label = PROBE_VERB_PAIRS.get((verb.lower(), argv[1].lower()))
        if label:
            return label
    if (len(tokens) >= 2 and basename_verb(tokens[0]) in INTERPRETERS
            and tokens[1].replace("\\", "/").lstrip("./").startswith(TEST_DIR_PREFIX)):
        return "test runner (bash hooks/tests/)"
    for tok in argv[1:]:
        if tok.lower() in PROBE_FLAGS:
            return PROBE_FLAGS[tok.lower()]
    return ""


def probe_shaped(cmd, probe_cmds=()):
    """A8 probe-shaped predicate. `--probe-command` is normalized EQUALITY, and EVERY
    chained segment must be probe-shaped — substring containment dismissed a documented
    probe with extra mutating commands appended (A8 amendment, BLOCKER 5)."""
    norm = " ".join(cmd.split())
    for extra in probe_cmds:
        if extra and " ".join(extra.split()) == norm:
            return "documented gate probe (--probe-command %s)" % snippet(extra)
    segments = [seg for seg in SEGMENT_SPLIT.split(norm) if seg.strip()]
    if not segments:
        return ""
    labels = [segment_probe_label(seg) for seg in segments]
    return labels[0] if all(labels) else ""


def classify_bash(cmd, n, probe_cmds=()):
    """A8 FR-10 triple — exactly 3 runs are LABELED; dismissed only when probe-shaped.
    Returns (status, label, evidence). `n` counts runs since the last write, not
    truly consecutive runs (parse_session clears the counter on Edit/Write)."""
    since = "%d runs since the last write (not necessarily consecutive)" % n
    if n != FR10_TRIPLE:
        return LIVE, "", since
    shape = probe_shaped(cmd, probe_cmds)
    if shape:
        return CLASSIFIED, "possible-FR-10-triple", "exactly %s; probe-shaped: %s" % (since, shape)
    return LIVE, "possible-FR-10-triple", (
        "exactly %s; command is NOT probe-shaped — 3 failed retries and 3 polls are "
        "count-identical to a genuine FR-10 reproduction triple, so this stays live" % since)


def session_findings(s, probe_cmds=()):
    f = []
    index = request_index(s)
    for key, n in sorted(s["read_counts"].items(), key=lambda kv: -kv[1]):
        events = s["read_events"].get(key, [])
        if len(events) == n and all(e[0] in s.get("image_only_read_seqs", ()) for e in events):
            continue
        fp, off, lim = key
        if n >= READ_REPEAT_MIN and fp:
            fp = s["read_display"].get(key, fp)
            win = "" if off is None and lim is None else " [offset=%s limit=%s]" % (off, lim)
            status, evidence = classify_re_read(s, key, n)
            f.append(Finding("re-read", "Read x%d identical window: %s%s" % (n, snippet(fp, keep_tail=True), win),
                             "FR-26 TE-02 — no re-reads of unchanged in-context files",
                             status, "growing-source-tail" if status == CLASSIFIED else "",
                             evidence, (), sum_known([payload_cost(s, index, e[0], e[1] / 4)
                                                       for e in events])))
    for cmd, n in sorted(s["bash_runs"].items(), key=lambda kv: -kv[1]):
        if n >= BASH_REPEAT_MIN and cmd:
            status, label, evidence = classify_bash(cmd, n, probe_cmds)
            wakes, tokens, cost = polling_cost(s, cmd)
            wake_text = "%d wakes; context sum %d tokens (cache-read rate estimate)" % (
                wakes, tokens) if wakes else ""
            f.append(Finding("polling", "Bash x%d (no intervening Edit/Write): %s" % (n, snippet(cmd)),
                             "FR-26 TE-08 — record-then-read (smoke-testing § Verification cost discipline)",
                             status, label, evidence, (), cost, wake_text))
    for i, (fp, chars) in enumerate(s["large_writes"]):
        seqs = s.get("large_write_seqs", [])
        cost = payload_cost(s, index, seqs[i], chars / 4, "output") if i < len(seqs) else None
        f.append(Finding("rewrite", "Write %d chars to pre-existing path: %s" % (chars, fp),
                         "FR-26 TE-06 — targeted edits over whole-file rewrites", LIVE, "", "", (), cost))
    # TRIPWIRE: cap across main + agents in selected_findings, never per transcript.
    large = sorted(
        ((r.chars, r.name, r.target, r.seq) for r in s["tool_results"]
         if r.chars >= LARGE_TOOL_RESULT_CHARS and is_output_heavy(r.name)),
        key=lambda r: (-r[0], r[1], r[2]),
    )
    for chars, name, target, seq in large:
        cost = payload_cost(s, index, seq, chars / 4)
        f.append(Finding("large-output",
                         "Tool result %d chars (~%d tokens): %s %s" % (chars, chars // 4, name, target),
                         "FR-26 TE-11/TE-17 — extract/scope/filter before reasoning over large output",
                         LIVE, "", "", (-chars, name, target), cost))
    # repeat-output: the SAME large body re-sent across turns (identical fingerprint).
    # One finding per recurring digest (count = times seen) — references-not-re-sends.
    by_digest = {}
    for r in s["tool_results"]:
        if r.chars >= LARGE_TOOL_RESULT_CHARS and is_output_heavy(r.name):
            by_digest.setdefault(r.digest, []).append(r)
    repeats = sorted(
        ((len(v), v[0].chars, v[0].name, v[0].target, digest)
         for digest, v in by_digest.items() if len(v) >= REPEAT_OUTPUT_MIN),
        key=lambda r: (-r[0], -r[1], r[2], r[3]),
    )
    for n, chars, name, target, digest in repeats:
        cost = sum_known([payload_cost(s, index, r.seq, r.chars / 4) for r in by_digest[digest]])
        f.append(Finding("repeat-output",
                         "Identical large result x%d (~%d chars each): %s %s" % (n, chars, name, target),
                         "FR-26 TE-07 — reference an in-context body by its handle, don't re-send it",
                         LIVE, "", "", (-n, -chars, name, target), cost))
    images_by_digest = {}
    for image in s.get("images", []):
        if image["digest"]:
            images_by_digest.setdefault(image["digest"], []).append(image)
    for images in images_by_digest.values():
        if len(images) >= 2:
            first = images[0]
            f.append(Finding("image-reread", "Identical image x%d: %s %s" % (
                len(images), first["name"], first["target"]),
                "FR-26 TE-02 — no re-reads of unchanged in-context files", LIVE, "",
                "same image bytes delivered repeatedly in this transcript", (),
                sum_known([payload_cost(s, index, image["seq"], image["tokens"])
                           for image in images])))
    f.extend(cache_rewrite_findings(s))
    return f


def selected_findings(sessions, probe_cmds=()):
    selected, suppressed = [], []
    for session in sessions:
        found = [(s, f) for s in transcripts([session])
                 for f in session_findings(s, probe_cmds)]
        residency = residency_finding(session)
        if residency:
            found.append((session, residency))
        kept = [(s, f) for s, f in found if f.cls not in ("large-output", "repeat-output", "cache-rewrite")]
        for cls in ("large-output", "repeat-output", "cache-rewrite"):
            ranked = sorted(((s, f) for s, f in found if f.cls == cls), key=lambda item: item[1].rank)
            kept.extend(ranked[:TOP_SINKS])
            if len(ranked) > TOP_SINKS:
                suppressed.append((session, cls, len(ranked) - TOP_SINKS))
        selected.append((session, sorted(kept, key=cost_order)))
    return selected, suppressed
