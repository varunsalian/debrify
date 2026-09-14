/// Navigation styles, sidebar order/labels, and phone navigation sync using
/// their existing separate keys, as do the three player control/dock styles,
/// Home addon-name visibility, ambient trailer volumes, and portable subtitle
/// appearance (including bundled-font selection).
/// Other appearance remains local to each profile on each installation. These keys
/// are still portable through explicit backups and profile-default copies;
/// only automatic WebDAV sync excludes them (including bootstrap and replay).
abstract final class ProfileAppearancePreferences {
  static const Set<String> keys = <String>{
    // This checkpoint belongs to the local appearance values it initializes.
    'defaults_generation',
    'app_theme',
    'detail_theme',
    'theme_overrides',
    'text_brightness',
    'launch_animation',
    'launch_ident_palette',
    'tv_ui_scale_percent',
    'tv_low_res_render',
    'tv_hero_artwork_quality',
    'tv_home_style',
    'tv_collection_list_style',
    'detail_page_style',
    'parents_guide_style',
    'debrify_tv_style',
    'iptv_style',
    'iptv_player_guide_style',
    'play_loader_style',
    'player_dock_palette',
    'player_dock_size',
    'discover_layout',
    'discover_show_type_tags',
    'discover_show_ratings',
    'discover_show_titles',
    'home_card_orientation',
    'home_collections_gif_touch',
    'home_collections_gif_remote',
    'home_collections_folder_layout',
    'home_hide_card_titles_and_ratings',
    'series_browser_dense_view',
    'playlist_view_modes_v1',
    'detail_trailer_autoplay_enabled',
    'home_hero_trailer_enabled',
    'home_hero_trailer_audio_enabled',
    'detail_trailer_audio_enabled',
    'tv_trailer_underlay_enabled',
    'iptv_channel_preview_enabled',
    'ui_sounds',
    'ui_haptics',
    'subtitle_extreme_bottom_default_adopted_v1',
  };
}
