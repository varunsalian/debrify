#!/usr/bin/env python3
"""Small size/import guard for the measured search-screen migration source set.

Run from any directory: python3 dev/tool/check_search_architecture.py
Review still establishes semantic ownership and appropriate dependency contracts.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ("search", "home", "discover", "sources", "stremio_tv")
# Register extracted/adopted application files outside the feature directories.
# The original screen/parts are tracked temporary exceptions in the phase plan;
# add a retained facade here once its migration is complete.
EXTRACTED_ELSEWHERE: tuple[str, ...] = (
    "lib/ui/core/retry_message.dart",
    "lib/models/mdblist_list_choice.dart",
    "lib/ui/core/source_results_pane.dart",
    "lib/models/source_playlist_resolver.dart",
    "lib/services/profiles/profile_playback_preparation.dart",
    "lib/models/debrify_tv_channel_action.dart",
    "lib/services/debrify_tv_channel_actions.dart",
    "lib/widgets/debrify_tv_channel_add_bridge.dart",
    "lib/widgets/channel_picker_dialog.dart",
    "lib/models/playlist_entry.dart",
    "lib/screens/video_player/models/playlist_entry.dart",
    "lib/services/profiles/profile_local_writes.dart",
    "lib/services/tracker_title_actions.dart",
    "lib/services/profile_tracker_title_actions.dart",
    "lib/models/home_collection_rows.dart",
    "lib/models/youtube_resolved_streams.dart",
    "lib/services/home_collection_rows.dart",
    "lib/core/metadata/metadata_presentation_cache.dart",
    "lib/models/metadata_presentation.dart",
    "lib/models/source_appearance.dart",
    "lib/services/source_appearance_preferences.dart",
    "lib/services/home_return_cache.dart",
    "lib/services/local_history_removal.dart",
    "lib/services/simkl/simkl_continue_watching_removal.dart",
    "lib/services/profiles/profile_session_memory.dart",
    "lib/models/home_preferences.dart",
    "lib/models/iptv_playlist.dart",
    "lib/services/stremio_tv_rotation.dart",
    "lib/services/stremio_tv_service.dart",
    "lib/models/stremio_tv/stremio_tv_channel.dart",
    "lib/models/stremio_tv/stremio_tv_now_playing.dart",
    "lib/models/debrify_tv/channel.dart",
    "lib/models/debrify_tv_channel_record.dart",
    "lib/models/iptv_cw_entry.dart",
    "lib/models/trakt_continue_watching_item.dart",
    "lib/models/simkl_continue_watching_item.dart",
    "lib/models/mdblist_continue_watching.dart",
    "lib/services/mdblist/mdblist_models.dart",
    "lib/services/iptv_cw_history.dart",
    "lib/models/local_source_document.dart",
    "lib/services/durable_source_binding.dart",
    "lib/models/playback_meta.dart",
    "lib/models/playback_resume_policy.dart",
    "lib/models/source_provider_ref.dart",
    "lib/services/source_ordering.dart",
    "lib/utils/torrent_quality.dart",
    "lib/utils/continue_watching_presentation.dart",
    "lib/utils/language_mapping.dart",
    "lib/screens/video_player/utils/language_mapping.dart",
    "lib/utils/torrent_filter_matcher.dart",
    "lib/utils/source_quality.dart",
    "lib/utils/format_tag_detector.dart",
    "lib/services/pinned_direct_stream_match.dart",
    "lib/models/iptv_source_result.dart",
    "lib/models/addon_search_status.dart",
    "lib/services/torrent_result_merge.dart",
    "lib/services/source_selection_diagnostics.dart",
    "lib/core/platform/system_clipboard.dart",
    "lib/ui/core/see_all_link.dart",
    "lib/ui/core/progress_reset_dialog.dart",
    "lib/ui/core/filter_sheet_header.dart",
    "lib/widgets/torrent_filters_sheet.dart",
    "lib/ui/core/source_metadata_labels.dart",
    "lib/models/series_source.dart",
    "lib/models/cinema_source_provider.dart",
)
# Context-dependent legacy actions are allowed only through these named bridges.
# Phase 4C owns binding preparation; phase 7 retains playback lifecycle review.
PRESENTATION_BRIDGE_IMPORTS = {
    # Plain exception declaration only; no authorization service I/O is exposed.
    "lib/features/home/presentation/home_saved_iptv_actions.dart": {
        "lib/services/profiles/connection_resource_service.dart": {"ResourceAuthorizationException"},
    },
    # Legacy row DTO/ID grammar only; the route bridge performs no list reads.
    "lib/features/home/presentation/home_see_all_navigation.dart": {
        "lib/services/home_list_rows.dart": {"HomeListSection", "HomeExtraRowIds"},
    },
    # App-shell callback/listener adapter; no persistence or business operations.
    "lib/features/discover/presentation/discover_shell_bridge.dart": {
        "lib/services/main_page_bridge.dart",
    },
    # Shared channel picker bridge composes owner-scoped data actions; widgets
    # receive callbacks and cannot access the database/repository directly.
    "lib/widgets/debrify_tv_channel_add_bridge.dart": {
        "lib/services/debrify_tv_channel_actions.dart",
        "lib/services/profiles/profile_session_memory.dart",
    },
    # Named legacy menu factories perform presentation only; action handlers and
    # service classes remain forbidden by the explicit show-declaration guard.
    "lib/features/home/presentation/home_detail_menus.dart": {
        "lib/services/trakt/trakt_service.dart": {"TraktTitleStatus"},
        "lib/services/simkl/simkl_service.dart": {"SimklTitleStatus"},
        "lib/services/mdblist/mdblist_models.dart": {"MdblistTitleStatus"},
        "lib/services/simkl/simkl_menu_helpers.dart": {
            "SimklMenuOption", "buildSimklMenuOptions",
        },
        "lib/services/mdblist/mdblist_menu_helpers.dart": {
            "MdblistMenuOption", "buildMdblistMenuOptions",
        },
    },
    # Legacy DTO/menu declarations only; this composition performs no service IO.
    "lib/features/home/presentation/home_detail_presentation.dart": {
        "lib/services/trakt/trakt_service.dart": {"TraktTitleStatus"},
        "lib/services/simkl/simkl_service.dart": {"SimklTitleStatus"},
        "lib/services/mdblist/mdblist_models.dart": {"MdblistTitleStatus"},
        "lib/services/simkl/simkl_menu_helpers.dart": {
            "SimklMenuOption", "SimklItemMenuAction",
        },
        "lib/services/mdblist/mdblist_menu_helpers.dart": {
            "MdblistMenuOption", "MdblistItemMenuAction",
        },
    },
    # Resolving-overlay UI only; playback data comes from injected feature owners.
    "lib/features/home/presentation/home_catalog_play_action.dart": {
        "lib/services/torrent_playback_service.dart",
    },
    # Plain menu-action enums only; no I/O names are exposed.
    "lib/features/home/presentation/home_detail_actions.dart": {
        "lib/services/simkl/simkl_menu_helpers.dart": {"SimklItemMenuAction"},
        "lib/services/mdblist/mdblist_menu_helpers.dart": {"MdblistItemMenuAction"},
    },
    # Enum-only dependencies for the borrowed legacy detail action contracts.
    "lib/features/home/presentation/home_detail_action_bridge.dart": {
        "lib/services/simkl/simkl_menu_helpers.dart",
        "lib/services/mdblist/mdblist_menu_helpers.dart",
    },
    "lib/features/home/presentation/home_catalog_playback_bridge.dart": {
        "lib/services/main_page_bridge.dart",
        "lib/services/torrent_playback_service.dart",
    },
    # TV Home's UI-only registration/cleanup boundary; no data or player APIs.
    "lib/features/home/presentation/home_hero_shell_bridge.dart": {
        "lib/services/main_page_bridge.dart",
        "lib/services/app_route_observer.dart",
    },
    # Identifiable factory wiring platform operations into stateless presentation.
    "lib/features/sources/presentation/local_source_picker_composition.dart": {
        "lib/services/android_local_source_service.dart",
    },
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
    if relative.startswith(("lib/utils/", "lib/services/", "lib/core/metadata/")):
        layer = "data"
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
            bridge = PRESENTATION_BRIDGE_IMPORTS.get(relative, set())
            if isinstance(bridge, dict) and target in bridge:
                shown = re.search(r"\bshow\s+([\w,\s]+)$", declaration)
                names = set(re.findall(r"\w+", shown.group(1))) if shown else set()
                if not names or not names <= bridge[target]:
                    problems.append(f"legacy presentation import must show only allowed declarations: {uri}")
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
