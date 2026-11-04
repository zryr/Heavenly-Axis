#!/usr/bin/env python3
"""Compile every maintained Lua file with a pinned Luau release (Linux x86_64)."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import platform
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.728"
SHA256 = "d3c81eb98c048c118a1fa0b0d3777e52226b5152e2df4f31d1baf660f7f0c115"
URL = f"https://github.com/luau-lang/luau/releases/download/{VERSION}/luau-ubuntu.zip"


def compiler() -> Path:
    override = os.environ.get("LUAU_COMPILE")
    if override:
        return Path(override).resolve()
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise RuntimeError("Set LUAU_COMPILE to your installed luau-compile executable on this platform")
    directory = ROOT / "work" / f"luau-{VERSION}"
    archive = directory / "luau-ubuntu.zip"
    executable = directory / "luau-compile"
    directory.mkdir(parents=True, exist_ok=True)
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        with urllib.request.urlopen(URL, timeout=60) as response:
            contents = response.read(32 * 1024 * 1024)
        if hashlib.sha256(contents).hexdigest() != SHA256:
            raise RuntimeError("Luau compiler archive checksum mismatch")
        archive.write_bytes(contents)
    # Re-extract from the verified archive; do not trust a modified cached executable.
    with zipfile.ZipFile(archive) as zipped:
        executable.write_bytes(zipped.read("luau-compile"))
    executable.chmod(0o755)
    return executable


def main() -> int:
    try:
        executable = compiler()
    except (OSError, RuntimeError) as exc:
        print(f"Luau compiler setup failed: {exc}", file=sys.stderr)
        return 1
    files = sorted((ROOT / "src").glob("*.lua")) + sorted((ROOT / "tests").glob("*.lua"))
    files += sorted((ROOT / "studio").glob("*.lua"))
    files += [ROOT / "Source", ROOT / "dist/HeavenlyAxis.lua"]
    result = subprocess.run([str(executable), "--null", *map(str, files)], cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        print(result.stdout + result.stderr, file=sys.stderr)
        return result.returncode
    print(f"Passed: Luau {VERSION} compiled {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
