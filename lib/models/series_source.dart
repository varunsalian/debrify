import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'media_server_source.dart';
import '../utils/catalog_source_scope.dart';

/// Represents a bound torrent source for a series.
/// When set, episode playback skips torrent search and uses this source directly.
class SeriesSource {
  static const String localService = 'local';
  static const String addonDirectService = 'stremio_direct';
  static const String iptvDirectService = 'iptv_direct';
  static const String mediaServerService = 'media_server';
  static const String localKindMovieFile = 'movie_file';
  static const String localKindSeriesFolder = 'series_folder';
  static const String cloudKindFile = 'file';
  static const String cloudKindFolder = 'folder';
  static const String cloudKindWebDownload = 'web_download';

  final String torrentHash;
  final String torrentName;
  final String debridService;
  final String debridTorrentId;
  // Provider-native cloud bindings do not expose an infohash. Their stable
  // file/folder/web-download reference lives in [debridTorrentId], while this
  // discriminator tells playback how to resolve it without fabricating a
  // magnet. Hash-backed records leave this null.
  final String? cloudSourceKind;
  final int boundAt; // epoch millis
  final String? localPath;
  final String? localUri;
  final String? localKind;
  final int? localSizeBytes;
  final int? localModifiedAt;
  final String? addonId;
  final String? addonKey;
  final String? addonCatalogId;
  final String? addonCatalogKey;
  final String? streamKey;
  final String? bingeGroup;
  final int? streamIndex;
  final String? iptvPlaylistId;
  final String? iptvCatalogType;
  final String? iptvEntryKey;

  const SeriesSource({
    required this.torrentHash,
    required this.torrentName,
    required this.debridService,
    required this.debridTorrentId,
    this.cloudSourceKind,
    required this.boundAt,
    this.localPath,
    this.localUri,
    this.localKind,
    this.localSizeBytes,
    this.localModifiedAt,
    this.addonId,
    this.addonKey,
    this.addonCatalogId,
    this.addonCatalogKey,
    this.streamKey,
    this.bingeGroup,
    this.streamIndex,
    this.iptvPlaylistId,
    this.iptvCatalogType,
    this.iptvEntryKey,
  });

  bool get isLocal => debridService == localService;
  bool get isMediaServer => debridService == mediaServerService;
  bool get isProviderNativeCloud =>
      !isLocal &&
      torrentHash.isEmpty &&
      debridTorrentId.trim().isNotEmpty &&
      (cloudSourceKind == cloudKindFile ||
          cloudSourceKind == cloudKindFolder ||
          cloudSourceKind == cloudKindWebDownload);
  bool get isAddonDirect =>
      debridService == addonDirectService &&
      (addonId?.trim().isNotEmpty ?? false) &&
      (addonKey?.trim().isNotEmpty ?? false);
  bool get isIptvDirect =>
      debridService == iptvDirectService &&
      (iptvPlaylistId?.trim().isNotEmpty ?? false) &&
      (iptvCatalogType?.trim().isNotEmpty ?? false) &&
      (iptvEntryKey?.trim().isNotEmpty ?? false);

  /// Origin configuration and catalog together define the pinned content.
  bool matchesCatalogScope({String? catalogId, String? catalogKey}) =>
      addonCatalogId == catalogId && addonCatalogKey == catalogKey;

  /// Stable identity used for dedupe, reorder keys, and removal. Existing
  /// hash-backed bindings retain their exact behavior; only hashless cloud
  /// bindings fall back to provider + kind + provider id.
  String get bindingKey {
    final catalogScope = catalogSourceScope(addonCatalogId, addonCatalogKey);
    if (torrentHash.isNotEmpty) return '${catalogScope}hash:$torrentHash';
    if (isLocal) {
      final path = (localPath ?? debridTorrentId).trim();
      return 'local:$path';
    }
    if (isAddonDirect) {
      if (bingeGroup != null && bingeGroup!.isNotEmpty) {
        return '${catalogScope}direct:${addonKey!.trim()}:group:${sha256.convert(utf8.encode(bingeGroup!))}';
      }
      // [streamIndex] is deliberately NOT part of the identity. It is the
      // stream's position in the addon's response, which moves between searches
      // as cache state and seeders change — so including it made a replay of the
      // SAME file compute a new key, miss the dedupe in _autoBindSeriesOnPlay /
      // _rebindOnSourceSwitch, and append a duplicate pin on every play. It is
      // still stored, because re-resolution needs it; it just cannot be identity.
      // [streamKey] is the real identity: a URL-free stream profile (see
      // StremioStream.streamKey), so it survives signed/expiring links.
      return '${catalogScope}direct:${addonKey!.trim()}:${streamKey?.trim() ?? ''}';
    }
    if (isIptvDirect) {
      return 'iptv:${iptvPlaylistId!.trim()}:${iptvCatalogType!.trim()}:${iptvEntryKey!.trim()}';
    }
    if (isMediaServer) return MediaServerSource.bindingKey(debridTorrentId);
    return 'cloud:$debridService:${cloudSourceKind ?? ''}:${debridTorrentId.trim()}';
  }

