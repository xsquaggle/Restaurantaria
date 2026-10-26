#!/usr/bin/env python3
"""Runs the server checks outside Studio with the Luau CLI and a mock of the Roblox APIs they
use (tests/offline/mock.luau). Mock evidence only: no engine, DataStore, network or player.

Usage: python3 -I tests/offline/run.py [check.luau ...]
The Luau CLI (https://github.com/luau-lang/luau/releases) must be on PATH or named by $LUAU.
With no arguments it runs the checks listed in DEFAULT_CHECKS.
"""

import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_CHECKS = [
    "tests/tutorial_bonus_check.luau",
    "tests/save_settlement_check.luau",
    "tests/save_backend_check.luau",
    "tests/summary_lines_check.luau",
    "tests/prep_check.luau",
    "tests/cut_check.luau",
]


def long_string(text):
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    # A long string drops one leading newline, so keep the first line intact.
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def main():
    checks = sys.argv[1:] or DEFAULT_CHECKS
    sources = sorted(p for p in (ROOT / "src").rglob("*.luau"))
    out = ["local SOURCES = {"]
    for p in sources:
        rel = p.relative_to(ROOT).as_posix()
        out.append("[ %s ] = %s," % (long_string(rel), long_string(p.read_text(encoding="utf-8"))))
    out.append("}")
    out.append("local TESTS = {")
    for c in checks:
        text = (ROOT / c).read_text(encoding="utf-8")
        out.append("{ path = %s, source = %s }," % (long_string(c), long_string(text)))
    out.append("}")
    out.append((ROOT / "tests/offline/mock.luau").read_text(encoding="utf-8"))
    luau = os.environ.get("LUAU", "luau")
    with tempfile.TemporaryDirectory() as tmp:
        bundle = pathlib.Path(tmp) / "bundle.luau"
        bundle.write_text("\n".join(out), encoding="utf-8")
        result = subprocess.run([luau, str(bundle)])
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
