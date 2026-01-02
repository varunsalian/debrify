import 'torbox_file.dart';

class TorboxWebDownload {
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
  final String originalUrl;
  final double progress;
  final int downloadSpeed;
  final int eta;
  final bool downloadPresent;
  final List<TorboxFile> files;
  final bool cached;
  final bool downloadFinished;
  final DateTime? cachedAt;
  final DateTime? expiresAt;
  final String? error;

  TorboxWebDownload({
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
    required this.originalUrl,
    required this.progress,
    required this.downloadSpeed,
    required this.eta,
    required this.downloadPresent,
    required this.files,
    required this.cached,
    required this.downloadFinished,
    required this.cachedAt,
    required this.expiresAt,
    required this.error,
  });

  bool get isCompleted => downloadState.toLowerCase() == 'completed';

  factory TorboxWebDownload.fromJson(Map<String, dynamic> json) {
    final filesJson = json['files'];
    final List<TorboxFile> parsedFiles = filesJson is List
        ? filesJson
              .whereType<Map<String, dynamic>>()
              .map((file) => TorboxFile.fromJson(file))
              .toList()
        : <TorboxFile>[];

    return TorboxWebDownload(
      id: _asInt(json['id']),
      authId: json['auth_id'] as String? ?? '',
      server: _asInt(json['server']),
      hash: json['hash'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Download',
      size: _asInt(json['size']),
      active: json['active'] as bool? ?? false,
      createdAt: _parseDate(json['created_at'] as String?) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at'] as String?) ?? DateTime.now(),
      downloadState: json['download_state'] as String? ?? 'unknown',
      originalUrl: json['original_url'] as String? ?? '',
      progress: _asDouble(json['progress']),
      downloadSpeed: _asInt(json['download_speed']),
      eta: _asInt(json['eta']),
      downloadPresent: json['download_present'] as bool? ?? false,
      files: parsedFiles,
      cached: json['cached'] as bool? ?? false,
      downloadFinished: json['download_finished'] as bool? ?? false,
      cachedAt: _parseDate(json['cached_at'] as String?),
      expiresAt: _parseDate(json['expires_at'] as String?),
      error: json['error'] as String?,
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

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}
