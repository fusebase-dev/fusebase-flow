#!/usr/bin/env python3
"""Fusebase Flow — single-process fixture runner (D6).

Imports each handler ONCE and drives its main() in-process, per fixture, so the
21-fixture suite is one python process instead of 21x(>=3 MSYS spawns). Handlers
and shared/ are UNMODIFIED (FR-07) — this only DRIVES them.

Default mode: run every fixtures/*.json (sorted, same order as run-tests.sh),
assert decision / rule_id exactly as the bash loop did, print PASS:/FAIL: lines,
exit = fail count. A synthetic `_parse-invariant` row is retained (D6).

`--compare-subprocess` mode: run every fixture BOTH in-process and via
`python hooks/handlers/<h> < fixture`, diff the TRIPLE (exit_code, decision,
rule_id). Any divergence names both triples and exits nonzero. Required 21/21.

Exit-code capture (B5): handlers END `raise SystemExit(main())`, so the SystemExit
path is production; in-process rc = _norm(main() return OR SystemExit.code)
with CPython semantics (None->0, int->value, other->1); subprocess rc =
proc.returncode. A crash (any other BaseException) => rc 1 + FAIL (a subprocess
crash is empty stdout => FAIL too).
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import traceback
from pathlib import Path


def _git_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip()).resolve()
    except Exception:
        return Path(__file__).resolve().parents[2]


ROOT = _git_root()
# Release gate contract: all 21 currently shipped handler fixtures must execute.
EXPECTED_HANDLER_FIXTURES = 21
# hooks/ on sys.path so `from shared...` resolves before any handler import (the
# handlers also self-insert their parent; this makes reset_cache importable now).
sys.path.insert(0, str(ROOT / "hooks"))
from shared.policy_loader import reset_cache  # noqa: E402


def _norm(code) -> int:
    """CPython SystemExit normalization: None->0, int(incl. bool)->value, other->1."""
    if code is None:
        return 0
    if isinstance(code, int):
        return int(code)
    return 1


def _parse(out: str) -> tuple[str, str]:
    """Decision + rule_id from handler stdout, exactly as run-tests.sh did:
    json.loads(out) if it starts with '{' else {}; decision default ''; rule_id
    default '' (or '' when null)."""
    try:
        data = json.loads(out) if out.strip().startswith("{") else {}
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    return data.get("decision", ""), (data.get("rule_id", "") or "")


_HANDLER_CACHE: dict[str, object] = {}


def _load_handler(handler_name: str):
    mod = _HANDLER_CACHE.get(handler_name)
    if mod is not None:
        return mod
    path = ROOT / "hooks" / "handlers" / handler_name
    spec = importlib.util.spec_from_file_location(f"ff_handler_{path.stem}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _HANDLER_CACHE[handler_name] = mod
    return mod


def _run_in_process(mod, raw_bytes: bytes) -> tuple[int, str, str | None]:
    """(rc, stdout, crash_detail|None). Cold policy cache per fixture (parity with
    each subprocess); raw fixture bytes as the subprocess pipe delivered them;
    stdout captured, stderr discarded (parity with the loop's 2>/dev/null)."""
    reset_cache()
    stdout = io.StringIO()
    old_stdin = sys.stdin
    sys.stdin = io.TextIOWrapper(io.BytesIO(raw_bytes), encoding="utf-8")
    rc = 1
    crash = None
    try:
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            try:
                rc = _norm(mod.main())
            except SystemExit as e:
                rc = _norm(e.code)
    except BaseException as e:  # crash == empty/invalid stdout == FAIL (subprocess parity)
        crash = "".join(traceback.format_exception_only(type(e), e)).strip()
        rc = 1
    finally:
        sys.stdin = old_stdin
    return rc, stdout.getvalue(), crash


def _run_subprocess(handler_name: str, raw_bytes: bytes) -> tuple[int, str, str]:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "hooks" / "handlers" / handler_name)],
        input=raw_bytes, capture_output=True, cwd=str(ROOT),
    )
    dec, rid = _parse(proc.stdout.decode("utf-8", errors="replace"))
    return proc.returncode, dec, rid


def _fixtures() -> list[Path]:
    return sorted((ROOT / "hooks" / "tests" / "fixtures").glob("*.json"))


def _assert(meta: dict, actual_decision: str, actual_rule_id: str) -> tuple[bool, str]:
    """Byte-identical to run-tests.sh:240-255 — each check applies only when the
    expected field is non-empty (decision exact, rule_id exact, rule_id-contains
    substring)."""
    expected_decision = meta.get("_expected_decision", "") or ""
    expected_rule_id = meta.get("_expected_rule_id", "") or ""
    expected_contains = meta.get("_expected_rule_id_contains", "") or ""
    ok = True
    detail = ""
    if expected_decision and expected_decision != actual_decision:
        ok = False
        detail += f" expected={expected_decision} got={actual_decision}"
    if expected_rule_id and expected_rule_id != actual_rule_id:
        ok = False
        detail += f" expected_rule={expected_rule_id} got={actual_rule_id}"
    if expected_contains and expected_contains not in actual_rule_id:
        ok = False
        detail += f" expected_rule_contains={expected_contains} got={actual_rule_id}"
    return ok, detail


