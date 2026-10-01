import 'package:debrify/services/profiles/profile_preferences.dart';

final class PlayerAppearanceStorage {
  const PlayerAppearanceStorage._();

  // ── Player dock (touch/desktop transport controls) ──────────────────────
  //
  // Three independent prefs so any style works in any palette at any size;
  // bundling them into one "look" would only remove combinations. Palette and
  // size are inert under `classic`, whose values are still preserved so
  // switching to a styled dock restores the user's choices.
  //
  // Read once at player launch. Televisions never consult these — they build
  // `TvControls`, not `Controls`.
  static const String _playerDockStyleKey = 'player_dock_style';
  static const Set<String> _playerDockStyles = {
    'classic',
    'auto',
    'compact',
    'tiers',
    'cinema',
    // The value shipped before the arrangements became selectable. Still
    // accepted on read so existing installs keep the dock they chose; it
    // means the same thing 'auto' does.
    'two_tier',
  };

  static Future<String> getPlayerDockStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockStyleKey);
    return _playerDockStyles.contains(raw) ? raw! : 'classic';
  }

  static Future<void> setPlayerDockStyle(String style) async {
    final normalized = _playerDockStyles.contains(style) ? style : 'classic';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockStyleKey, normalized);
  }

  static const String _playerDockPaletteKey = 'player_dock_palette';
  static const Set<String> _playerDockPalettes = {
    'ultraviolet',
    'crimson',
    'aurum',
    'ice',
  };

  static Future<String> getPlayerDockPalette() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockPaletteKey);
    return _playerDockPalettes.contains(raw) ? raw! : 'ultraviolet';
  }

  static Future<void> setPlayerDockPalette(String palette) async {
    final normalized = _playerDockPalettes.contains(palette) ? palette : 'ultraviolet';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockPaletteKey, normalized);
  }

  static const String _playerDockSizeKey = 'player_dock_size';
  static const Set<String> _playerDockSizes = {
    'auto',
    'small',
    'medium',
    'large',
  };

  static Future<String> getPlayerDockSize() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockSizeKey);
    return _playerDockSizes.contains(raw) ? raw! : 'auto';
  }

  static Future<void> setPlayerDockSize(String size) async {
    final normalized = _playerDockSizes.contains(size) ? size : 'auto';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockSizeKey, normalized);
  }

  static const String _playLoaderStyleKey = 'play_loader_style';
  static const Set<String> _playLoaderStyles = {'marquee', 'classic'};

  /// The look of the play → resolve loader: 'marquee' (the default — backdrop,
  /// logo art and a segmented stage rail) or 'classic' (the poster-and-
  /// checklist card this overlay shipped with). Unknown or unset coerces to
  /// 'marquee' on BOTH read and write, so a value written by a newer build can
  /// never pin a look this one cannot render.
  ///
  /// The play path reads it synchronously through
  /// [PlayLoaderStyleController.cached]; this getter is the warm source.
  static Future<String> getPlayLoaderStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playLoaderStyleKey);
    return _playLoaderStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setPlayLoaderStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _playLoaderStyleKey,
      _playLoaderStyles.contains(style) ? style : 'marquee',
    );
  }

  static const String _tvPlayerControlsStyleKey = 'tv_player_controls_style';
  static const Set<String> _tvPlayerControlsStyles = {
    'classic',
    'ott',
    'frost',
    'marquee',
    'broadcast',
    'pulse',
    'ticket',
  };

  /// Control skin for the NATIVE Android TV player: 'ott' (the Apple TV dock
  /// ported to Kotlin — the default), 'marquee' (editorial serif),
  /// 'classic' (the legacy Cinema Mode controls), or one of the other
  /// premium dock skins ('frost', 'broadcast', 'pulse', 'ticket'). Android TV only; tvOS runs the
  /// Flutter player and has nothing to choose. Read once per player launch — the native side via
  /// `ProfilePreferenceProjection.getString("tv_player_controls_style")`
  /// (falling back to `flutter.tv_player_controls_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'ott' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getTvPlayerControlsStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_tvPlayerControlsStyleKey);
    return _tvPlayerControlsStyles.contains(raw) ? raw! : 'ott';
  }

  static Future<void> setTvPlayerControlsStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _tvPlayerControlsStyleKey,
      _tvPlayerControlsStyles.contains(style) ? style : 'ott',
    );
  }
}
