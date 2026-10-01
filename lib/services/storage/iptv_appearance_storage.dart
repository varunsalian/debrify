import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/utils/platform_util.dart';

final class IptvAppearanceStorage {
  const IptvAppearanceStorage._();

  static const String _iptvStyleKey = 'iptv_style';
  static const String kIptvStyleDefault = 'spotlight';
  static const Set<String> _iptvStyles = {
    'command',
    'edition',
    'console',
    'spotlight',
  };

  /// Whether browsing IPTV channels may open the focused channel in the
  /// embedded side preview. This is on by default to preserve the shipped
  /// experience; users whose provider enforces a small connection limit can
  /// turn it off without affecting explicit fullscreen playback.
  static const String _iptvChannelPreviewEnabledKey = 'iptv_channel_preview_enabled';

  static Future<bool> getIptvChannelPreviewEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvChannelPreviewEnabledKey) ?? true;
  }

  static Future<void> setIptvChannelPreviewEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvChannelPreviewEnabledKey, enabled);
  }

  /// IPTV appearance for TV and desktop. Phones and touch tablets keep their
  /// existing layouts. Missing or unknown values use Spotlight Guide; valid
  /// saved choices remain unchanged.
  ///
  /// Synchronous mirror for Looks, refreshed by the async getter and reset
  /// to the default when switching profiles.
  static String iptvStyleCached = kIptvStyleDefault;

  static Future<String> getIptvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvStyleKey);
    return iptvStyleCached = _iptvStyles.contains(raw) ? raw! : kIptvStyleDefault;
  }

  static Future<void> setIptvStyle(String style) async {
    final normalized = _iptvStyles.contains(style) ? style : kIptvStyleDefault;
    iptvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iptvStyleKey, normalized);
  }

  static const String _iptvPlayerGuideStyleKey = 'iptv_player_guide_style';
  static const Set<String> _iptvPlayerGuideStyles = {
    'classic',
    'glass',
    'edition',
    'console',
    'spotlight',
  };

  /// In-player IPTV guide look (zap banner, channel sheet, native guide
  /// overlay + dock): 'classic' (today's look, the default), 'glass'
  /// (Cinema Glass), 'edition' (Midnight Edition) or 'console' (Master
  /// Control). Both players read it once at launch — the Dart player via
  /// this getter, the native TV player via `flutter.iptv_player_guide_style`
  /// in FlutterSharedPreferences. Unknown or unset coerces to 'classic' on
  /// BOTH read and write, so an old build downgrading past a newer value can
  /// never pin a look the reader treats as the exception.
  static Future<String> getIptvPlayerGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvPlayerGuideStyleKey);
    if (_iptvPlayerGuideStyles.contains(raw)) return raw!;
    // Never chosen: Apple TV gets its native idiom, everything else keeps
    // the shipped look. An explicit pick (either way) is stored and wins.
    return PlatformUtil.isTvOS ? 'spotlight' : 'classic';
  }

  static Future<void> setIptvPlayerGuideStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvPlayerGuideStyleKey,
      _iptvPlayerGuideStyles.contains(style) ? style : 'classic',
    );
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    iptvStyleCached = kIptvStyleDefault;
  }
}
