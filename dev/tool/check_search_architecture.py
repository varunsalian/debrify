#!/usr/bin/env python3
"""Small size/import guard for the measured search-screen migration source set.

Run from any directory: python3 dev/tool/check_search_architecture.py
Review still establishes semantic ownership and appropriate dependency contracts.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ("search", "home", "discover", "sources")
# Register extracted/adopted application files outside the feature directories.
# The original screen/parts are tracked temporary exceptions in the phase plan;
# add a retained facade here once its migration is complete.
EXTRACTED_ELSEWHERE: tuple[str, ...] = (
    "lib/services/source_selection_diagnostics.dart",
    "lib/core/platform/system_clipboard.dart",
    "lib/ui/core/see_all_link.dart",
    "lib/ui/core/filter_sheet_header.dart",
    "lib/widgets/torrent_filters_sheet.dart",
    "lib/ui/core/source_metadata_labels.dart",
    "lib/models/series_source.dart",
    "lib/models/cinema_source_provider.dart",
)
# Context-dependent legacy actions are allowed only through these named bridges.
# Phase 4C owns binding preparation; phase 7 retains playback lifecycle review.
PRESENTATION_BRIDGE_IMPORTS = {
    "lib/features/sources/presentation/source_playback_bridge.dart": {
        "lib/services/torrent_playback_service.dart",
    },
    "lib/features/sources/presentation/source_binding_bridge.dart": {
        "lib/services/iptv_source_search.dart",
        "lib/services/torrent_playback_service.dart",
    },
}
GENERATED_SUFFIXES = (".g.dart", ".freezed.dart")
DIRECTIVES = re.compile(r"^\s*(?:import|export)\s+([^;]+);", re.MULTILINE)
URIS = re.compile(r"['\"]([^'\"]+)['\"]")


def violations(path: Path) -> list[str]:
    source = path.read_text()
    relative = path.relative_to(ROOT).as_posix()
    problems = []
    lines = len(source.splitlines())
    if lines > 800:
        problems.append(f"{lines} lines exceeds the 800-line ceiling")
    if re.search(r"^\s*part\s+of\b", source, re.MULTILINE):
        problems.append("handwritten part of a shared library")
    for part in re.findall(r"^\s*part\s+['\"]([^'\"]+)", source, re.MULTILINE):
        if not part.endswith(GENERATED_SUFFIXES):
            problems.append(f"handwritten part directive: {part}")

    layer = next((x for x in ("application", "data", "models", "presentation")
                  if x in path.parts), None)
    if relative.startswith(("lib/ui/", "lib/widgets/")):
        layer = "presentation"
    for declaration in DIRECTIVES.findall(source):
        for uri in URIS.findall(declaration):
            target = uri
            if uri.startswith("package:debrify/"):
                target = "lib/" + uri.removeprefix("package:debrify/")
            elif not uri.startswith(("dart:", "package:")):
                resolved = (path.parent / uri).resolve()
                if resolved.is_relative_to(ROOT):
                    target = resolved.relative_to(ROOT).as_posix()
            if layer in ("application", "data", "models"):
                if (target.startswith(("lib/screens/", "lib/widgets/", "lib/ui/"))
                        or "/presentation/" in target
                        or (target.startswith("package:flutter/")
                            and target != "package:flutter/foundation.dart")):
                    problems.append(f"{layer} imports/exports UI: {uri}")
            if layer in ("data", "models") and (
                    "riverpod" in target or target.startswith("package:provider/")):
                problems.append(f"{layer} depends on state/DI framework: {uri}")
            if layer == "presentation" and target.startswith((
                    "lib/services/", "package:http/", "package:shared_preferences/",
                    "package:sqflite")) and target not in (
                        PRESENTATION_BRIDGE_IMPORTS.get(relative, set())):
                problems.append(f"view directly imports data/platform API: {uri}")
            if target.startswith("package:provider/"):
                problems.append(f"new feature DI must use Riverpod: {uri}")
    return [f"{relative}: {problem}" for problem in problems]


def main() -> int:
    paths = {
        p for feature in FEATURES
        for p in (ROOT / "lib/features" / feature).rglob("*.dart")
        if not p.name.endswith(GENERATED_SUFFIXES)
    }
    paths.update(ROOT / p for p in EXTRACTED_ELSEWHERE)
    problems = []
    if not paths:
        problems.append("No migrated sources found; check the measured source set.")
    for path in sorted(paths):
        if not path.is_file():
            problems.append(f"Registered extracted source is missing: {path}")
        else:
            problems.extend(violations(path))
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"Search architecture: {len(paths)} migrated files passed size/import checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
