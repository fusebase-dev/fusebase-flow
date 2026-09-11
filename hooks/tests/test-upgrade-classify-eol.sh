#!/usr/bin/env bash
# Fusebase Flow — managed-content classification: the git-proven LF<->CRLF exception.
# Defect, contract and tampering table: docs/backlog/stamper-hashes-worktree-not-artifact/README.md.
#
# The consumer condition is built in SEPARATE repos: this repository ships a .gitattributes that
# forces LF, so it cannot reproduce the case by construction.
#
# Output contract (parsed by run-tests.sh): "PASS: upgrade-classify-eol <name>" /
# "FAIL: upgrade-classify-eol <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MCM="$ROOT/hooks/local/lib/managed_content_manifest.py"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: upgrade-classify-eol $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: upgrade-classify-eol $1 (${2:-})"; }
finish() { echo "[test-upgrade-classify-eol] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { bad "python3-present" "python3 not on PATH"; finish; }
[ -f "$MCM" ] || { bad "classifier-present" "missing $MCM"; finish; }

# ---- 1. Classifier boundary: every tampering row, run as upgrade.sh runs it (-I -S) ----
PY_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PYEOL' 2>&1
from __future__ import annotations
import hashlib, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(sys.argv[1])
LIB = ROOT / "hooks" / "local" / "lib"
MCM, HKM, PY = LIB / "managed_content_manifest.py", LIB / "hook_manifest.py", sys.executable
sys.path.insert(0, str(LIB))
import managed_content_manifest as mcm  # noqa: E402

TMP = Path(tempfile.mkdtemp())
CLEAN = "hooks/shared/clean.py"                # the accepted case; covered by BOTH manifests
QUIET = "workflows/wf.md"                      # upstream never changes it
TAMPER = ("unstaged", "staged", "committed", "mixed", "lone_cr", "nul_byte", "no_eol", "filtered",
          "attr_filter", "attr_unset", "attr_ident", "attr_wte", "untracked", "editor_crlf",
          "racer")
GITCFG = TMP / "gitconfig"
GITCFG.write_text("[user]\n\temail = t@t.t\n\tname = t\n[init]\n\tdefaultBranch = main\n"
                  "[core]\n\tautocrlf = false\n[gc]\n\tauto = 0\n[maintenance]\n\tauto = false\n")
ENV = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
# Host system config (Git for Windows ships autocrlf=true) must not decide a fixture's bytes.
ENV.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(GITCFG))
# The in-process _eol_proven rows below launch git through os.environ, not ENV, so the same
# isolation has to reach there or the host system config decides their verdicts.
os.environ.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(GITCFG))


def P(name: str) -> str:
    return f"hooks/shared/{name}.py"


def body(rel: str, version: str = "v1") -> bytes:
    return f"{Path(rel).stem} {version}\nsecond line\n".encode()


def crlf(data: bytes) -> bytes:
    return data.replace(b"\n", b"\r\n")


def emit(line: str) -> None:
    sys.stdout.buffer.write((line + "\n").encode("utf-8"))
    sys.stdout.buffer.flush()


def run(cmd, check=True):
    r = subprocess.run([str(c) for c in cmd], capture_output=True, env=ENV, timeout=120)
    if check and r.returncode:
        raise RuntimeError(f"{cmd[:4]} rc={r.returncode}: {r.stderr.decode('utf-8', 'replace')}")
    return r


def git(repo, *args, check=True):
    return run(["git", "-C", repo, *args], check=check)


def write(root: Path, rel: str, data: bytes) -> None:
    (root / rel).parent.mkdir(parents=True, exist_ok=True)
    (root / rel).write_bytes(data)


