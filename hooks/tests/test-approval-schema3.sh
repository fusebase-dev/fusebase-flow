#!/usr/bin/env bash
# Fusebase Flow — schema-3 command approvals + git_push_v1 ref-update binding (acceptance).
# Rows = docs/backlog/approval-binding-omits-head/ premise review item 9. Each row drives the
# REAL writer (approve-local.sh), command gate, pre_tool_use handler and pre-push hook inside a
# throwaway repository with a bare remote, so the same file discriminates against a tree
# without the contract: there the writer's artifact keeps authorizing after the change.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: approval-schema3 <row>" / "FAIL: approval-schema3 <row> (<detail>)"; exit = fails.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! command -v python3 >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "PASS: approval-schema3 skipped-no-python3-or-git"; exit 0
fi

ROWS_OUT="$(mktemp)"
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' | tee "$ROWS_OUT"
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT / "hooks"))
sys.path.insert(0, str(ROOT / "hooks" / "tests" / "fixtures"))
from approval_fixture import (  # noqa: E402
    BASH, CREATED, FUTURE, Repo, case, expect, git, prefix_artifact, run, upd,
)
# TRIPWIRE: the failure COUNT is read through the module, never imported by value - `case()`
# increments the fixture's own counter, and a `from … import FAILS` would exit on the 0 it
# captured at import time, turning every failed row into a green phase.
import approval_fixture  # noqa: E402
import json  # noqa: E402
import shutil  # noqa: E402
from shared.approval_artifact import (  # noqa: E402
    compute_command_digest, compute_repo_id,
)
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

PUSH = "git push origin main"


def digest_omission(r: Repo, p: list[str]) -> None:
    rc, body, err = r.mint("fusebase deploy")
    if body is None:
        p.append(f"writer failed: {err.strip()[-200:]}")
        return
    expect(r.gate("fusebase deploy"), "allow", None, "writer-artifact", p)
    body.pop("command_digest", None)
    r.write(body)
    expect(r.gate("fusebase deploy"), "deny", None, "digest-omitted", p)
    body["command_digest"] = "   "
    r.write(body)
    expect(r.gate("fusebase deploy"), "deny", None, "digest-blank", p)


def schema_downgrade(r: Repo, p: list[str]) -> None:
    rc, body, err = r.mint(PUSH)
    if body is None:
        p.append(f"writer failed: {err.strip()[-200:]}")
        return
    expect(r.gate(PUSH), "allow", None, "writer-artifact", p)
    r.write({**body, "schema_version": 2})
    expect(r.gate(PUSH), "deny", "LEGACY_SCHEMA", "schema-2", p)
    for bad in (3.0, True, "3"):
        r.write({**body, "schema_version": bad})
        expect(r.gate(PUSH), "deny", None, f"schema-type[{bad!r}]", p)
    weaker = {k: v for k, v in body.items() if k != "updates"}
    weaker.update(schema_version=3, binding_profile="command_only_v1")
    r.write(weaker)
    expect(r.gate(PUSH), "deny", "PROFILE_MISMATCH", "profile-downgrade", p)


def legacy_rejection(r: Repo, p: list[str]) -> None:
    digest, rid = compute_command_digest("fusebase deploy"), compute_repo_id(r.work)
    bodies = {
        "absent": {"action": "production_deploy", "expires_at": FUTURE},
        "v1": {"schema_version": 1, "action": "production_deploy", "expires_at": FUTURE},
        "v2-bound": {"schema_version": 2, "action": "production_deploy", "expires_at": FUTURE,
                     "created_at": CREATED, "command_digest": digest, "repo_id": rid},
    }
    paths = {}
    for slug, body in bodies.items():
        for f in (r.work / "state" / "approvals").glob("*.json"):
            f.unlink()
        paths[slug] = r.write(body, slug=slug)
        before = paths[slug].read_bytes()
        expect(r.gate("fusebase deploy"), "deny", "LEGACY_SCHEMA", f"legacy-{slug}", p)
        if paths[slug].read_bytes() != before:
            p.append(f"legacy-{slug}: artifact was modified")
    for slug, body in bodies.items():
        r.write(body, slug=slug)
    inv = run(r.work, BASH, "hooks/local/approve-local.sh", "--inventory")
    for slug in bodies:
        name = f"production_deploy-{slug}-20260911.json"
        line = next((l for l in inv.stdout.splitlines() if l.strip().startswith(name + ":")), "")
        if "LEGACY_SCHEMA" not in line:
            p.append(f"inventory does not name {name} as LEGACY_SCHEMA")
    if len(list((r.work / "state" / "approvals").glob("*.json"))) != 3:
        p.append("inventory removed or added artifacts")


def branch_moved_head_fixed(r: Repo, p: list[str]) -> None:
    git(r.work, "checkout", "-q", "-b", "work")
    rc, body, err = r.mint(PUSH)
    expect(r.gate(PUSH), "allow", None, "before-move", p)
    head = r.oid("HEAD")
    moved = git(r.work, "commit-tree", "-p", head, "-m", "B", f"{head}^{{tree}}")
    git(r.work, "branch", "-f", "main", moved)        # main moves; HEAD (work) does not
    if r.oid("HEAD") != head or r.oid("main") != moved:
        p.append("fixture: expected main to move while HEAD stays fixed")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "main-moved-head-fixed", p)


