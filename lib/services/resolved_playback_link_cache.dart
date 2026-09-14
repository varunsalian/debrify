import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';

import '../models/torrent.dart';
import 'profiles/profile_preferences.dart';
import 'secret_vault.dart';
import 'series_source_service.dart';

/// Device-local, encrypted links. Durable pins remain the source of truth.
class ResolvedPlaybackLinkCache {
  static const preferenceKey = 'resolved_playback_links_v1';
  static const maxAge = Duration(hours: 72);
  static final _lock = Lock();

  static String key(
    String id,
    String type,
    int? season,
    int? episode,
    String addon,
    String profile,
  ) => sha256
      .convert(
        utf8.encode(jsonEncode([id, type, season, episode, addon, profile])),
      )
      .toString();

  static DateTime expiresAt(String url, DateTime now) {
    var expiry = now.add(maxAge);
    final query =
        Uri.tryParse(url)?.queryParameters ?? const <String, String>{};
    for (final entry in query.entries) {
      if (!const ['exp', 'expires', 'expiry'].contains(entry.key.toLowerCase()))
        continue;
      final n = int.tryParse(entry.value);
      final value = n == null
          ? DateTime.tryParse(entry.value)
          : DateTime.fromMillisecondsSinceEpoch(
              n < 100000000000 ? n * 1000 : n,
            );
      if (value != null && value.isBefore(expiry)) expiry = value;
    }
    return expiry;
  }

  static Future<Map<String, dynamic>> _read(ProfilePreferences prefs) async {
    try {
      final raw = prefs.getString(preferenceKey);
      if (raw == null || !raw.startsWith(SecretVault.prefix)) return {};
      return jsonDecode(await SecretVault.open(raw) ?? '{}')
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save({
    required String id,
    required String type,
    int? season,
    int? episode,
    required Torrent source,
  }) async {
    if (source.directUrl == null ||
        source.stremioAddonKey == null ||
        source.stremioStreamKey == null)
      return;
    if (type != 'movie' && (season == null || episode == null)) return;
    final prefs = await ProfilePreferences.instance();
    await _lock.synchronized(() async {
      final now = DateTime.now();
      var expiry = expiresAt(source.directUrl!, now);
      if (!expiry.isAfter(now)) return;
      final entries = await _read(prefs);
      entries.removeWhere(
        (_, value) =>
            (value['expires'] as int? ?? 0) <= now.millisecondsSinceEpoch,
      );
      final cacheKey = key(
        id,
        type,
        season,
        episode,
        source.stremioAddonKey!,
        source.stremioStreamKey!,
      );
      final previous = entries[cacheKey];
      if (previous != null &&
          previous['source']['direct_url'] == source.directUrl) {
        final oldExpiry = DateTime.fromMillisecondsSinceEpoch(
          previous['expires'] as int,
        );
        if (oldExpiry.isBefore(expiry)) expiry = oldExpiry;
      }
      entries.remove(cacheKey);
      entries[cacheKey] = {
        'expires': expiry.millisecondsSinceEpoch,
        'source': source.toJson(),
      };
      while (entries.length > 64) {
        entries.remove(entries.keys.first);
      }
      await prefs.setString(
        preferenceKey,
        await SecretVault.seal(jsonEncode(entries)),
      );
    });
  }

  static Future<Torrent?> get({
    required String id,
    required String type,
    int? season,
    int? episode,
    required SeriesSource pin,
  }) async {
    try {
      final prefs = await ProfilePreferences.instance();
      final entries = await _read(prefs);
      final entry =
          entries[key(
            id,
            type,
            season,
            episode,
            pin.addonKey!,
            pin.streamKey ?? '',
          )];
      if (entry == null ||
          (entry['expires'] as int) <= DateTime.now().millisecondsSinceEpoch)
        return null;
      final source = Torrent.fromJson(
        Map<String, dynamic>.from(entry['source']),
      );
      if (source.stremioBingeGroup != pin.bingeGroup ||
          source.stremioStreamIndex != pin.streamIndex)
        return null;
      return source;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove({
    required String id,
    required String type,
    int? season,
    int? episode,
    required SeriesSource pin,
  }) async {
    final prefs = await ProfilePreferences.instance();
    await _lock.synchronized(() async {
      final entries = await _read(prefs);
      entries.remove(
        key(id, type, season, episode, pin.addonKey!, pin.streamKey ?? ''),
      );
      await prefs.setString(
        preferenceKey,
        await SecretVault.seal(jsonEncode(entries)),
      );
    });
  }
}
