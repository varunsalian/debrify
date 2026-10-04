import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shape sweep's ratchet.
///
/// Phase four moved every `BorderRadius.circular(<literal>)` it could onto
/// `app.shape.br()` / `.brImg()` / `.brPill`. "Could" is doing real work in
/// that sentence: a site only converts where `app` is in scope and the
/// expression is not `const`, and the sweep discovered which by asking the
/// analyzer and reverting everything it complained about. What is left is the
/// residue of those two constraints, not a judgement about which radii deserve
/// to follow the theme.
///
/// ## What this test proves, and what it does not
///
/// It is a **tripwire, not a proof**, and it is worth being exact about which:
///
///  * it catches a NEW bare radius added to an already-swept file, which is
///    how a sweep erodes over the following months;
///  * it catches a wholesale revert, via the floor on total token calls;
///  * it does NOT prove a site was classified correctly as surface-vs-artwork,
///    nor that a rewrite preserved its argument. Nothing lexical can.
///  * and like every ratchet, it can be defeated by raising a number in the
///    same change that regresses — that is what review is for.
///
/// What actually bounds the risk is arithmetic: legacy's shape scale is
/// exactly 1, so a converted site under the shipped theme renders its own
/// literal or it does not compile. `test/theme/goldens_test.dart`'s legacy
/// golden came through the entire sweep unchanged, which is the pixel
/// evidence.
///
/// ## Lowering a number here is always allowed
///
/// The residue shrinks as `const` sites are opened up or `app` is threaded
/// further. Update the entry when you do. RAISING one needs a reason.
const Map<String, int> kShapeResidue = {
  // Addon hub: every destination and the facade, including zero budgets.
  'lib/features/addon_hub/presentation/addon_hub_action_button.dart': 0,
  'lib/features/addon_hub/presentation/addon_hub_dialog.dart': 0,
  'lib/features/addon_hub/presentation/addon_hub_option_tile.dart': 0,
  'lib/features/addon_hub/presentation/addon_hub_options_sheet.dart': 0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_actions.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_row.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_filter_bar.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_install_actions.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_list.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_row.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_menus.dart':
      0,

  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_player_tiles.dart':
      0,
  'lib/features/iptv_settings/presentation/iptv_settings_playlist_name_dialog.dart':
      0,
  'lib/features/iptv_settings/presentation/iptv_settings_tv_tab_bar.dart': 0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_desktop_episode.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_card.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_metadata.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_file_list.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_mobile_episode.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_view.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_layout.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_bulk_delete.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_selected_delete.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search_layout.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_bar.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_seasons_list.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_feedback.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search_layout.dart':
      2,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_link_actions.dart':
      1,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_download_bulk_delete.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_download_toolbar.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_series_browser.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_toolbar.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_options.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_options.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_toolbar.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_selection_sheet.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_bar.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search_layout.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_search.dart':
      2,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_link_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_download_options.dart':
      3,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_bulk_delete.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_series_layout.dart':
      0,
  'lib/features/iptv/presentation/iptv_stage_chip.dart': 0,
  'lib/features/iptv/presentation/key_cap.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_cockpit_stage.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_focus_stage_info.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_loaded_layout.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_preview_layout.dart': 1,
  'lib/features/iptv/presentation/legacy_iptv/iptv_rail_info.dart': 0,
  // Search presentation extracted from search_screen.dart (tokens moved, not lost).
  'lib/features/search/presentation/catalog_search_prompt.dart': 0,
  'lib/features/search/presentation/keyword_search_page.dart': 0,
  'lib/features/search/presentation/keyword_selection_overlay.dart': 0,
  'lib/features/search/presentation/keyword_source_tabs.dart': 0,
  'lib/features/search/presentation/keyword_toolbar.dart': 0,
  'lib/features/search/presentation/search_query_field.dart': 0,
  'lib/features/home/presentation/home_source_editor.dart': 0,
  'lib/features/home/presentation/home_bound_source_tile.dart': 0,
  'lib/features/home/presentation/home_canvas_tabs.dart': 0,
  'lib/features/home/presentation/home_tonight_queue_row.dart': 0,
  'lib/features/home/presentation/home_tonight_card_caption.dart': 0,
  'lib/features/home/presentation/home_takeover_info.dart': 0,
  'lib/features/home/presentation/home_art_poster.dart': 0,
  'lib/features/sources/presentation/source_provider_strip.dart': 0,
  'lib/features/sources/presentation/source_toolbar_controls.dart': 0,
  'lib/features/sources/presentation/source_active_filters.dart': 0,
  'lib/features/sources/presentation/source_pending_results_pill.dart': 0,
  'lib/features/search/presentation/source_toggle_row.dart': 0,
  'lib/features/search/presentation/source_action_chip.dart': 0,
  'lib/features/search/presentation/source_dialog_shell.dart': 0,
  'lib/features/home/presentation/category_tag.dart': 0,
  'lib/features/search/presentation/search_mode_toggle.dart': 0,
  'lib/ui/core/see_all_link.dart': 0,
  'lib/screens/alldebrid/alldebrid_files_screen.dart': 1,
  'lib/screens/cloud_screen.dart': 0,
  'lib/screens/debrify_tv/dialogs/community_channels_dialog.dart': 12,
  'lib/screens/debrify_tv/dialogs/external_player_notice_dialog.dart': 0,
  'lib/screens/debrify_tv/dialogs/spotlight_dialog.dart': 0,
  'lib/screens/debrify_tv/widgets/tv_focusable_button.dart': 0,
  'lib/screens/debrify_tv/widgets/tv_focusable_card.dart': 0,
  'lib/screens/downloads_screen.dart': 2,
  'lib/screens/magic_tv_screen.dart': 7,
  'lib/screens/playlist_screen.dart': 0,
  'lib/screens/premiumize/premiumize_files_screen.dart': 6,
  'lib/features/home/presentation/home_catalog_card.dart': 0,
  'lib/ui/core/trailer_indicators.dart': 1,
  'lib/features/home/presentation/home_hero_live_layer.dart': 0,
  'lib/features/search/presentation/keyword_search_rows.dart': 0,
  'lib/screens/see_all/catalog_see_all_screen.dart': 0,
  'lib/screens/settings/app_theme_page.dart': 1,
  'lib/screens/settings/debrify_tv_settings_page.dart': 0,
  'lib/screens/settings/detail_theme_page.dart': 1,
  // Raised 2026-10-03 to the counts found at refactor/codebase 17db33f2: these
  // radii arrived with feature work after the sweep (see the settings plan's
  // "Found, not fixed"). The guard stays armed against further growth.
  'lib/screens/settings/filter_settings_page.dart': 2,
  'lib/screens/settings/iptv_hidden_categories_page.dart': 1,
  'lib/screens/settings/iptv_settings_two_pane.dart': 7,
  'lib/screens/settings/provider_settings_page.dart': 0,
  'lib/screens/settings/quick_play_settings_page.dart': 0,
  'lib/screens/settings/settings_tv_layout.dart': 0,
  'lib/screens/settings/simkl_settings_page.dart': 1,
  'lib/screens/settings/trakt_settings_page.dart': 1,
  'lib/screens/settings/widgets/dynamic_settings_builder.dart': 7,
  'lib/screens/settings/widgets/settings_widgets.dart': 10,
  'lib/features/settings/presentation/legacy_settings/settings_release_details.dart':
      0,
  'lib/screens/stremio_tv/stremio_tv_filter_page.dart': 0,
  'lib/screens/stremio_tv/stremio_tv_screen.dart': 0,
  'lib/screens/stremio_tv/widgets/stremio_tv_empty_state.dart': 0,
  'lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart': 4,
  'lib/screens/stremio_tv/widgets/stremio_tv_repo_browser_dialog.dart': 3,
  'lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart': 0,
  'lib/screens/trakt_calendar_screen.dart': 2,
  'lib/screens/webdav/webdav_files_screen.dart': 0,
  'lib/widgets/adaptive_playlist_section.dart': 0,
  'lib/widgets/catalog_item_tile.dart': 0,
  'lib/widgets/cloud/cloud_file_row.dart': 0,
  'lib/widgets/cloud/cloud_segmented_tabs.dart': 0,
  'lib/widgets/desktop_sidebar_nav.dart': 0,
  'lib/widgets/home/cw_card_menu.dart': 0,
  'lib/widgets/iptv/iptv_channel_row.dart': 1,
  'lib/widgets/iptv/iptv_command_rail.dart': 0,
  'lib/widgets/iptv/iptv_epg_panel.dart': 2,
  'lib/widgets/iptv/iptv_filters.dart': 4,
  'lib/widgets/iptv/iptv_list_name_dialog.dart': 0,
  'lib/widgets/iptv/iptv_list_picker_dialog.dart': 0,
  'lib/widgets/iptv/iptv_stage_panel.dart': 2,
  'lib/widgets/mobile_classic_nav.dart': 0,
  'lib/widgets/mobile_floating_nav.dart': 0,
  'lib/widgets/playlist_grid_card.dart': 0,
  'lib/widgets/see_all/discover_detail_rail.dart': 1,
  'lib/widgets/see_all/discover_trailer_stage.dart': 0,
  'lib/widgets/see_all/mdblist_list_card.dart': 0,
  'lib/widgets/see_all/mdblist_save_button.dart': 0,
  'lib/widgets/see_all/see_all_filter_bar.dart': 0,
  'lib/widgets/see_all/see_all_header.dart': 0,
  'lib/widgets/see_all/see_all_random_button.dart': 0,
  'lib/widgets/see_all/stremio_dropdown.dart': 2,
  'lib/widgets/trakt_calendar_day_sheet.dart': 0,
  'lib/widgets/tv_sidebar_nav.dart': 1,
  'lib/widgets/tvmaze_search_dialog.dart': 0,
  'lib/widgets/youtube/youtube_video_card.dart': 0,

  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_feedback.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_layout.dart':
      2,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_toolbar_layout.dart':
      1,
};