def head_moved_branch_fixed(r: Repo, p: list[str]) -> None:
    git(r.work, "checkout", "-q", "-b", "work")
    rc, body, err = r.mint(PUSH)
    r.commit("unrelated")                             # HEAD moves, main does not
    expect(r.gate(PUSH), "allow", None, "unrelated-head-movement", p)


def identical_tree(r: Repo, p: list[str]) -> None:
    rc, body, err = r.mint(PUSH)
    first = r.oid("main")
    git(r.work, "commit", "-q", "--amend", "--allow-empty", "-m", "A-reworded")
    if r.oid("main^{tree}") != git(r.work, "rev-parse", f"{first}^{{tree}}") or r.oid("main") == first:
        p.append("fixture: expected an identical tree under a different commit")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "same-tree-new-commit", p)


def endpoint_change(r: Repo, p: list[str]) -> None:
    r.commit("B")
    rc, body, err = r.mint(PUSH)
    expect(r.gate(PUSH), "allow", None, "before", p)
    git(r.work, "remote", "set-url", "origin", "../remote2.git")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "endpoint-changed", p)
    # TRIPWIRE: assembled at runtime. A literal URL carrying credentials in its authority is a
    # real secret-scanner pattern, and a fixture must never need a whitelist to commit.
    token = "t0ken" + "-fixture"
    cred = "https://" + "u5er" + ":" + token + "@example.invalid/x.git"
    git(r.work, "remote", "set-url", "origin", cred)
    rc, body, err = r.mint(PUSH)
    if rc == 0 or body is not None:
        p.append("writer bound a credential-bearing remote instead of refusing it")
    if token in (err or ""):
        p.append("the refusal echoed the credential back")
    # Hand-written, it must still not authorize: the stored endpoint is not a bindable form.
    r.write(r.schema3(PUSH, [upd("refs/heads/main", r.oid("main"), endpoint=cred)]))
    expect(r.gate(PUSH), "deny", None, "credential-endpoint-artifact", p)


def extra_refs(r: Repo, p: list[str]) -> None:
    r.commit("B")
    rc, body, err = r.mint(PUSH)
    git(r.work, "branch", "feature")
    two = "git push origin main feature"
    r.write({**(body or {}), "command_digest": compute_command_digest(two)})
    expect(r.gate(two), "deny", "UPDATE_MISMATCH", "unbound-extra-refspec", p)
    rc, body, err = r.mint(PUSH)
    git(r.work, "config", "push.followTags", "true")
    expect(r.gate(PUSH), "deny", "BINDING_UNRESOLVED", "followTags-config", p)
    git(r.work, "tag", "-a", "v9", "-m", "v9")
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("pre-push: a push carrying an unbound tag succeeded")


def compound_mutation(r: Repo, p: list[str]) -> None:
    compound = "git commit -q --allow-empty -m B && git push origin main"
    rc, body, err = r.mint(compound)
    if rc == 0 and body is not None and body.get("schema_version") == 3:
        p.append("writer minted an approval for a compound push")
    if body is None:
        body = r.schema3(compound, [upd("refs/heads/main", r.oid("main"))])
    r.write(body)
    expect(r.gate(compound), "deny", "BINDING_UNRESOLVED", "compound-command", p)
    git(r.work, "branch", "feature")
    for chained in ("git push origin main\ngit push origin feature",
                    "git push origin main; git push origin feature",
                    "git push origin main | cat", "git push origin main\techo"):
        r.write(r.schema3(chained, [upd("refs/heads/main", r.oid("main"))]))
        expect(r.gate(chained), "deny", None, f"chained[{chained!r}]", p)
    rc, body, err = r.mint(PUSH)                      # bound to main @ A
    expect(r.gate(PUSH), "allow", None, "pre-command-check", p)
    r.commit("B")                                     # the `commit &&` half, after the check
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("pre-push: a commit made after the check was pushed on the old approval")


def lookup_failures(r: Repo, p: list[str]) -> None:
    main = r.oid("main")
    for cmd in ("git push nosuch main", "git push origin nosuchbranch:refs/heads/main",
                "git push origin HEAD:main", "git push origin main --force-if-includes",
                "git push origin +main"):
        rc, body, err = r.mint(cmd)
        if rc == 0 and body and body.get("schema_version") == 3:
            p.append(f"writer bound an unresolvable push: {cmd}")
        r.write(body or r.schema3(cmd, [upd("refs/heads/main", main)]))
        expect(r.gate(cmd), "deny", None, f"unresolved[{cmd}]", p)
    broken = r.tmp / "not-a-repo"
    (broken / "policies").mkdir(parents=True)
    (broken / ".git").mkdir()
    (broken / "state" / "approvals").mkdir(parents=True)
    for name in ("command-policy.yml", "approval-policy.yml"):
        shutil.copy(r.work / "policies" / name, broken / "policies" / name)
    (broken / "state" / "approvals" / "production_deploy-t-20260911.json").write_text(
        json.dumps({**r.schema3(PUSH, [upd("refs/heads/main", main)]),
                    "repo_id": compute_repo_id(broken)}), encoding="utf-8")
    reset_cache()
    dec = evaluate(PUSH, root=broken)
    if dec.decision != "deny":
        p.append(f"git-unusable: expected deny got {dec.decision}")


