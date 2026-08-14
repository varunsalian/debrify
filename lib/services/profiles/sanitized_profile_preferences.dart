/// The complete preference schema permitted in an unencrypted, shareable
/// profile package.
///
/// This is deliberately an allowlist with value validation. Adding a normal
/// profile preference does not make it portable: a new entry must be reviewed
/// here first, and both export and import consume this same policy.
abstract final class SanitizedProfilePreferences {
  static bool allowsEntry(Object? key, Object? value) {
    if (key is! String) return false;
    switch (key) {
      case 'ui_sounds':
      case 'ui_haptics':
      case 'tv_keyboard_enabled':
      case 'player_start_portrait':
      case 'player_system_audio_effects':
      case 'subtitle_auto_sync_enabled':
      case 'recording_engine_enabled':
      case 'home_hero_trailer_enabled':
      case 'detail_trailer_autoplay_enabled':
      case 'home_hero_trailer_audio_enabled':
      case 'detail_trailer_audio_enabled':
      case 'tv_trailer_underlay_enabled':
      case 'subtitle_bold':
        return value is bool;
      case 'tv_ui_scale_percent':
        return value is int && const <int>{80, 90, 100}.contains(value);
      case 'player_default_aspect_index':
        return _boundedInt(value, 0, 9);
      case 'player_default_aspect_index_tv':
        return _boundedInt(value, 0, 2);
      case 'player_night_mode_index':
        return _boundedInt(value, 0, 7);
      case 'home_hero_trailer_volume':
      case 'detail_trailer_volume':
        return _boundedInt(value, 10, 100);
      case 'subtitle_size_index':
        return _boundedInt(value, 0, 6);
      case 'subtitle_style_index':
        return _boundedInt(value, 0, 4);
      case 'subtitle_color_index':
        return _boundedInt(value, 0, 7);
      case 'subtitle_bg_index':
        return _boundedInt(value, 0, 4);
      case 'subtitle_outline_color_index':
        return _boundedInt(value, 0, 9);
      case 'subtitle_elevation_index':
        return _boundedInt(value, 0, 4);
      case 'app_theme':
        return value is String && _appThemes.contains(value);
      case 'detail_theme':
        return value is String && _detailThemes.contains(value);
      case 'text_brightness':
        return value is String &&
            const <String>{'bright', 'soft', 'dim'}.contains(value);
      case 'tv_home_style':
        return value is String && _tvHomeStyles.contains(value);
      case 'tv_sidebar_style':
        return value is String && _tvSidebarStyles.contains(value);
      case 'desktop_sidebar_style':
        return value is String &&
            const <String>{'rail', 'pill'}.contains(value);
      case 'phone_nav_style':
        return value is String &&
            const <String>{'classic', 'floating'}.contains(value);
      case 'discover_layout':
        return value is String &&
            const <String>{'stage', 'grid'}.contains(value);
      case 'debrify_tv_style':
        return value is String &&
            const <String>{'grid', 'spotlight'}.contains(value);
      case 'detail_page_style':
        return value is String && _detailPageStyles.contains(value);
      case 'parents_guide_style':
        return value is String &&
            const <String>{'classic', 'compass'}.contains(value);
      case 'iptv_style':
        return value is String &&
            const <String>{'command', 'edition', 'console'}.contains(value);
      case 'player_dock_style':
        return value is String && _playerDockStyles.contains(value);
      case 'player_dock_palette':
        return value is String && _playerDockPalettes.contains(value);
      case 'player_dock_size':
        return value is String &&
            const <String>{'auto', 'small', 'medium', 'large'}.contains(value);
      case 'launch_animation':
        return value is String && _launchAnimations.contains(value);
      case 'launch_ident_palette':
        return value is String &&
            const <String>{'ident', 'theme'}.contains(value);
      case 'iptv_player_guide_style':
        return value is String && _iptvPlayerGuideStyles.contains(value);
      case 'tv_hero_artwork_quality':
        return value is String &&
            const <String>{
              'automatic',
              'performance',
              'full_hd',
            }.contains(value);
    }
    return false;
  }

  static bool _boundedInt(Object? value, int minimum, int maximum) =>
      value is int && value >= minimum && value <= maximum;

  static const Set<String> _detailThemes = <String>{
    'signal',
    'noir',
    'broadsheet',
    'phosphor',
    'aurora',
    'concrete',
    'velvet',
    'blueprint',
    'broadcast',
    'sepia',
    'obsidian',
    'halo',
    'prestige',
    'deep_field',
    'graphite',
    'vault',
    'spectrum',
    'verdant',
    'frost',
    'cinemascope',
    'glass',
    'field',
    'hearth',
    'console',
    'reel',
    'spotlight',
  };

  static const Set<String> _appThemes = <String>{'legacy', ..._detailThemes};

  static const Set<String> _tvHomeStyles = <String>{
    'canvas',
    'classic',
    'atrium',
    'mosaic',
    'promenade',
    'deck',
    'tonight',
    'spotlight',
  };

  static const Set<String> _tvSidebarStyles = <String>{
    'classic',
    'ghost',
    'island',
    'marquee',
    'badge',
    'pill',
  };

  static const Set<String> _detailPageStyles = <String>{
    'classic',
    'marquee',
    'dossier',
    'broadsheet',
    'stage',
    'filmstrip',
    'console',
    'vista',
    'monolith',
    'mosaic',
    'halo',
    'premiere',
    'showcase',
  };

  static const Set<String> _playerDockStyles = <String>{
    'classic',
    'auto',
    'compact',
    'tiers',
    'cinema',
    'two_tier',
  };

  static const Set<String> _playerDockPalettes = <String>{
    'ultraviolet',
    'crimson',
    'aurum',
    'ice',
  };

  static const Set<String> _launchAnimations = <String>{
    'drop',
    'marquee',
    'prism',
    'horizon',
    'neon',
    'chrome',
    'monogram',
    'aperture',
    'blueprint',
    'ripple',
    'ember',
    'swiss',
    'origami',
    'anamorphic',
    'constellation',
    'silk',
    'rackfocus',
  };

  static const Set<String> _iptvPlayerGuideStyles = <String>{
    'classic',
    'glass',
    'edition',
    'console',
    'spotlight',
  };
}
