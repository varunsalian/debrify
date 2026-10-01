import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class PlayerNetworkStorage {
  const PlayerNetworkStorage._();
  // Network tuning (Debrify player). 'standard' = leave the player's own
  // defaults completely untouched — see NetworkTuning.
  static const String _networkConnectPatienceKey = 'network_connect_patience';
  static const String _iptvDecoderModeKey = 'iptv_decoder_mode';
  static const String _networkBufferSizeKey = 'network_buffer_size';
  static const String _contentDisplayMatchModeKey = 'content_display_match_mode';

  /// Android TV IPTV video decoder: 'auto' | 'hardware' | 'software'.
  ///
  /// Some TV boxes (MediaTek/Amlogic especially) freeze the picture while
  /// audio keeps playing when their hardware decoder is handed a live stream
  /// it mishandles — a device defect no app can work around reliably, which
  /// is why every IPTV player ships this switch. 'software' puts Android's
  /// own software codecs (c2.android.* / OMX.google.*) first; 'auto' leaves
  /// the platform's decoder order untouched.
  static const List<String> iptvDecoderModes = ['auto', 'hardware', 'software'];

  static Future<String> getIptvDecoderMode() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_iptvDecoderModeKey) ?? 'auto';
    return iptvDecoderModes.contains(value) ? value : 'auto';
  }

  static Future<void> setIptvDecoderMode(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvDecoderModeKey,
      iptvDecoderModes.contains(value) ? value : 'auto',
    );
  }

  // Network tuning (Debrify player)
  /// 'standard' | 'extended' | 'patient'. Standard = player defaults untouched.
  static Future<String> getNetworkConnectPatience() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_networkConnectPatienceKey) ?? 'standard';
  }

  static Future<void> setNetworkConnectPatience(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_networkConnectPatienceKey, value);
  }

  /// 'standard' | 'large' | 'huge'. Standard = player defaults untouched.
  static Future<String> getNetworkBufferSize() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_networkBufferSizeKey) ?? 'standard';
  }

  static Future<void> setNetworkBufferSize(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_networkBufferSizeKey, value);
  }

  /// Television output matching. The default deliberately preserves the
  /// behavior from before this setting existed instead of silently changing
  /// display modes for existing profiles.
  static Future<ContentDisplayMatchMode> getContentDisplayMatchMode() async {
    final prefs = await ProfilePreferences.instance();
    return ContentDisplayMatchMode.fromStorage(
      prefs.getString(_contentDisplayMatchModeKey),
    );
  }

  static Future<void> setContentDisplayMatchMode(
    ContentDisplayMatchMode mode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_contentDisplayMatchModeKey, mode.storageKey);
  }
}
