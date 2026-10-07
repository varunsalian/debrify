#!/usr/bin/env python3
"""Small size/import guard for the measured search-screen migration source set.

Run from any directory: python3 dev/tool/check_search_architecture.py
Review still establishes semantic ownership and appropriate dependency contracts.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ("search", "home", "discover", "sources", "stremio_tv", "player_launch", "settings", "iptv", "torbox_downloads", "debrid_downloads", "pikpak_files", "playback_settings", "iptv_settings", "playlist_content", "merged_detail", "addon_hub", "detail_showcase", "spotlight_board", "episodes_panel", "catalog_detail", "stremio_tv_tuner")
FEATURES += ("premiumize_files",)
PREMIUMIZE_COMPLETE = False
PREMIUMIZE_FACADE = "lib/screens/premiumize/premiumize_files_screen.dart"
PREMIUMIZE_BRIDGE = "lib/features/premiumize_files/presentation/legacy_premiumize/"
PREMIUMIZE_FACADE_CAP = 400  # Measured downward at step 7.
FEATURES += ("debrify_tv",)
FEATURES += ("stremio_tv_catalogs",)
STREMIO_TV_CATALOGS_COMPLETE = True
STREMIO_TV_CATALOGS_FACADE = "lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart"
STREMIO_TV_CATALOGS_BRIDGE = "lib/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/"
# Measured pure-export facade; completion activates its cap.
STREMIO_TV_CATALOGS_FACADE_CAP = 8
STREMIO_TV_CATALOGS_PUBLIC_NAMES = frozenset([
    "LocalCatalogExportPayload", "LocalCatalogExporter", "LocalCatalogImporter",
    "StremioTvLocalCatalogEditorDialog", "StremioTvLocalCatalogsDialog",
])
# Creation commits register exact measurements. Exit: separately characterized
# item-card extraction (editor) and public list-source model extraction (Trakt).
STREMIO_TV_CATALOGS_SIZE_EXCEPTIONS = {
    STREMIO_TV_CATALOGS_BRIDGE + "local_catalog_trakt_import_dialog.dart": 554,
    STREMIO_TV_CATALOGS_BRIDGE + "local_catalog_editor_dialog.dart": 632,
}
# Exit: inject an import data contract instead of HTTP in this legacy dialog.
STREMIO_TV_CATALOGS_URL_IMPORT_HTTP_IMPORT = (
    STREMIO_TV_CATALOGS_BRIDGE + "local_catalog_url_import_dialog.dart", "package:http/http.dart",
)
# settings_widgets: feature checks apply from the first move; facade completes at step 4.
FEATURES += ("settings_widgets",)
SETTINGS_WIDGETS_COMPLETE = True
SETTINGS_WIDGETS_FACADE = "lib/screens/settings/widgets/settings_widgets.dart"
SETTINGS_WIDGETS_FACADE_CAP = 63  # settings_widgets: 63 export lines, 0 comments/blanks.
SETTINGS_WIDGETS_PUBLIC_NAMES = frozenset(['ConnectionCard', 'ConnectionInfo', 'ConnectionsSummary', 'SettingsBackground', 'SettingsBannerTone', 'SettingsHeader', 'SettingsInfoBanner', 'SettingsInfoTile', 'SettingsLookHero', 'SettingsPageHeader', 'SettingsPageScaffold', 'SettingsRowContent', 'SettingsRows', 'SettingsSection', 'SettingsSectionLabel', 'SettingsSelectDropdown', 'SettingsSelectOption', 'SettingsSkeleton', 'SettingsTile', 'SettingsToggleTile', 'TvRenderQualityChoice', 'TvUiScaleChoice', 'WebDavSyncPendingBadge', 'kSettingsAccent', 'kSettingsAccent2', 'kSettingsAmber', 'kSettingsBg', 'kSettingsDim', 'kSettingsDim2', 'kSettingsGreen', 'kSettingsLine', 'kSettingsMaxWidth', 'kSettingsPanel', 'kSettingsPanel2', 'kSettingsRed', 'kTvRenderQualityChoices', 'kTvUiScaleChoices', 'launchSettingsUrl', 'pushSettingsPage', 'settingsConnectionIsReady', 'settingsConnectionNeedsAttention', 'settingsInitialsFor', 'settingsPageTheme', 'showLegacyModeInfoDialog', 'showSettingsDialog', 'tvRenderQualityLabel', 'tvUiScaleLabel'])
STREMIO_TV_COMPLETE = True
STREMIO_TV_FACADE = "lib/screens/stremio_tv/stremio_tv_screen.dart"
STREMIO_TV_BRIDGE = "lib/features/stremio_tv/presentation/legacy_stremio_tv/"
# The original screen's catalog-detail caller moves unchanged to this file.
STREMIO_TV_CATALOG_DETAIL_CALLER = STREMIO_TV_BRIDGE + "stremio_tv_channel_actions.dart"
# Final cap is activated only at completion and measured over every line.
STREMIO_TV_FACADE_CAP = 115
STREMIO_TV_PREEXISTING = {
    "lib/features/stremio_tv/" + path for path in (
        "application/stremio_tv_providers.dart",
        "data/stremio_tv_catalog_editor.dart",
        "models/stremio_tv_catalog_option.dart",
        "models/stremio_tv_catalog_picker_result.dart",
        "presentation/stremio_tv_catalog_picker_dialog.dart",
        "presentation/stremio_tv_catalog_picker_views.dart",
        "presentation/stremio_tv_focus_frame.dart",
    )
}
# D2: one original build body cannot be split by a move. Measure at creation.
# Exit: separately characterized header/channel paint decomposition with goldens.
STREMIO_TV_SIZE_EXCEPTIONS = {
    STREMIO_TV_BRIDGE + "stremio_tv_layout.dart": 707,
}
STREMIO_TV_HANDOFF_FILES = {
    STREMIO_TV_BRIDGE + "stremio_tv_play_channel.dart",
    STREMIO_TV_BRIDGE + "stremio_tv_player_guide.dart",
}
# Completion alone activates the facade cap; feature scans are unconditional.
# Pure UI tuner extraction. All feature guards apply before completion.
STREMIO_TV_TUNER_COMPLETE = True
STREMIO_TV_TUNER_FACADE = "lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart"
STREMIO_TV_TUNER_BRIDGE = "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/"
STREMIO_TV_TUNER_FACADE_CAP = 299
STREMIO_TV_TUNER_SIZE_EXCEPTIONS = {}

DEBRIFY_TV_COMPLETE = True
DEBRIFY_TV_FACADE = "lib/screens/magic_tv_screen.dart"
DEBRIFY_TV_BRIDGE = "lib/features/debrify_tv/presentation/legacy_debrify_tv/"
DEBRIFY_TV_FACADE_CAP = 109
# Move-only size exception: a move cannot split one original method body.
# Exit: separately characterized decompositions of quick-play twin RD closures
# and channel-switch per-provider arms, with independent goldens and review.
DEBRIFY_TV_SIZE_EXCEPTIONS = {
    DEBRIFY_TV_BRIDGE + "debrify_tv_quick_play.dart": 946,
    DEBRIFY_TV_BRIDGE + "debrify_tv_channel_switch.dart": 524,
}
# Approved D1 exact import pair. Exit: a channel-download data contract.
DEBRIFY_TV_URL_IMPORT_HTTP_IMPORT = (
    DEBRIFY_TV_BRIDGE + "debrify_tv_url_import.dart", "package:http/http.dart",
)
# Screen-level wiring that composes several features (the composition
# boundary). Measured for size; features must not import it.
COMPOSITION = "lib/screens/search_screen"
FACADE = "lib/screens/search_screen.dart"
STORAGE_SOURCE_DIR = 'lib/services/storage'
STORAGE_ENUM_FILES = ('lib/models/ambient_trailer_surface.dart', 'lib/models/tv_render_quality.dart')
PLAYBACK_FACADE = "lib/services/torrent_playback_service.dart"
PLAYER_LAUNCH_FACADE = "lib/services/video_player_launcher.dart"
SETTINGS_FACADE = "lib/screens/settings_screen.dart"
# Step 7 enabled the facade cap and the TEMP(iptv_settings) rejection.
IPTV_SETTINGS_COMPLETE = True
IPTV_SETTINGS_FACADE = "lib/screens/settings/iptv_settings_page.dart"
IPTV_SETTINGS_BRIDGE = "lib/features/iptv_settings/presentation/legacy_iptv_settings/"
SETTINGS_COMPLETE = True
IPTV_COMPLETE = True
TORBOX_COMPLETE = True
PLAYBACK_SETTINGS_COMPLETE = True
PLAYBACK_SETTINGS_FACADE = "lib/screens/settings/external_player_settings_page.dart"
PLAYBACK_SETTINGS_BRIDGE = "lib/features/playback_settings/presentation/legacy_playback_settings/"
# Completed Spotlight composition facade; cap includes every physical line.
SPOTLIGHT_BOARD_COMPLETE = True
SPOTLIGHT_BOARD_FACADE_CAP = 451
SPOTLIGHT_BOARD_FACADE = "lib/widgets/home/spotlight_board.dart"
SPOTLIGHT_BOARD_BRIDGE = "lib/features/spotlight_board/presentation/legacy_spotlight_board/"
# Only the whole original _buildCard method may exceed 500. Measure at creation;
# exit: a separately reviewed behavior-level card decomposition with goldens.
SPOTLIGHT_BOARD_SIZE_EXCEPTIONS = {
    SPOTLIGHT_BOARD_BRIDGE + "spotlight_board_card_layout.dart": 585,
}
PLAYLIST_CONTENT_COMPLETE = True
PLAYLIST_CONTENT_FACADE = "lib/screens/playlist_content_view_screen.dart"
PLAYLIST_CONTENT_BRIDGE = "lib/features/playlist_content/presentation/legacy_playlist_content/"
DETAIL_SHOWCASE_COMPLETE = True
DETAIL_SHOWCASE_FACADE = "lib/widgets/detail/showcase_parts.dart"
# Measured at completion: twelve export directives occupy 24 physical lines.
DETAIL_SHOWCASE_FACADE_LIMIT = 24
DETAIL_SHOWCASE_PUBLIC_NAMES = frozenset(['ShowcaseMetrics', 'ShowcaseMetricsScope', 'kShowcaseGutter', 'ShowcaseAmbient', 'ShowcaseBackdropScrim', 'ShowcaseStickyLogo', 'ShowcaseIdentity', 'ShowcaseSeasons', 'ShowcaseEpisodeCell', 'ShowcaseEpisodeCardCompact', 'ShowcaseCast', 'ShowcaseSources', 'ShowcaseRecs', 'ShowcaseGuide', 'ShowcaseUniverse', 'ShowcaseDidYouKnow', 'ShowcaseBandNote', 'ShowcaseDetails'])
EPISODES_PANEL_COMPLETE = True
EPISODES_PANEL_FACADE = "lib/widgets/episodes_panel.dart"
EPISODES_PANEL_BRIDGE = "lib/features/episodes_panel/presentation/legacy_episodes_panel/"
# One immutable DTO import, scoped to this exact model and target.
EPISODES_PANEL_MODEL_IMPORTS = {
    "lib/features/episodes_panel/models/episodes_panel_view.dart": {
        "lib/services/trakt/trakt_episode_model.dart",
    },
}
# Set to the measured completed facade at step 7 (at most 450).
EPISODES_PANEL_FACADE_LIMIT = 281
CATALOG_DETAIL_COMPLETE = True
CATALOG_DETAIL_FACADE = "lib/screens/catalog_item_detail_screen.dart"
CATALOG_DETAIL_BRIDGE = "lib/features/catalog_detail/presentation/legacy_catalog_detail/"
MERGED_DETAIL_COMPLETE = True
MERGED_DETAIL_FACADE = "lib/screens/merged_series_detail_screen.dart"
MERGED_DETAIL_BRIDGE = "lib/features/merged_detail/presentation/legacy_merged_detail/"
ADDON_HUB_COMPLETE = True
ADDON_HUB_FACADE = "lib/screens/addons/addon_hub_screen.dart"
ADDON_HUB_BRIDGE = "lib/features/addon_hub/presentation/legacy_addon_hub/"
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
    # Pure catalog compatibility export surface; feature files own declarations.
    STREMIO_TV_CATALOGS_FACADE,
    # settings_widgets: pure compatibility exports; feature files own every declaration.
    SETTINGS_WIDGETS_FACADE,
    # Tuner facade wires its live widget view, owners and legacy sections.
    STREMIO_TV_TUNER_FACADE,
    # Stremio TV facade wires route-owned records, live State and frozen sections.
    STREMIO_TV_FACADE,
    # Debrify TV facade wires concrete legacy bridge sections and live State.
    DEBRIFY_TV_FACADE,
    ADDON_HUB_FACADE,
    # Spotlight facade wires concrete legacy bridge sections.
    SPOTLIGHT_BOARD_FACADE,
    FACADE,
    # Episodes panel's composition root owns live State wiring and lifecycle.
    EPISODES_PANEL_FACADE,
    PLAYLIST_CONTENT_FACADE,
    # Pure compatibility export surface; feature files own the widgets.
    DETAIL_SHOWCASE_FACADE,
    PIKPAK_FACADE,
    PREMIUMIZE_FACADE,
    PLAYBACK_SETTINGS_FACADE,
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
    # settings_widgets: exact legacy type/static imports; exits recorded in its plan.
    'lib/features/settings_widgets/presentation/settings_connection_card.dart': {
        'lib/services/main_page_bridge.dart': {'MainPageBridge'},
    },
    'lib/features/settings_widgets/presentation/settings_legacy_mode_dialog.dart': {
        'lib/services/profiles/profile_bootstrap.dart': {'ProfileBootstrap'},
    },
    # Detail showcase exact type/cache imports. No service logic.
    'lib/features/detail_showcase/presentation/showcase_cast.dart': {
        'lib/services/debrify_image_cache.dart': {'DebrifyImageCache'},
        'lib/services/imdb_enrichment_service.dart': {'CastMember'},
    },
    'lib/features/detail_showcase/presentation/showcase_did_you_know.dart': {
        'lib/services/imdb_enrichment_service.dart': {'DidYouKnowEntry'},
    },
    'lib/features/detail_showcase/presentation/showcase_episodes.dart': {
        'lib/services/debrify_image_cache.dart': {'DebrifyImageCache'},
        'lib/services/trakt/trakt_episode_model.dart': {'TraktEpisode'},
    },
    'lib/features/detail_showcase/presentation/showcase_grounds.dart': {
        'lib/services/debrify_image_cache.dart': {'DebrifyImageCache'},
    },
    'lib/features/detail_showcase/presentation/showcase_guide.dart': {
        'lib/services/imdb_parents_guide_service.dart': {'ParentsGuideResult', 'ParentsGuideCategory', 'ParentsGuideItem'},
    },
    'lib/features/detail_showcase/presentation/showcase_identity_readouts.dart': {
        'lib/services/debrify_image_cache.dart': {'DebrifyImageCache'},
    },
    'lib/features/detail_showcase/presentation/showcase_recs.dart': {
        'lib/services/debrify_image_cache.dart': {'DebrifyImageCache'},
    },
    'lib/features/detail_showcase/presentation/showcase_sources.dart': {
        'lib/services/series_source_service.dart': {'SeriesSource'},
    },
    'lib/features/detail_showcase/presentation/showcase_universe.dart': {
        'lib/services/debrify_image_cache.dart': {'DebrifyImageCache'},
        'lib/services/imdb_enrichment_service.dart': {'UniverseTitle'},
    },
    # End detail showcase imports.
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
    PREMIUMIZE_BRIDGE,
    PLAYBACK_SETTINGS_BRIDGE,
    # Bounded move-only settings bridge; exit: IPTV settings data contracts.
    IPTV_SETTINGS_BRIDGE,
    PLAYLIST_CONTENT_BRIDGE,
    MERGED_DETAIL_BRIDGE,
    ADDON_HUB_BRIDGE,
    SPOTLIGHT_BOARD_BRIDGE,
    EPISODES_PANEL_BRIDGE,
    CATALOG_DETAIL_BRIDGE,
    DEBRIFY_TV_BRIDGE,
    # Move-only catalog dialogs; exit: import/refresh contracts + Riverpod controllers.
    STREMIO_TV_CATALOGS_BRIDGE,
    STREMIO_TV_TUNER_BRIDGE,
    # Move-only State bridge; exit: Stremio TV data contracts/Riverpod.
    STREMIO_TV_BRIDGE,
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
# data contract in a later control-flow change. The only other approved HTTP
# import pair is DEBRIFY_TV_URL_IMPORT_HTTP_IMPORT (D1).
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
    if relative.startswith("lib/features/stremio_tv_catalogs/"):
        limit = STREMIO_TV_CATALOGS_SIZE_EXCEPTIONS.get(relative, 500)
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line Stremio TV catalogs extraction limit")
        if "TEMP(stremio_tv_catalogs)" in source and (STREMIO_TV_CATALOGS_COMPLETE or not relative.startswith(STREMIO_TV_CATALOGS_BRIDGE)):
            problems.append("Stremio TV catalogs temporary cross-call outside its exact legacy bridge")
    if STREMIO_TV_CATALOGS_COMPLETE and relative == STREMIO_TV_CATALOGS_FACADE:
        if lines > STREMIO_TV_CATALOGS_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {STREMIO_TV_CATALOGS_FACADE_CAP}-line Stremio TV catalogs facade limit")
        if "TEMP(stremio_tv_catalogs)" in source:
            problems.append("Stremio TV catalogs temporary cross-call remains in the facade")
        without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
        exports = re.compile(r"export\s+['\"]([^'\"]+)['\"]\s+show\s+([\w,\s]+);", re.MULTILINE)
        names = [name.strip() for match in exports.finditer(without_comments)
                 for name in match.group(2).split(",")]
        if exports.sub("", without_comments).strip():
            problems.append("Stremio TV catalogs facade must contain only export directives and comments")
        if len(names) != 5 or set(names) != STREMIO_TV_CATALOGS_PUBLIC_NAMES:
            problems.append("Stremio TV catalogs facade must export exactly the original five names")
        if any(not match.group(1).startswith("package:debrify/features/stremio_tv_catalogs/")
               for match in exports.finditer(without_comments)):
            problems.append("Stremio TV catalogs facade must export its feature destinations")
    if relative.startswith("lib/features/stremio_tv_tuner/"):
        limit = max(500, STREMIO_TV_TUNER_SIZE_EXCEPTIONS.get(relative, 0))
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line Stremio TV tuner extraction limit")
        if "TEMP(stremio_tv_tuner)" in source and (STREMIO_TV_TUNER_COMPLETE or not relative.startswith(STREMIO_TV_TUNER_BRIDGE)):
            problems.append("Stremio TV tuner temporary cross-call outside its exact legacy bridge")
    if relative.startswith("lib/features/stremio_tv_tuner/") or relative == STREMIO_TV_TUNER_FACADE:
        if re.search(r"\b(?:KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack)\b|package:media_kit|hero_trailer_backdrop|video_player_launcher|features/player_launch", source):
            problems.append("Stremio TV tuner adds keep-alive or playback engine ownership")
    if STREMIO_TV_TUNER_COMPLETE and relative == STREMIO_TV_TUNER_FACADE:
        if lines > STREMIO_TV_TUNER_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {STREMIO_TV_TUNER_FACADE_CAP}-line Stremio TV tuner facade limit")
        if "TEMP(stremio_tv_tuner)" in source:
            problems.append("Stremio TV tuner temporary cross-call remains in the facade")
    stremio_tv = relative.startswith("lib/features/stremio_tv/")
    if stremio_tv and relative not in STREMIO_TV_PREEXISTING:
        limit = max(500, STREMIO_TV_SIZE_EXCEPTIONS.get(relative, 0))
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line Stremio TV extraction limit")
        if "TEMP(stremio_tv)" in source and (STREMIO_TV_COMPLETE or not relative.startswith(STREMIO_TV_BRIDGE)):
            problems.append("Stremio TV temporary cross-call outside its exact legacy bridge")
        if relative not in STREMIO_TV_HANDOFF_FILES and re.search(r"\b(?:VideoPlayerLauncher\s*\.\s*push|VideoPlayerScreen)\s*\(", source):
            problems.append("Stremio TV playback entry outside its registered handoff files")
    if STREMIO_TV_COMPLETE and relative == STREMIO_TV_FACADE:
        if lines > STREMIO_TV_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {STREMIO_TV_FACADE_CAP}-line Stremio TV facade limit")
        if "TEMP(stremio_tv)" in source:
            problems.append("Stremio TV temporary cross-call remains in the facade")
    if relative.startswith("lib/features/debrify_tv/"):
        limit = max(500, DEBRIFY_TV_SIZE_EXCEPTIONS.get(relative, 0))
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line Debrify TV extraction limit")
        if "TEMP(debrify_tv)" in source and (DEBRIFY_TV_COMPLETE or not relative.startswith(DEBRIFY_TV_BRIDGE)):
            problems.append("Debrify TV temporary cross-call outside its exact legacy bridge")
    if DEBRIFY_TV_COMPLETE and relative == DEBRIFY_TV_FACADE:
        if lines > DEBRIFY_TV_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {DEBRIFY_TV_FACADE_CAP}-line Debrify TV facade limit")
        if "TEMP(debrify_tv)" in source:
            problems.append("Debrify TV temporary cross-call remains in the facade")
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
    if relative.startswith("lib/features/playback_settings/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line playback settings extraction limit")
        if "TEMP(playback_settings)" in source and (PLAYBACK_SETTINGS_COMPLETE or not relative.startswith(PLAYBACK_SETTINGS_BRIDGE)):
            problems.append("temporary playback settings cross-call outside the staged legacy bridge")
    if PLAYBACK_SETTINGS_COMPLETE and relative == PLAYBACK_SETTINGS_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line playback settings facade limit")
        if "TEMP(playback_settings)" in source:
            problems.append("temporary playback settings cross-call remains in the facade")
    # settings_widgets: no feature size exceptions; completion adds the pure facade.
    if relative.startswith("lib/features/settings_widgets/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line settings widgets limit")
    if relative.startswith("lib/features/settings_widgets/") or relative == SETTINGS_WIDGETS_FACADE:
        if "TEMP(settings_widgets)" in source:
            problems.append("temporary settings widgets cross-call remains")
    if SETTINGS_WIDGETS_COMPLETE and relative == SETTINGS_WIDGETS_FACADE:
        if lines > SETTINGS_WIDGETS_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {SETTINGS_WIDGETS_FACADE_CAP}-line settings widgets facade limit")
        without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
        exports = re.compile(r"export\s+['\"]([^'\"]+)['\"]\s+show\s+([\w,\s]+);", re.MULTILINE)
        names = [name.strip() for match in exports.finditer(without_comments)
                 for name in match.group(2).split(",")]
        if exports.sub("", without_comments).strip():
            problems.append("settings widgets facade must contain only export directives and comments")
        if len(names) != 47 or set(names) != SETTINGS_WIDGETS_PUBLIC_NAMES:
            problems.append("settings widgets facade must export exactly the original 47 names")
        if any(not match.group(1).startswith("package:debrify/features/settings_widgets/presentation/")
               for match in exports.finditer(without_comments)):
            problems.append("settings widgets facade must export its feature destinations")
    if DETAIL_SHOWCASE_COMPLETE and relative == DETAIL_SHOWCASE_FACADE:
        if lines > DETAIL_SHOWCASE_FACADE_LIMIT:
            problems.append(f"{lines} lines exceeds the {DETAIL_SHOWCASE_FACADE_LIMIT}-line detail showcase facade limit")
        if "TEMP(detail_showcase)" in source:
            problems.append("temporary detail showcase cross-call remains in the facade")
        without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
        exports = re.compile(r"export\s+['\"]([^'\"]+)['\"]\s+show\s+([\w,\s]+);", re.MULTILINE)
        names = [name.strip() for match in exports.finditer(without_comments)
                 for name in match.group(2).split(",")]
        if exports.sub("", without_comments).strip():
            problems.append("detail showcase facade must contain only export directives and comments")
        if len(names) != 18 or set(names) != DETAIL_SHOWCASE_PUBLIC_NAMES:
            problems.append("detail showcase facade must export exactly the original eighteen names")
        if any(not match.group(1).startswith("package:debrify/features/detail_showcase/presentation/showcase_")
               for match in exports.finditer(without_comments)):
            problems.append("detail showcase facade must export its feature destinations")
    # Always scan the feature, including intermediate extraction checkpoints.
    if relative.startswith("lib/features/detail_showcase/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line detail showcase extraction limit")
        if "TEMP(detail_showcase)" in source:
            problems.append("temporary detail showcase cross-call remains")
        if re.search(r"\b(?:FocusNode|[A-Za-z]*Controller|Timer|KeepAlive)\s*\(", source):
            problems.append("detail showcase constructs an owned resource")
        if re.search(r"\b(?:node|focusNode|nodes\[[^]]+\])\s*\.\s*dispose\s*\(", source):
            problems.append("detail showcase disposes a borrowed focus node")
    if relative.startswith("lib/features/episodes_panel/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line episodes panel extraction limit")
        if "TEMP(episodes_panel)" in source and (EPISODES_PANEL_COMPLETE or not relative.startswith(EPISODES_PANEL_BRIDGE)):
            problems.append("episodes panel temporary cross-call outside its staged legacy bridge")
        if re.search(r"\b(?:VideoPlayerLauncher|VideoPlayerScreen|SeriesSourceFetcher|mergeSources|TorrentPlayback\w*)\b", source):
            problems.append("episodes panel contains a playback/source-launch symbol")
    if EPISODES_PANEL_COMPLETE and relative == EPISODES_PANEL_FACADE:
        if lines > EPISODES_PANEL_FACADE_LIMIT:
            problems.append(f"{lines} lines exceeds the {EPISODES_PANEL_FACADE_LIMIT}-line episodes panel facade limit")
        if "TEMP(episodes_panel)" in source:
            problems.append("episodes panel temporary cross-call remains in the facade")
    if relative.startswith("lib/features/catalog_detail/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line catalog-detail extraction limit")
        if "TEMP(catalog_detail)" in source and (CATALOG_DETAIL_COMPLETE or not relative.startswith(CATALOG_DETAIL_BRIDGE)):
            problems.append("temporary catalog-detail cross-call outside the staged legacy bridge")
    if CATALOG_DETAIL_COMPLETE and relative == CATALOG_DETAIL_FACADE:
        if lines > 360:
            problems.append(f"{lines} lines exceeds the 360-line catalog-detail facade limit")
        if "TEMP(catalog_detail)" in source:
            problems.append("temporary catalog-detail cross-call remains in the facade")
    if relative.startswith("lib/features/merged_detail/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line merged-detail extraction limit")
        if "TEMP(merged_detail)" in source and (MERGED_DETAIL_COMPLETE or not relative.startswith(MERGED_DETAIL_BRIDGE)):
            problems.append("temporary merged-detail cross-call outside the staged legacy bridge")
    if MERGED_DETAIL_COMPLETE and relative == MERGED_DETAIL_FACADE:
        if lines > 450:
            problems.append(f"{lines} lines exceeds the 450-line merged-detail facade limit")
        if "TEMP(merged_detail)" in source:
            problems.append("temporary merged-detail cross-call remains in the facade")
    if relative.startswith("lib/features/premiumize_files/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line Premiumize extraction limit")
        if "TEMP(premiumize)" in source and (PREMIUMIZE_COMPLETE or not relative.startswith(PREMIUMIZE_BRIDGE)):
            problems.append("temporary Premiumize cross-call outside the staged legacy bridge")
        if relative.startswith("lib/features/premiumize_files/application/") and re.search(r"\bBuildContext\b", source):
            problems.append("pure Premiumize application helper references BuildContext")
        if re.search(r"\blate\b", source):
            problems.append("Premiumize extraction introduces late initialization")
    if PREMIUMIZE_COMPLETE and relative == PREMIUMIZE_FACADE:
        if lines > PREMIUMIZE_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {PREMIUMIZE_FACADE_CAP}-line Premiumize facade limit")
        if "TEMP(premiumize)" in source:
            problems.append("temporary Premiumize cross-call remains in the facade")
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
    if relative.startswith("lib/features/spotlight_board/"):
        limit = max(500, SPOTLIGHT_BOARD_SIZE_EXCEPTIONS.get(relative, 0))
        if lines > limit:
            problems.append(f"{lines} lines exceeds the {limit}-line spotlight board extraction limit")
        if "TEMP(spotlight_board)" in source and (SPOTLIGHT_BOARD_COMPLETE or not relative.startswith(SPOTLIGHT_BOARD_BRIDGE)):
            problems.append("spotlight board temporary cross-call outside its bounded bridge")
        if re.search(r"\b(?:KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack)\b|package:media_kit|hero_trailer_backdrop|video_player_launcher|features/player_launch", source):
            problems.append("spotlight board adds keep-alive or playback engine ownership")
    if SPOTLIGHT_BOARD_COMPLETE and relative == SPOTLIGHT_BOARD_FACADE:
        if lines > SPOTLIGHT_BOARD_FACADE_CAP:
            problems.append(f"{lines} lines exceeds the {SPOTLIGHT_BOARD_FACADE_CAP}-line spotlight board facade limit")
        if "TEMP(spotlight_board)" in source:
            problems.append("spotlight board temporary cross-call remains in the facade")
    if relative.startswith("lib/features/playlist_content/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line playlist content extraction limit")
        if "TEMP(playlist_content)" in source and (PLAYLIST_CONTENT_COMPLETE or not relative.startswith(PLAYLIST_CONTENT_BRIDGE)):
            problems.append("playlist content temporary cross-call outside its bounded bridge")
    if PLAYLIST_CONTENT_COMPLETE and relative == PLAYLIST_CONTENT_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line playlist content facade limit")
        if "TEMP(playlist_content)" in source:
            problems.append("playlist content facade retains a temporary cross-call")
    if relative.startswith("lib/features/addon_hub/"):
        if lines > 500:
            problems.append(f"{lines} lines exceeds the 500-line addon hub extraction limit")
        if "TEMP(addon_hub)" in source and (ADDON_HUB_COMPLETE or not relative.startswith(ADDON_HUB_BRIDGE)):
            problems.append("addon hub temporary cross-call outside its exact legacy bridge")
    if ADDON_HUB_COMPLETE and relative == ADDON_HUB_FACADE:
        if lines > 400:
            problems.append(f"{lines} lines exceeds the 400-line addon hub facade limit")
        if "TEMP(addon_hub)" in source:
            problems.append("addon hub facade retains a temporary cross-call")
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
    if lines > max(800, PLAYER_LAUNCH_SIZE_EXCEPTIONS.get(relative, 0), DEBRIFY_TV_SIZE_EXCEPTIONS.get(relative, 0)):
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
            if relative.startswith("lib/features/stremio_tv_catalogs/"):
                if target == STREMIO_TV_CATALOGS_FACADE:
                    problems.append("Stremio TV catalogs feature imports its facade")
                if (not relative.startswith((STREMIO_TV_CATALOGS_BRIDGE, "lib/features/stremio_tv_catalogs/data/"))
                        and target.startswith("lib/services/")):
                    problems.append("Stremio TV catalogs service import outside data or its exact legacy bridge")
                if target.startswith("package:http/") and (relative, target) != STREMIO_TV_CATALOGS_URL_IMPORT_HTTP_IMPORT:
                    problems.append("Stremio TV catalogs HTTP import outside its exact URL-dialog pair")
            if relative.startswith("lib/features/") and target.startswith("lib/features/"):
                own_catalog_feature = relative.split("/")[2]
                other_catalog_feature = target.split("/")[2]
                if ({own_catalog_feature, other_catalog_feature} == {"stremio_tv", "stremio_tv_catalogs"}
                        and not target.startswith(f"lib/features/{other_catalog_feature}/models/")):
                    problems.append("Stremio TV/catalogs implementation cross-import outside models")
            # settings_widgets: physical directive targets, never facade resolution.
            if relative.startswith("lib/features/settings_widgets/"):
                if target == SETTINGS_WIDGETS_FACADE:
                    problems.append("settings widgets feature imports its facade")
                if target.startswith("lib/screens/"):
                    problems.append("settings widgets feature imports a screen")
                if target.startswith("lib/services/") and target not in PRESENTATION_BRIDGE_IMPORTS.get(relative, {}):
                    problems.append("settings widgets service import outside its exact registered show entry")
                if "url_launcher" in target and relative != "lib/features/settings_widgets/presentation/settings_links.dart":
                    problems.append("settings widgets URL launcher import outside its links file")
                if (target.startswith(("package:http/", "package:shared_preferences/", "package:sqflite", "lib/services/storage/"))
                        or any(name in target for name in ("media_kit", "video_player", "player_launch", "torrent_playback", "trailer_engine"))):
                    problems.append("settings widgets imports a playback/storage/http implementation")
            if relative.startswith("lib/features/") and target.startswith("lib/features/"):
                own_widgets_feature, other_widgets_feature = relative.split("/")[2], target.split("/")[2]
                widgets_peers = {"settings", "playback_settings", "iptv_settings"}
                if ((own_widgets_feature == "settings_widgets" and other_widgets_feature in widgets_peers)
                        or (other_widgets_feature == "settings_widgets" and own_widgets_feature in widgets_peers)):
                    if not target.startswith(f"lib/features/{other_widgets_feature}/models/"):
                        problems.append("settings widgets/settings-family implementation cross-import")
            if stremio_tv:
                if target == STREMIO_TV_FACADE:
                    problems.append("Stremio TV feature imports its facade")
                if relative not in STREMIO_TV_PREEXISTING:
                    if not relative.startswith(STREMIO_TV_BRIDGE) and target.startswith("lib/services/"):
                        problems.append("Stremio TV service import outside its exact legacy bridge")
                    if relative not in STREMIO_TV_HANDOFF_FILES and any(name in target for name in (
                            "video_player_launcher", "player_launch", "media_kit", "lib/screens/video_player/")):
                        problems.append("Stremio TV playback import outside its registered handoff files")
            if relative.startswith("lib/features/addon_hub/"):
                if target in (ADDON_HUB_FACADE, "lib/screens/addons_screen.dart", "lib/screens/settings/stremio_addons_page.dart"):
                    problems.append("addon hub feature imports a legacy addon screen")
                if not relative.startswith(ADDON_HUB_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("addon hub service import outside its exact legacy bridge")
            if relative.startswith("lib/features/") and target.startswith("lib/features/"):
                own, other = relative.split("/")[2], target.split("/")[2]
                if ((own == "addon_hub" and other in ("sources", "settings")) or
                    (other == "addon_hub" and own in ("sources", "settings"))):
                    problems.append("addon hub/sources/settings cross-feature import")
            if relative.startswith("lib/features/detail_showcase/") or relative == DETAIL_SHOWCASE_FACADE:
                if any(name in target for name in ("media_kit", "hero_trailer_backdrop", "trailer_engine", "video_player_launcher", "player_launch")):
                    problems.append("detail showcase imports a playback implementation")
                if relative.startswith("lib/features/detail_showcase/") and target == DETAIL_SHOWCASE_FACADE:
                    problems.append("detail showcase feature imports its facade")
            if relative.startswith("lib/features/spotlight_board/"):
                if target == SPOTLIGHT_BOARD_FACADE:
                    problems.append("spotlight board feature imports its facade")
                if not relative.startswith(SPOTLIGHT_BOARD_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("spotlight board service import outside the exact legacy bridge")
            if relative.startswith("lib/features/stremio_tv_tuner/"):
                if target == STREMIO_TV_TUNER_FACADE:
                    problems.append("Stremio TV tuner feature imports its facade")
                if not relative.startswith(STREMIO_TV_TUNER_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("Stremio TV tuner service import outside its exact legacy bridge")
            if relative.startswith("lib/features/") and target.startswith("lib/features/"):
                own_tuner_feature = relative.split("/")[2]
                other_tuner_feature = target.split("/")[2]
                if ((own_tuner_feature == "stremio_tv_tuner" and other_tuner_feature in ("stremio_tv", "stremio_tv_catalogs"))
                        or (other_tuner_feature == "stremio_tv_tuner" and own_tuner_feature in ("stremio_tv", "stremio_tv_catalogs"))):
                    if not target.startswith(f"lib/features/{other_tuner_feature}/models/"):
                        problems.append("Stremio TV tuner/TV/catalogs implementation cross-import")
            if relative.startswith("lib/features/debrify_tv/"):
                if target == DEBRIFY_TV_FACADE:
                    problems.append("Debrify TV feature imports its facade")
                if not relative.startswith(DEBRIFY_TV_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("Debrify TV service import outside its exact legacy bridge")
            if target.startswith("lib/features/") and relative.startswith("lib/features/"):
                own_feature = relative.split("/")[2]
                other_feature = target.split("/")[2]
                if {own_feature, other_feature} == {"spotlight_board", "home"} and not target.startswith(f"lib/features/{other_feature}/models/"):
                    problems.append("spotlight board/home implementation cross-import")
            if relative.startswith("lib/features/episodes_panel/"):
                if target == EPISODES_PANEL_FACADE:
                    problems.append("episodes panel feature imports its facade")
                if (not relative.startswith(EPISODES_PANEL_BRIDGE)
                        and target.startswith("lib/services/")
                        and target not in EPISODES_PANEL_MODEL_IMPORTS.get(relative, set())):
                    problems.append("episodes panel service/storage import outside its exact legacy bridge")
            if target.startswith("lib/features/") and relative.startswith("lib/features/"):
                own_panel_feature = relative.split("/")[2]
                other_panel_feature = target.split("/")[2]
                panel_peers = {"merged_detail", "catalog_detail", "detail_showcase"}
                if ((own_panel_feature == "episodes_panel" and other_panel_feature in panel_peers)
                        or (other_panel_feature == "episodes_panel" and own_panel_feature in panel_peers)):
                    if not target.startswith(f"lib/features/{other_panel_feature}/models/"):
                        problems.append("episodes panel/detail implementation cross-import")
            if relative.startswith("lib/features/playback_settings/") and not relative.startswith(PLAYBACK_SETTINGS_BRIDGE) and target.startswith("lib/services/"):
                problems.append("playback settings outside the legacy bridge imports a service")
            if relative.startswith("lib/features/iptv_settings/"):
                if target == IPTV_SETTINGS_FACADE:
                    problems.append("IPTV settings feature imports its facade")
                if not relative.startswith(IPTV_SETTINGS_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("IPTV settings service import outside the exact legacy bridge")
            if target.startswith("lib/features/") and relative.startswith("lib/features/"):
                own_feature = relative.split("/")[2]
                other_feature = target.split("/")[2]
                if ((own_feature == "iptv_settings" and other_feature in ("settings", "iptv", "playback_settings")) or
                        (other_feature == "iptv_settings" and own_feature in ("settings", "iptv", "playback_settings"))):
                    if not target.startswith(f"lib/features/{other_feature}/models/"):
                        problems.append("IPTV settings/settings/IPTV/playback settings implementation cross-import")
            if relative.startswith("lib/features/iptv/application/") and target.startswith("lib/services/"):
                problems.append("pure IPTV application helper imports a legacy service")
            if relative.startswith("lib/features/torbox_downloads/application/") and target.startswith("lib/services/"):
                problems.append("pure TorBox application helper imports a legacy service")
            if relative.startswith("lib/features/premiumize_files/application/") and target.startswith(("package:http/", "package:shared_preferences/", "package:sqflite")):
                problems.append("pure Premiumize application helper imports a data implementation")
            if relative.startswith("lib/features/premiumize_files/application/") and target.startswith("lib/services/"):
                problems.append("pure Premiumize application helper imports a legacy service")
            if relative.startswith("lib/features/pikpak_files/application/") and target.startswith("lib/services/"):
                problems.append("pure PikPak application helper imports a legacy service")
            if relative.startswith("lib/features/debrid_downloads/application/") and target.startswith("lib/services/"):
                problems.append("pure Real-Debrid application helper imports a legacy service")
            if relative.startswith("lib/features/playlist_content/application/") and target.startswith("lib/services/"):
                problems.append("pure playlist content application helper imports a legacy service")
            if relative.startswith("lib/features/playlist_content/") and target == "lib/services/playlist_player_service.dart":
                problems.append("playlist content imports the playlist player service")
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
                if relative.startswith("lib/features/detail_showcase/") and names != bridge[target]:
                    problems.append(f"detail showcase service import must show the exact registered declarations: {uri}")
                if relative.startswith("lib/features/settings_widgets/") and names != bridge[target]:
                    problems.append(f"settings widgets service import must show the exact registered declarations: {uri}")
                if not names or not names <= bridge[target]:
                    problems.append(f"legacy presentation import must show only allowed declarations: {uri}")
            legacy_bridge = (relative.startswith(LEGACY_PLAYBACK_BRIDGES)
                             and target.startswith("lib/services/"))
            if layer == "presentation" and target.startswith((
                    "lib/services/", "package:http/", "package:shared_preferences/",
                    "package:sqflite")) and not legacy_bridge and (relative, target) not in (PLAYER_LAUNCH_DEOVR_HTTP_IMPORT, DEBRIFY_TV_URL_IMPORT_HTTP_IMPORT, STREMIO_TV_CATALOGS_URL_IMPORT_HTTP_IMPORT) and target not in (
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
                if own == "playback_settings" and target == PLAYBACK_SETTINGS_FACADE:
                    problems.append("playback settings feature imports its facade")
                if target.startswith("lib/features/") and {own, target.split("/")[2]} in ({"playback_settings", "settings"}, {"playback_settings", "iptv_settings"}) and "/models/" not in target:
                    problems.append("playback/settings cross-feature import outside models")
                if target.startswith("lib/features/"):
                    other = target.split("/")[2]
                    if ((own == "detail_showcase" and other in ("merged_detail", "catalog_detail")) or
                            (other == "detail_showcase" and own in ("merged_detail", "catalog_detail"))):
                        if not target.startswith(f"lib/features/{other}/models/"):
                            problems.append("detail showcase/detail implementation cross-import")
                clouds = {"debrid_downloads", "torbox_downloads", "pikpak_files"}
                if target.startswith("lib/features/"):
                    other = target.split("/")[2]
                    if (own == "playlist_content" and other in clouds) or (other == "playlist_content" and own in clouds):
                        problems.append("playlist content/cloud cross-feature import")
                if own == "playlist_content" and target == PLAYLIST_CONTENT_FACADE:
                    problems.append("playlist content feature imports its facade")
                if (target == CATALOG_DETAIL_FACADE and
                        relative != "lib/features/home/presentation/home_detail_presentation.dart" and
                        relative != STREMIO_TV_CATALOG_DETAIL_CALLER):
                    problems.append("feature imports the catalog-detail facade outside the existing Home caller")
                if own == "catalog_detail" and not relative.startswith(CATALOG_DETAIL_BRIDGE) and target.startswith("lib/services/"):
                    problems.append("catalog-detail service/storage import outside the legacy bridge")
                if target.startswith("lib/features/") and {own, target.split("/")[2]} == {"catalog_detail", "merged_detail"}:
                    problems.append("catalog-detail/merged-detail cross-feature import")
                if own == "merged_detail" and target == MERGED_DETAIL_FACADE:
                    problems.append("merged-detail feature imports the detail facade")
                if own == "merged_detail" and not relative.startswith(MERGED_DETAIL_BRIDGE) and target.startswith(("lib/services/", "lib/services/storage/")):
                    problems.append("merged-detail service/storage/launcher import outside the legacy bridge")
                if own == "premiumize_files" and target == PREMIUMIZE_FACADE:
                    problems.append("Premiumize feature imports the files facade")
                if target.startswith("lib/features/") and "premiumize_files" in {own, target.split("/")[2]}:
                    other = target.split("/")[2] if own == "premiumize_files" else own
                    if other in {"pikpak_files", "torbox_downloads", "debrid_downloads", "alldebrid_files"}:
                        problems.append("Premiumize/cloud feature cross-import")
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


def premiumize_peer_import_violations(path):
    relative = path.relative_to(ROOT).as_posix()
    problems = []
    for declaration in re.findall(r"^\s*import\s+([^;]+);", path.read_text(), re.MULTILINE):
        for uri in URIS.findall(declaration):
            target = uri
            if uri.startswith("package:debrify/"):
                target = "lib/" + uri.removeprefix("package:debrify/")
            elif not uri.startswith(("dart:", "package:")):
                resolved = (path.parent / uri).resolve()
                if resolved.is_relative_to(ROOT):
                    target = resolved.relative_to(ROOT).as_posix()
            if target.startswith("lib/features/premiumize_files/"):
                problems.append(f"{relative}: Premiumize/cloud feature cross-import")
    return problems


def main() -> int:
    paths = {
        p for feature in FEATURES
        for p in (ROOT / "lib/features" / feature).rglob("*.dart")
        if not p.name.endswith(GENERATED_SUFFIXES)
    }
    # Scan the catalog peer even before its independent feature registration.
    paths.update((ROOT / "lib/features/stremio_tv_catalogs").rglob("*.dart"))
    paths.update(ROOT / p for p in EXTRACTED_ELSEWHERE)
    if PLAYBACK_SETTINGS_COMPLETE:
        paths.add(ROOT / PLAYBACK_SETTINGS_FACADE)
    if IPTV_SETTINGS_COMPLETE:
        paths.add(ROOT / IPTV_SETTINGS_FACADE)
    if SPOTLIGHT_BOARD_COMPLETE:
        paths.add(ROOT / SPOTLIGHT_BOARD_FACADE)
    if PLAYLIST_CONTENT_COMPLETE:
        paths.add(ROOT / PLAYLIST_CONTENT_FACADE)
    if SETTINGS_WIDGETS_COMPLETE:
        paths.add(ROOT / SETTINGS_WIDGETS_FACADE)
    if DETAIL_SHOWCASE_COMPLETE:
        paths.add(ROOT / DETAIL_SHOWCASE_FACADE)
    if EPISODES_PANEL_COMPLETE:
        paths.add(ROOT / EPISODES_PANEL_FACADE)
    if CATALOG_DETAIL_COMPLETE:
        paths.add(ROOT / CATALOG_DETAIL_FACADE)
    if MERGED_DETAIL_COMPLETE:
        paths.add(ROOT / MERGED_DETAIL_FACADE)
    if ADDON_HUB_COMPLETE:
        paths.add(ROOT / ADDON_HUB_FACADE)
    if DEBRIFY_TV_COMPLETE:
        paths.add(ROOT / DEBRIFY_TV_FACADE)
    if STREMIO_TV_CATALOGS_COMPLETE:
        paths.add(ROOT / STREMIO_TV_CATALOGS_FACADE)
    if STREMIO_TV_TUNER_COMPLETE:
        paths.add(ROOT / STREMIO_TV_TUNER_FACADE)
    if STREMIO_TV_COMPLETE:
        paths.add(ROOT / STREMIO_TV_FACADE)
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
    if not (ROOT / "lib/features/spotlight_board").is_dir():
        problems.append("Registered spotlight board directory is missing")
    if STREMIO_TV_COMPLETE and not (ROOT / STREMIO_TV_FACADE).is_file():
        problems.append("Stremio TV facade is missing")
    if not (ROOT / STORAGE_SOURCE_DIR).is_dir():
        problems.append(f'Registered storage directory is missing: {STORAGE_SOURCE_DIR}')
    if not paths:
        problems.append("No migrated sources found; check the measured source set.")
    if "alldebrid_files" not in FEATURES:
        for path in sorted((ROOT / "lib/features/alldebrid_files").rglob("*.dart")):
            problems.extend(premiumize_peer_import_violations(path))
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
