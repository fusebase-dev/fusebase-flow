"""Fusebase Flow — policy_loader.

Loads YAML policies from policies/, layers an optional .local
override on top, and caches per-process. Handlers call get_policy(name) and
get back a plain dict. Schema validation is intentionally minimal in v0.1;
hooks treat unknown keys defensively rather than failing closed on schema drift.
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

    # Honor approval-policy.yml: local_override_may_relax flag for approval-policy specifically.
    if name == "approval-policy" and base.get("local_override_may_relax") is False and local:
        # Local override may only tighten, never relax. Drop any keys that would relax.
        local = _restrict_to_tightening(base, local)

    merged = _deep_merge(base, local)
    _POLICY_CACHE[cache_key] = merged
    return merged


def _restrict_to_tightening(base: dict[str, Any], local: dict[str, Any]) -> dict[str, Any]:
    """For approval-policy: drop local entries that would relax (e.g., set enforce: false
    where base has enforce: true). Conservative: when in doubt, keep base."""
    out = dict(local)
    if "require_approval" in local and isinstance(local["require_approval"], dict):
        for op, cfg in list(out["require_approval"].items()):
            base_op = (base.get("require_approval") or {}).get(op)
            if base_op and isinstance(cfg, dict) and isinstance(base_op, dict):
                if base_op.get("enforce") is True and cfg.get("enforce") is False:
                    cfg["enforce"] = True  # tighten, don't relax
    if local.get("on_missing_artifact") == "warn" and base.get("on_missing_artifact") == "deny":
        out["on_missing_artifact"] = "deny"
    if local.get("on_expired_artifact") == "warn" and base.get("on_expired_artifact") == "deny":
        out["on_expired_artifact"] = "deny"
    return out


def reset_cache() -> None:
    """Test helper: clear the cache between calls."""
    _POLICY_CACHE.clear()


__all__ = ["get_policy", "find_git_root", "policies_dir", "reset_cache"]