  /// Group identity wins when available on both sides; older pins can still
  /// match their original profile during migration. Position is not identity.
  bool matchesAddonDirect({
    required String? candidateAddonKey,
    required String? candidateStreamKey,
    String? candidateBingeGroup,
  }) =>
      isAddonDirect &&
      addonKey == candidateAddonKey &&
      (bingeGroup != null && candidateBingeGroup != null
          ? bingeGroup == candidateBingeGroup
          : streamKey == candidateStreamKey);

  bool get isLocalMovieFile =>
      isLocal && (localKind == null || localKind == localKindMovieFile);
  bool get isLocalSeriesFolder => isLocal && localKind == localKindSeriesFolder;

  static String localSourceHash(String path) {
    final normalizedPath = path.trim();
    final digest = sha1.convert(utf8.encode(normalizedPath)).toString();
    return 'local:$digest';
  }

  /// Secret-free stable reference for provider-native items whose provider
  /// exposes only an original URL (for example AllDebrid saved links).
  static String opaqueCloudReference(String value) =>
      sha256.convert(utf8.encode(value.trim())).toString();

  Map<String, dynamic> toJson() => {
    'torrentHash': torrentHash,
    'torrentName': torrentName,
    'debridService': debridService,
    'debridTorrentId': debridTorrentId,
    if (cloudSourceKind != null) 'cloudSourceKind': cloudSourceKind,
    'boundAt': boundAt,
    if (localPath != null) 'localPath': localPath,
    if (localUri != null) 'localUri': localUri,
    if (localKind != null) 'localKind': localKind,
    if (localSizeBytes != null) 'localSizeBytes': localSizeBytes,
    if (localModifiedAt != null) 'localModifiedAt': localModifiedAt,
    if (addonId != null) 'addonId': addonId,
    if (addonKey != null) 'addonKey': addonKey,
    if (addonCatalogId != null) 'addonCatalogId': addonCatalogId,
    if (addonCatalogKey != null) 'addonCatalogKey': addonCatalogKey,
    if (streamKey != null) 'streamKey': streamKey,
    if (bingeGroup != null) 'bingeGroup': bingeGroup,
    if (streamIndex != null) 'streamIndex': streamIndex,
    if (iptvPlaylistId != null) 'iptvPlaylistId': iptvPlaylistId,
    if (iptvCatalogType != null) 'iptvCatalogType': iptvCatalogType,
    if (iptvEntryKey != null) 'iptvEntryKey': iptvEntryKey,
  };

  factory SeriesSource.fromJson(Map<String, dynamic> json) => SeriesSource(
    torrentHash: json['torrentHash'] as String? ?? '',
    torrentName: json['torrentName'] as String? ?? '',
    debridService: json['debridService'] as String? ?? 'rd',
    debridTorrentId: json['debridTorrentId'] as String? ?? '',
    cloudSourceKind: json['cloudSourceKind'] as String?,
    boundAt: json['boundAt'] as int? ?? 0,
    localPath: json['localPath'] as String?,
    localUri: json['localUri'] as String?,
    localKind: json['localKind'] as String?,
    localSizeBytes: json['localSizeBytes'] as int?,
    localModifiedAt: json['localModifiedAt'] as int?,
    addonId: json['addonId'] as String?,
    addonKey: json['addonKey'] as String?,
    addonCatalogId: json['addonCatalogId'] as String?,
    addonCatalogKey: json['addonCatalogKey'] as String?,
    streamKey: json['streamKey'] as String?,
    bingeGroup: json['bingeGroup'] as String?,
    streamIndex: json['streamIndex'] as int?,
    iptvPlaylistId: json['iptvPlaylistId'] as String?,
    iptvCatalogType: json['iptvCatalogType'] as String?,
    iptvEntryKey: json['iptvEntryKey'] as String?,
  );
}