// Migration files with no remaining shape-token sites of their own. Keep their
// residue guarded without counting them as swept. The keyword field retains its
// old literal; all Sources shape-token calls now live in registered widgets.
const Map<String, int> kExtractedShapeResidue = {
  // Addon hub: every destination and the facade, including zero budgets.
  'lib/features/addon_hub/application/addon_hub_labels.dart': 0,
  'lib/features/addon_hub/models/addon_hub_kinds.dart': 0,
  'lib/features/addon_hub/presentation/addon_hub_addon_info.dart': 4,
  'lib/features/addon_hub/presentation/addon_hub_focus_card.dart': 1,
  'lib/features/addon_hub/presentation/addon_hub_installed_row.dart': 0,
  'lib/features/addon_hub/presentation/addon_hub_row_nav.dart': 0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_body.dart': 0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_composition.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_list.dart':
      1,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_filters.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_layout.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_loading.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_management.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_list.dart':
      1,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart':
      0,
  'lib/features/addon_hub/presentation/legacy_addon_hub/addon_hub_sections.dart':
      0,
  'lib/screens/addons/addon_hub_screen.dart': 0,
  // Spotlight board: facade and every destination, preserving three radii.
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_compact_hero.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_backdrop.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_foreground.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_identity.dart':
      1,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_root_layout.dart':
      1,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_shelves.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_wide_hero.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_focus.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_movement.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_selection.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_ambient.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_cadence.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_art.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_warmup.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_state.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_navigation_state.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_scroll_state.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_selection_state.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card_layout.dart':
      0,
  'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_logo_or_title.dart':
      0,
  'lib/features/spotlight_board/presentation/spotlight_hero_open_pill.dart': 1,
  'lib/features/spotlight_board/presentation/spotlight_shelf_title_link.dart':
      0,
  'lib/widgets/home/spotlight_board.dart': 0,
  'lib/features/spotlight_board/presentation/spotlight_board_metrics.dart': 0,
  'lib/features/spotlight_board/presentation/spotlight_board_types.dart': 0,

  // Episodes panel move-only slice: seven original bare radii.
  'lib/widgets/episodes_panel.dart': 0,
  'lib/features/episodes_panel/application/episodes_panel_policies.dart': 0,
  'lib/features/episodes_panel/models/episodes_panel_view.dart': 0,
  'lib/features/episodes_panel/presentation/episodes_panel_season_step.dart': 0,
  'lib/features/episodes_panel/presentation/episodes_panel_source_button.dart':
      1,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_chrome.dart':
      3,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_content.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_layout.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_row.dart':
      3,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_episode_options.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_mode.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_parts.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_root_layout.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_season_options.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_seasons.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart':
      0,
  'lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart':
      0,
  // Playback settings: every remaining destination and the facade, at zero.
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_audio_section.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_defaults_card.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_external_section.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_font_actions.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_ios_actions.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_linux_actions.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_mac_actions.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_player_appearance.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_player_mode_actions.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_player_section.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_player_setters.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_sections.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_settings_layout.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_settings_load.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_settings_test_access.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_setters.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_video_section.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_vr_section.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_vr_setters.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_windows_actions.dart':
      0,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart':
      0,
  'lib/screens/settings/external_player_settings_page.dart': 0,
  'lib/features/playback_settings/presentation/playback_setting_dropdown.dart':
      1,
  'lib/features/playback_settings/presentation/playback_dropdown_setting.dart':
      1,
  'lib/features/playback_settings/presentation/playback_checkbox_tile.dart': 2,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_windows_section.dart':
      2,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_section.dart':
      1,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_player_mode_option.dart':
      3,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_night_mode_section.dart':
      3,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_mac_section.dart':
      3,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_linux_section.dart':
      2,
  'lib/features/playback_settings/presentation/legacy_playback_settings/playback_ios_section.dart':
      2,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_root_layout.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_category_views.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_actions.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_views.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_phone_hub.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_views.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_view.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_forms.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_views.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_two_pane.dart':
      0,

  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_row.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_actions.dart':
      0,

  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_xtream_add.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_url_add.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_removal.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_refresh.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_edit.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sections.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_profile_actions.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_load_settings.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_actions.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_file_import.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_feedback.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_edit_dialog.dart':
      0,
  'lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_composition.dart':
      0,
  'lib/screens/settings/iptv_settings_page.dart': 0,
  'lib/features/iptv_settings/presentation/iptv_settings_focusable_tile.dart':
      0,
  'lib/features/iptv_settings/presentation/iptv_settings_dialog_button_style.dart':
      0,
  'lib/features/iptv_settings/presentation/iptv_settings_back_button.dart': 0,
  'lib/features/iptv_settings/presentation/iptv_settings_icon_button.dart': 0,
  'lib/features/iptv_settings/presentation/iptv_shared_source_delete_dialog.dart':
      0,
  'lib/features/iptv_settings/presentation/iptv_settings_playlist_tile.dart': 1,
  'lib/features/iptv_settings/presentation/iptv_settings_tv_button.dart': 1,
  'lib/features/iptv_settings/models/iptv_settings_phone_section.dart': 0,
  'lib/features/iptv_settings/models/iptv_settings_playlist_edit.dart': 0,
  'lib/features/iptv_settings/application/normalize_xtream_server_url.dart': 0,

  'lib/screens/playlist_content_view_screen.dart': 0,
  'lib/features/playlist_content/application/playlist_content_file_trees.dart':
      0,
  'lib/features/playlist_content/application/playlist_content_formatting.dart':
      0,
  'lib/features/playlist_content/application/playlist_content_sort_policy.dart':
      0,
  'lib/features/playlist_content/models/playlist_content_search_result.dart': 0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_launches.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_loading.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_composition.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_content_loading.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_debrid_launches.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_dormant.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_list.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_initialization.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_play_entries.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_playlist_order.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_posters.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_progress.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_root_layout.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_sections.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_metadata.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_view_modes.dart':
      0,
  'lib/features/playlist_content/presentation/legacy_playlist_content/playlist_content_watched.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_file_workflows_composition.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_catalog_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_node_playlist_links.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_browsing_composition.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_download_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_navigation.dart':
      2,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_navigation_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_layout.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_root_layout.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_add_input_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_file_actions.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_focus_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_library_lists.dart':
      2,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_file_playback.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_view_selector.dart':
      1,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_single_delete_actions.dart':
      2,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_download_row.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_node_row.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_multifile_playback.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_magnet_actions.dart':
      1,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_catalog_loading.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_download_action.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_view_modes.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_download_row_actions.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_catalog_actions_composition.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_composition_bindings.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_composition.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_delete_all_actions.dart':
      2,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_back_navigation.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_focus_actions.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_playlist_actions.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_actions.dart':
      1,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_row.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_view_state.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_file_downloads.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_torrent_actions.dart':
      0,
  'lib/features/debrid_downloads/presentation/legacy_debrid/debrid_modern_file_card.dart':
      9,
  'lib/features/debrid_downloads/application/debrid_input_policy.dart': 0,
  'lib/features/debrid_downloads/application/debrid_error_policy.dart': 0,
  'lib/features/debrid_downloads/application/debrid_folder_policy.dart': 0,
  'lib/features/debrid_downloads/models/debrid_downloads_view.dart': 0,
  'lib/features/debrid_downloads/models/folder_view_mode.dart': 0,
  'lib/features/debrid_downloads/models/rd_search_result.dart': 0,
  'lib/screens/debrid_downloads_screen.dart': 0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_view_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_playback.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_composition_bindings.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_back_navigation.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_file_downloads.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_workflows_composition.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_search_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_composition.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_enqueue.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_navigation.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_playlist_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_actions_composition.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_row.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_library_lists.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_magnet_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_view_selector.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_playback.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_initial_action.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_selection_card.dart':
      6,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_view_modes.dart':
      1,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_delete_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_download_action.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_row.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_navigation_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_zip_download.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_playlist_links.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_browsing_composition.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_root_layout.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_create_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_stream_request.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_add_input_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_row.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_actions.dart':
      1,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_link_playlist_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_loading.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_focus_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_downloads.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_actions.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_delete_action.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_focus_state.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_list_layouts.dart':
      1,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_web_playback.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart':
      0,
  'lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_zip_download.dart':
      0,
  'lib/features/torbox_downloads/presentation/torbox_downloads_view.dart': 0,
  'lib/features/torbox_downloads/presentation/torbox_more_option.dart': 0,
  'lib/features/torbox_downloads/presentation/maybe_blur.dart': 0,
  'lib/features/torbox_downloads/presentation/folder_view_mode.dart': 0,
  'lib/features/torbox_downloads/application/torbox_file_policy.dart': 0,
  'lib/features/torbox_downloads/application/torbox_folder_policy.dart': 0,
  'lib/features/torbox_downloads/application/torbox_magnet_policy.dart': 0,
  'lib/features/torbox_downloads/models/torbox_episode_candidate.dart': 0,
  'lib/features/torbox_downloads/models/torbox_search_result.dart': 0,
  'lib/features/torbox_downloads/models/torbox_file_entry.dart': 0,
  'lib/screens/torbox/torbox_downloads_screen.dart': 0,
  'lib/features/iptv/application/iptv_layout_policy.dart': 0,
  'lib/features/iptv/application/iptv_load_status_policy.dart': 0,
  'lib/features/iptv/application/iptv_rail_resolution.dart': 0,
  'lib/features/iptv/application/iptv_status_chip_types.dart': 0,
  'lib/features/iptv/presentation/iptv_rail_hints.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_browsing_composition.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_composition.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_facades.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_loading.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_maintenance.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_network.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_presentation.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_refresh.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_catchup.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_categories.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_category_order.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_classic_layout.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_composition_owners.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_content_layout.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_desktop_recording.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_favorites.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_filters.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_guide_context.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_landing_policy.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_load_status.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_navigation.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_playback.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_playback_actions.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_playback_composition.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_playback_refresh.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_player_browse.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_player_payload.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_player_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_preview_and_selection_composition.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_preview_handoff.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_quiet_filters.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_record_now.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_recording_support.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_recordings_composition.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_root_layout.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_schedule_actions.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_settings_loading.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_source_counts.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_actions.dart': 2,
  'lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_composition.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_content.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_focus.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_hero.dart': 2,
  'lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_layout.dart': 1,
  'lib/features/iptv/presentation/legacy_iptv/iptv_stage_floor.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_standard_layouts_composition.dart':
      0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_startup_launch.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_startup_resolution.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_status_chip.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_status_state.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_tablet_identity.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_tablet_selection.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_two_pane_layout.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_view_sections.dart': 0,
  'lib/features/iptv/presentation/legacy_iptv/iptv_virtual_results.dart': 0,
  'lib/features/iptv/presentation/spotlight_category_picker_dialog.dart': 1,
  'lib/features/iptv/presentation/tuning_waves_painter.dart': 0,
  'lib/widgets/iptv/iptv_results_view.dart': 0,
  'lib/screens/settings_screen.dart': 0,
  'lib/features/settings/presentation/legacy_settings/settings_download_location.dart':
      1,
  'lib/features/settings/presentation/settings_search_bar.dart': 3,
  // Every other Settings hub file, at its measured count (0 unless noted).
  'lib/features/settings/application/settings_backup_formatting.dart': 0,
  'lib/features/settings/application/settings_pending_credentials.dart': 0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_builder.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_01.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_02.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_03.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_04.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_05.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_06.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_07.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_08.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_09.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_10.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_index_slice_11.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_builder.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_01.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_02.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_03.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_04.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_05.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_06.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_07.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_08.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_09.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_10.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_leaf_slice_11.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_account_captions.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_backup.dart': 0,
  'lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_connections.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_diagnostics.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_index_composition.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_layout_composition.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_maintenance.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_restore.dart': 0,
  'lib/features/settings/presentation/legacy_settings/settings_search_navigation.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_sections.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_snacks.dart': 0,
  'lib/features/settings/presentation/legacy_settings/settings_summaries.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_summary_loader.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart':
      0,
  'lib/features/settings/presentation/legacy_settings/settings_updates.dart': 0,
  'lib/features/settings/presentation/settings_categories.dart': 0,
  'lib/features/settings/presentation/settings_classic_layout.dart': 0,
  'lib/features/settings/presentation/settings_connection_grid.dart': 0,
  'lib/features/settings/presentation/settings_layout.dart': 0,
  'lib/features/settings/presentation/settings_spotlight_category.dart': 0,
  'lib/features/settings/presentation/settings_spotlight_layout.dart': 0,
  'lib/screens/search_screen/home_saved_composition.dart': 0,
  'lib/screens/search_screen/discover_panel_composition.dart': 0,
  'lib/screens/search_screen/search_input_composition.dart': 0,
  'lib/features/home/presentation/home_rows_navigation.dart': 0,
  'lib/features/home/presentation/home_board_loading.dart': 0,
  'lib/features/home/presentation/home_classic_section.dart': 0,
  'lib/features/home/presentation/home_board_rendering.dart': 0,

  'lib/features/home/presentation/home_stage_cells.dart': 0,
  'lib/features/home/presentation/home_stage_boards.dart': 0,
  'lib/features/home/presentation/home_atrium_section.dart': 0,
  'lib/features/home/presentation/home_tonight_section.dart': 0,
  'lib/features/home/presentation/home_spotlight_rows.dart': 0,
  'lib/features/home/presentation/home_spotlight_boards.dart': 0,
  'lib/screens/search_screen/search_spotlight_results.dart': 0,
  'lib/features/home/presentation/home_stage_favorites.dart': 0,
  'lib/features/search/presentation/search_spotlight_shell.dart': 0,
  'lib/features/home/presentation/home_continuation_rows.dart': 0,
  'lib/features/home/presentation/home_continuation_announcements.dart': 0,
  'lib/features/home/presentation/home_continuation_menu.dart': 0,
  'lib/features/home/presentation/home_playlist_actions.dart': 0,
  'lib/features/home/presentation/home_saved_content_rows.dart': 0,
  'lib/features/home/presentation/home_saved_iptv_actions.dart': 0,
  'lib/features/home/presentation/home_watchlist_actions.dart': 0,
  'lib/features/home/presentation/home_item_actions.dart': 0,
  'lib/features/home/presentation/home_playback_navigation.dart': 0,
  'lib/features/search/presentation/search_input_section.dart': 0,
  'lib/features/search/presentation/catalog_search_section.dart': 0,
  'lib/features/search/presentation/lists_search_rows.dart': 0,

  'lib/screens/search_screen.dart': 0,
  'lib/features/search/presentation/keyword_search_frame.dart': 0,

  'lib/features/search/presentation/keyword_search_dialogs.dart': 1,
  'lib/features/search/presentation/keyword_search_actions.dart': 0,
  'lib/features/discover/presentation/discover_section.dart': 0,
  'lib/features/home/presentation/home_hero_spotlight.dart': 0,
  // Moved out of the hero spotlight and the Stremio TV picker with their radii.
  'lib/features/home/presentation/home_hero_identity.dart': 1,
  'lib/features/home/presentation/home_catalog_card_layers.dart': 0,
  'lib/features/home/presentation/home_poster_flight.dart': 0,
  'lib/features/stremio_tv/presentation/stremio_tv_catalog_picker_views.dart':
      2,
  'lib/features/home/presentation/home_hero_transitions.dart': 0,
  'lib/features/home/presentation/home_hero_tint_surface.dart': 0,
  'lib/features/home/presentation/home_hero_title_art.dart': 0,
  'lib/features/home/presentation/home_hero_trailer_layer.dart': 0,
  'lib/ui/core/spotlight_search_button.dart': 0,
  'lib/features/home/presentation/home_classic_layout.dart': 0,
  'lib/features/home/presentation/home_trailer_transitions.dart': 0,
  'lib/features/home/presentation/home_classic_rows.dart': 0,
  'lib/features/home/presentation/home_row_entrance.dart': 0,
  'lib/features/home/presentation/home_board_cell.dart': 0,
  'lib/features/home/presentation/home_card_metadata_view.dart': 0,
  'lib/features/home/presentation/home_favorite_cell.dart': 0,
  'lib/features/discover/presentation/discover_stage_backdrop.dart': 0,
  'lib/features/discover/presentation/discover_stage_veils.dart': 0,
  'lib/features/discover/presentation/discover_grid_dim.dart': 0,
  'lib/features/discover/presentation/discover_grid_layout.dart': 0,
  'lib/features/discover/presentation/discover_stage_layout.dart': 0,
  'lib/features/discover/presentation/discover_content.dart': 0,
  'lib/features/sources/presentation/source_keyword_field.dart': 1,

  'lib/screens/pikpak/pikpak_files_screen.dart': 0,
  'lib/features/pikpak_files/application/pikpak_link_policy.dart': 0,
  'lib/features/pikpak_files/application/pikpak_playlist_titles.dart': 0,
  'lib/features/pikpak_files/application/pikpak_sort_policy.dart': 0,
  'lib/features/pikpak_files/models/folder_view_mode.dart': 0,
  'lib/features/pikpak_files/models/pikpak_playlist_item.dart': 0,
  'lib/features/pikpak_files/models/pikpak_search_result.dart': 0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_actions_composition.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_back_navigation.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_composition.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_data_composition.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_delete_actions.dart':
      1,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_download.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_list.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_playback.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_actions.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_download.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_navigation.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_playback.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_layout_composition.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_actions.dart':
      5,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_state.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_composition.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_playlist_actions.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_root_layout.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_actions.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_sections.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_state.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_source_binding.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_status_layout.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_modes.dart':
      0,
  'lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart':
      0,
  // Merged-detail complete slice: 26 original bare radii, zero token calls.
  'lib/features/merged_detail/application/merged_detail_simkl_labels.dart': 0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_ambient_still.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_cast_tile.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_action_layout.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_body_layout.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_episodes_layout.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_hero_layout.dart':
      2,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_menus.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_actions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_loading.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_pane_layout.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_parts.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_playback_actions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_rail_layout.dart':
      2,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_simkl_descriptions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_detail_watchlist_actions.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_rec_card.dart':
      2,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_simkl_sheet.dart':
      0,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_simkl_status_row.dart':
      1,
  'lib/features/merged_detail/presentation/legacy_merged_detail/merged_trakt_sheet.dart':
      0,
  'lib/features/merged_detail/presentation/merged_detail_action_descriptions.dart':
      0,
  'lib/features/merged_detail/presentation/merged_detail_palette.dart': 0,
  'lib/features/merged_detail/presentation/merged_focus_halo.dart': 0,
  'lib/features/merged_detail/presentation/merged_ghost_button.dart': 4,
  'lib/features/merged_detail/presentation/merged_primary_button.dart': 4,
  'lib/features/merged_detail/presentation/merged_quick_actions_menu.dart': 0,
  'lib/features/merged_detail/presentation/merged_rail_edge_trap.dart': 0,
  'lib/features/merged_detail/presentation/merged_round_icon_button.dart': 0,
  'lib/features/merged_detail/presentation/merged_scroll_anchor.dart': 0,
  'lib/features/merged_detail/presentation/merged_sheet_action_row.dart': 0,
  'lib/features/merged_detail/presentation/merged_sheet_group_label.dart': 0,
  'lib/features/merged_detail/presentation/merged_sheet_rating_strip.dart': 3,
  'lib/features/merged_detail/presentation/merged_sheet_switch_row.dart': 2,
  'lib/features/merged_detail/presentation/merged_source_pill.dart': 4,
  'lib/features/merged_detail/presentation/merged_stagger_reveal.dart': 0,
  'lib/features/merged_detail/presentation/merged_tracker_pill.dart': 1,
  'lib/features/merged_detail/presentation/merged_tracker_sheet_header.dart': 0,
  'lib/features/merged_detail/presentation/merged_trailer_playing_chip.dart': 1,
  'lib/screens/merged_series_detail_screen.dart': 0,
  // Detail showcase: exact slice total 18; every created file and facade.
  'lib/features/detail_showcase/presentation/showcase_cast.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_did_you_know.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_episodes.dart': 6,
  'lib/features/detail_showcase/presentation/showcase_grounds.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_guide.dart': 5,
  'lib/features/detail_showcase/presentation/showcase_identity.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_identity_actions.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_identity_readouts.dart':
      1,
  'lib/features/detail_showcase/presentation/showcase_metrics.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_notes.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_recs.dart': 2,
  'lib/features/detail_showcase/presentation/showcase_seasons.dart': 2,
  'lib/features/detail_showcase/presentation/showcase_sources.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_style.dart': 0,
  'lib/features/detail_showcase/presentation/showcase_universe.dart': 2,
  'lib/widgets/detail/showcase_parts.dart': 0,
  // End detail showcase.
  'lib/screens/catalog_item_detail_screen.dart': 0,
  'lib/features/catalog_detail/presentation/catalog_action_row.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_backdrop.dart': 0,
  'lib/features/catalog_detail/presentation/catalog_cert_badge.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_description.dart': 0,
  'lib/features/catalog_detail/presentation/catalog_genre_chip.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_glass_card.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_glass_icon_button.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_metacritic_badge.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_quick_actions.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_rec_card.dart': 1,
  'lib/features/catalog_detail/presentation/catalog_reveal.dart': 0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_cast_avatar.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_action_layout.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_bound_sources.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_content_columns.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_credits_sections.dart':
      8,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_hero_sections.dart':
      7,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_parts.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_rail_sections.dart':
      5,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_watchlist.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_mdblist_quick_actions.dart':
      0,
  'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_simkl_quick_actions.dart':
      1,
};

