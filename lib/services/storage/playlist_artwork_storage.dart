import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:flutter/foundation.dart';

final class PlaylistArtworkStorage {
  const PlaylistArtworkStorage._();

  /// Update an existing playlist item with poster URL
  /// Supports both RealDebrid (rdTorrentId) and PikPak (pikpakCollectionId)
  static Future<bool> updatePlaylistItemPoster(
    String posterUrl, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
  }) async {
    debugPrint('🎨 updatePlaylistItemPoster called with:');
    debugPrint('  posterUrl: $posterUrl');
    debugPrint('  rdTorrentId: $rdTorrentId');
    debugPrint('  torboxTorrentId: $torboxTorrentId');
    debugPrint('  pikpakCollectionId: $pikpakCollectionId');
    debugPrint('  webDavServerId: $webDavServerId');
    debugPrint('  webDavPath: $webDavPath');

    final items = await PlaylistStorage.getPlaylistItemsRaw();
    debugPrint('  Total playlist items: ${items.length}');

    int itemIndex = -1;

    // Search by rdTorrentId if provided (RealDebrid)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by rdTorrentId at index $itemIndex');
      }
    }

    // Search by torboxTorrentId if provided and not found yet (Torbox)
    if (itemIndex == -1 && torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
      debugPrint('  Searching for torboxTorrentId: $torboxTorrentId');
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final torboxId = item['torboxTorrentId'];
        debugPrint(
          '    Item[$i] torboxTorrentId: $torboxId (type: ${torboxId.runtimeType})',
        );
        if (torboxId != null && torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          debugPrint('  ✅ Found item by torboxTorrentId at index $itemIndex');
          break;
        }
      }
    }

    // Search by pikpakCollectionId if provided and not found yet (PikPak)
    if (itemIndex == -1 && pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        // Check single PikPak files
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) {
          return true;
        }

        // Check PikPak collections (first file ID in array)
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          final firstId = pikpakFileIds[0].toString();
          if (firstId == pikpakCollectionId) {
            return true;
          }
        }

        return false;
      });
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by pikpakCollectionId at index $itemIndex');
      }
    }

    // Search by Premiumize infohash if provided and not found yet (Premiumize)
    if (itemIndex == -1 && premiumizeHash != null && premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() == premiumizeHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeHash at index $itemIndex');
      }
    }

    // Search by Premiumize cloud item id if provided and not found yet
    // (cloud-browser items have no torrent hash).
    if (itemIndex == -1 && premiumizeItemId != null && premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeItemId at index $itemIndex');
      }
    }

    // Search by AllDebrid infohash if provided and not found yet.
    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() == allDebridHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by allDebridHash at index $itemIndex');
      }
    }

    if (itemIndex == -1 &&
        webDavPath != null &&
        webDavPath.isNotEmpty &&
        ((webDavServerId != null && webDavServerId.isNotEmpty) ||
            (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty))) {
      final webDavKey = PlaylistStorage.computePlaylistDedupeKey({
        'provider': 'webdav',
        if (webDavServerId != null && webDavServerId.isNotEmpty) 'webdavServerId': webDavServerId,
        if (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty) 'webdavBaseUrl': webDavBaseUrl,
        'webdavPath': webDavPath,
      });
      itemIndex = items.indexWhere(
        (item) => PlaylistStorage.computePlaylistDedupeKey(item) == webDavKey,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by WebDAV key at index $itemIndex');
      }
    }

    if (itemIndex == -1) {
      debugPrint('  ❌ Item not found in playlist!');
      return false;
    }

    debugPrint('  💾 Saving poster to item at index $itemIndex');
    items[itemIndex]['posterUrl'] = posterUrl;
    await PlaylistStorage.savePlaylistItemsRaw(items);
    debugPrint('  ✅ Poster saved successfully!');
    return true;
  }
}
