#!/usr/bin/env python3
"""Small size/import guard for the measured search-screen migration source set.

Run from any directory: python3 dev/tool/check_search_architecture.py
Review still establishes semantic ownership and appropriate dependency contracts.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ("search", "home", "discover", "sources", "stremio_tv", "player_launch", "settings", "iptv", "torbox_downloads", "debrid_downloads", "pikpak_files", "iptv_settings")
# Screen-level wiring that composes several features (the composition
# boundary). Measured for size; features must not import it.
COMPOSITION = "lib/screens/search_screen"
FACADE = "lib/screens/search_screen.dart"
STORAGE_SOURCE_DIR = 'lib/services/storage'
STORAGE_ENUM_FILES = ('lib/models/ambient_trailer_surface.dart', 'lib/models/tv_render_quality.dart')
PLAYBACK_FACADE = "lib/services/torrent_playback_service.dart"
PLAYER_LAUNCH_FACADE = "lib/services/video_player_launcher.dart"
SETTINGS_FACADE = "lib/screens/settings_screen.dart"
# Step 6 enables the facade cap and rejects remaining temporary cross-calls.
# Until then, the facade is measured only by the repo-wide shrinking ratchet.
IPTV_SETTINGS_COMPLETE = False
IPTV_SETTINGS_FACADE = "lib/screens/settings/iptv_settings_page.dart"
IPTV_SETTINGS_BRIDGE = "lib/features/iptv_settings/presentation/legacy_iptv_settings/"
SETTINGS_COMPLETE = True
IPTV_COMPLETE = True
TORBOX_COMPLETE = True
PIKPAK_COMPLETE = True
PIKPAK_FACADE = "lib/screens/pikpak/pikpak_files_screen.dart"
PIKPAK_BRIDGE = "lib/features/pikpak_files/presentation/legacy_pikpak/"
DEBRID_COMPLETE = True
DEBRID_FACADE = "lib/screens/debrid_downloads_screen.dart"
DEBRID_BRIDGE = "lib/features/debrid_downloads/presentation/legacy_debrid/"
TORBOX_FACADE = "lib/screens/torbox/torbox_downloads_screen.dart"
TORBOX_BRIDGE = "lib/features/torbox_downloads/presentation/legacy_torbox/"
IPTV_FACADE = "lib/widgets/iptv/iptv_results_view.dart"
IPTV_BRIDGE = "lib/features/iptv/presentation/legacy_iptv/"
SETTINGS_BRIDGE = "lib/features/settings/presentation/legacy_settings/"
SETTINGS_SIZE_EXCEPTIONS = {
    # Original 588-line loader plus typed dependencies/imports, measured at step 4.
    SETTINGS_BRIDGE + "settings_summary_loader.dart": 658,
    "lib/features/settings/presentation/settings_classic_layout.dart": 420,
}
# Verbatim playback extraction source set; exceptions and exit milestones are
# recorded in docs/refactoring/torrent-playback-plan.md.
TORRENT_PLAYBACK_SOURCE_FILES = {
    "lib/features/sources/application/source_cache_ordering.dart",
    "lib/features/sources/application/source_candidate_checks.dart",
    "lib/features/sources/application/source_candidate_ranking.dart",
    "lib/features/sources/application/source_curation.dart",
    "lib/features/sources/application/source_filter_ladder.dart",
    "lib/features/sources/application/source_iptv_availability.dart",
    "lib/features/sources/application/source_probing.dart",
    "lib/features/sources/application/source_provider_config.dart",
    "lib/features/sources/application/source_search_plans.dart",
    "lib/features/sources/data/curated_source_search.dart",
    "lib/features/sources/data/deovr_json_upload.dart",
    "lib/features/sources/data/iptv_quick_play_search.dart",
    "lib/features/sources/data/recovery_source_resolution.dart",
    "lib/features/sources/data/series_pack_search.dart",
    "lib/features/sources/data/source_engine_fetchers.dart",
    "lib/features/sources/data/source_movie_fetcher.dart",
    "lib/features/sources/data/source_series_fetcher.dart",
    "lib/features/sources/models/playback_cancel_token.dart",
    "lib/features/sources/models/resolved_source.dart",
    "lib/features/sources/presentation/legacy_playback/addon_stream_playback.dart",
    "lib/features/sources/presentation/legacy_playback/automatic_play_best.dart",
    "lib/features/sources/presentation/legacy_playback/automatic_play_selection.dart",
    "lib/features/sources/presentation/legacy_playback/bound_source_playback.dart",
    "lib/features/sources/presentation/legacy_playback/bound_source_resolution.dart",
    "lib/features/sources/presentation/legacy_playback/deovr_launch.dart",
    "lib/features/sources/presentation/legacy_playback/manual_source_activation.dart",
    "lib/features/sources/presentation/legacy_playback/provider_accepted_actions.dart",
    "lib/features/sources/presentation/legacy_playback/provider_action_menu.dart",
    "lib/features/sources/presentation/legacy_playback/provider_zip_actions.dart",
    "lib/features/sources/presentation/legacy_playback/source_binding_actions.dart",
    "lib/features/sources/presentation/legacy_playback/source_loading_overlays.dart",
    "lib/features/sources/presentation/legacy_playback/source_next_episode.dart",
    "lib/features/sources/presentation/legacy_playback/source_play_action.dart",
    "lib/features/sources/presentation/legacy_playback/source_player_args.dart",
    "lib/features/sources/presentation/legacy_playback/source_player_launch.dart",
    "lib/features/sources/presentation/legacy_playback/source_provider_choice.dart",
}
TORRENT_PLAYBACK_PIPELINES = {
    "lib/features/sources/presentation/legacy_playback/automatic_play_best.dart",
    "lib/features/sources/presentation/legacy_playback/automatic_play_selection.dart",
    "lib/features/sources/presentation/legacy_playback/addon_stream_playback.dart",
    "lib/features/sources/presentation/legacy_playback/bound_source_playback.dart",
}
# The screen's composition root binds concrete services, as AGENTS.md allows
# for composition: the facade (it captures the bootstrap Home configuration and
# profile scope for the State) plus the composer and its three factories. They
# are not import-checked. Every other file in COMPOSITION is presentation and
# keeps the presentation import rules.
COMPOSITION_ROOTS = {
    FACADE,
    PIKPAK_FACADE,
    DEBRID_FACADE,
    IPTV_FACADE,
    # Temporary forwarding-only bridge, with its own 400-line cap.
    PLAYBACK_FACADE,
    PLAYER_LAUNCH_FACADE,
    f"{COMPOSITION}/search_screen_composer.dart",
    f"{COMPOSITION}/search_screen_search_composition.dart",
    f"{COMPOSITION}/search_screen_home_composition.dart",
    f"{COMPOSITION}/search_screen_session_composition.dart",
}
# Register extracted/adopted application files outside the feature directories.
# Retained facades join this source set when their migration reaches its final checks.
EXTRACTED_ELSEWHERE: tuple[str, ...] = (
    PLAYBACK_FACADE,
    PLAYER_LAUNCH_FACADE,
    "lib/ui/core/trailer_indicators.dart",
    "lib/ui/core/spotlight_search_button.dart",
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
    # Immutable session identity declaration only; no static state or I/O.
    "lib/features/discover/presentation/discover_session_lifecycle.dart": {
        "lib/services/profiles/profile_session_memory.dart": {"ProfileSessionOwner"},
    },
    # Immutable profile-session identity only; capture and storage operations stay outside.
    "lib/screens/search_screen/search_session_lifecycle.dart": {
        "lib/services/profiles/profile_session_memory.dart": {"ProfileSessionOwner"},
    },
    # Plain exception declaration only; no authorization service I/O is exposed.
    "lib/features/home/presentation/home_saved_iptv_actions.dart": {
        "lib/services/profiles/connection_resource_service.dart": {"ResourceAuthorizationException"},
    },
    # Legacy row DTO/ID grammar only; the route bridge performs no list reads.
    "lib/features/home/presentation/home_see_all_navigation.dart": {
        "lib/services/home_list_rows.dart": {"HomeListSection", "HomeExtraRowIds"},
    },
    # App-shell callback/listener adapter; no persistence or business operations.
    # Tab-shell handler registration. Like the other shell bridges it may use
    # the MainPageBridge statics; a `show` list could not narrow that further
    # because the class itself carries every app-shell hook.
    "lib/screens/search_screen/home_tab_shell_registration.dart": {
        "lib/services/main_page_bridge.dart",
    },
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
# Temporary named bridge for TorrentPlaybackService code that moved verbatim
# (docs/refactoring/torrent-playback-plan.md). Its context-taking pipelines
# still call legacy services directly, so files here may import lib/services/;
# http, shared_preferences and sqflite stay forbidden. Exit milestone: those
# calls move behind Sources data contracts and this folder is dissolved.
LEGACY_PLAYBACK_BRIDGES = (
    "lib/features/sources/presentation/legacy_playback/",
    # Move-only launcher bridge; exit: data contracts replace service calls.
    "lib/features/player_launch/presentation/legacy_launch/",
    # Bounded State-driven settings bridge; exit: Settings data contracts.
    SETTINGS_BRIDGE,
    # Verbatim State-driven IPTV bridge; exit: IPTV data contracts/Riverpod.
    IPTV_BRIDGE,
    TORBOX_BRIDGE,
    DEBRID_BRIDGE,
    PIKPAK_BRIDGE,
    # Bounded move-only settings bridge; exit: IPTV settings data contracts.
    IPTV_SETTINGS_BRIDGE,
)
# Each pending cap is zero until measured in the file's creation commit.
# No further player-launch size exception is authorized by this plan.
PLAYER_LAUNCH_SIZE_EXCEPTIONS = {
    # Whole native launch: split during a later control-flow change.
    "lib/features/player_launch/data/android_tv_native_launch.dart": 1302,
    # Whole payload builder: split during a later control-flow change.
    "lib/features/player_launch/data/android_tv_payload_builder.dart": 924,
    # Whole progress/completion handlers: split in a later control-flow change.
    "lib/features/player_launch/data/native_progress_handler.dart": 584,
    # Whole router: split during a later control-flow change.
    "lib/features/player_launch/presentation/legacy_launch/launch_router.dart": 592,
}
# User-approved verbatim DeoVR upload/UI bridge; exit: extract upload into a
# data contract in a later control-flow change. No other HTTP bridge is allowed.
PLAYER_LAUNCH_DEOVR_HTTP_IMPORT = (
    "lib/features/player_launch/presentation/legacy_launch/deovr_launch.dart",
    "package:http/http.dart",
)
GENERATED_SUFFIXES = (".g.dart", ".freezed.dart")
DIRECTIVES = re.compile(r"^\s*(?:import|export)\s+([^;]+);", re.MULTILINE)
URIS = re.compile(r"['\"]([^'\"]+)['\"]")


def violations(path: Path) -> list[str]:
    source = path.read_text()
    relative = path.relative_to(ROOT).as_posix()
    problems = []
    lines = len(source.splitlines())
    if relative == FACADE and lines > 300:
        problems.append(f"{lines} lines exceeds the 300-line facade limit")
    if relative == PLAYER_LAUNCH_FACADE and lines > 300:
        problems.append(f"{lines} lines exceeds the 300-line launcher facade limit")
    if relative == PLAYBACK_FACADE and lines > 400:
        problems.append(f"{lines} lines exceeds the 400-line playback facade limit")
    if SETTINGS_COMPLETE and relative == SETTINGS_FACADE and lines > 400:
        problems.append(f"{lines} lines exceeds the 400-line settings facade limit")
    if SETTINGS_COMPLETE and relative == SETTINGS_FACADE and "TEMP(settings)" in source:
        problems.append("temporary settings cross-call remains in the facade")
    if relative.startswith("lib/features/settings/"):
        limit = SETTINGS_SIZE_EXCEPTIONS.get(relative, 500)
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line settings extraction limit")
        if "TEMP(settings)" in source and (SETTINGS_COMPLETE or not relative.startswith(SETTINGS_BRIDGE)):
            problems.append("temporary settings cross-call outside the staged legacy bridge")
    if relative.startswith("lib/features/iptv_settings/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line IPTV settings extraction limit")
        if "TEMP(iptv_settings)" in source and (IPTV_SETTINGS_COMPLETE or not relative.startswith(IPTV_SETTINGS_BRIDGE)):
            problems.append("temporary IPTV settings cross-call outside the staged legacy bridge")
    if IPTV_SETTINGS_COMPLETE and relative == IPTV_SETTINGS_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line IPTV settings facade limit")
        if "TEMP(iptv_settings)" in source:
            problems.append("temporary IPTV settings cross-call remains in the facade")
    if relative.startswith("lib/features/iptv/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line IPTV extraction limit")
        if "TEMP(iptv)" in source and (IPTV_COMPLETE or not relative.startswith(IPTV_BRIDGE)):
            problems.append("temporary IPTV cross-call outside the staged legacy bridge")
    if IPTV_COMPLETE and relative == IPTV_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line IPTV facade limit")
        if "TEMP(iptv)" in source:
            problems.append("temporary IPTV cross-call remains in the facade")
    if relative.startswith("lib/features/torbox_downloads/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line TorBox extraction limit")
        if "TEMP(torbox)" in source and (TORBOX_COMPLETE or not relative.startswith(TORBOX_BRIDGE)):
            problems.append("temporary TorBox cross-call outside the staged legacy bridge")
    if TORBOX_COMPLETE and relative == TORBOX_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line TorBox facade limit")
        if "TEMP(torbox)" in source:
            problems.append("temporary TorBox cross-call remains in the facade")
    if relative.startswith("lib/features/debrid_downloads/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line Real-Debrid extraction limit")
        if "TEMP(debrid)" in source and (DEBRID_COMPLETE or not relative.startswith(DEBRID_BRIDGE)):
            problems.append("temporary Real-Debrid cross-call outside the staged legacy bridge")
    if DEBRID_COMPLETE and relative == DEBRID_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line Real-Debrid facade limit")
        if "TEMP(debrid)" in source:
            problems.append("temporary Real-Debrid cross-call remains in the facade")
    if relative.startswith("lib/features/pikpak_files/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line PikPak extraction limit")
        if "TEMP(pikpak)" in source and (PIKPAK_COMPLETE or not relative.startswith(PIKPAK_BRIDGE)):
            problems.append("temporary PikPak cross-call outside the staged legacy bridge")
    if PIKPAK_COMPLETE and relative == PIKPAK_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line PikPak facade limit")
        if "TEMP(pikpak)" in source:
            problems.append("temporary PikPak cross-call remains in the facade")
    if relative in TORRENT_PLAYBACK_SOURCE_FILES:
        limit = 800 if relative in TORRENT_PLAYBACK_PIPELINES else 500
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line playback extraction limit")
    if relative in TORRENT_PLAYBACK_SOURCE_FILES or relative == PLAYBACK_FACADE:
        if "TEMP(tps)" in source:
            problems.append("temporary TorrentPlaybackService cross-call remains")
    if relative.startswith(STORAGE_SOURCE_DIR + '/') or relative in STORAGE_ENUM_FILES:
        if lines > 500:
            problems.append(f'{lines} lines exceeds the 500-line storage limit')
    if relative.startswith("lib/features/player_launch/") or relative == PLAYER_LAUNCH_FACADE:
        if "TEMP(vpl)" in source:
            problems.append("temporary VideoPlayerLauncher cross-call remains")
    if relative.startswith("lib/features/player_launch/"):
        limit = PLAYER_LAUNCH_SIZE_EXCEPTIONS.get(relative, 500)
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line launcher extraction limit")
        if layer_hint := next((x for x in ("data", "models") if x in path.parts), None):
            if re.search(r"\bBuildContext\b", source):
                problems.append(f"{layer_hint} references BuildContext")
    if lines > max(800, PLAYER_LAUNCH_SIZE_EXCEPTIONS.get(relative, 0)):
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
    if relative in COMPOSITION_ROOTS:
        layer = None
    elif relative.startswith(COMPOSITION + "/"):
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
            if relative.startswith("lib/features/iptv_settings/"):
                if target == IPTV_SETTINGS_FACADE:
                    problems.append("IPTV settings feature imports its facade")
                if not relative.startswith(IPTV_SETTINGS_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("IPTV settings service import outside the exact legacy bridge")
            if target.startswith("lib/features/") and relative.startswith("lib/features/"):
                own_feature = relative.split("/")[2]
                other_feature = target.split("/")[2]
                if ((own_feature == "iptv_settings" and other_feature in ("settings", "iptv")) or
                        (other_feature == "iptv_settings" and own_feature in ("settings", "iptv"))):
                    if not target.startswith(f"lib/features/{other_feature}/models/"):
                        problems.append("IPTV settings/settings/IPTV implementation cross-import")
            if relative.startswith("lib/features/iptv/application/") and target.startswith("lib/services/"):
                problems.append("pure IPTV application helper imports a legacy service")
            if relative.startswith("lib/features/torbox_downloads/application/") and target.startswith("lib/services/"):
                problems.append("pure TorBox application helper imports a legacy service")
            if relative.startswith("lib/features/pikpak_files/application/") and target.startswith("lib/services/"):
                problems.append("pure PikPak application helper imports a legacy service")
            if relative.startswith("lib/features/debrid_downloads/application/") and target.startswith("lib/services/"):
                problems.append("pure Real-Debrid application helper imports a legacy service")
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
            legacy_bridge = (relative.startswith(LEGACY_PLAYBACK_BRIDGES)
                             and target.startswith("lib/services/"))
            if layer == "presentation" and target.startswith((
                    "lib/services/", "package:http/", "package:shared_preferences/",
                    "package:sqflite")) and not legacy_bridge and (relative, target) != PLAYER_LAUNCH_DEOVR_HTTP_IMPORT and target not in (
                        PRESENTATION_BRIDGE_IMPORTS.get(relative, set())):
                problems.append(f"view directly imports data/platform API: {uri}")
            if target.startswith("package:provider/"):
                problems.append(f"new feature DI must use Riverpod: {uri}")
            if relative.startswith("lib/features/"):
                own = relative.split("/")[2]
                if target.startswith("lib/features/"):
                    other = target.split("/")[2]
                    if other != own and not target.startswith(
                            f"lib/features/{other}/models/"):
                        # Features meet through small model contracts; the
                        # wiring that needs several features lives in
                        # COMPOSITION, outside lib/features.
                        problems.append(
                            f"cross-feature import outside {other}/models: {uri}")
                if own in ("debrid_downloads", "torbox_downloads") and target.startswith("lib/features/"):
                    other = target.split("/")[2]
                    if {own, other} == {"debrid_downloads", "torbox_downloads"}:
                        problems.append("Real-Debrid/TorBox cross-feature import")
                if own in ("debrid_downloads", "torbox_downloads", "pikpak_files") and target.startswith("lib/features/"):
                    other = target.split("/")[2]
                    if own != other and other in ("debrid_downloads", "torbox_downloads", "pikpak_files"):
                        problems.append("PikPak/Real-Debrid/TorBox cross-feature import")
                if own == "pikpak_files" and target == PIKPAK_FACADE:
                    problems.append("PikPak feature imports the files facade")
                if own == "debrid_downloads" and target == DEBRID_FACADE:
                    problems.append("Real-Debrid feature imports the downloads facade")
                if own == "torbox_downloads" and target == TORBOX_FACADE:
                    problems.append("TorBox feature imports the downloads facade")
                if own == "iptv" and target == IPTV_FACADE:
                    problems.append("IPTV feature imports the results facade")
                if own == "player_launch" and layer in ("data", "models") and target == "lib/services/video_player_launcher.dart":
                    problems.append("launcher data/models call back through the facade")
                if target.startswith(COMPOSITION + "/") or target == FACADE:
                    problems.append(f"feature imports the composition layer: {uri}")
    return [f"{relative}: {problem}" for problem in problems]


def main() -> int:
    paths = {
        p for feature in FEATURES
        for p in (ROOT / "lib/features" / feature).rglob("*.dart")
        if not p.name.endswith(GENERATED_SUFFIXES)
    }
    paths.update(ROOT / p for p in EXTRACTED_ELSEWHERE)
    if IPTV_SETTINGS_COMPLETE:
        paths.add(ROOT / IPTV_SETTINGS_FACADE)
    if PIKPAK_COMPLETE:
        paths.add(ROOT / PIKPAK_FACADE)
    if DEBRID_COMPLETE:
        paths.add(ROOT / DEBRID_FACADE)
    if TORBOX_COMPLETE:
        paths.add(ROOT / TORBOX_FACADE)
    if IPTV_COMPLETE:
        paths.add(ROOT / IPTV_FACADE)
    if SETTINGS_COMPLETE:
        paths.add(ROOT / SETTINGS_FACADE)
    paths.update(ROOT / p for p in TORRENT_PLAYBACK_SOURCE_FILES)
    paths.update((ROOT / COMPOSITION).rglob("*.dart"))
    paths.add(ROOT / FACADE)
    paths.update(ROOT / p for p in STORAGE_ENUM_FILES)
    paths.update((ROOT / STORAGE_SOURCE_DIR).rglob('*.dart'))
    problems = [
        f"Composition root is missing (update COMPOSITION_ROOTS): {root}"
        for root in sorted(COMPOSITION_ROOTS)
        if not (ROOT / root).is_file()
    ]
    if not (ROOT / STORAGE_SOURCE_DIR).is_dir():
        problems.append(f'Registered storage directory is missing: {STORAGE_SOURCE_DIR}')
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
