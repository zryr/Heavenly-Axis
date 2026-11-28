#!/usr/bin/env python3
"""Run isolated Lua 5.4 test suites and syntax-check bundled Lua sources."""
from __future__ import annotations

import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    try:
        from lupa.lua54 import LuaRuntime, LuaError
    except ImportError:
        print("Install dev dependencies: python3 -m pip install -r requirements-dev.txt", file=sys.stderr)
        return 1
    os.chdir(ROOT)
    suites = sorted((ROOT / "tests").glob("*.lua"))
    if not suites:
        print("Failed: no tests/*.lua found", file=sys.stderr)
        return 1
    failures = 0
    count = 0
    for suite in suites:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("package.path = './src/?.lua;./tests/?.lua;' .. package.path")
        try:
            result = lua.execute(suite.read_text(encoding="utf-8"), name="@" + str(suite.relative_to(ROOT)))
            cases = result if isinstance(result, int) and not isinstance(result, bool) else 1
            count += cases
            print(f"Passed: {suite.relative_to(ROOT)} ({cases} checks)", flush=True)
        except (LuaError, Exception) as exc:
            failures += 1
            print(f"Failed: {suite.relative_to(ROOT)}\n{exc}", file=sys.stderr, flush=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    syntax_files = sorted((ROOT / "src").glob("*.lua")) + sorted((ROOT / "studio").glob("*.lua"))
    syntax_files += [p for p in (ROOT / "Source", ROOT / "dist/HeavenlyAxis.lua") if p.exists()]
    compile_lua = lua.eval("function(source, name) local fn, err = load(source, name); if not fn then error(err) end end")
    for path in syntax_files:
        try:
            compile_lua(path.read_text(encoding="utf-8"), "@" + str(path.relative_to(ROOT)))
        except LuaError as exc:
            failures += 1
            print(f"Failed syntax: {path.relative_to(ROOT)}\n{exc}", file=sys.stderr)
    print(f"{len(suites)} suites, {count} reported checks, {len(syntax_files)} Lua syntax checks, {failures} failures", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
