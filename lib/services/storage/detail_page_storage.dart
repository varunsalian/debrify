import 'package:debrify/models/detail_page_section_visibility.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:synchronized/synchronized.dart';

final class DetailPageStorage {
  const DetailPageStorage._();

  // Shared within lib/services/storage/.
  static const String detailPageStyleKey = 'detail_page_style';

  /// Every value storage will persist for the merged details page look
  /// (Appearance → Details Page). Every known layout is accepted — a
  /// choice written by a newer build has to survive a downgrade rather than be
  /// silently rewritten to the default the first time an older build reads it.
  ///
  /// What a given BUILD can actually draw is a narrower set —
  /// `kDetailPageStylesShipped` in `screens/settings/detail_page_style_page.dart`
  /// — and dispatch/labels/picker all go through `effectiveDetailPageStyle`.
  static const Set<String> kDetailPageStyles = {
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

  /// The layout a fresh install — and anyone who has never opened the picker —
  /// gets.
  ///
  /// **Console rather than Classic, and that is a deliberate change to what
  /// the app looks like out of the box.** Classic is the one layout that is
  /// deliberately unthemed: it paints its own literals and ignores the app
  /// theme entirely. With Classic as the default, picking an App Theme
  /// appeared to do nothing on the page most people judge the app by — the
  /// setting looked broken when it was working. A themed layout as the default
  /// is what makes it honest.
  ///
  /// This is the FALLBACK, so it moves everyone with no stored value — not
  /// just new installs, but every user who never opened the picker. That
  /// breadth is the point rather than a side effect; Classic is still one row
  /// away for anyone who wants it back.
  static const String kDetailPageStyleDefault = 'console';

  /// Synchronous mirror, warmed in main() before runApp: `MergedDetailScreen`
  /// picks its body in the first build, so an async-only read would paint the
  /// default for a frame and then re-lay-out the whole page.
  ///
  /// Normalizes toward [kDetailPageStyleDefault] on BOTH sides — an
  /// unrecognized value has to mean the default for the reader and the writer
  /// alike.
  static String detailPageStyleCached = kDetailPageStyleDefault;

  static Future<String> getDetailPageStyle() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(detailPageStyleKey);
    detailPageStyleCached = kDetailPageStyles.contains(value) ? value! : kDetailPageStyleDefault;
    return detailPageStyleCached;
  }

  static Future<void> setDetailPageStyle(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kDetailPageStyles.contains(value) ? value : kDetailPageStyleDefault;
    await prefs.setString(detailPageStyleKey, normalized);
    detailPageStyleCached = normalized;
  }

  static const String _detailShowWhereToWatchKey = 'detail_show_where_to_watch';
  static const String _detailShowRentKey = 'detail_show_rent';
  static const String _detailShowBuyKey = 'detail_show_buy';
  static const String _detailShowAvailabilityLinkKey = 'detail_show_availability_link';
  static const String _detailShowDidYouKnowKey = 'detail_show_did_you_know';

  /// Public key set lets profile/WebDAV refresh update the synchronous mirror
  /// when one of these independently stored switches changes remotely.
  static const Set<String> detailPageSectionPreferenceKeys = {
    _detailShowWhereToWatchKey,
    _detailShowRentKey,
    _detailShowBuyKey,
    _detailShowAvailabilityLinkKey,
    _detailShowDidYouKnowKey,
  };

  /// Warmed before the first frame and on profile activation because Showcase
  /// builds its optional bands synchronously.
  static DetailPageSectionVisibility detailPageSectionVisibilityCached = DetailPageSectionVisibility.defaults;
  static final Lock _detailPageSectionWriteLock = Lock();
  static int _detailPageSectionWriteGeneration = 0;