def unchanged_retry(r: Repo, p: list[str]) -> None:
    r.commit("B")
    rc, body, err = r.mint(PUSH)
    for attempt in (1, 2):
        expect(r.gate(PUSH), "allow", None, f"gate-attempt-{attempt}", p)
        res = r.push("origin", "main")
        if res.returncode != 0:
            p.append(f"push-attempt-{attempt} rc={res.returncode}: {res.stderr.strip()[-200:]}")


def replay_two_commits(r: Repo, p: list[str]) -> None:
    cmd = "git push origin HEAD:refs/heads/main"
    r.commit("B")
    rc, body, err = r.mint(cmd)
    expect(r.gate(cmd), "allow", None, "first-commit-gate", p)
    res = r.push("origin", "HEAD:refs/heads/main")
    if res.returncode != 0:
        p.append(f"first push rc={res.returncode}: {res.stderr.strip()[-200:]}")
    r.commit("C")
    expect(r.gate(cmd), "deny", "UPDATE_MISMATCH", "second-commit-gate", p)
    res = r.push("origin", "HEAD:refs/heads/main")
    if res.returncode == 0:
        p.append("second commit was pushed on the first commit's approval")
    remote_main = git(r.tmp / "remote.git", "rev-parse", "refs/heads/main")
    if remote_main == r.oid("HEAD"):
        p.append("remote main advanced to the unapproved commit")


def boundary_scope(r: Repo, p: list[str]) -> None:
    r.commit("B")
    git(r.work, "branch", "feature")
    res = r.push("origin", "feature")
    if res.returncode != 0:
        p.append(f"ungated destination blocked: {res.stderr.strip()[-160:]}")
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("gated destination pushed with no approval")
    elif "BLOCKED (FR-12 pre-push)" not in res.stderr:
        p.append(f"denial text: {res.stderr.strip()[-160:]}")
    (r.work / "policies" / "approval-policy.local.yml").write_text(
        "workflow_mode: branch_pr\n", encoding="utf-8")
    res = r.push("origin", "main")
    if res.returncode != 0:
        p.append("branch_pr mode: the direct_to_main rule gated a push")


def writer_refuses(r: Repo, p: list[str]) -> None:
    for cmd in ("echo hi", "git push", "git push origin main; rm -rf x"):
        rc, body, err = r.mint(cmd)
        if rc == 0:
            p.append(f"writer wrote an artifact for {cmd!r}")
    rc, body, err = r.mint("npx prisma migrate deploy", action="database_migration")
    if rc != 0 or not body or body.get("binding_profile") != "command_only_v1" \
            or "updates" in body:
        p.append(f"migration approval not command_only_v1: rc={rc} {err.strip()[-160:]}")


def resolver_config_remaps(r: Repo, p: list[str]) -> None:
    from shared.git_push_binding import resolve_command_updates   # absent before schema 3
    ok, why = resolve_command_updates(PUSH, r.work)
    if ok is None or len(ok) != 1 or ok[0][1:] != ("refs/heads/main", r.oid("main"), "update"):
        p.append(f"plain push did not resolve to main@HEAD: {ok} {why}")
    remaps = [("push.default", "upstream"), ("remote.origin.push", "refs/heads/main:refs/heads/prod"),
              ("push.recurseSubmodules", "on-demand"), ("remote.origin.mirror", "true")]
    for key, value in remaps:
        git(r.work, "config", key, value)
        got, why = resolve_command_updates(PUSH, r.work)
        if got is not None:
            p.append(f"{key}={value} still resolved: {got}")
        git(r.work, "config", "--unset-all", key)
    main = r.oid("main")
    for cmd, want in (("git push origin :refs/heads/old", ("refs/heads/old", None, "delete")),
                      (f"git push origin {main}:refs/heads/pinned", ("refs/heads/pinned", main, "update")),
                      ("git push -u origin HEAD", ("refs/heads/main", main, "update"))):
        got, why = resolve_command_updates(cmd, r.work)
        if not got or got[0][1:] != want:
            p.append(f"{cmd!r}: {got} {why}")
    # A value-less key is git-true and only settable by writing the config file itself.
    cfg = r.work / ".git" / "config"
    original = cfg.read_text(encoding="utf-8")
    cfg.write_text(original + "[push]\n\tfollowTags\n", encoding="utf-8")
    if resolve_command_updates(PUSH, r.work)[0] is not None:
        p.append("value-less push.followTags (true) still resolved")
    if resolve_command_updates(PUSH + " --no-follow-tags", r.work)[0] is None:
        p.append("--no-follow-tags did not override push.followTags")
    cfg.write_text(original, encoding="utf-8")
    # Spelling-by-spelling coverage lives in the config-spellings row.


