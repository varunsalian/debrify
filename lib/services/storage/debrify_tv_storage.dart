import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/profile_policy_storage.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:flutter/foundation.dart';

final class DebrifyTvStorage {
  const DebrifyTvStorage._();
  static const String _debrifyTvStartRandomKey = 'debrify_tv_start_random';
  static const String _debrifyTvHideSeekbarKey = 'debrify_tv_hide_seekbar';
  static const String _debrifyTvShowChannelNameKey = 'debrify_tv_show_watermark';
  static const String _debrifyTvShowVideoTitleKey = 'debrify_tv_show_video_title';
  static const String _debrifyTvHideOptionsKey = 'debrify_tv_hide_options';
  static const String _debrifyTvHideBackButtonKey = 'debrify_tv_hide_back_button';
  static const String _debrifyTvAvoidNsfwKey = 'debrify_tv_avoid_nsfw';
  static const String _debrifyTvProviderKey = 'debrify_tv_provider';
  static const String _debrifyTvRandomStartPercentKey = 'debrify_tv_random_start_percent';
  static const String _debrifyTvChannelsKey = 'debrify_tv_channels';
  // Debrify TV playback filters. Quality is matched on the torrent NAME
  // (applied when a channel's cache is read); size is matched on the real
  // per-FILE byte count after the debrid provider returns its file list —
  // per-file sizes are per-episode, so packs need no series/movie detection.
  static const String _debrifyTvFilterQualitiesKey = 'debrify_tv_filter_qualities';
  static const String _debrifyTvFilterSizesKey = 'debrify_tv_filter_sizes';

  // "You're using an external player" notice shown before Debrify TV hands a
  // stream to another app. Dismissible forever, because the trade-off it
  // explains (one title, no channel rotation) never changes.
  static const String _debrifyTvExternalNoticeDismissedKey = 'debrify_tv_external_notice_dismissed';

  static const String _debrifyTvFavoriteChannelsKey = 'debrify_tv_favorite_channels_v1';

  static const int _debrifyTvRandomStartPercentDefault = 20;
  static const int _debrifyTvRandomStartPercentMin = 10;
  static const int _debrifyTvRandomStartPercentMax = 90;

  // Shared within lib/services/storage/.
  static const String debrifyTvStyleKey = 'debrify_tv_style';

  /// Every shipping Debrify TV layout. 'grid' is the historical default — the
  /// channel wall `build()` has always drawn; 'spotlight' is the standing
  /// rail + stage (list + sheet on phone). One key covers every device class:
  /// the style resolves its own layout per device, like `detail_page_style`.
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one lands on 'grid' rather than rendering nothing.
  static const Set<String> kDebrifyTvStyles = {'grid', 'spotlight'};

  /// Synchronous mirror of `debrify_tv_style`, kept so a Look can read the
  /// current value without an await. Every existing caller still goes through
  /// the async getter, which also refreshes this.
  static String debrifyTvStyleCached = 'grid';

