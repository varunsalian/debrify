import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a bound torrent source for a series.
/// When set, episode playback skips torrent search and uses this source directly.
class SeriesSource {
  final String torrentHash;
  final String torrentName;
  final String debridService; // 'rd', 'torbox', 'pikpak'
  final String debridTorrentId;
  final int boundAt; // epoch millis

  const SeriesSource({
    required this.torrentHash,
    required this.torrentName,
    required this.debridService,
    required this.debridTorrentId,
    required this.boundAt,
  });

  Map<String, dynamic> toJson() => {
        'torrentHash': torrentHash,
        'torrentName': torrentName,
        'debridService': debridService,
        'debridTorrentId': debridTorrentId,
        'boundAt': boundAt,
      };

  factory SeriesSource.fromJson(Map<String, dynamic> json) => SeriesSource(
        torrentHash: json['torrentHash'] as String? ?? '',
        torrentName: json['torrentName'] as String? ?? '',
        debridService: json['debridService'] as String? ?? 'rd',
        debridTorrentId: json['debridTorrentId'] as String? ?? '',
        boundAt: json['boundAt'] as int? ?? 0,
      );
}

/// Manages series-to-torrent source bindings.
/// Stores in SharedPreferences with key prefix 'series_source_'.
class SeriesSourceService {
  static const String _prefix = 'series_source_';

  static Future<SeriesSource?> getSource(String imdbId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_prefix$imdbId');
    if (json == null) return null;
    try {
      return SeriesSource.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSource(String imdbId, SeriesSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$imdbId', jsonEncode(source.toJson()));
  }

  static Future<void> removeSource(String imdbId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$imdbId');
  }

  static Future<bool> hasSource(String imdbId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_prefix$imdbId');
  }
}
