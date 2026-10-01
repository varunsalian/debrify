import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:flutter/foundation.dart';

final class PlaylistMetadataStorage {
  const PlaylistMetadataStorage._();

  static Future<bool> updatePlaylistItemImdbId(
    String imdbId, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    bool force = false,
  }) async {
    final items = await PlaylistStorage.getPlaylistItemsRaw();
    int itemIndex = -1;

    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
    }

    if (itemIndex == -1 && premiumizeHash != null && premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() == premiumizeHash.toLowerCase(),
      );
    }

    if (itemIndex == -1 && premiumizeItemId != null && premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
    }

    if (itemIndex == -1 && torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        final torboxId = items[i]['torboxTorrentId'];
        if (torboxId != null && torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          break;
        }
      }
    }

    if (itemIndex == -1 && pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) return true;
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          return pikpakFileIds[0].toString() == pikpakCollectionId;
        }
        return false;
      });
    }

    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() == allDebridHash.toLowerCase(),
      );
    }

    if (itemIndex == -1) return false;

    if (!force) {
      final existing = items[itemIndex]['imdbId'] as String?;
      if (existing != null && existing.isNotEmpty) return true;
    }

    items[itemIndex]['imdbId'] = imdbId;
    await PlaylistStorage.savePlaylistItemsRaw(items);
    debugPrint(
      'StorageService: Saved imdbId $imdbId to playlist item "${items[itemIndex]['title']}"',
    );
    return true;
  }
}
