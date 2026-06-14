"""Self-test Layer 3 — path-containment / --root escape + write-path safety.

Extracted from selftest.py along the test-layer seam (FR-25 module ceiling): the
synthetic / evidence-sourcing / scoping layers stay in selftest.py; this module
owns the write-path SAFETY layer — the load-bearing read-only-safety case for
Phase 2A (the analyzer writes NOTHING outside state/audit/).

It covers: a non-Flow / traversal / symlinked-state-audit root is rejected; the
contained_audit_path basename guard; and the write_audit_file TARGET guards — a
symlink (f) and a HARDLINK (g2) pre-planted at the output path must never let a
write leak through to a file OUTSIDE state/audit/, while a normal write (g, g3)
still lands report + proposals JSON UNDER state/audit/. Host-capability-gated
fixtures (no symlink/hardlink privilege) report SKIP, not FAIL.

Non-writing against the real repo: every fixture builds a throwaway temp repo and
cleans it up.
"""

import datetime
import os
import shutil
import tempfile
from pathlib import Path


def containment_cases(check_bool):
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "fwe_main", str(Path(__file__).resolve().parent.parent / "find-wasted-effort.py"))
    main_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(main_mod)
    RootError = main_mod.RootError
    today = datetime.date.today().isoformat()

    # (a) a non-Flow directory is rejected as a root
    tmp = Path(tempfile.mkdtemp(prefix="fwe-noflow-"))
    try:
        rejected = False
        try:
            main_mod.resolve_root(str(tmp))
        except RootError:
            rejected = True
        check_bool("containment: non-Flow --root rejected", rejected, True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # (b) a traversal root (../outside) does not let the report escape: a Flow
    #     fixture root with a SYMLINKED state/audit pointing outside is rejected.
    base = Path(tempfile.mkdtemp(prefix="fwe-symesc-"))
    try:
        repo = base / "repo"
        outside = base / "outside"
        repo.mkdir(); outside.mkdir()
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")  # Flow marker
        (repo / "state").mkdir()
        symlink_ok = True
        try:
            os.symlink(str(outside), str(repo / "state" / "audit"),
                       target_is_directory=True)
        except (OSError, NotImplementedError):
            symlink_ok = False  # no symlink privilege (some Windows) -> skip, don't fail
        if symlink_ok:
            root = main_mod.resolve_root(str(repo))
            escaped = False
            rejected = False
            try:
                rp = main_mod.contained_report_path(root, today)
                # if not rejected, the resolved report must still be inside repo
                escaped = not main_mod._is_relative_to(rp.resolve(), repo.resolve())
            except RootError:
                rejected = True
            check_bool("containment: symlinked state/audit escape rejected",
                       rejected or not escaped, True)
        else:
            check_bool("containment: symlinked state/audit escape (host lacks symlink privilege)",
                       None, None, skipped=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (c) a well-formed Flow root yields a contained report path inside state/audit
    tmp = Path(tempfile.mkdtemp(prefix="fwe-ok-"))
    try:
        (tmp / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(tmp))
        rp = main_mod.contained_report_path(root, today)
        inside = main_mod._is_relative_to(rp, (root / "state" / "audit").resolve())
        check_bool("containment: valid Flow root -> report inside state/audit", inside, True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # (d) privilege-INDEPENDENT escape guard: a sibling path outside state/audit
    #     must be rejected by the containment predicate (the same predicate
    #     contained_report_path() uses to assert no traversal/absolute/symlink escape).
    base = Path(tempfile.mkdtemp(prefix="fwe-guard-"))
    try:
        repo = base / "repo"; (repo / "state" / "audit").mkdir(parents=True)
        sibling = base / "outside" / "report.md"
        sibling.parent.mkdir(parents=True)
        contained = main_mod._is_relative_to(sibling.resolve(),
                                             (repo / "state" / "audit").resolve())
        check_bool("containment: sibling path rejected by guard predicate", contained, False)
        legit = (repo / "state" / "audit" / "find-wasted-effort-x.md")
        ok = main_mod._is_relative_to(legit.resolve(),
                                      (repo / "state" / "audit").resolve())
        check_bool("containment: in-audit path accepted by guard predicate", ok, True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (e) a traversal-style --root that resolves to a non-Flow dir is rejected
    base = Path(tempfile.mkdtemp(prefix="fwe-trav-"))
    try:
        (base / "sub").mkdir()
        rejected = False
        try:
            # ../ from a Flow-less sub resolves to a Flow-less parent -> RootError
            main_mod.resolve_root(str(base / "sub" / ".." / "nowhere"))
        except RootError:
            rejected = True
        check_bool("containment: traversal --root to non-Flow dir rejected", rejected, True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (f) write_report TOCTOU guard (LOW finding): a symlinked report TARGET planted
    #     after path resolution is rejected via lstat before any write occurs.
    base = Path(tempfile.mkdtemp(prefix="fwe-wsym-"))
    try:
        repo = base / "repo"
        (repo / "state" / "audit").mkdir(parents=True)
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        report_path = main_mod.contained_report_path(root, today)
        outside = base / "outside.md"
        outside.write_text("attacker\n", encoding="utf-8")
        symlink_ok = True
        try:
            os.symlink(str(outside), str(report_path))
        except (OSError, NotImplementedError):
            symlink_ok = False  # no symlink privilege -> skip, don't fail
        if symlink_ok:
            rejected = False
            try:
                main_mod.write_report(root, report_path, "report body")
            except main_mod.RootError:
                rejected = True
            wrote_through = outside.read_text(encoding="utf-8") != "attacker\n"
            check_bool("containment: write_report rejects symlinked report target (lstat)",
                       rejected and not wrote_through, True)
        else:
            check_bool("containment: report-symlink write guard (host lacks symlink privilege)",
                       None, None, skipped=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (g) write_report happy path: a real Flow root yields a written file inside
    #     state/audit (re-asserted containment lets the legitimate write through).
    base = Path(tempfile.mkdtemp(prefix="fwe-wok-"))
    try:
        repo = base / "repo"; repo.mkdir()
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        report_path = main_mod.contained_report_path(root, today)
        wrote = main_mod.write_report(root, report_path, "report body\n")
        inside = main_mod._is_relative_to(Path(wrote).resolve(),
                                          (repo / "state" / "audit").resolve())
        check_bool("containment: write_report writes inside state/audit on a valid root",
                   inside and Path(wrote).read_text(encoding="utf-8") == "report body\n", True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (g2) write_audit_file HARDLINK guard (Codex final-review LOW): a hardlink
    #     pre-planted at the report TARGET aliases a file OUTSIDE state/audit. After a
    #     write, the OUTSIDE file MUST be unchanged (atomic temp+os.replace severs the
    #     alias; the up-front st_nlink>1 check refuses to write through it), and the
    #     report still lands correctly UNDER state/audit. Proves the read-only-safety
    #     invariant holds against a hardlink, the way (f) proves it against a symlink.
    base = Path(tempfile.mkdtemp(prefix="fwe-whard-"))
    try:
        repo = base / "repo"
        (repo / "state" / "audit").mkdir(parents=True)
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        report_path = main_mod.contained_report_path(root, today)
        outside = base / "outside.md"
        outside.write_text("attacker\n", encoding="utf-8")
        hardlink_ok = True
        try:
            os.link(str(outside), str(report_path))  # plant a hardlink at the target
        except (OSError, NotImplementedError, AttributeError):
            hardlink_ok = False  # host can't hardlink (cross-device / no privilege) -> skip
        if hardlink_ok:
            # write through the planted hardlink target
            try:
                main_mod.write_audit_file(root, report_path, "report body\n")
            except main_mod.RootError:
                pass  # refusing up-front is an acceptable outcome (alias not followed)
            # the OUTSIDE aliased file is UNCHANGED (no write leaked through the alias)
            outside_intact = outside.read_text(encoding="utf-8") == "attacker\n"
            check_bool("containment: hardlink-aliased OUTSIDE file untouched after write",
                       outside_intact, True)
            # and a legitimate report still lands UNDER state/audit (re-run, alias now
            # severed by the replace / refusal — a fresh write must succeed & be inside)
            try:
                os.remove(str(report_path))
            except OSError:
                pass
            wrote = main_mod.write_audit_file(root, report_path, "report body\n")
            inside = main_mod._is_relative_to(Path(wrote).resolve(),
                                              (repo / "state" / "audit").resolve())
            check_bool("containment: report still lands under state/audit despite planted hardlink",
                       inside and Path(wrote).read_text(encoding="utf-8") == "report body\n", True)
        else:
            check_bool("containment: hardlink-target write guard (host lacks hardlink capability)",
                       None, None, skipped=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (g3) write_audit_file NORMAL write (no pre-planted target): both the .md report
    #     and the .json proposals sibling are written UNDER state/audit, as before —
    #     the atomic temp+replace path is exercised on the happy path with a NEW inode
    #     (st_nlink == 1) and leaves no temp turd behind in the audit dir.
    base = Path(tempfile.mkdtemp(prefix="fwe-wnorm-"))
    try:
        repo = base / "repo"; repo.mkdir()
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        audit = (repo / "state" / "audit")
        report_path = main_mod.contained_report_path(root, today)
        json_path = main_mod.contained_proposals_path(root, today)
        wrote_md = main_mod.write_audit_file(root, report_path, "report body\n")
        wrote_js = main_mod.write_audit_file(root, json_path, "{}\n")
        md_ok = (main_mod._is_relative_to(Path(wrote_md).resolve(), audit.resolve())
                 and Path(wrote_md).read_text(encoding="utf-8") == "report body\n"
                 and Path(wrote_md).lstat().st_nlink == 1)
        js_ok = (main_mod._is_relative_to(Path(wrote_js).resolve(), audit.resolve())
                 and Path(wrote_js).read_text(encoding="utf-8") == "{}\n")
        check_bool("containment: normal write lands report + proposals JSON under state/audit",
                   md_ok and js_ok, True)
        # no leftover temp files from the atomic write
        leftovers = [p.name for p in audit.iterdir() if p.name.startswith(".find-wasted-effort-")]
        check_bool("containment: atomic write leaves no temp file in state/audit",
                   leftovers, [])
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (h) basename hardening (Codex Phase-2A LOW): contained_audit_path REJECTS a
    #     basename that is absolute or carries ../ / a path separator (internal-misuse
    #     traversal), and ACCEPTS a flat basename, resolving it under state/audit.
    base = Path(tempfile.mkdtemp(prefix="fwe-bname-"))
    try:
        repo = base / "repo"; repo.mkdir()
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        audit = (repo / "state" / "audit")

        evil_rejected = False
        try:
            main_mod.contained_audit_path(root, "../evil.md")
        except RootError:
            evil_rejected = True
        check_bool("containment: contained_audit_path rejects '../evil.md' basename",
                   evil_rejected, True)
        # the rejected basename wrote nothing outside state/audit
        check_bool("containment: rejected '../evil.md' wrote no escape file",
                   (base / "evil.md").exists() or (repo / "evil.md").exists(), False)

        for bad in ("nested/x.md", "..", "/etc/passwd"):
            rejected = False
            try:
                main_mod.contained_audit_path(root, bad)
            except RootError:
                rejected = True
            check_bool("containment: contained_audit_path rejects %r basename" % bad,
                       rejected, True)

        # a normal flat basename resolves under state/audit
        ok_path = main_mod.contained_audit_path(root, "find-wasted-effort-x.md")
        check_bool("containment: contained_audit_path accepts a flat basename under state/audit",
                   main_mod._is_relative_to(ok_path.resolve() if ok_path.exists() else ok_path,
                                            audit.resolve()), True)
    finally:
        shutil.rmtree(base, ignore_errors=True)
