"""Load the packaged default mapping, optionally overlaid by a user TOML file."""

from __future__ import annotations

import tomllib
from importlib import resources
from pathlib import Path


def _merge(base: dict, override: dict) -> dict:
    out = dict(base)
    for k, v in override.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config(path: str | Path | None = None) -> dict:
    text = resources.files("lc6000_bridge").joinpath("default_mapping.toml").read_text()
    cfg = tomllib.loads(text)
    if path:
        with open(path, "rb") as f:
            cfg = _merge(cfg, tomllib.load(f))
    return cfg