  static Future<DetailPageSectionVisibility> getDetailPageSectionVisibility() async {
    final prefs = await ProfilePreferences.instance();
    return detailPageSectionVisibilityCached = DetailPageSectionVisibility(
      whereToWatch: prefs.getBool(_detailShowWhereToWatchKey) ?? true,
      rent: prefs.getBool(_detailShowRentKey) ?? true,
      buy: prefs.getBool(_detailShowBuyKey) ?? true,
      availabilityLink: prefs.getBool(_detailShowAvailabilityLinkKey) ?? true,
      didYouKnow: prefs.getBool(_detailShowDidYouKnowKey) ?? true,
    );
  }

  static Future<void> setDetailPageSectionVisibility(
    DetailPageSectionVisibility visibility,
  ) async {
    // Publish before awaiting disk so a details page opened immediately after
    // the tap cannot observe the previous value for one frame.
    final generation = ++_detailPageSectionWriteGeneration;
    detailPageSectionVisibilityCached = visibility;
    // Capture the active profile before joining the write queue. A profile
    // switch then makes this facade reject the stale write instead of sending
    // an old profile's choice into the newly active profile.
    final prefs = await ProfilePreferences.instance();
    await _detailPageSectionWriteLock.synchronized(() async {
      if (generation != _detailPageSectionWriteGeneration) return;
      await Future.wait([
        prefs.setBool(_detailShowWhereToWatchKey, visibility.whereToWatch),
        prefs.setBool(_detailShowRentKey, visibility.rent),
        prefs.setBool(_detailShowBuyKey, visibility.buy),
        prefs.setBool(
          _detailShowAvailabilityLinkKey,
          visibility.availabilityLink,
        ),
        prefs.setBool(_detailShowDidYouKnowKey, visibility.didYouKnow),
      ]);
    });
  }

  // Shared within lib/services/storage/.
  static const String detailThemeKey = 'detail_theme';

  /// Every look the details page can wear (Appearance → Details Theme).
  ///
  /// Same contract as [kDetailPageStyles]: all values are accepted from day
  /// one so a theme written by a newer build survives a downgrade, and what a
  /// given BUILD can draw is the narrower `kDetailThemesShipped` in
  /// `screens/settings/detail_theme_page.dart`.
  ///
  /// The layout and the theme are orthogonal — one says where things are, the
  /// other what they look like.
  static const Set<String> kDetailThemes = {
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
    // The five premium looks. Accepted here from the build that introduces
    // them, for the same downgrade reason as everything above: a value a newer
    // build wrote must survive being read by an older one, which normalizes it
    // to 'signal' rather than losing the key.
    'glass',
    'field',
    'hearth',
    'console',
    'reel',

    'spotlight',
  };

  /// Synchronous mirror, warmed in main() before runApp — the details page
  /// picks its theme in the first build, so an async-only read would paint
  /// Signal for a frame and then repaint the whole page.
  static String detailThemeCached = 'signal';

  static Future<String> getDetailTheme() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(detailThemeKey);
    detailThemeCached = kDetailThemes.contains(value) ? value! : 'signal';
    return detailThemeCached;
  }

  static Future<void> setDetailTheme(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kDetailThemes.contains(value) ? value : 'signal';
    await prefs.setString(detailThemeKey, normalized);
    detailThemeCached = normalized;
  }

  static const String _parentsGuideStyleKey = 'parents_guide_style';
  static const Set<String> kParentsGuideStyles = {'classic', 'compass'};

  /// Synchronous mirror used by the Parents Guide widget. Compass is the new
  /// default; Classic remains available as a zero-risk fallback in Appearance.
  static String parentsGuideStyleCached = 'compass';

  static Future<String> getParentsGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_parentsGuideStyleKey);
    parentsGuideStyleCached = kParentsGuideStyles.contains(value) ? value! : 'compass';
    return parentsGuideStyleCached;
  }

  static Future<void> setParentsGuideStyle(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kParentsGuideStyles.contains(value) ? value : 'compass';
    await prefs.setString(_parentsGuideStyleKey, normalized);
    parentsGuideStyleCached = normalized;
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    detailPageStyleCached = kDetailPageStyleDefault;
    detailPageSectionVisibilityCached = DetailPageSectionVisibility.defaults;
    detailThemeCached = 'signal';
    parentsGuideStyleCached = 'compass';
  }
}
