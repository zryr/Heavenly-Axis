#!/usr/bin/env python3
"""Convert the pinned Lucide subset into native Roblox stroke data; local files only."""
from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from svgpathtools import parse_path

REVISION = "ba77aa6a76152a93c0388910427c7ece3f75dd61"
VERSION = "0.511.0"
ICONS = sorted("""
    activity arrow-left arrow-right bookmark check chevron-down chevron-left chevron-right chevron-up
    circle-alert circle-check circle-check-big circle-dot circle-help circle-play circle-small circle-x clipboard-list copy crosshair
    download droplet ellipsis eye eye-off focus folder-open gamepad-2 grid-2x2 grip group hand history image info
    keyboard layers layers-2 lock lock-open maximize maximize-2 menu minus monitor mouse mouse-pointer-2
    mouse-pointer-click move panel-right panel-top panel-top-close plus redo redo-2 rotate-ccw rotate-cw save scan scaling settings
    shield sliders-horizontal smartphone target text trash-2 triangle-alert undo undo-2 upload users wrench x zap
""".split())
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src" / "LucideGlyphs.lua"
TOLERANCE = 0.22
SIMPLIFY_TOLERANCE = 0.12


def deviation(point: complex, start: complex, finish: complex) -> float:
    chord = finish - start
    if abs(chord) < 1e-8:
        return abs(point - start)
    unit = chord / abs(chord)
    along = ((point - start) * unit.conjugate()).real
    projected = start + min(abs(chord), max(0.0, along)) * unit
    return abs(point - projected)


def trace(segment, t0: float = 0.0, t1: float = 1.0, depth: int = 0) -> list[complex]:
    start, finish = segment.point(t0), segment.point(t1)
    span = t1 - t0
    points = [segment.point(t0 + span * factor) for factor in (0.25, 0.5, 0.75)]
    if depth >= 7 or max(deviation(point, start, finish) for point in points) <= TOLERANCE:
        return [start, finish]
    middle = (t0 + t1) / 2
    return trace(segment, t0, middle, depth + 1)[:-1] + trace(segment, middle, t1, depth + 1)


def simplify(points: list[complex]) -> list[complex]:
    if len(points) <= 2:
        return points
    errors = [deviation(point, points[0], points[-1]) for point in points[1:-1]]
    largest = max(errors)
    if largest <= SIMPLIFY_TOLERANCE:
        return [points[0], points[-1]]
    pivot = errors.index(largest) + 1
    return simplify(points[: pivot + 1])[:-1] + simplify(points[pivot:])


def coordinates(points: list[complex]) -> tuple[float, ...]:
    return tuple(axis for point in points for axis in (point.real, point.imag))


def svg_shapes(source: bytes) -> list[tuple[str | float, ...]]:
    root = ET.fromstring(source)
    if root.attrib.get("viewBox") != "0 0 24 24":
        raise ValueError("expected the standard Lucide 24 × 24 viewBox")
    shapes: list[tuple[str | float, ...]] = []
    for element in root:
        name = element.tag.split("}")[-1]
        attrs = element.attrib
        if "transform" in attrs:
            raise ValueError(f"unsupported SVG transform on {name}")
        if name == "path":
            for path in parse_path(attrs["d"]).continuous_subpaths():
                points: list[complex] = []
                for segment in path:
                    sampled = trace(segment)
                    points.extend(sampled[1:] if points else sampled)
                if points:
                    shapes.append(coordinates(simplify(points)))
        elif name in {"polyline", "polygon"}:
            values = tuple(float(value) for value in re.split(r"[\s,]+", attrs["points"].strip()))
            shapes.append(values + values[:2] if name == "polygon" else values)
        elif name == "line":
            shapes.append(tuple(float(attrs[key]) for key in ("x1", "y1", "x2", "y2")))
        elif name == "circle":
            x, y, radius = (float(attrs[key]) for key in ("cx", "cy", "r"))
            size = radius * 2
            shapes.append(("rounded", x, y, size, size, radius))
        elif name == "rect":
            x, y, width, height = (float(attrs.get(key, 0)) for key in ("x", "y", "width", "height"))
            shapes.append(("rounded", x + width / 2, y + height / 2, width, height, float(attrs.get("rx", 0))))
        else:
            raise ValueError(f"unsupported SVG shape {name}")
    if not shapes:
        raise ValueError("empty icon")
    return shapes


def literal(value: str | float) -> str:
    if isinstance(value, str):
        return f'"{value}"'
    if math.isclose(value, 0, abs_tol=.0005):
        return "0"
    return f"{value:.3f}".rstrip("0").rstrip(".")


def generate(source: Path) -> str:
    digest = hashlib.sha256()
    lines = []
    for icon in ICONS:
        svg = (source / "icons" / f"{icon}.svg").read_bytes()
        digest.update(icon.encode() + b"\0" + svg)
        try:
            data = svg_shapes(svg)
        except ValueError as exc:
            raise ValueError(f"{icon}: {exc}") from exc
        shapes = ", ".join("{" + ", ".join(literal(value) for value in shape) + "}" for shape in data)
        lines.append(f'    ["{icon}"] = {{{shapes}}},')
    notices = "\n\n".join((source / name).read_text().strip() for name in ("LICENSE", "Feather-LICENSE"))
    header = (
        "-- Generated by tools/lucide_subset.py.\n"
        f"-- Lucide {VERSION}, commit {REVISION}.\n"
        f"-- Input icon SVGs SHA-256: {digest.hexdigest()}.\n"
        "-- Native data preserves the official view box, paths, circles and rectangles.\n"
    )
    return header + "--[[\n" + notices + "\n]]\nreturn {\n" + "\n".join(lines) + "\n}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Lucide checkout containing icons/, LICENSE and Feather-LICENSE")
    parser.add_argument("--check", action="store_true", help="compare generated glyphs without writing")
    args = parser.parse_args()
    expected = generate(args.source)
    if args.check:
        if OUTPUT.read_text() != expected:
            print(f"Regenerate {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            return 1
        print(f"Verified {len(ICONS)} pinned Lucide glyphs")
    else:
        OUTPUT.write_text(expected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
