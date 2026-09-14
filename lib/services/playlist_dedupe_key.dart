/// Pure, provider-aware playlist identity shared by local storage and sync.
abstract final class PlaylistDedupeKey {
  static String compute(Map<String, dynamic> item) {
    final providerRaw = (item['provider'] as String?) ?? 'realdebrid';
    final provider = providerRaw.toLowerCase();
    if (provider == 'webdav') {
      final server = (item['webdavServerId'] ?? item['webdavBaseUrl'] ?? '')
          .toString();
      final path = (item['webdavPath'] ?? item['webdavFolderPath'] ?? '')
          .toString();
      if (server.isNotEmpty && path.isNotEmpty) {
        return '$provider|server:${server.toLowerCase()}|path:$path';
      }
    }
    final torrentHash = item['torrent_hash'] as String?;
    if (torrentHash != null && torrentHash.isNotEmpty) {
      return '$provider|hash:${torrentHash.toLowerCase()}';
    }
    final torboxIdRaw = item['torboxTorrentId'];
    if (torboxIdRaw != null) {
      final torboxId = torboxIdRaw.toString();
      final singleFileId = item['torboxFileId'];
      if (singleFileId != null) {
        final fileKey = 'torbox:$torboxId:file:${singleFileId.toString()}';
        return '$provider|${fileKey.toLowerCase()}';
      }
      final multiFileIds = item['torboxFileIds'];
      if (multiFileIds is List && multiFileIds.isNotEmpty) {
        final joined = multiFileIds.map((value) => value.toString()).join(',');
        final filesKey = 'torbox:$torboxId:files:$joined';
        return '$provider|${filesKey.toLowerCase()}';
      }
      return '$provider|torbox:${torboxId.toLowerCase()}';
    }
    final pikpakFileId = item['pikpakFileId'];
    if (pikpakFileId != null) {
      return '$provider|pikpak:file:${pikpakFileId.toString().toLowerCase()}';
    }
    final pikpakFileIds = item['pikpakFileIds'];
    if (pikpakFileIds is List && pikpakFileIds.isNotEmpty) {
      final joined = pikpakFileIds.map((value) => value.toString()).join(',');
      return '$provider|pikpak:files:${joined.toLowerCase()}';
    }
    final premiumizeItemId = item['premiumizeItemId'];
    if (premiumizeItemId != null && premiumizeItemId.toString().isNotEmpty) {
      return '$provider|premiumize:item:'
          '${premiumizeItemId.toString().toLowerCase()}';
    }
    final premiumizeItemIds = item['premiumizeItemIds'];
    if (premiumizeItemIds is List && premiumizeItemIds.isNotEmpty) {
      final joined = premiumizeItemIds
          .map((value) => value.toString())
          .join(',');
      return '$provider|premiumize:items:${joined.toLowerCase()}';
    }
    final rdId = item['rdTorrentId'] as String?;
    if (rdId != null && rdId.isNotEmpty) {
      return '$provider|rd:${rdId.toLowerCase()}';
    }
    final source =
        (item['restrictedLink'] as String?)?.trim() ??
        (item['url'] as String?)?.trim() ??
        '';
    final title = (item['title'] as String?)?.trim() ?? '';
    return '$provider|${'$source|$title'.toLowerCase()}';
  }
}
