import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';

final class SourceCacheOrdering {
  const SourceCacheOrdering._();

  static Future<List<Torrent>> cacheFirst(
    String provider,
    List<Torrent> candidates,
  ) async {
    final hashes = candidates
        .map((t) => t.infohash.toLowerCase())
        .where((h) => h.isNotEmpty)
        .toList();
    final cached = <String>{};
    try {
      if (provider == 'torbox') {
        final key = (await TorboxStorage.getTorboxApiKey()) ?? '';
        cached.addAll(
          await TorboxService.checkCachedTorrents(
            apiKey: key,
            infoHashes: hashes,
          ),
        );
      } else if (provider == 'premiumize') {
        final key = (await PremiumizeStorage.getPremiumizeApiKey()) ?? '';
        final res = await PremiumizeService.checkCache(key, hashes);
        for (var i = 0; i < hashes.length && i < res.length; i++) {
          if (res[i]) cached.add(hashes[i]);
        }
      }
    } catch (_) {}
    if (cached.isEmpty) return candidates;
    final hit = candidates
        .where((t) => cached.contains(t.infohash.toLowerCase()))
        .toList();
    final miss = candidates
        .where((t) => !cached.contains(t.infohash.toLowerCase()))
        .toList();
    return [...hit, ...miss];
  }
}
