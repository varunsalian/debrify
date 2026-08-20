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
  'lib/screens/addons/addon_hub_screen.dart': 7,
  'lib/screens/alldebrid/alldebrid_files_screen.dart': 1,
  'lib/screens/cloud_screen.dart': 0,
  'lib/screens/debrid_downloads_screen.dart': 23,
  'lib/screens/debrify_tv/dialogs/community_channels_dialog.dart': 12,
  'lib/screens/debrify_tv/dialogs/external_player_notice_dialog.dart': 0,
  'lib/screens/debrify_tv/dialogs/import_channels_dialog.dart': 0,
  'lib/screens/debrify_tv/widgets/tv_focusable_button.dart': 0,
  'lib/screens/debrify_tv/widgets/tv_focusable_card.dart': 0,
  'lib/screens/downloads_screen.dart': 2,
  'lib/screens/magic_tv_screen.dart': 7,
  'lib/screens/pikpak/pikpak_files_screen.dart': 9,
  'lib/screens/playlist_content_view_screen.dart': 0,
  'lib/screens/playlist_screen.dart': 0,
  'lib/screens/premiumize/premiumize_files_screen.dart': 6,
  'lib/screens/search/search_card_widgets.dart': 0,
  'lib/screens/search/search_hero_widgets.dart': 2,
  'lib/screens/search/search_sources.dart': 3,
  'lib/screens/search/search_stage_widgets.dart': 0,
  'lib/screens/search_screen.dart': 1,
  'lib/screens/see_all/catalog_see_all_screen.dart': 0,
  'lib/screens/settings/app_theme_page.dart': 1,
  'lib/screens/settings/debrify_tv_settings_page.dart': 0,
  'lib/screens/settings/detail_theme_page.dart': 1,
  'lib/screens/settings/external_player_settings_page.dart': 18,
  'lib/screens/settings/filter_settings_page.dart': 2,
  'lib/screens/settings/iptv_hidden_categories_page.dart': 1,
  'lib/screens/settings/iptv_settings_page.dart': 2,
  'lib/screens/settings/iptv_settings_two_pane.dart': 7,
  'lib/screens/settings/provider_settings_page.dart': 0,
  'lib/screens/settings/quick_play_settings_page.dart': 0,
  'lib/screens/settings/settings_tv_layout.dart': 0,
  'lib/screens/settings/simkl_settings_page.dart': 1,
  'lib/screens/settings/trakt_settings_page.dart': 1,
  'lib/screens/settings/widgets/dynamic_settings_builder.dart': 7,
  'lib/screens/settings/widgets/settings_widgets.dart': 10,
  'lib/screens/settings_screen.dart': 4,
  'lib/screens/stremio_tv/stremio_tv_filter_page.dart': 0,
  'lib/screens/stremio_tv/stremio_tv_screen.dart': 0,
  'lib/screens/stremio_tv/widgets/stremio_tv_empty_state.dart': 0,
  'lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart': 4,
  'lib/screens/stremio_tv/widgets/stremio_tv_repo_browser_dialog.dart': 3,
  'lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart': 0,
  'lib/screens/torbox/torbox_downloads_screen.dart': 14,
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
  'lib/widgets/iptv/iptv_results_view.dart': 1,
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
  'lib/widgets/see_all/stremio_dropdown.dart': 0,
  'lib/widgets/trakt_calendar_day_sheet.dart': 0,
  'lib/widgets/tv_sidebar_nav.dart': 0,
  'lib/widgets/tvmaze_search_dialog.dart': 0,
  'lib/widgets/youtube/youtube_video_card.dart': 0,
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
    for (final entry in kShapeResidue.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) {
        fail('\${entry.key} is in the shape manifest but no longer exists — '
            'remove its entry if the file was deleted');
      }
      final found = _radius.allMatches(file.readAsStringSync()).length;
      if (found > entry.value) {
        grew.add('\${entry.key}: \${entry.value} → \$found');
      }
    }
    expect(grew, isEmpty,
        reason: 'these files are on the shape tokens; a new bare '
            'BorderRadius.circular in one is a site that will not follow the '
            'theme. Use app.shape.br()/brImg()/brPill, or lower the manifest '
            'entry if you genuinely removed radii: \$grew');
  });

  test('the manifest describes files that are actually swept', () {
    // A file listed with residue but no token calls at all would mean the
    // sweep was reverted wholesale and the ratchet is guarding nothing.
    final unswept = <String>[];
    for (final path in kShapeResidue.keys) {
      final src = File(path).readAsStringSync();
      if (!src.contains('app.shape.')) unswept.add(path);
    }
    expect(unswept, isEmpty,
        reason: 'listed as swept but contains no shape-token call: \$unswept');
  });

  test('the sweep is still substantial', () {
    // A blunt floor. If someone reverts the sweep file by file, the per-file
    // ratchet above stays green (residue never grows) while the conversion
    // quietly disappears — this is the backstop for that.
    var calls = 0;
    for (final path in kShapeResidue.keys) {
      calls += RegExp(r'app\.shape\.br')
          .allMatches(File(path).readAsStringSync())
          .length;
    }
    expect(calls, greaterThanOrEqualTo(490),
        reason: 'the shape sweep converted 500 sites; only \$calls remain');
  });
}
