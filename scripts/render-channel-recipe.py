#!/usr/bin/env python3
"""Render a BlueBuild recipe for a specific Bazzite channel and package name."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_prefixed_line(lines: list[str], prefix: str, replacement: str) -> list[str]:
    replaced = False
    rendered: list[str] = []

    for line in lines:
        if line.startswith(prefix):
            rendered.append(replacement)
            replaced = True
        else:
            rendered.append(line)

    if not replaced:
        raise SystemExit(f"Could not find required line starting with {prefix!r}.")

    return rendered


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--name", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    lines = args.recipe.read_text(encoding="utf-8").splitlines()
    lines = replace_prefixed_line(lines, "name:", f"name: {args.name}")
    lines = replace_prefixed_line(lines, "image-version:", f"image-version: {args.channel}")
    lines = [
        line.replace(" stable image ", f" {args.channel} image ")
        if line.startswith("description:")
        else line
        for line in lines
    ]

    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Rendered {args.output} for {args.name}:{args.channel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
