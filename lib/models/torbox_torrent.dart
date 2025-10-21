import 'torbox_file.dart';

class TorboxTorrent {
  final int id;
  final String authId;
  final int server;
  final String hash;
  final String name;
  final int size;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String downloadState;
  final int seeds;
  final int peers;
  final double ratio;
  final double progress;
  final int downloadSpeed;
  final int uploadSpeed;
  final int eta;
  final bool torrentFile;
  final bool downloadPresent;
  final List<TorboxFile> files;
  final bool cached;
  final bool downloadFinished;
  final DateTime? cachedAt;
  final String owner;
  final String downloadPath;

  TorboxTorrent({
    required this.id,
    required this.authId,
    required this.server,
    required this.hash,
    required this.name,
    required this.size,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    required this.downloadState,
    required this.seeds,
    required this.peers,
    required this.ratio,
    required this.progress,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.eta,
    required this.torrentFile,
    required this.downloadPresent,
    required this.files,
    required this.cached,
    required this.downloadFinished,
    required this.cachedAt,
    required this.owner,
    required this.downloadPath,
  });

  bool get isCachedOrCompleted =>
      downloadFinished ||
      downloadState.toLowerCase() == 'cached' ||
      downloadState.toLowerCase() == 'completed';

  factory TorboxTorrent.fromJson(Map<String, dynamic> json) {
    final filesJson = json['files'];
    final List<TorboxFile> parsedFiles = filesJson is List
        ? filesJson
              .whereType<Map<String, dynamic>>()
              .map((file) => TorboxFile.fromJson(file))
              .toList()
        : <TorboxFile>[];

    return TorboxTorrent(
      id: _asInt(json['id']),
      authId: json['auth_id'] as String? ?? '',
      server: _asInt(json['server']),
      hash: json['hash'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Torrent',
      size: _asInt(json['size']),
      active: json['active'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      downloadState: json['download_state'] as String? ?? 'unknown',
      seeds: _asInt(json['seeds']),
      peers: _asInt(json['peers']),
      ratio: _asDouble(json['ratio']),
      progress: _asDouble(json['progress']),
      downloadSpeed: _asInt(json['download_speed']),
      uploadSpeed: _asInt(json['upload_speed']),
      eta: _asInt(json['eta']),
      torrentFile: json['torrent_file'] as bool? ?? false,
      downloadPresent: json['download_present'] as bool? ?? false,
      files: parsedFiles,
      cached: json['cached'] as bool? ?? false,
      downloadFinished: json['download_finished'] as bool? ?? false,
      cachedAt: _tryParseDate(json['cached_at'] as String?),
      owner: json['owner'] as String? ?? '',
      downloadPath: json['download_path'] as String? ?? '',
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _tryParseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}
