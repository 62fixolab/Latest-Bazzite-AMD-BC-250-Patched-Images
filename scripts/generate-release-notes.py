#!/usr/bin/env python3
"""Generate grouped GitHub release notes for published BC-250 images."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import time
from pathlib import Path


PACKAGES = [
    {
        "group": "recommended",
        "variant": "Deck / Game Mode",
        "name": "bazzite-bc250-patched-deck",
    },
    {
        "group": "recommended",
        "variant": "GNOME",
        "name": "bazzite-bc250-patched-gnome",
    },
    {
        "group": "recommended",
        "variant": "KDE",
        "name": "bazzite-bc250-patched-kde",
    },
    {
        "group": "experimental",
        "variant": "Deck / Game Mode 40CU",
        "name": "bazzite-bc250-patched-deck-40cu",
    },
    {
        "group": "experimental",
        "variant": "GNOME 40CU",
        "name": "bazzite-bc250-patched-gnome-40cu",
    },
    {
        "group": "experimental",
        "variant": "KDE 40CU",
        "name": "bazzite-bc250-patched-kde-40cu",
    },
]

SPONSORS = """# 🎉 Sponsors

## Printer Tools App
[![Banner - Printer Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-printer-tools.png)](https://printertools.app)

## Scooter Tools App
[![Banner - Scooter Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-scooter-tools.png)](https://scootertools.app)

## AdMate App
[![Banner - AdMate App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-admate.png)](https://admate.dev)
"""


def normalize_date(value: str | None) -> tuple[str, str]:
    if value is None:
        today = dt.datetime.now(dt.timezone.utc).date()
        return today.strftime("%Y%m%d"), today.strftime("%Y.%m.%d")

    raw = value.strip()
    match = re.fullmatch(r"(\d{4})[.-]?(\d{2})[.-]?(\d{2})", raw)
    if not match:
        raise SystemExit(f"Invalid date '{value}'. Use YYYY.MM.DD, YYYY-MM-DD, or YYYYMMDD.")

    y, m, d = match.groups()
    dt.date(int(y), int(m), int(d))
    return f"{y}{m}{d}", f"{y}.{m}.{d}"


def run_json(command: list[str], retries: int, retry_delay: int) -> object:
    last_error = ""

    for attempt in range(1, retries + 1):
        proc = subprocess.run(command, text=True, capture_output=True, check=False)
        if proc.returncode == 0:
            return json.loads(proc.stdout)

        last_error = proc.stderr.strip() or proc.stdout.strip()
        if attempt < retries:
            time.sleep(retry_delay)

    raise RuntimeError(f"Command failed after {retries} attempts: {' '.join(command)}\n{last_error}")


def fetch_package_versions(owner: str, package: str, retries: int, retry_delay: int) -> list[dict]:
    errors: list[str] = []

    for scope in ("users", "orgs"):
        path = f"/{scope}/{owner}/packages/container/{package}/versions?per_page=100"
        try:
            data = run_json(["gh", "api", path], retries, retry_delay)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        if isinstance(data, list):
            return data

    raise RuntimeError("\n".join(errors))


def version_tags(version: dict) -> list[str]:
    metadata = version.get("metadata") or {}
    container = metadata.get("container") or {}
    tags = container.get("tags") or []
    return [str(tag) for tag in tags]


def collect_entries(owner: str, date_ymd: str, retries: int, retry_delay: int) -> list[dict]:
    entries: list[dict] = []
    exact_tag_re = re.compile(rf"^{re.escape(date_ymd)}-(\d+)$")

    for package in PACKAGES:
        versions = fetch_package_versions(owner, package["name"], retries, retry_delay)

        for version in versions:
            tags = version_tags(version)
            exact_tags = sorted(tag for tag in tags if exact_tag_re.fullmatch(tag))
            if not exact_tags:
                continue

            exact_tag = exact_tags[-1]
            os_version = exact_tag.rsplit("-", 1)[-1]
            commit_tags = sorted(
                tag
                for tag in tags
                if re.fullmatch(r"(?!\d{8}-\d+$)[0-9a-f]{7,40}-\d+", tag)
            )
            digest = str(version.get("name", ""))
            if not digest.startswith("sha256:"):
                digest = f"sha256:{digest}"

            entries.append(
                {
                    **package,
                    "exact_tag": exact_tag,
                    "os_version": os_version,
                    "digest": digest,
                    "created_at": version.get("created_at", ""),
                    "commit_tag": commit_tags[-1] if commit_tags else "",
                }
            )
            break

    return entries


def list_dates(owner: str, retries: int, retry_delay: int) -> list[str]:
    dates: set[str] = set()
    date_tag_re = re.compile(r"^(\d{4})(\d{2})(\d{2})(?:-\d+)?$")

    for package in PACKAGES:
        versions = fetch_package_versions(owner, package["name"], retries, retry_delay)
        for version in versions:
            for tag in version_tags(version):
                match = date_tag_re.fullmatch(tag)
                if match:
                    dates.add(".".join(match.groups()))

    return sorted(dates)


def unique_package_commit_tag(entries: list[dict]) -> str:
    commit_tags = sorted(
        {
            entry["commit_tag"].split("-", 1)[0]
            for entry in entries
            if entry.get("commit_tag")
        }
    )
    return commit_tags[0] if len(commit_tags) == 1 else ""


def package_url(repo_url: str, package: str) -> str:
    return f"{repo_url}/pkgs/container/{package}"


def image_ref(owner: str, package: str, tag: str) -> str:
    return f"ghcr.io/{owner}/{package}:{tag}"


def install_block(owner: str, entry: dict, tag: str) -> str:
    return "\n".join(
        [
            f"{entry['variant']}:",
            "",
            "```bash",
            f"rpm-ostree rebase ostree-image-signed:docker://{image_ref(owner, entry['name'], tag)}",
            "systemctl reboot",
            "```",
        ]
    )


def markdown_table(entries: list[dict], owner: str, repo_url: str) -> str:
    lines = [
        "| Variant | Image | Exact tag | Digest |",
        "| --- | --- | --- | --- |",
    ]

    for entry in entries:
        image = f"ghcr.io/{owner}/{entry['name']}"
        package_link = package_url(repo_url, entry["name"])
        lines.append(
            f"| {entry['variant']} | [`{image}`]({package_link}) | "
            f"`{entry['exact_tag']}` | `{entry['digest']}` |"
        )

    return "\n".join(lines)


def render_notes(
    *,
    owner: str,
    repo: str,
    date_display: str,
    entries: list[dict],
    commit: str | None,
    run_url: str | None,
) -> str:
    repo_url = f"https://github.com/{owner}/{repo}"
    recommended = [entry for entry in entries if entry["group"] == "recommended"]
    experimental = [entry for entry in entries if entry["group"] == "experimental"]

    lines: list[str] = [
        SPONSORS.rstrip(),
        "",
        f"# Bazzite BC-250 Patched Images {date_display}",
        "",
        "New Bazzite AMD BC-250 patched image batch published to GHCR.",
        "",
        "> [!IMPORTANT]",
        "> These are OCI images, not ISOs. Install or update with `rpm-ostree rebase`.",
        "",
        "## What changed",
        "",
        "- Rebuilt from current official Bazzite stable bases.",
        "- Published normal Deck, GNOME, and KDE images.",
    ]

    if experimental:
        lines.append("- Published optional experimental `-40cu` images.")

    lines.extend(
        [
            "- Includes `cyan-skillfish-governor-smu`, GPU frequency scaling, and the MangoHud/radeontop `655%` telemetry fix.",
            "- Images are signed for `ostree-image-signed` rebases.",
            "",
            "## Recommended images",
            "",
            "Use these unless you are deliberately testing extra CUs." if experimental else "These are the images published in this batch.",
            "",
            markdown_table(recommended, owner, repo_url),
            "",
            "### Install recommended images",
            "",
        ]
    )

    for entry in recommended:
        lines.append(install_block(owner, entry, "latest"))
        lines.append("")

    lines.extend(
        [
            "Pin this exact build by replacing `latest` with the exact tag from the table above.",
            "",
        ]
    )

    if experimental:
        lines.extend(
            [
                "## Experimental 40CU images",
                "",
                "> [!CAUTION]",
                "> The `-40cu` images do not force 40CU on boot. They include tools to test extra CUs. 32CU/40CU stability is silicon lottery.",
                "",
                markdown_table(experimental, owner, repo_url),
                "",
                f"Full 40CU guide: {repo_url}/blob/main/docs/40cu.md",
                "",
                "### Install recommended experimental 40CU images",
                "",
                "Use these only if you want to test optional CU unlock tooling. For normal daily use, install one of the recommended non-40CU images above.",
                "",
            ]
        )

        for entry in experimental:
            lines.append(install_block(owner, entry, "latest"))
            lines.append("")

        lines.extend(
            [
                "Pin this exact build by replacing `latest` with the exact tag from the table above.",
                "",
            ]
        )

    lines.extend(
        [
            "## Documentation",
            "",
            f"- Main README: {repo_url}",
        ]
    )

    if experimental:
        lines.extend(
            [
                f"- Full 40CU guide: {repo_url}/blob/main/docs/40cu.md",
                "",
                "> [!WARNING]",
                "> If you install a `-40cu` image, read the 40CU guide before saving any boot profile. The image includes testing tools, but extra CUs are still silicon lottery.",
                "",
            ]
        )
    else:
        lines.append("")

    lines.extend(
        [
            "## Package pages",
            "",
        ]
    )

    for entry in entries:
        lines.append(f"- {package_url(repo_url, entry['name'])}")

    lines.extend(
        [
            "",
            "## Source build",
            "",
        ]
    )

    if run_url:
        lines.append(f"- Workflow run: {run_url}")
    if commit:
        lines.append(f"- Commit: `{commit}`")
    else:
        commit_tag = unique_package_commit_tag(entries)
        if commit_tag:
            lines.append(f"- Package commit tag: `{commit_tag}`")
    lines.append(f"- Build date: `{date_display}`")

    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner", required=True, help="GitHub/GHCR owner, for example 62fixolab.")
    parser.add_argument("--repo", default="Latest-Bazzite-AMD-BC-250-Patched-Images")
    parser.add_argument("--date", help="Release date as YYYY.MM.DD, YYYY-MM-DD, or YYYYMMDD. Defaults to UTC today.")
    parser.add_argument("--commit", help="Commit SHA to show in release notes.")
    parser.add_argument("--run-url", help="Workflow run URL to show in release notes.")
    parser.add_argument("--output", help="Write release notes to this file. Defaults to stdout.")
    parser.add_argument("--list-dates", action="store_true", help="List known publish dates and exit.")
    parser.add_argument("--print-package-commit-tag", action="store_true", help="Print the unique package commit tag for a date and exit.")
    parser.add_argument("--retries", type=int, default=8)
    parser.add_argument("--retry-delay", type=int, default=10)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.list_dates:
        for date_value in list_dates(args.owner, args.retries, args.retry_delay):
            print(date_value)
        return 0

    date_ymd, date_display = normalize_date(args.date)
    entries = collect_entries(args.owner, date_ymd, args.retries, args.retry_delay)
    if not entries:
        raise SystemExit(f"No package tags found for {date_display}.")

    if args.print_package_commit_tag:
        commit_tag = unique_package_commit_tag(entries)
        if commit_tag:
            print(commit_tag)
        return 0

    notes = render_notes(
        owner=args.owner,
        repo=args.repo,
        date_display=date_display,
        entries=entries,
        commit=args.commit,
        run_url=args.run_url,
    )

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(notes, encoding="utf-8")
    else:
        sys.stdout.write(notes)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