def dry_run_cannot_authorize(r: Repo, p: list[str]) -> None:
    """A dry run performs no update, so it must not be able to authorize one.

    git hands pre-push the SAME update lines for a dry run, and that boundary cannot see the
    command — so an approval minted for `git push --dry-run origin main` authorized the REAL
    push of those objects (independent review of 87ed0ff, blocker 1).
    """
    r.commit("B")
    for dry in ("git push --dry-run origin main", "git push -n origin main"):
        rc, body, err = r.mint(dry)
        if rc == 0 or body is not None:
            p.append(f"writer minted an execution-authorizing artifact for {dry!r}")
        if body is None and "dry" not in err.lower():
            p.append(f"refusal for {dry!r} does not say why: {err.strip()[-120:]}")
        # Even hand-written, a dry-run-bound artifact must not pass the command gate.
        r.write(r.schema3(dry, [upd("refs/heads/main", r.oid("main"))]))
        expect(r.gate(dry), "deny", "BINDING_UNRESOLVED", f"gate[{dry}]", p)
    # End to end, with the artifact RETAINED (not cleared): a pre-fix artifact minted by the
    # old writer for a dry run binds the real push's updates, and pre-push never compares the
    # command digest — so only the binding revision can reject it.
    r.write(prefix_artifact(r, "git push --dry-run origin main",
                            [upd("refs/heads/main", r.oid("main"))]))
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("a real push succeeded on a retained dry-run approval")
    r.mint("git push --dry-run origin main")
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("a real push succeeded after approving only a dry run")


def ssh_principal_binding(r: Repo, p: list[str]) -> None:
    """`alice@host:repo.git` and `bob@host:repo.git` are different repositories.

    Stripping the SSH login merged them (independent review of 87ed0ff, blocker 2); an HTTPS
    userinfo is authentication material and must still never be stored.
    """
    from shared.approval_artifact import bindable_endpoint
    from shared.command_policy import evaluate_push_boundary
    # Credential-bearing forms are assembled here, never written as literals (secret scanner).
    https_creds = "https://" + "u5er" + ":" + "t0k3n" + "@host/o/r.git"
    https_token = "https://" + "t0k3n" + "@host/o/r.git"
    ssh_creds = "ssh://" + "alice" + ":" + "s3cret" + "@host/x.git"
    helper_creds = "helper::https://" + "alice" + ":" + "fixture" + "@host/x"
    # A bindable endpoint is returned VERBATIM; anything else is refused. No folding, ever.
    verbatim = ["alice@host:repo.git", "ssh://alice@host/~/repo.git", "SSH://alice@host/~/repo.git",
                "ssh+git://alice@host/~/x", "https://host/o/r.git", "file:///srv/x.git",
                "file://C:/projects/repo", "../remote.git", "C:/Users/a/repo", "git://host/x.git",
                "ssh://alice@host:22/~/x"]
    for raw in verbatim:
        got = bindable_endpoint(raw)
        if got != raw:
            p.append(f"bindable_endpoint({raw!r}) = {got!r}, expected it unchanged")
    for raw in (https_creds, https_token, ssh_creds, helper_creds, "transport::address",
                "./repo.git ", "ssh://host ", "file://host/share"):
        if bindable_endpoint(raw) is not None:
            p.append(f"{raw!r} was bound; credentials/whitespace/helper forms must be refused")
    if bindable_endpoint("SSH://host/x") == bindable_endpoint("ssh://host/x"):
        p.append("scheme case was folded: two spellings compare equal")
    # The CLOSED SET: every supported SSH spelling keeps its principal, and everything this
    # function does not fully understand is refused rather than canonicalized by a fallback.
    for scheme in ("ssh", "git+ssh", "ssh+git"):
        if bindable_endpoint(f"{scheme}://alice@host/~/x") ==            bindable_endpoint(f"{scheme}://bob@host/~/x"):
            p.append(f"{scheme}:// still collapses two logins to one endpoint")
        if bindable_endpoint(f"{scheme}://alice@host/~/x") != f"{scheme}://alice@host/~/x":
            p.append(f"{scheme}:// did not preserve the principal")
    if bindable_endpoint("alice@host:repo.git") == bindable_endpoint("bob@host:repo.git"):
        p.append("two SSH logins still collapse to one endpoint")
    pct = "%3A"
    refused = ["ssh://alice" + pct + "fixture@host/x",   # decodes to a password separator
               "ssh://alice%40evil@host/x", "ssh://@host/x", "git://user@host/x",
               "ftp://host/x.git", "ftps://host/x.git", "rsync://host/x", "unknown://host/x",
               "https://host/x?token=1", "alice%40host:repo.git"]
    for bad in refused:
        if bindable_endpoint(bad) is not None:
            p.append(f"unsupported endpoint form was bound: {bad!r} -> {bindable_endpoint(bad)!r}")

    # Gate 1 — the command gate, through the real writer and a changed remote.
    r.commit("B")
    git(r.work, "remote", "set-url", "origin", "alice@host:repo.git")
    rc, body, err = r.mint(PUSH)
    if body is None:
        p.append(f"writer could not bind an ssh remote: {err.strip()[-160:]}")
        return
    if body["updates"][0]["push_endpoint"] != "alice@host:repo.git":
        p.append(f"endpoint not bound as minted: {body['updates'][0]['push_endpoint']!r}")
    expect(r.gate(PUSH), "allow", None, "same-principal", p)
    git(r.work, "remote", "set-url", "origin", "bob@host:repo.git")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "changed-principal", p)

    # Gate 2 — the pre-push boundary, given the updates git would hand it for bob's remote.
    line = f"refs/heads/main {r.oid('main')} refs/heads/main {'0' * 40}"
    for endpoint, want in (("alice@host:repo.git", "allow"), ("bob@host:repo.git", "deny")):
        decision = evaluate_push_boundary(endpoint, [line], root=r.work)
        if decision.decision != want:
            p.append(f"boundary[{endpoint}]: expected {want} got {decision.decision} "
                     f"[{decision.approval_verdict}]")


