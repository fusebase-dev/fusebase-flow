"""Fusebase Flow — policy_loader.

Loads YAML policies from policies/, layers an optional .local
override on top, and caches per-process. Handlers call get_policy(name) and
get back a plain dict. Schema validation is intentionally minimal in v0.1;
hooks treat unknown keys defensively rather than failing closed on schema drift.

A .local override only ever TIGHTENS (6.0.0-m7 item 5, review r2-34): it may add deny and
approval rules, protected paths and secret patterns, lower a TTL or a limit, and turn a
strict switch on; it never removes, replaces or weakens a shipped entry, and any other key
it holds is dropped. What a project loosens belongs in a committed, protected file.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

try:
    import yaml  # PyYAML; standard hook runtime dep
except ImportError:  # pragma: no cover
    raise SystemExit(
        "PyYAML is required for Fusebase Flow hooks. Install with: pip install pyyaml"
    )


_POLICY_CACHE: dict[str, dict[str, Any]] = {}


def find_git_root(start: Path | None = None) -> Path:
    """Walk up from start (default: cwd) until a .git directory is found."""
    p = (start or Path.cwd()).resolve()
    for candidate in [p, *p.parents]:
        if (candidate / ".git").exists():
            return candidate
    # Fallback: if no .git, treat the FUSEBASE_FLOW_ROOT env var as authoritative.
    env_root = os.environ.get("FUSEBASE_FLOW_ROOT")
    if env_root:
        return Path(env_root)
    raise FileNotFoundError(
        "Cannot locate git root from cwd; set FUSEBASE_FLOW_ROOT to override."
    )


def policies_dir(root: Path | None = None) -> Path:
    return (root or find_git_root()) / "policies"


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"Policy file {path} must contain a mapping at top level.")
    return data


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Override wins on scalar/list collisions; dicts merge recursively."""
    out = dict(base)
    for k, v in override.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def get_policy(name: str, *, root: Path | None = None, refresh: bool = False) -> dict[str, Any]:
    """Load policy by base filename (without .yml). Layers .local override if present.

    Example: get_policy("command-policy") loads command-policy.yml and merges
    command-policy.local.yml on top if it exists.
    """
    cache_key = f"{root or ''}::{name}"
    if not refresh and cache_key in _POLICY_CACHE:
        return _POLICY_CACHE[cache_key]

    pdir = policies_dir(root)
    base = _load_yaml(pdir / f"{name}.yml")
    local = _load_yaml(pdir / f"{name}.local.yml")
    # TRIPWIRE (6.0.0-m7 item 5, review r2-34): a gitignored local file only ever tightens, whatever the
    # committed file's local_override_may_relax says. Written through Bash, `deny: []` in
    # command-policy.local.yml used to empty the deny list and let `git commit --no-verify` through.
    merged = _tighten(name, base, local) if local else base
    _POLICY_CACHE[cache_key] = merged
    return merged


def _tighten(name: str, base: dict[str, Any], local: dict[str, Any]) -> dict[str, Any]:
    """The shipped policy plus what `local` may add to it; every other local key is dropped."""
    out = dict(base)
    if name == "command-policy":  # more deny and approval rules; never fewer, never an allow or a default
        for stage in ("deny", "require_approval"):
            mine = list(base.get(stage) or [])
            out[stage] = mine + [r for r in local.get(stage) or [] if isinstance(r, dict) and r not in mine]
    elif name == "secret-patterns":  # more patterns; a shipped id keeps its shipped entry; no whitelist
        mine = list(base.get("patterns") or [])
        ids = {p.get("id") for p in mine if isinstance(p, dict)}
        out["patterns"] = mine + [p for p in local.get("patterns") or [] if isinstance(p, dict) and p.get("id") not in ids]
    elif name == "protected-paths":  # more paths and categories; never fewer (T27/#5)
        cats = {k: dict(v) for k, v in (base.get("categories") or {}).items() if isinstance(v, dict)}
        for cat, cfg in (local.get("categories") or {}).items():
            if isinstance(cfg, dict):
                cats.setdefault(cat, {k: v for k, v in cfg.items() if k != "paths"})
                cats[cat]["paths"] = list(dict.fromkeys([*(cats[cat].get("paths") or []),
                                                        *[p for p in cfg.get("paths") or [] if isinstance(p, str)]]))
        out = _restrict_protected_paths_additive(base, {**out, "categories": cats})
    elif name == "approval-policy":
        out = _deep_merge(base, _restrict_to_tightening(base, local))
    return out


