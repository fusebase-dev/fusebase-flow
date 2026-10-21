#!/usr/bin/env python3
"""The post-publish re-check of core-release.yml (6.0.0-m8 item 5, M6-11; review r1-60, r2-101; O-8): after a release is
published, or found already published, its tag must still name the commit core-verify verified.

  python3 maintainer/release_check.py --tag <tag> --sha <verified commit> [--repo owner/name] [--api URL]

Reads GitHub's REST API (GH_TOKEN or GITHUB_TOKEN when set): the release for the tag, then the tag's ref, dereferenced
through annotated tag objects to its commit. Exit 0 when the release exists and the tag names that commit; 1, with an
::error:: line naming both commits, when it does not or when the API cannot answer (a check that cannot run fails).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TRIES, PAUSE = 3, 5.0  # a release just created can take a moment to be readable


def get(api: str, path: str, token: str) -> dict:
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "fusebase-flow-release-check"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    for attempt in range(1, TRIES + 1):
        try:
            with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=60) as reply:
                return json.loads(reply.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if attempt == TRIES or exc.code not in (404, 500, 502, 503, 504):
                raise
        except urllib.error.URLError:
            if attempt == TRIES:
                raise
        time.sleep(PAUSE)
    raise RuntimeError("unreachable")


def tag_commit(api: str, repo: str, tag: str, token: str) -> str:
    """The commit `tag` names, through any annotated tag objects."""
    obj = get(api, f"/repos/{repo}/git/ref/tags/{urllib.parse.quote(tag)}", token)["object"]
    for _ in range(8):
        if obj.get("type") == "commit":
            return str(obj["sha"])
        if obj.get("type") != "tag":
            raise ValueError(f"tag {tag} names a {obj.get('type')!r}, not a commit")
        obj = get(api, f"/repos/{repo}/git/tags/{obj['sha']}", token)["object"]
    raise ValueError(f"tag {tag}: more than 8 nested tag objects")


def check(api: str, repo: str, tag: str, sha: str, token: str) -> str:
    """"" when the release for `tag` exists and the tag names `sha`, else why."""
    try:
        release = get(api, f"/repos/{repo}/releases/tags/{urllib.parse.quote(tag)}", token)
        if release.get("tag_name") != tag:
            return f"the release found for {tag} is {release.get('tag_name')!r}"
        named = tag_commit(api, repo, tag, token)
    except (urllib.error.URLError, ValueError, KeyError, TypeError) as exc:
        return f"the API could not confirm the release {tag} ({exc})"
    if named != sha:
        return (f"the published release {tag} now names commit {named}, not {sha}, the commit core-verify verified: "
                "the tag moved after verification; the release must not stand on an unverified commit")
    return ""


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="release_check.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--tag", required=True)
    ap.add_argument("--sha", required=True, help="the verified commit (GITHUB_SHA)")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    ap.add_argument("--api", default=os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    args = ap.parse_args(argv)
    if not args.repo:
        ap.error("--repo (or GITHUB_REPOSITORY) is required")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    why = check(args.api.rstrip("/"), args.repo, args.tag, args.sha, token)
    if why:
        print(f"::error::{why}")
        return 1
    print(f"release {args.tag} names the verified commit {args.sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