def prefix_binding_revision(r: Repo, p: list[str]) -> None:
    """An artifact minted before the binding fixes must authorize nothing, and be RETAINED.

    Schema 3 never shipped, so this is our own development population — but the boundary
    skips the command digest, so a pre-fix artifact binding today's objects would otherwise
    authorize a real push (independent re-review of ae09d8b).
    """
    from shared.command_policy import evaluate_push_boundary
    r.commit("B")
    stale = r.write(prefix_artifact(r, PUSH, [upd("refs/heads/main", r.oid("main"))]))
    before = stale.read_bytes()
    expect(r.gate(PUSH), "deny", "LEGACY_SCHEMA", "command-gate", p)
    line = f"refs/heads/main {r.oid('main')} refs/heads/main {'0' * 40}"
    decision = evaluate_push_boundary("../remote.git", [line], root=r.work)
    if decision.decision != "deny":
        p.append(f"boundary accepted a pre-fix artifact: {decision.decision}")
    res = r.push("origin", "main")           # the artifact stays on disk for the real push
    if res.returncode == 0:
        p.append("a real push succeeded on a retained pre-fix artifact")
    if stale.read_bytes() != before:
        p.append("the rejected artifact was modified instead of preserved")
    inv = run(r.work, BASH, "hooks/local/approve-local.sh", "--inventory")
    if "LEGACY_SCHEMA" not in inv.stdout or "binding_revision" not in inv.stdout:
        p.append("inventory does not name the superseded binding revision")
    # A freshly minted artifact for the same push IS accepted, so this is not a blanket deny.
    rc, body, err = r.mint(PUSH)
    if not body or body.get("binding_revision") != 1:
        p.append(f"writer did not record binding_revision: {err.strip()[-140:]}")
    expect(r.gate(PUSH), "allow", None, "reissued", p)
    res = r.push("origin", "main")           # the reissue must actually carry a real push
    if res.returncode != 0:
        p.append(f"the reissued approval did not authorize the push: {res.stderr.strip()[-160:]}")


def record_boundaries(r: Repo, p: list[str]) -> None:
    """A configured endpoint must never be split, trimmed or rewritten on its way to storage.

    Reproduced on 5d0f9c4: `./repo.git\n` stored as `./repo.git`, and `./one<U+2028>./two`
    stored as TWO endpoints — the original then got boundary deny while the altered one got
    allow, on that same approval. Python's splitlines() breaks on far more than LF.
    """
    from shared.approval_artifact import bindable_endpoint, has_record_separator
    from shared.git_push_binding import boundary_updates, resolve_command_updates
    r.commit("B")
    sep_cases = {"trailing-newline": "./repo.git\n", "line-separator": "./one\u2028./two",
                 "paragraph-separator": "./a\u2029./b", "carriage-return": "./repo.git\r",
                 "next-line": "./a\u0085b", "vertical-tab": "./a\u000bb",
                 "form-feed": "./a\u000cb", "file-separator": "./a\u001cb"}
    for label, value in sep_cases.items():
        if not has_record_separator(value):
            p.append(f"{label}: separator not detected")
        if bindable_endpoint(value) is not None:
            p.append(f"{label}: bound despite a record separator")
        # The real path: configure it as the remote and ask the resolver for a binding.
        git(r.work, "remote", "set-url", "origin", value)
        got, why = resolve_command_updates(PUSH, r.work)
        if got is not None:
            stored = [u[0] for u in got]
            p.append(f"{label}: resolver bound {stored!r} from a separator-bearing URL")
        rc, body, err = r.mint(PUSH)
        if rc == 0 or body is not None:
            p.append(f"{label}: writer minted an artifact for a separator-bearing URL")
    git(r.work, "remote", "set-url", "origin", "../remote.git")

    # A ref name may legally carry U+2028; the boundary must refuse it, never split it.
    oid = r.oid("main")
    forged = f"refs/heads/main\u2028refs/heads/evil {oid} refs/heads/main\u2028x {'0' * 40}"
    got, why = boundary_updates("../remote.git", [forged])
    if got:
        p.append(f"boundary accepted a separator-bearing ref: {got!r}")
    # And the ordinary line still parses, so this is a refusal and not a blanket deny.
    good = f"refs/heads/main {oid} refs/heads/main {'0' * 40}"
    got, why = boundary_updates("../remote.git", [good])
    if not got or got[0][1] != "refs/heads/main":
        p.append(f"an ordinary update line stopped parsing: {got!r} {why}")