/// Both spellings of a literal circular radius. `BorderRadius.all(
/// Radius.circular(8))` is the same site wearing a different constructor, and
/// counting only the short form would let a conversion be undone by rewriting
/// it.
final _radius = RegExp(
  r'BorderRadius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*\)'
  r'|BorderRadius\.all\(\s*Radius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*\)\s*\)',
);

void main() {
  test('no swept file grows a new bare radius', () {
    final grew = <String>[];
    for (final entry in {...kShapeResidue, ...kExtractedShapeResidue}.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) {
        fail(
          '${entry.key} is in the shape manifest but no longer exists — '
          'remove its entry if the file was deleted',
        );
      }
      var source = file.readAsStringSync();
      // Playback's extraction changes indentation; tall formatting can add a
      // trailing comma to the same literal call. Preserve its original count.
      if (entry.key.startsWith('lib/features/playback_settings/') ||
          entry.key.startsWith('lib/features/addon_hub/') ||
          entry.key ==
              'lib/screens/settings/external_player_settings_page.dart') {
        source = source.replaceAllMapped(
          RegExp(r'(BorderRadius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*),'),
          (match) => match.group(1)!,
        );
      }
      final found = _radius.allMatches(source).length;
      if (found > entry.value) {
        grew.add('${entry.key}: ${entry.value} → $found');
      }
    }
    expect(
      grew,
      isEmpty,
      reason:
          'these files are on the shape tokens; a new bare '
          'BorderRadius.circular in one is a site that will not follow the '
          'theme. Use app.shape.br()/brImg()/brPill, or lower the manifest '
          'entry if you genuinely removed radii: $grew',
    );
  });

  test('the manifest describes files that are actually swept', () {
    // A file listed with residue but no token calls at all would mean the
    // sweep was reverted wholesale and the ratchet is guarding nothing.
    final unswept = <String>[];
    for (final path in kShapeResidue.keys) {
      final src = File(path).readAsStringSync();
      if (!src.contains('app.shape.')) unswept.add(path);
    }
    expect(
      unswept,
      isEmpty,
      reason: 'listed as swept but contains no shape-token call: $unswept',
    );
  });

  test('the sweep is still substantial', () {
    // A blunt floor. If someone reverts the sweep file by file, the per-file
    // ratchet above stays green (residue never grows) while the conversion
    // quietly disappears — this is the backstop for that.
    var calls = 0;
    for (final path in kShapeResidue.keys) {
      calls += RegExp(
        r'app\.shape\.br',
      ).allMatches(File(path).readAsStringSync()).length;
    }
    // 488, not 490: refactor 8b6e1627 merged two duplicated Sources pills into
    // the shared control, removing two token call sites without reverting any.
    expect(
      calls,
      greaterThanOrEqualTo(488),
      reason: 'the shape sweep converted 500 sites; only $calls remain',
    );
  });
}