def h(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fresh(name: str) -> Path:
    return Path(tempfile.mkdtemp(prefix=name + "-", dir=TMP)) / name


def make_origin() -> Path:
    """The consumer's installed history: LF blobs plus the base manifest the install recorded."""
    o = fresh("origin")
    git(TMP, "init", "-q", o)
    write(o, "VERSION", b"4.6.1\n")
    for rel in [CLEAN, QUIET, "FLOW_RULES.md"] + [P(n) for n in TAMPER]:
        write(o, rel, body(rel))
    run([PY, MCM, "stamp", "--root", o])
    run([PY, HKM, "stamp", "--root", o])
    git(o, "add", "-A")
    git(o, "commit", "-qm", "install 4.6.1")
    return o


ORIGIN = make_origin()


def make_upstream(changed=None, drop=()) -> Path:
    u = fresh("upstream")
    write(u, "VERSION", b"4.7.0\n")
    for rel in [CLEAN, QUIET, "FLOW_RULES.md"] + [P(n) for n in TAMPER]:
        moved = rel not in (QUIET, "FLOW_RULES.md") and (changed is None or rel in changed)
        write(u, rel, body(rel, "v2" if moved else "v1"))
    write(u, "audit/hook-layer-manifest.json", (ORIGIN / "audit/hook-layer-manifest.json").read_bytes())
    for rel in drop:
        (u / rel).unlink()
    return u


UPSTREAM = make_upstream()


def consumer(autocrlf: str, attributes: str = "", config=()) -> Path:
    """A real clone + checkout: git itself writes the working-tree bytes."""
    c = fresh("consumer")
    git(TMP, "-c", f"core.autocrlf={autocrlf}", "clone", "-q", "--no-checkout", ORIGIN, c)
    git(c, "config", "core.autocrlf", autocrlf)
    for key, value in config:
        git(c, "config", key, value)
    if attributes:
        write(c, ".git/info/attributes", attributes.encode())
    git(c, "checkout", "-q", "HEAD", "--", ".")
    return c


def classify(c: Path, u: Path = UPSTREAM, base: Path | None = None) -> dict:
    base = base or c / "audit/managed-content-manifest.json"
    r = run([PY, "-I", "-S", MCM, "classify", "--json", "--root", c, "--upstream", u, "--base", base])
    return {row["path"]: row for row in json.loads(r.stdout)}


fails = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global fails
    if cond:
        emit(f"PASS: upgrade-classify-eol {name}")
    else:
        fails += 1
        emit(f"FAIL: upgrade-classify-eol {name} ({detail})")


def expect(name: str, rows: dict, path: str, want: str) -> None:
    row = rows.get(path)
    got = (row["classification"], bool(row.get("eol_proven"))) if row else None
    check(name, got == (want, want in ("upstream-only", "upstream-deleted-clean")), f"got {got}")


# ---- One autocrlf=true consumer carries every row, each on its own path ----
ATTRS = "".join(f"{P(n)} {a}\n" for n, a in (
    ("filtered", "filter=hide"), ("attr_filter", "filter=nodriver"), ("attr_unset", "-filter"),
    ("attr_ident", "ident"), ("attr_wte", "working-tree-encoding=UTF-8")))
c = consumer("true", ATTRS, (("filter.hide.smudge", "sed -e s/v1/EDITED/"),
                             ("filter.hide.clean", "sed -e s/EDITED/v1/")))
check("fixture-is-a-real-crlf-checkout",
      (c / CLEAN).read_bytes() == crlf(body(CLEAN)) and not (c / ".gitattributes").exists(),
      repr((c / CLEAN).read_bytes()))
filtered = (c / P("filtered")).read_bytes()
check("filter-fixture-hides-the-edit-from-git-status",
      b"EDITED" in filtered and not git(c, "status", "--porcelain", "--", P("filtered")).stdout,
      repr(filtered))

write(c, P("committed"), crlf(b"committed v1\n# local hardening\nsecond line\n"))
git(c, "add", P("committed"))
git(c, "rm", "-q", "--cached", P("untracked"))
git(c, "commit", "-qm", "local hardening; untrack one path")
check("committed-edit-fixture-matches-git-checkout",
      (c / P("committed")).read_bytes() == crlf(git(c, "cat-file", "-p", f"HEAD:{P('committed')}").stdout),
      "the installed digest must be the ONLY guard left")
check("untracked-fixture-still-crlf", (c / P("untracked")).read_bytes() == crlf(body(P("untracked"))))
write(c, P("unstaged"), crlf(b"unstaged v1\n# local hardening\nsecond line\n"))
write(c, P("staged"), crlf(b"staged v1\n# local hardening\nsecond line\n"))
git(c, "add", P("staged"))
for name, data in (("mixed", b"mixed v1\r\nsecond line\n"),
                   ("lone_cr", b"lone_cr\r v1\r\nsecond line\r\n"),
                   ("nul_byte", b"nul_byte v1\r\nsecond\0 line\r\n"),
                   ("no_eol", b"no_eol v1\r\nsecond line")):
    write(c, P(name), data)

manifest_before = (c / "audit/managed-content-manifest.json").read_bytes()
rows = classify(c)
expect("crlf-checkout-upstream-changed-is-upstream-only", rows, CLEAN, "upstream-only")
expect("crlf-checkout-upstream-unchanged-is-upstream-only", rows, QUIET, "upstream-only")
for name, label in (("unstaged", "unstaged-hook-edit-rejected"),
                    ("staged", "staged-hook-edit-rejected"),
                    ("committed", "committed-hook-edit-with-retained-base-rejected"),
                    ("mixed", "mixed-eol-rejected"), ("lone_cr", "lone-cr-rejected"),
                    ("nul_byte", "inserted-nul-rejected"), ("no_eol", "removed-trailing-newline-rejected"),
                    ("filtered", "filter-hiding-content-edit-rejected"),
                    ("attr_filter", "attribute-presence-blocks-proof-filter"),
                    ("attr_unset", "attribute-presence-blocks-proof-filter-unset"),
                    ("attr_ident", "attribute-presence-blocks-proof-ident"),
                    ("attr_wte", "attribute-presence-blocks-proof-working-tree-encoding"),
                    ("untracked", "path-absent-from-head-rejected")):
    expect(label, rows, P(name), "changed-by-both")

pf, rf = fresh("plan"), fresh("report")
r = run([PY, "-I", "-S", MCM, "plan", "--root", c, "--upstream", make_upstream(changed=(CLEAN,)),
         "--auto-yes", "--base", c / "audit/managed-content-manifest.json",
         "--plan-file", pf, "--report-file", rf], check=False)
report = rf.read_text(encoding="utf-8") if rf.is_file() else r.stderr.decode("utf-8", "replace")
plan_ops = pf.read_text(encoding="utf-8") if pf.is_file() else ""
check("plan-no-longer-aborts", r.returncode == 0 and f"copy\t{CLEAN}" in plan_ops,
      f"rc={r.returncode} :: {report}")
check("report-counts-line-ending-matches", "(line endings only)" in report, report)
check("base-manifest-bytes-unchanged",
      (c / "audit/managed-content-manifest.json").read_bytes() == manifest_before)
v1 = run([PY, MCM, "verify", "--root", c, "--json"], check=False)
v2 = run([PY, HKM, "verify", "--root", c, "--json"], check=False)
drift = {f["path"]: f["status"] for f in json.loads(v1.stdout or b"{}").get("files", [])}
check("integrity-verify-stays-exact-managed-content",
      v1.returncode == 1 and drift.get(CLEAN) == "modified", f"rc={v1.returncode} {drift.get(CLEAN)}")
check("integrity-verify-stays-exact-hook-layer",
      v2.returncode == 1 and CLEAN in v2.stdout.decode("utf-8", "replace"), f"rc={v2.returncode}")
expect("upstream-deleted-crlf-file-is-clean", classify(c, make_upstream(drop=(CLEAN,))),
       CLEAN, "upstream-deleted-clean")
bare = fresh("no-git")
shutil.copytree(c, bare, ignore=shutil.ignore_patterns(".git"))
expect("no-git-evidence-rejected", classify(bare), CLEAN, "changed-by-both")
check("no-base-stays-unknown-base",
      classify(c, base=fresh("nobase"))[CLEAN]["classification"] == "unknown-base")

# ---- autocrlf=false: an older CRLF base digest, and CRLF git would not write ----
c2 = consumer("false")
doc = json.loads((c2 / "audit/managed-content-manifest.json").read_text(encoding="utf-8"))
for asset in doc["assets"]:
    if asset["path"] == CLEAN:
        asset["sha256"] = h(crlf(body(CLEAN)))
crlf_base = fresh("crlf-base")
crlf_base.write_text(json.dumps(doc), encoding="utf-8")
write(c2, P("editor_crlf"), crlf(body(P("editor_crlf"))))
rows2 = classify(c2, base=crlf_base)
expect("lf-checkout-against-crlf-base-is-upstream-only", rows2, CLEAN, "upstream-only")
expect("crlf-not-written-by-git-rejected", rows2, P("editor_crlf"), "changed-by-both")

# ---- Function level: the clean grant, concurrent change, unsafe paths, mutations ----
base = {CLEAN: h(body(CLEAN))}
check("proof-grants-the-clean-case",
      mcm._eol_proven(c, c, base, {CLEAN: h((c / CLEAN).read_bytes())}, [CLEAN]) == {CLEAN})
check("concurrent-byte-change-rejected",
      mcm._eol_proven(c, c, base, {CLEAN: h(b"hashed before the file changed")}, [CLEAN]) == set())
unsafe = ("../x", "a/./b", "a//b", " lead", "trail ", "a\nb", "a\\b", "a\x7fb")
check("unsafe-paths-rejected", not any(mcm._safe_rel(c, p) for p in unsafe),
      str([p for p in unsafe if mcm._safe_rel(c, p)]))
try:
    os.symlink(c / "hooks" / "shared", c / "hooks" / "linked", target_is_directory=True)
    linked = True
except OSError:
    linked = False                                 # unprivileged Windows: no symlink to test
if linked:
    check("symlinked-ancestor-rejected", not mcm._safe_rel(c, "hooks/linked/clean.py"))

# ---- Interleaving: an edit and a filter attribute that land WHILE git runs ----
# `_git` is the ONLY boundary the proof crosses into git; firing on check-attr puts the race
# exactly where it is real - after the local read and the attribute snapshot, before conversion.
real_git, race = mcm._git, [None]


def racing_git(*a, **k):                       # signature-agnostic: also drives a RED baseline
    out = real_git(*a, **k)
    if a[1][0] == "check-attr" and race[0]:
        race[0]()
    return out


mcm._git = racing_git
cbase, clocal = {CLEAN: h(body(CLEAN))}, {CLEAN: h((c / CLEAN).read_bytes())}
race[0] = lambda: write(c, CLEAN, crlf(b"clean v1\n# landed mid-proof\nsecond line\n"))
check("edit-during-git-confirmation-rejected",
      mcm._eol_proven(c, c, cbase, clocal, [CLEAN]) == set())
write(c, CLEAN, crlf(body(CLEAN)))
if linked:
    race[0] = lambda: ((c / CLEAN).unlink(), os.symlink(c / QUIET, c / CLEAN))
    check("symlink-swap-during-git-confirmation-rejected",
          mcm._eol_proven(c, c, cbase, clocal, [CLEAN]) == set())
    (c / CLEAN).unlink()
    write(c, CLEAN, crlf(body(CLEAN)))

RACER, MARK = P("racer"), TMP / "smudge-driver-ran"
git(c, "config", "filter.marker.smudge", f"printf ran > '{MARK.as_posix()}'; cat")
race[0] = lambda: write(c, ".git/info/attributes", (ATTRS + f"{RACER} filter=marker\n").encode())
granted = mcm._eol_proven(c, c, {RACER: h(body(RACER))},
                          {RACER: h((c / RACER).read_bytes())}, [RACER])
mcm._git, race[0] = real_git, None
check("filter-attribute-added-mid-proof-executes-no-driver",
      not MARK.exists() and granted == {RACER}, f"marker={MARK.exists()} granted={granted}")
oid = git(c, "rev-parse", f"HEAD:{RACER}").stdout.decode("ascii").strip()
git(c, "cat-file", "--filters", f"--path={RACER}", oid)
check("marker-proves-that-driver-really-runs", MARK.exists(), "the negative row would be vacuous")
write(c, ".git/info/attributes", ATTRS.encode())

# ---- Config snapshot: one record per setting, whatever the value contains ----
def poisoned(config=(), raw=""):
    """A consumer whose core.* config the proof reads back; local bytes are hand-written CRLF."""
    p = consumer("false", "", config)
    if raw:
        with (p / ".git/config").open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(raw)
    write(p, CLEAN, crlf(body(CLEAN)))
    return p, {CLEAN: h(body(CLEAN))}, {CLEAN: h(crlf(body(CLEAN)))}


pe, be, le = poisoned(config=(("core.eol", "lf\ncore.autocrlf true"),))
check("config-value-newline-cannot-mint-a-second-setting",
      mcm._eol_proven(pe, pe, be, le, [CLEAN]) == set(),
      "core.autocrlf is false in this repo, so git would not write CRLF here")
pv, bv, lv = poisoned(raw="[core]\n\tautocrlf\n")
check("valueless-boolean-reads-as-gits-implicit-true",
      mcm._eol_proven(pv, pv, bv, lv, [CLEAN]) == {CLEAN},
      "a valueless core.autocrlf is true and overrides the earlier false")
pu, bu, lu = poisoned()
git(pu, "config", "--unset", "core.autocrlf")
os.environ["GIT_CONFIG_GLOBAL"] = os.devnull        # now NO core.* setting exists in any scope
check("absent-core-config-falls-back-to-gits-own-defaults",
      mcm._eol_proven(pu, pu, bu, lu, [CLEAN]) == set(),
      "no core.autocrlf/core.eol at all: autocrlf is false, so git would not write CRLF")
os.environ["GIT_CONFIG_GLOBAL"] = str(GITCFG)

real_confirm, survivors, mutations = mcm._git_confirm, [], 0
mcm._git_confirm = lambda root, pending: set(pending)       # observe the digest prefilter alone
lcrlf, probe = crlf(body(CLEAN)), fresh("mutations")
alphabet = [bytes([v]) for v in range(256)]                 # every byte, not a chosen few
variants = [lcrlf[:i] + lcrlf[i + 1:] for i in range(len(lcrlf))]
variants += [lcrlf[:i] + b + lcrlf[i:] for i in range(len(lcrlf) + 1) for b in alphabet]
variants += [lcrlf[:i] + b + lcrlf[i + 1:] for i in range(len(lcrlf)) for b in alphabet]
for m in variants:
    if m == lcrlf:
        continue
    mutations += 1
    write(probe, CLEAN, m)
    if mcm._eol_proven(probe, probe, base, {CLEAN: h(m)}, [CLEAN]):
        survivors.append(m)
mcm._git_confirm = real_confirm
check("single-byte-mutations-never-pass-the-anchor", not survivors and mutations > 10000,
      f"{len(survivors)}/{mutations}: {survivors[:3]}")

shutil.rmtree(TMP, ignore_errors=True)
emit(json.dumps({"fails": fails}))
PYEOL
)"
PY_RC=$?
printf '%s\n' "$PY_OUT" | tr -d '\r' | grep -E '^(PASS|FAIL): upgrade-classify-eol ' || true
p="$(printf '%s\n' "$PY_OUT" | tr -d '\r' | grep -c '^PASS: upgrade-classify-eol ')"
f="$(printf '%s\n' "$PY_OUT" | tr -d '\r' | grep -c '^FAIL: upgrade-classify-eol ')"
pass=$((pass + p)); fail=$((fail + f))
if ! printf '%s\n' "$PY_OUT" | tr -d '\r' | tail -1 | grep -q '^{"fails": '; then
  bad "classifier-rows-completed" "rc=$PY_RC :: $(printf '%s\n' "$PY_OUT" | tail -8 | tr '\n' '|')"
