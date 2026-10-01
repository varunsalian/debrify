import 'package:debrify/models/sidebar_configuration.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class SidebarStorage {
  const SidebarStorage._();

  static const String _phoneNavStyleKey = 'phone_nav_style';
  static const String _phoneNavBarIndicesKey = 'phone_nav_bar_indices';

  /// Phone navigation chrome: 'classic' (bottom bar, the default) or
  /// 'floating' (the glass button menu). TV and wide-desktop never read it.
  static Future<String> getPhoneNavStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_phoneNavStyleKey);
    return raw == 'floating' ? 'floating' : 'classic';
  }

  static Future<void> setPhoneNavStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _phoneNavStyleKey,
      style == 'floating' ? 'floating' : 'classic',
    );
  }

  // Shared within lib/services/storage/.
  static const String tvSidebarStyleKey = 'tv_sidebar_style';
  static const Set<String> _tvSidebarStyles = {
    'classic',
    'ghost',
    'island',
    'marquee',
    'badge',
    'pill',
  };

  /// TV sidebar chrome: 'ghost' (chromeless, the default), 'classic' (the
  /// original liquid glass), 'island', 'marquee', 'badge' or 'pill'.
  ///
  /// The LEFT-only focus model is shared by every style. Chrome-only for the
  /// first five; **'pill' is the one that also changes LAYOUT** — it shows no
  /// rail at rest, so content runs full-bleed and gains 64px. Read the inset
  /// through `TvSidebarNav.contentInsetFor` rather than assuming the constant.
  /// Phone/desktop never read any of it.
  /// Synchronous mirror of `tvSidebarStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String tvSidebarStyleCached = 'ghost';

  static Future<String> getTvSidebarStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(tvSidebarStyleKey);
    return tvSidebarStyleCached = (raw != null && _tvSidebarStyles.contains(raw)) ? raw : 'ghost';
  }

  static Future<void> setTvSidebarStyle(String style) async {
    final normalized = _tvSidebarStyles.contains(style) ? style : 'ghost';
    tvSidebarStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(tvSidebarStyleKey, normalized);
  }

  // Shared within lib/services/storage/.
  static const String desktopSidebarStyleKey = 'desktop_sidebar_style';
  static const Set<String> _desktopSidebarStyles = {'rail', 'pill'};

  /// Desktop/tablet sidebar chrome, read only at the wide (≥600) non-TV
  /// layout: 'rail' (the fixed icon rail, the default) or 'pill' (no rail —
  /// content runs full-bleed and a floating capsule shows the current tab;
  /// clicking it opens the menu as an overlay). The TV rail has its own key
  /// above and never reads this; phones never reach the wide layout.
  /// Warmed in `main()` before the first frame — the shell's field
  /// initializer reads it so a migrated/pill user never flashes the rail.
  static String desktopSidebarStyleCached = 'rail';

  static Future<String> getDesktopSidebarStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(desktopSidebarStyleKey);
    return desktopSidebarStyleCached = (raw != null && _desktopSidebarStyles.contains(raw)) ? raw : 'rail';
  }

  static Future<void> setDesktopSidebarStyle(String style) async {
    desktopSidebarStyleCached = _desktopSidebarStyles.contains(style) ? style : 'rail';
    final normalized = _desktopSidebarStyles.contains(style) ? style : 'rail';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(desktopSidebarStyleKey, normalized);
  }

  static const String _sidebarConfigurationKey = 'sidebar_configuration_v1';

  /// Profile-scoped order and label overrides shared by the Android TV and
  /// desktop/tablet sidebars. The cached mirror is warmed before runApp so a
  /// customized profile never flashes the default order on frame one.
  static SidebarConfiguration sidebarConfigurationCached = SidebarConfiguration.defaults();

  static Future<SidebarConfiguration> getSidebarConfiguration() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_sidebarConfigurationKey);
    return sidebarConfigurationCached =
        (raw == null ? null : SidebarConfiguration.tryDecode(raw)) ?? SidebarConfiguration.defaults();
  }

  static Future<bool> setSidebarConfiguration(
    SidebarConfiguration configuration,
  ) async {
    final normalized = SidebarConfiguration(
      order: configuration.order,
      labels: configuration.labels,
    );
    final prefs = await ProfilePreferences.instance();
    final saved = await prefs.setString(
      _sidebarConfigurationKey,
      normalized.encode(),
    );
    if (saved) sidebarConfigurationCached = normalized;
    return saved;
  }

  static Future<bool> resetSidebarConfiguration() async {
    final prefs = await ProfilePreferences.instance();
    final removed = await prefs.remove(_sidebarConfigurationKey);
    if (removed || !prefs.containsKey(_sidebarConfigurationKey)) {
      sidebarConfigurationCached = SidebarConfiguration.defaults();
      return true;
    }
    return false;
  }

  /// The classic bar's user-chosen middle slots, as REAL tab indices (Home
  /// and More are fixed anchors and never stored). Null = never customized
  /// (defaults apply); an explicit short list is a deliberate choice and the
  /// bar respects its length.
  static Future<List<int>?> getPhoneNavBarIndices() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getStringList(_phoneNavBarIndicesKey);
    if (raw == null) return null;
    return [
      for (final s in raw)
        if (int.tryParse(s) != null) int.parse(s),
    ];
  }

  static Future<void> setPhoneNavBarIndices(List<int> indices) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_phoneNavBarIndicesKey, [
      for (final i in indices) '$i',
    ]);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    tvSidebarStyleCached = 'ghost';
    desktopSidebarStyleCached = 'rail';
    sidebarConfigurationCached = SidebarConfiguration.defaults();
  }
}
