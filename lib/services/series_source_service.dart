import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a bound torrent source for a series.
/// When set, episode playback skips torrent search and uses this source directly.
class SeriesSource {
  static const String localService = 'local';
  static const String localKindMovieFile = 'movie_file';
  static const String localKindSeriesFolder = 'series_folder';

  final String torrentHash;
  final String torrentName;
  final String debridService; // 'rd', 'torbox', 'pikpak', 'local'
  final String debridTorrentId;
  final int boundAt; // epoch millis
  final String? localPath;
  final String? localUri;
  final String? localKind;
  final int? localSizeBytes;
  final int? localModifiedAt;

  const SeriesSource({
    required this.torrentHash,
    required this.torrentName,
    required this.debridService,
    required this.debridTorrentId,
    required this.boundAt,
    this.localPath,
    this.localUri,
    this.localKind,
    this.localSizeBytes,
    this.localModifiedAt,
  });

  bool get isLocal => debridService == localService;
  bool get isLocalMovieFile =>
      isLocal && (localKind == null || localKind == localKindMovieFile);
  bool get isLocalSeriesFolder => isLocal && localKind == localKindSeriesFolder;

  static String localSourceHash(String path) {
    final normalizedPath = path.trim();
    final digest = sha1.convert(utf8.encode(normalizedPath)).toString();
    return 'local:$digest';
  }

  Map<String, dynamic> toJson() => {
    'torrentHash': torrentHash,
    'torrentName': torrentName,
    'debridService': debridService,
    'debridTorrentId': debridTorrentId,
    'boundAt': boundAt,
    if (localPath != null) 'localPath': localPath,
    if (localUri != null) 'localUri': localUri,
    if (localKind != null) 'localKind': localKind,
    if (localSizeBytes != null) 'localSizeBytes': localSizeBytes,
    if (localModifiedAt != null) 'localModifiedAt': localModifiedAt,
  };

  factory SeriesSource.fromJson(Map<String, dynamic> json) => SeriesSource(
    torrentHash: json['torrentHash'] as String? ?? '',
    torrentName: json['torrentName'] as String? ?? '',
    debridService: json['debridService'] as String? ?? 'rd',
    debridTorrentId: json['debridTorrentId'] as String? ?? '',
    boundAt: json['boundAt'] as int? ?? 0,
    localPath: json['localPath'] as String?,
    localUri: json['localUri'] as String?,
    localKind: json['localKind'] as String?,
    localSizeBytes: json['localSizeBytes'] as int?,
    localModifiedAt: json['localModifiedAt'] as int?,
  );
}

/// Manages series-to-torrent source bindings (multiple sources per series).
/// Stores in SharedPreferences with key prefix 'series_source_'.
/// Backward compatible: reads old single-source format and migrates to list.
class SeriesSourceService {
  static const String _prefix = 'series_source_';

  /// Get all bound sources for a series, ordered by priority (first = highest).
  static Future<List<SeriesSource>> getSources(String imdbId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$imdbId');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      // New format: JSON array
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((j) => SeriesSource.fromJson(j))
            .toList();
      }
      // Old format: single JSON object — migrate
      if (decoded is Map<String, dynamic>) {
        final source = SeriesSource.fromJson(decoded);
        // Auto-migrate to list format
        await _saveSources(prefs, imdbId, [source]);
        return [source];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get the first (highest priority) source. Convenience for quick checks.
  static Future<SeriesSource?> getSource(String imdbId) async {
    final sources = await getSources(imdbId);
    return sources.isEmpty ? null : sources.first;
  }

  /// Add a source to the list (appends at end = lowest priority).
  /// Deduplicates by torrentHash — if the same hash exists, it's replaced in-place.
  static Future<void> addSource(String imdbId, SeriesSource source) async {
    final prefs = await SharedPreferences.getInstance();
    final sources = await getSources(imdbId);
    // Replace if same hash already exists
    final existingIdx = sources.indexWhere(
      (s) => s.torrentHash == source.torrentHash,
    );
    if (existingIdx >= 0) {
      sources[existingIdx] = source;
    } else {
      sources.add(source);
    }
    await _saveSources(prefs, imdbId, sources);
  }

  /// Remove a specific source by torrentHash.
  static Future<void> removeSourceByHash(
    String imdbId,
    String torrentHash,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sources = await getSources(imdbId);
    sources.removeWhere((s) => s.torrentHash == torrentHash);
    if (sources.isEmpty) {
      await prefs.remove('$_prefix$imdbId');
    } else {
      await _saveSources(prefs, imdbId, sources);
    }
  }

  /// Remove all sources for a series.
  static Future<void> removeAllSources(String imdbId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$imdbId');
  }

  /// Replace the entire source list (for reordering).
  static Future<void> setSources(
    String imdbId,
    List<SeriesSource> sources,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (sources.isEmpty) {
      await prefs.remove('$_prefix$imdbId');
    } else {
      await _saveSources(prefs, imdbId, sources);
    }
  }

  /// Check if any sources are bound.
  static Future<bool> hasSource(String imdbId) async {
    final sources = await getSources(imdbId);
    return sources.isNotEmpty;
  }

  // Keep old setSource/removeSource for backward compatibility during transition
  /// @deprecated Use addSource instead.
  static Future<void> setSource(String imdbId, SeriesSource source) =>
      addSource(imdbId, source);

  /// @deprecated Use removeAllSources instead.
  static Future<void> removeSource(String imdbId) => removeAllSources(imdbId);

  static Future<void> _saveSources(
    SharedPreferences prefs,
    String imdbId,
    List<SeriesSource> sources,
  ) async {
    final jsonList = sources.map((s) => s.toJson()).toList();
    await prefs.setString('$_prefix$imdbId', jsonEncode(jsonList));
  }
}