def run_normal() -> int:
    os.chdir(ROOT)  # relative transcript_path fixtures resolve from the git root
    fail = 0
    exercised = 0
    for fx in _fixtures():
        name = fx.name
        raw = fx.read_bytes()
        try:
            meta = json.loads(raw.decode("utf-8"))
        except Exception:
            fail += 1
            print(f"FAIL: {name} — malformed/no _handler")
            continue
        if not isinstance(meta, dict):
            fail += 1
            print(f"FAIL: {name} — malformed/no _handler")
            continue
        handler = meta.get("_handler", "")
        test_name = meta.get("_test", "")
        if not handler:
            fail += 1
            print(f"FAIL: {name} — malformed/no _handler")
            continue
        exercised += 1
        mod = _load_handler(handler)
        rc, out, crash = _run_in_process(mod, raw)
        actual_decision, actual_rule_id = _parse(out)
        ok, detail = _assert(meta, actual_decision, actual_rule_id)
        if crash:
            ok = False
            detail += f" crash={crash}"
        if ok:
            print(f"PASS: {name}  ({test_name}) -> decision={actual_decision}")
        else:
            fail += 1
            print(f"FAIL: {name}  ({test_name}) ->{detail} (rc={rc} raw={out})")

    # _parse-invariant (D6): with an EMPTY _expected_rule_id + a non-empty
    # _expected_rule_id_contains, the SUBSTRING path must be selected (the empty
    # exact-match check must NOT fire). Deterministic, handler-independent.
    ok_inv, _ = _assert(
        {"_expected_rule_id": "", "_expected_rule_id_contains": "FR-12"},
        actual_decision="warn", actual_rule_id="FR-12",
    )
    if ok_inv:
        print("PASS: _parse-invariant  (empty _expected_rule_id preserved; substring FR-12 selected)")
    else:
        fail += 1
        print("FAIL: _parse-invariant  (empty _expected_rule_id not preserved — substring path not selected)")
    if exercised != EXPECTED_HANDLER_FIXTURES:
        fail += 1
        print(f"FAIL: handler fixture coverage — exercised {exercised}, "
              f"expected {EXPECTED_HANDLER_FIXTURES}")
    return fail


def run_compare() -> int:
    os.chdir(ROOT)
    n = 0
    mism = 0
    for fx in _fixtures():
        raw = fx.read_bytes()
        try:
            meta = json.loads(raw.decode("utf-8"))
        except Exception:
            mism += 1
            print(f"FAIL: {fx.name} — malformed/no _handler")
            continue
        if not isinstance(meta, dict):
            mism += 1
            print(f"FAIL: {fx.name} — malformed/no _handler")
            continue
        handler = meta.get("_handler", "")
        if not handler:
            mism += 1
            print(f"FAIL: {fx.name} — malformed/no _handler")
            continue
        n += 1
        mod = _load_handler(handler)
        ip_rc, ip_out, ip_crash = _run_in_process(mod, raw)
        ip_dec, ip_rid = _parse(ip_out)
        sp_rc, sp_dec, sp_rid = _run_subprocess(handler, raw)
        ip = (ip_rc, ip_dec, ip_rid)
        sp = (sp_rc, sp_dec, sp_rid)
        if ip_crash is not None:
            mism += 1
            print(f"FAIL: {fx.name} — in-process crash: {ip_crash}")
            continue
        if ip != sp:
            mism += 1
            print(f"MISMATCH: {fx.name} "
                  f"in-process=(exit={ip_rc}, decision={ip_dec!r}, rule_id={ip_rid!r}) "
                  f"subprocess=(exit={sp_rc}, decision={sp_dec!r}, rule_id={sp_rid!r})")
        else:
            print(f"OK: {fx.name} (exit={ip_rc}, decision={ip_dec!r}, rule_id={ip_rid!r})")
    if n != EXPECTED_HANDLER_FIXTURES:
        mism += 1
        print(f"FAIL: handler fixture coverage — exercised {n}, "
              f"expected {EXPECTED_HANDLER_FIXTURES}")
    if mism == 0 and n == EXPECTED_HANDLER_FIXTURES:
        print(f"[run_hook_tests] parity {n}/{n} identical (exit_code, decision, rule_id)")
        return 0
    return 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--compare-subprocess" in argv:
        return run_compare()
    return run_normal()


if __name__ == "__main__":
    raise SystemExit(main())
