import '../models/torrent.dart';
import 'package:flutter/foundation.dart';
import 'resolved_playback_link_cache.dart';
import 'series_source_service.dart';

/// Forget only the saved binding represented by a rejected playback source.
/// This is not a blacklist: fresh searches and manual playback remain allowed.
class FailedSavedSource {
  /// Cleanup is best-effort: a storage failure must not block playback recovery.
  /// Attempt both stores independently so a failed pin write cannot leave a
  /// removable stale link behind (and vice versa).
  static Future<void> cleanup({
    required Future<void> Function() removePin,
    Future<void> Function()? removeCache,
  }) async {
    for (final operation in [removePin, if (removeCache != null) removeCache]) {
      try {
        await operation();
      } catch (error) {
        debugPrint('Saved source cleanup failed: ${error.runtimeType}');
      }
    }
  }

  static bool matches(SeriesSource pin, Torrent source) {
    if (pin.isAddonDirect) {
      if (pin.addonKey != source.stremioAddonKey) return false;
      if (pin.bingeGroup?.isNotEmpty == true) {
        return pin.bingeGroup == source.stremioBingeGroup;
      }
      return pin.streamKey?.isNotEmpty == true &&
          pin.streamKey == source.stremioStreamKey;
    }
    return source.hasRealInfoHash &&
        source.infohash.isNotEmpty &&
        pin.torrentHash.toLowerCase() == source.infohash.toLowerCase();
  }

  static Future<void> forget(
    String? imdbId,
    Torrent source, {
    String? reason,
  }) async {
    // A valid pack that lacks this episode is not a broken saved source.
    if (reason == 'playlist-missing-episode') return;
    await cleanup(
      removeCache: () => ResolvedPlaybackLinkCache.removeFailedSource(source),
      removePin: () async {
        if (imdbId == null || imdbId.isEmpty) return;
        for (final pin in await SeriesSourceService.getSources(imdbId)) {
          if (matches(pin, source)) {
            await SeriesSourceService.removeSourceEntry(imdbId, pin);
          }
        }
      },
    );
  }
}