def single_value_resolution(r: Repo, p: list[str]) -> None:
    """One question, one answer: ambiguity, multi-URL remotes and multi-record output refuse.

    Round-6 findings: `--format=%(refname)%00` emits NUL AND LF, so NUL-only splitting lost
    later refs and an ambiguous `topic` bound `refs/heads/topic` instead of refusing; and a
    changed config snapshot let `./changed.git\n\n` keep a matching record count and bind a
    trimmed endpoint. Both parsers are gone; these rows pin what replaced them.
    """
    from shared.git_push_binding import _one_line, resolve_command_updates
    # The exact output shapes git produces, asserted directly against the reader.
    for shape, want in (("./one.git\n", "./one.git"), ("./changed.git\n\n", None),
                        ("a\nb\n", None), ("no-trailing-newline", None), ("", None),
                        ("refs/heads/main\x00\nrefs/heads/topic\x00\n", None)):
        got = _one_line(shape)
        if got != want:
            p.append(f"_one_line({shape!r}) = {got!r}, expected {want!r}")

    # A name that is BOTH a branch and a tag: git refuses that push; so must the binding.
    r.commit("B")
    git(r.work, "branch", "topic")
    git(r.work, "tag", "topic")
    for cmd in ("git push origin topic:refs/heads/main", "git push origin topic"):
        got, why = resolve_command_updates(cmd, r.work)
        if got is not None:
            p.append(f"ambiguous source bound anyway: {cmd!r} -> {[u[1:] for u in got]}")
        rc, body, err = r.mint(cmd)
        if rc == 0 or body is not None:
            p.append(f"writer minted an artifact for an ambiguous source: {cmd!r}")
    real = r.push("origin", "topic:refs/heads/main")      # git itself refuses it too
    if real.returncode == 0:
        p.append("git accepted the ambiguous push, so the refusal was not conservative")
    git(r.work, "tag", "-d", "topic")
    got, why = resolve_command_updates("git push origin topic:refs/heads/main", r.work)
    if got is None:
        p.append(f"unambiguous branch stopped resolving once the tag was gone: {why}")

    # A multi-URL remote pushes to several repositories at once: refuse, naming the remedy.
    git(r.work, "remote", "set-url", "--add", "--push", "origin", "../remote2.git")
    git(r.work, "remote", "set-url", "--add", "--push", "origin", "../remote.git")
    got, why = resolve_command_updates(PUSH, r.work)
    if got is not None:
        p.append(f"multi-URL remote bound {len(got)} endpoint(s) instead of refusing")
    elif "separately" not in why:
        p.append(f"multi-URL refusal does not name the remedy: {why!r}")


def config_spellings(r: Repo, p: list[str]) -> None:
    """Config that can remap refs refuses on PRESENCE; push.default matches git's spellings."""
    from shared.git_push_binding import resolve_command_updates
    r.commit("B")
    for key in ("push.recurseSubmodules", "remote.origin.mirror", "push.followTags",
                "remote.origin.push"):
        for value in ("no", "false", "0", "on-demand", "true"):
            git(r.work, "config", key, value)
            got, why = resolve_command_updates(PUSH, r.work)
            if got is not None:
                p.append(f"{key}={value!r} was set and still resolved")
            git(r.work, "config", "--unset-all", key)
    # push.default is compared against git's own spellings, case-sensitive and UNTRIMMED.
    for value, should_bind in (("simple", True), ("current", True), ("matching", True),
                               ("nothing", True), ("upstream", False), ("tracking", False),
                               ("Simple", False), ("simple\n", False), ("bogus", False)):
        git(r.work, "config", "push.default", value)
        got, why = resolve_command_updates(PUSH, r.work)
        if bool(got) != should_bind:
            p.append(f"push.default={value!r}: bound={bool(got)}, expected {should_bind} ({why})")
        git(r.work, "config", "--unset-all", "push.default")
    if resolve_command_updates(PUSH, r.work)[0] is None:
        p.append("a clean config stopped resolving after the push.default cases")

    # A config stream that ends mid-record was truncated or injected; it is not a snapshot.
    # The damage is not a wrong value, it is a key cut inside its NAME: `remote.origin.pus`
    # reads as ABSENT, so the presence check that exists to refuse `remote.origin.push` passes
    # and the push binds anyway. Framing is a property of the READ, so it is asserted there.
    import shared.git_push_binding as gpb
    real_git = gpb._git

    def unterminated(root, *args):
        rc, out = real_git(root, *args)
        if args[:3] == ("config", "--list", "-z") and rc == 0:
            return rc, out + "remote.origin.pus"       # the terminating NUL never arrives
        return rc, out

    gpb._git = unterminated
    try:
        got, why = resolve_command_updates(PUSH, r.work)
    finally:
        gpb._git = real_git
    if got is not None:
        p.append("an unterminated config stream resolved; a key cut off mid-name read as absent")