  static Future<String> getDebrifyTvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(debrifyTvStyleKey);
    return debrifyTvStyleCached = kDebrifyTvStyles.contains(raw) ? raw! : 'grid';
  }

  static Future<void> setDebrifyTvStyle(String style) async {
    final normalized = kDebrifyTvStyles.contains(style) ? style : 'grid';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    debrifyTvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(debrifyTvStyleKey, normalized);
  }

  static const String _debrifyTvPlayerStyleKey = 'debrify_tv_player_style';
  static const Set<String> _debrifyTvPlayerStyles = {
    'classic',
    'network',
    'cinema',
    'guide',
    'spotlight',
    'prestige',
  };

  /// Playback-screen style for the NATIVE Debrify TV player
  /// (TorboxTvPlayerActivity): 'cinema' (poster + gilded spec line — the
  /// default), 'network' (broadcast lower-third), 'guide' (opaque
  /// broadcast band), 'spotlight' (frosted glass panel), 'prestige'
  /// (quiet serif identity), or 'classic' (the legacy ESPN-style bar +
  /// top marquee). Android TV only. Read once per player launch — the
  /// native side via
  /// `ProfilePreferenceProjection.getString("debrify_tv_player_style")`
  /// (falling back to `flutter.debrify_tv_player_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'cinema' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getDebrifyTvPlayerStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvPlayerStyleKey);
    return _debrifyTvPlayerStyles.contains(raw) ? raw! : 'cinema';
  }

  static Future<void> setDebrifyTvPlayerStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _debrifyTvPlayerStyleKey,
      _debrifyTvPlayerStyles.contains(style) ? style : 'cinema',
    );
  }

  // Debrify TV settings methods
  static Future<String> getDebrifyTvProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_debrifyTvProviderKey) ?? 'real_debrid';
  }

  static Future<void> saveDebrifyTvProvider(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvProviderKey, value);
  }

  static Future<bool> hasDebrifyTvProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.containsKey(_debrifyTvProviderKey);
  }

  static Future<bool> getDebrifyTvStartRandom() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvStartRandomKey) ?? true;
  }

  static Future<void> saveDebrifyTvStartRandom(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvStartRandomKey, value);
  }

  static int _normalizeDebrifyTvRandomStartPercent(int? value) {
    final candidate = value ?? _debrifyTvRandomStartPercentDefault;
    if (candidate < _debrifyTvRandomStartPercentMin) {
      return _debrifyTvRandomStartPercentMin;
    }
    if (candidate > _debrifyTvRandomStartPercentMax) {
      return _debrifyTvRandomStartPercentMax;
    }
    return candidate;
  }

  static Future<int> getDebrifyTvRandomStartPercent() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getInt(_debrifyTvRandomStartPercentKey);
    return _normalizeDebrifyTvRandomStartPercent(stored);
  }

  static Future<void> saveDebrifyTvRandomStartPercent(int value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _normalizeDebrifyTvRandomStartPercent(value);
    await prefs.setInt(_debrifyTvRandomStartPercentKey, normalized);
  }

  static Future<bool> getDebrifyTvHideSeekbar() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideSeekbarKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideSeekbar(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideSeekbarKey, value);
  }

  static Future<bool> getDebrifyTvShowChannelName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvShowChannelNameKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowChannelName(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvShowChannelNameKey, value);
  }

  static Future<bool> getDebrifyTvShowVideoTitle() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvShowVideoTitleKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowVideoTitle(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvShowVideoTitleKey, value);
  }

  static Future<bool> getDebrifyTvHideOptions() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideOptionsKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideOptions(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideOptionsKey, value);
  }

  static Future<bool> getDebrifyTvHideBackButton() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideBackButtonKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideBackButton(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideBackButtonKey, value);
  }

  static Future<bool> getDebrifyTvAvoidNsfw() async {
    if (!await ProfilePolicyStorage.profileAllowsAdultContent()) return true;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvAvoidNsfwKey) ?? true; // Default enabled
  }

  static Future<void> saveDebrifyTvAvoidNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _debrifyTvAvoidNsfwKey,
      await ProfilePolicyStorage.profileAllowsAdultContent() ? value : true,
    );
  }

  static Future<List<Map<String, dynamic>>> getDebrifyTvChannels() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvChannelsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw) as List<dynamic>;
      return list.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> saveDebrifyTvChannels(
    List<Map<String, dynamic>> channels,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvChannelsKey, jsonEncode(channels));
  }

  /// Clear Debrify TV provider and legacy channels key
  static Future<void> clearDebrifyTvProviderAndLegacy() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_debrifyTvProviderKey);
    await prefs.remove(_debrifyTvChannelsKey);
  }

  /// Clear all Debrify TV display and engine settings
  static Future<void> clearAllDebrifyTvSettings() async {
    final prefs = await ProfilePreferences.instance();
    // Display settings
    await prefs.remove(_debrifyTvStartRandomKey);
    await prefs.remove(_debrifyTvHideSeekbarKey);
    await prefs.remove(_debrifyTvShowChannelNameKey);
    await prefs.remove(_debrifyTvShowVideoTitleKey);
    await prefs.remove(_debrifyTvHideOptionsKey);
    await prefs.remove(_debrifyTvHideBackButtonKey);
    await prefs.remove(_debrifyTvAvoidNsfwKey);
    await prefs.remove(_debrifyTvRandomStartPercentKey);
    // Playback filters
    await prefs.remove(_debrifyTvFilterQualitiesKey);
    await prefs.remove(_debrifyTvFilterSizesKey);
    for (final key
        in prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith('engine_tv_') ||
                  key.startsWith('debrify_tv_use_') ||
                  key.startsWith('debrify_tv_channel_small_') ||
                  key.startsWith('debrify_tv_channel_large_') ||
                  key.startsWith('debrify_tv_quick_play_') ||
                  key == 'debrify_tv_keyword_threshold' ||
                  key == 'debrify_tv_min_torrents_per_keyword',
            )
            .toList()) {
      await prefs.remove(key);
    }
  }

  // ==========================================================================
  // Debrify TV Channel Favorites
  // ==========================================================================

  /// Check if a Debrify TV channel is favorited
  static Future<bool> isDebrifyTvChannelFavorited(String channelId) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelId);
    } catch (e) {
      debugPrint('Error reading Debrify TV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a Debrify TV channel
  static Future<void> setDebrifyTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (isFavorited) {
      favorites[channelId] = true;
    } else {
      favorites.remove(channelId);
    }

    await prefs.setString(_debrifyTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Debrify TV channel IDs
  static Future<Set<String>> getDebrifyTvFavoriteChannelIds() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading Debrify TV channel favorites: $e');
      return {};
    }
  }

  // Debrify TV Filter Settings — scoped to Debrify TV only, deliberately
  // separate from the Search tab's default filters above so tuning a channel
  // feed never changes search behaviour (and vice versa).
  static Future<List<String>> getDebrifyTvFilterQualities() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_debrifyTvFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDebrifyTvFilterQualities(
    List<String> qualities,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDebrifyTvFilterSizes() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_debrifyTvFilterSizesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDebrifyTvFilterSizes(List<String> sizes) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvFilterSizesKey, jsonEncode(sizes));
  }

  /// Whether the user dismissed the Debrify TV external-player notice forever.
  static Future<bool> getDebrifyTvExternalNoticeDismissed() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvExternalNoticeDismissedKey) ?? false;
  }

  static Future<void> setDebrifyTvExternalNoticeDismissed(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvExternalNoticeDismissedKey, value);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    debrifyTvStyleCached = 'grid';
  }
}