fi

# ---- 2. END-TO-END: the real upgrade.sh no longer stops a CRLF consumer at exit 3 -------
# shellcheck source=lib/upgrade-fixtures.sh
. "$ROOT/hooks/tests/lib/upgrade-fixtures.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin"; C="$TMP/consumer"; U="$C/.fusebase-flow-source"
mkdir -p "$O/hooks/shared" "$O/hooks/local/lib" "$O/workflows"
git init -q "$O"
git -C "$O" config user.email t@t.t; git -C "$O" config user.name t; git -C "$O" config core.autocrlf false
printf '4.6.1\n' > "$O/VERSION"
printf 'validator v1\nsecond line\n' > "$O/hooks/shared/clean.py"
printf 'wf v1\nbody\n' > "$O/workflows/wf.md"
cp "$ROOT/hooks/local/upgrade.sh" "$ROOT/hooks/local/bootstrap-upgrade.sh" "$O/hooks/local/"
cp "$MCM" "$O/hooks/local/lib/"
copy_boundary_libs "$O/hooks/local/lib"
( cd "$O" && python3 "$MCM" stamp --root . >/dev/null 2>&1 )
git -C "$O" add -A; git -C "$O" commit -qm "install 4.6.1"
git -c core.autocrlf=true clone -q --no-checkout "$O" "$C"
git -C "$C" config core.autocrlf true
# TRIPWIRE (platform): Linux bash refuses a CRLF script, so only *.sh is pinned LF — in
# info/attributes, keeping the consumer's tree free of .gitattributes. The measurands are .py/.md.
printf '*.sh text eol=lf\n' > "$C/.git/info/attributes"
git -C "$C" checkout -q HEAD -- .
mkdir -p "$U"
cp -R "$O/hooks" "$O/workflows" "$O/audit" "$O/VERSION" "$U/"
printf '4.7.0\n' > "$U/VERSION"
printf 'validator v2\nsecond line\n' > "$U/hooks/shared/clean.py"
( cd "$U" && python3 "$MCM" stamp --root . >/dev/null 2>&1 )
if has_cr "$C/hooks/shared/clean.py" && has_cr "$C/workflows/wf.md"; then
  ( cd "$C" && bash hooks/local/upgrade.sh --auto-yes ) > "$TMP/e2e.log" 2>&1
  E2E_RC=$?
  e2e_fail=""
  [ "$E2E_RC" -eq 0 ] || e2e_fail="$e2e_fail [rc $E2E_RC, expected 0 — 3 is the reported defect]"
  grep -q "BOTH changed these" "$TMP/e2e.log" && e2e_fail="$e2e_fail [changed-by-both reported]"
  cmp -s "$U/hooks/shared/clean.py" "$C/hooks/shared/clean.py" \
    || e2e_fail="$e2e_fail [upstream change not delivered]"
  grep -q "(line endings only)" "$TMP/e2e.log" || e2e_fail="$e2e_fail [report omits the line-ending count]"
  [ "$(tr -d '\n\r' < "$C/VERSION")" = "4.7.0" ] || e2e_fail="$e2e_fail [VERSION did not advance]"
  if [ -z "$e2e_fail" ]; then ok "e2e-crlf-consumer-upgrades-instead-of-exit-3"
  else bad "e2e-crlf-consumer-upgrades-instead-of-exit-3" "$e2e_fail :: $(tail -12 "$TMP/e2e.log" | tr '\n' '|')"; fi
else
  bad "e2e-crlf-consumer-upgrades-instead-of-exit-3" "fixture error: git did not check the consumer out CRLF"
fi

finish