def exact_ref_lookup(r: Repo, p: list[str]) -> None:
    """A source ref is resolved by EXACT lookup, and the binding agrees with what git pushes.

    `rev-parse --verify refs/heads/topic` is a REVISION resolver, so it answers even when that
    ref does not exist (`refs/tags/refs/heads/topic`) and it never reports the ambiguity git's
    push matcher sees (round 7). Every assertion here goes through the module's own entry point
    and compares the result against what git ACTUALLY does with the same command — no private
    helper is imported, so the row discriminates on BEHAVIOUR, not on a symbol being present.
    """
    from shared.git_push_binding import resolve_command_updates
    base = r.oid("main")
    other = r.commit("B")
    git(r.work, "update-ref", "refs/heads/main", base)

    # Ambiguous sources: git refuses the push, so the binding must refuse too. A revision
    # resolver sees no ambiguity in either of these and confidently returns one object.
    git(r.work, "update-ref", "refs/heads/topic", base)
    git(r.work, "update-ref", "refs/tags/heads/topic", other)
    git(r.work, "update-ref", "refs/tags/refs/heads/topic", other)
    for src in ("heads/topic", "refs/heads/topic"):
        cmd = f"git push origin {src}:refs/heads/main"
        got, why = resolve_command_updates(cmd, r.work)
        real = r.push("origin", f"{src}:refs/heads/main")
        if got is not None:
            p.append(f"{src!r}: bound {[u[1:] for u in got]} where git says "
                     f"{real.stderr.strip().splitlines()[0][:60]!r}")
        elif "matches more than one" not in why:
            p.append(f"{src!r}: refusal does not name the ambiguity: {why!r}")
        if real.returncode == 0:
            p.append(f"{src!r}: git performed an ambiguous push, so refusing was not conservative")

    # A source that names no ref at all: git refuses, and so must the binding.
    git(r.work, "update-ref", "-d", "refs/heads/topic")
    git(r.work, "update-ref", "-d", "refs/tags/heads/topic")
    got, why = resolve_command_updates("git push origin topic:refs/heads/main", r.work)
    if got is not None:
        p.append(f"unresolvable source still bound: {[u[1:] for u in got]}")

    # The one case git DOES push: the binding must be the object git actually sends.
    got, why = resolve_command_updates("git push origin refs/heads/topic:refs/heads/main", r.work)
    if not got:
        p.append(f"the only ref strongly matching the source stopped binding: {why}")
    elif got[0][2] != other:
        p.append(f"bound {got[0][2]!r}, but the only matching ref holds {other!r}")
    else:
        rc, body, err = r.mint("git push origin refs/heads/topic:refs/heads/main")
        if not body:
            p.append(f"writer refused a push git performs: {err.strip()[-140:]}")
        else:
            res = r.push("origin", "refs/heads/topic:refs/heads/main")
            if res.returncode != 0:
                p.append(f"the push git performs was denied on its own binding: "
                         f"{res.stderr.strip()[-160:]}")
            remote_main = git(r.tmp / "remote.git", "rev-parse", "refs/heads/main")
            if remote_main != other:
                p.append(f"remote main is {remote_main!r}, expected the approved {other!r}")


def shadowed_head(r: Repo, p: list[str]) -> None:
    """`HEAD` as a source is the checked-out branch only while no ref shadows that name.

    Built on disk, pushed for real: with refs/tags/HEAD present, git reports
    `* [new tag] HEAD -> HEAD` and leaves refs/heads/main alone, so a resolver that answers
    with the symbolic ref names the wrong destination AND the wrong object. This row records
    what git does and requires the binding to agree with it or refuse (round 7 fix 1).
    """
    from shared.git_push_binding import resolve_command_updates
    a = r.oid("main")

    # Healthy first: nothing shadows HEAD, so the colon-less form still binds the branch.
    got, why = resolve_command_updates("git push origin HEAD", r.work)
    if not got or got[0][1] != "refs/heads/main" or got[0][2] != a:
        p.append(f"an unshadowed HEAD stopped binding the checked-out branch: {got} {why}")

    b = r.commit("B")
    git(r.work, "update-ref", "refs/heads/main", a)
    git(r.work, "update-ref", "refs/tags/HEAD", b)
    got, why = resolve_command_updates("git push origin HEAD", r.work)

    # What git ACTUALLY does with the same command, against the second remote so the recorded
    # behaviour is git's own and not a gate result.
    git(r.work, "remote", "add", "other", "../remote2.git")
    res = r.push("other", "HEAD")
    refs = dict(
        (line.split()[0], line.split()[1])
        for line in git(r.tmp / "remote2.git", "for-each-ref",
                        "--format=%(refname) %(objectname)").splitlines() if line)
    if res.returncode != 0 or refs.get("refs/tags/HEAD") != b:
        p.append(f"git did not do what this row is pinned to (rc={res.returncode}, "
                 f"remote2={refs}); re-establish the behaviour before trusting the assertion")
    if "refs/heads/main" in refs:
        p.append(f"git pushed the checked-out branch after all: {refs}")

    if got is None:
        if "shadow" not in why:
            p.append(f"refusal does not name the shadowing: {why!r}")
    elif (got[0][1], got[0][2]) != ("refs/tags/HEAD", b):
        p.append(f"bound {got[0][1:]} but git updated refs/tags/HEAD -> {b}")


def handler_route(r: Repo, p: list[str]) -> None:
    def hook(command: str) -> str:
        proc = run(r.work, sys.executable, str(r.work / "hooks/handlers/pre_tool_use.py"),
                   input_text=json.dumps({"event": "pre_tool_use", "cwd": str(r.work),
                                          "tool_name": "Bash", "tool_input": {"command": command}}))
        try:
            return json.loads(proc.stdout).get("decision", "")
        except Exception:
            return f"unparseable({proc.stdout[-120:]!r})"
    r.write({"schema_version": 2, "action": "production_deploy", "expires_at": FUTURE,
             "command_digest": compute_command_digest("fusebase deploy"),
             "repo_id": compute_repo_id(r.work)}, slug="legacy")
    if hook("fusebase deploy") != "deny":
        p.append("pre_tool_use accepted a schema-2 artifact")
    r.mint("fusebase deploy")
    if hook("fusebase deploy") != "allow":
        p.append("pre_tool_use rejected a writer-minted schema-3 artifact")


