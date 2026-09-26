import '../models/series_source.dart';
import '../models/torrent.dart';

/// Builds a durable descriptor without storing transient playback URLs/headers.
/// Classifiers, media-server descriptors, time and provider mapping are supplied
/// by the caller; media-server ownership takes precedence over IPTV/addons.
SeriesSource? durableSourceBinding(
  Torrent source,
  String provider, {
  required int now,
  required bool Function(Torrent) isMediaServer,
  required SeriesSource? Function(Torrent) mediaServerBinding,
  required bool Function(Torrent) isIptv,
  required String Function(String) storedProviderKey,
  String? addonCatalogId,
  String? addonCatalogKey,
}) {
  if (source.streamType == StreamType.directUrl) {
    if (isMediaServer(source)) return mediaServerBinding(source);
    if (isIptv(source)) {
      final playlistId = source.iptvPlaylistId;
      final catalogType = source.iptvCatalogType;
      final entryKey = source.iptvEntryKey;
      if (playlistId == null ||
          playlistId.isEmpty ||
          catalogType == null ||
          catalogType.isEmpty ||
          entryKey == null ||
          entryKey.isEmpty) {
        return null;
      }
      return SeriesSource(
        torrentHash: '',
        torrentName: source.name,
        debridService: SeriesSource.iptvDirectService,
        debridTorrentId: '',
        boundAt: now,
        iptvPlaylistId: playlistId,
        iptvCatalogType: catalogType,
        iptvEntryKey: entryKey,
      );
    }
    final addonId = source.stremioAddonId;
    final addonKey = source.stremioAddonKey;
    final streamKey = source.stremioStreamKey;
    if (addonId == null ||
        addonId.isEmpty ||
        addonKey == null ||
        addonKey.isEmpty ||
        streamKey == null ||
        streamKey.isEmpty) {
      return null;
    }
    return SeriesSource(
      torrentHash: '',
      torrentName: source.name,
      debridService: SeriesSource.addonDirectService,
      debridTorrentId: '',
      boundAt: now,
      addonId: addonId,
      addonKey: addonKey,
      addonCatalogId: addonCatalogId,
      addonCatalogKey: addonCatalogKey,
      streamKey: streamKey,
      bingeGroup: source.stremioBingeGroup,
      streamIndex: source.stremioStreamIndex ?? 0,
    );
  }
  if (source.streamType != StreamType.torrent ||
      source.infohash.isEmpty ||
      provider == SeriesSource.localService ||
      provider == SeriesSource.addonDirectService ||
      provider == SeriesSource.iptvDirectService) {
    return null;
  }
  return SeriesSource(
    torrentHash: source.infohash,
    torrentName: source.name,
    debridService: storedProviderKey(provider),
    debridTorrentId: '',
    boundAt: now,
    addonCatalogId: addonCatalogId,
    addonCatalogKey: addonCatalogKey,
  );
}