def _lower(have: Any, want: Any) -> Any:
    """`want` where it is a positive number not above `have` (per mode for a mapping), else `have`."""
    if isinstance(have, dict) and isinstance(want, dict):
        return {k: _lower(v, want.get(k, v)) for k, v in have.items()}
    ok = all(isinstance(x, int) and not isinstance(x, bool) for x in (have, want)) and 0 < want <= have
    return want if ok else have


def _restrict_protected_paths_additive(base: dict[str, Any], merged: dict[str, Any]) -> dict[str, Any]:
    """For protected-paths: guarantee every base category's paths survive a local override.

    Additive-only: the merged category paths = union(base paths, merged paths), so a local
    override can ADD paths but never remove/empty a base category (esp. fusebase_flow_internals).
    A base category the local dropped entirely is restored. Order-preserving, dedup'd.
    """
    base_cats = base.get("categories")
    if not isinstance(base_cats, dict):
        return merged
    out = dict(merged)
    cats = dict(out.get("categories") or {})
    for name, base_cfg in base_cats.items():
        if not isinstance(base_cfg, dict):
            continue
        base_paths = base_cfg.get("paths") or []
        merged_cfg = dict(cats.get(name) or {})
        merged_paths = merged_cfg.get("paths") or []
        union: list[str] = []
        seen: set[str] = set()
        for p in [*base_paths, *merged_paths]:
            if p not in seen:
                seen.add(p)
                union.append(p)
        merged_cfg["paths"] = union
        cats[name] = merged_cfg
    out["categories"] = cats
    return out


def _restrict_to_tightening(base: dict[str, Any], local: dict[str, Any]) -> dict[str, Any]:
    """For approval-policy: what a local override may set. An approval stays enforced, a TTL or gate_rounds only drops,
    deny stays deny, strict_approvals only turns on; a new action may be added whole. Every other key (workflow_mode,
    approval_artifact_dir, local_override_may_relax ...) is dropped (6.0.0-m7 item 5)."""
    out: dict[str, Any] = {}
    ops = {}
    for op, cfg in (local.get("require_approval") or {}).items():
        base_op = (base.get("require_approval") or {}).get(op)
        if not isinstance(cfg, dict):
            continue
        if not isinstance(base_op, dict):
            ops[op] = {**cfg, "enforce": True}
            continue
        ops[op] = {"enforce": True} if cfg.get("enforce") is True else {}
        if "artifact_ttl_minutes" in cfg and "artifact_ttl_minutes" in base_op:
            ops[op]["artifact_ttl_minutes"] = _lower(base_op["artifact_ttl_minutes"], cfg["artifact_ttl_minutes"])
    if ops:
        out["require_approval"] = ops
    for key in ("on_missing_artifact", "on_expired_artifact"):
        if local.get(key) == "deny":
            out[key] = "deny"
    # TRIPWIRE (K7): strict_approvals is tighten-only. Once the base default flips to
    # true, a gitignored approval-policy.local.yml must not be able to set it back to
    # false — that would be an invisible kill switch on the schema gate. Local may only
    # turn it ON.
    if local.get("strict_approvals") is True:
        out["strict_approvals"] = True
    if "gate_rounds" in local:
        out["gate_rounds"] = _lower(base.get("gate_rounds"), local["gate_rounds"])
    # TRIPWIRE (M9): stale_approval_warn_after_days is tighten-only and LOWER days is
    # TIGHTER. An invalid or raised value RAISES rather than being coerced to base: a
    # silent coercion is indistinguishable from acceptance to whoever wrote the override,
    # and this key exists so a forgotten approval cannot stay invisible.
    if "stale_approval_warn_after_days" in local:
        want = local["stale_approval_warn_after_days"]
        have = base.get("stale_approval_warn_after_days")
        if isinstance(want, bool) or not isinstance(want, int) or want < 1:
            raise ValueError(
                "approval-policy.local.yml: stale_approval_warn_after_days must be a "
                f"positive integer number of days, got {want!r}."
            )
        if isinstance(have, int) and not isinstance(have, bool) and want > have:
            raise ValueError(
                "approval-policy.local.yml: stale_approval_warn_after_days may only be "
                f"lowered or equal (lower days = tighter). Shipped value is {have}, local "
                f"asked for {want}, and local_override_may_relax is false."
            )
        out["stale_approval_warn_after_days"] = want
    return out


def reset_cache() -> None:
    """Test helper: clear the cache between calls."""
    _POLICY_CACHE.clear()


__all__ = ["get_policy", "find_git_root", "policies_dir", "reset_cache"]