case("digest-omission-denies", digest_omission)
case("schema-and-profile-downgrade-denies", schema_downgrade)
case("legacy-rejected-preserved-and-inventoried", legacy_rejection)
case("branch-moved-head-fixed-denies", branch_moved_head_fixed)
case("head-moved-branch-fixed-allows", head_moved_branch_fixed)
case("identical-tree-different-commit-denies", identical_tree)
case("endpoint-change-denies-and-no-credentials", endpoint_change)
case("extra-refs-deny", extra_refs)
case("compound-command-mutation-denies", compound_mutation)
case("lookup-failures-fail-closed", lookup_failures)
case("unchanged-input-retry-allows", unchanged_retry)
case("replay-two-commits-authorizes-only-first", replay_two_commits)
case("pre-push-gates-destinations-only", boundary_scope)
case("writer-refuses-unbindable-and-labels-command-only", writer_refuses)
case("resolver-config-remaps-fail-closed", resolver_config_remaps)
case("dry-run-approval-cannot-authorize-a-real-push", dry_run_cannot_authorize)
case("ssh-principal-change-denies-at-both-gates", ssh_principal_binding)
case("pre-fix-binding-revision-authorizes-nothing", prefix_binding_revision)
case("endpoint-record-boundaries-are-never-split", record_boundaries)
case("single-value-resolution-refuses-ambiguity", single_value_resolution)
case("config-spellings-match-git-and-refuse-on-presence", config_spellings)
case("source-refs-resolve-by-exact-lookup", exact_ref_lookup)
case("shadowed-head-refuses-instead-of-guessing", shadowed_head)
case("pre-tool-use-handler-route", handler_route)
sys.exit(approval_fixture.FAILS)
PY
PY_FAILS=${PIPESTATUS[0]}
# TRIPWIRE: a python that dies before scoring (an import error, say) still exits nonzero, and
# printing "N-1/N PASS" for it would report a score no row produced. A phase that did not score
# says so.
if [ "$PY_FAILS" -ne 0 ] && ! grep -q "^FAIL: approval-schema3 " "$ROWS_OUT"; then
  echo "[test-approval-schema3] ABORTED: the row phase exited $PY_FAILS without scoring a row"
  rm -f "$ROWS_OUT"; exit "$PY_FAILS"
fi
rm -f "$ROWS_OUT"

# ---- The health report must agree with the gate (bash: the lib fills the CALLER's arrays) --
# A legacy command approval authorizes nothing, so it must not be reported ACTIVE; it surfaces
# as a warning naming the file. Path/deferral artifacts keep their own carrier's contract.
AA_DIR="$(mktemp -d)"
mkdir -p "$AA_DIR/state/approvals" "$AA_DIR/policies"
cp "$ROOT/policies/approval-policy.yml" "$ROOT/policies/command-policy.yml" "$AA_DIR/policies/"
cat > "$AA_DIR/state/approvals/production_deploy-legacy-20260728.json" <<'EOFL'
{"schema_version":2,"action":"production_deploy","scope":"legacy","expires_at":"2099-01-01T00:00:00Z"}
EOFL
cat > "$AA_DIR/state/approvals/health_check_deferral-x-20260728.json" <<'EOFD'
{"action":"health_check_deferral","scope":"x","expires_at":"2099-01-01T00:00:00Z","deferred_checks":["mirror_drift"]}
EOFD
AA_OUT="$(
  cd "$AA_DIR" || exit 1
  # shellcheck source=/dev/null
  . "$ROOT/hooks/local/lib/active-approvals.sh"
  ACTIVE_ARTIFACTS=(); ARTIFACT_NOTES=(); DEFERRED_CHECKS=(); DEFERRED_BY_ARTIFACT=(); APPROVAL_WARNINGS=()
  ffhc_collect_active_approvals
  printf 'ART:%s\n' "${ACTIVE_ARTIFACTS[@]:-}"
  printf 'WARN:%s\n' "${APPROVAL_WARNINGS[@]:-}"
  echo "DEFERRED=${DEFERRED_CHECKS[*]:-}"
)"
rm -rf "$AA_DIR"
aa_fail=""
case "$AA_OUT" in *"ART:production_deploy-legacy"*) aa_fail="$aa_fail [a legacy command approval was reported ACTIVE]" ;; *) ;; esac
case "$AA_OUT" in *"WARN:production_deploy-legacy-20260728.json: no longer authorizes commands"*) ;; *) aa_fail="$aa_fail [no warning naming the artifact]" ;; esac
case "$AA_OUT" in *"DEFERRED=mirror_drift"*) ;; *) aa_fail="$aa_fail [the deferral carrier stopped working]" ;; esac
if [ -z "$aa_fail" ]; then
  echo "PASS: approval-schema3 health-report-drops-legacy-command-approvals"
  AA_FAILS=0
else
  echo "FAIL: approval-schema3 health-report-drops-legacy-command-approvals ($aa_fail :: $AA_OUT)"
  AA_FAILS=1
fi

TOTAL_FAILS=$((PY_FAILS + AA_FAILS))
echo "[test-approval-schema3] $((25 - TOTAL_FAILS))/25 PASS"
exit "$TOTAL_FAILS"
