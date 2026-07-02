#!/usr/bin/env python3
"""Prepare GitHub Actions matrices for changed Bazzite channel digests."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


NORMAL_RECIPES = {
    "deck": ("bazzite-deck-patched.yml", "bazzite-bc250-patched-deck"),
    "gnome": ("bazzite-gnome-patched.yml", "bazzite-bc250-patched-gnome"),
    "kde": ("bazzite-kde-patched.yml", "bazzite-bc250-patched-kde"),
}

FORTYCU_RECIPES = {
    "deck": ("bazzite-deck-patched-40cu.yml", "bazzite-bc250-patched-deck-40cu"),
    "gnome": ("bazzite-gnome-patched-40cu.yml", "bazzite-bc250-patched-gnome-40cu"),
    "kde": ("bazzite-kde-patched-40cu.yml", "bazzite-bc250-patched-kde-40cu"),
}


def read_digest_file(path: Path) -> dict[tuple[str, str], str]:
    digests: dict[tuple[str, str], str] = {}
    if not path.exists():
        return digests

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue

        # Current format: channel<TAB>variant<TAB>base_image<TAB>digest
        parts = line.split("\t")
        if len(parts) >= 4:
            channel, variant, _base_image, digest = parts[:4]
            digests[(channel, variant)] = digest
            continue

        # Legacy stable cache format kept for migration from the previous workflow.
        if "=" in line:
            variant, digest = line.split("=", 1)
            digests[("stable", variant)] = digest

    return digests


def read_current_entries(path: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue

        parts = line.split("\t")
        if len(parts) != 4:
            raise SystemExit(f"Invalid current digest line: {raw_line}")

        channel, variant, base_image, digest = parts
        entries.append(
            {
                "channel": channel,
                "variant": variant,
                "base_image": base_image,
                "base_digest": digest,
            }
        )

    return entries


def channel_package_name(base_name: str, channel: str) -> str:
    if channel == "stable":
        return base_name
    return f"{base_name}-{channel}"


def matrix_entry(entry: dict[str, str], recipe: str, base_package: str) -> dict[str, str]:
    return {
        **entry,
        "recipe": recipe,
        "image_name": channel_package_name(base_package, entry["channel"]),
    }


def github_output(values: dict[str, str]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with Path(output_path).open("a", encoding="utf-8") as handle:
            for key, value in values.items():
                handle.write(f"{key}={value}\n")
    else:
        for key, value in values.items():
            print(f"{key}={value}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    current_entries = read_current_entries(args.current)
    previous = read_digest_file(args.previous) if args.previous else {}

    normal: list[dict[str, str]] = []
    fortycu: list[dict[str, str]] = []

    for entry in current_entries:
        key = (entry["channel"], entry["variant"])
        previous_digest = previous.get(key)
        if not args.force and previous_digest == entry["base_digest"]:
            continue

        variant = entry["variant"]
        normal_recipe, normal_package = NORMAL_RECIPES[variant]
        fortycu_recipe, fortycu_package = FORTYCU_RECIPES[variant]

        normal.append(matrix_entry(entry, normal_recipe, normal_package))
        fortycu.append(matrix_entry(entry, fortycu_recipe, fortycu_package))

    normal_matrix = {"include": normal}
    fortycu_matrix = {"include": fortycu}
    total_count = len(normal) + len(fortycu)

    github_output(
        {
            "normal-matrix": json.dumps(normal_matrix, separators=(",", ":")),
            "normal-count": str(len(normal)),
            "fortycu-matrix": json.dumps(fortycu_matrix, separators=(",", ":")),
            "fortycu-count": str(len(fortycu)),
            "should-build": "true" if total_count else "false",
        }
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
