/// A magnet (torrent) on the user's AllDebrid account, as returned by
/// `/v4.1/magnet/status`. AllDebrid's "cloud" is a flat list of these — each
/// magnet has files that are fetched separately via `magnet/files`.
class AllDebridMagnet {
  final String id;
  final String name;
  final int size;

  /// AllDebrid status code: 0–3 = processing/downloading, 4 = ready,
  /// >= 5 = error.
  final int statusCode;
  final String statusText;

  /// Fraction downloaded (0.0–1.0) when still processing; 1.0 when ready.
  final double progress;

  AllDebridMagnet({
    required this.id,
    required this.name,
    required this.size,
    required this.statusCode,
    required this.statusText,
    required this.progress,
  });

  bool get isReady => statusCode == 4;
  bool get isError => statusCode >= 5;
  bool get isProcessing => statusCode >= 0 && statusCode <= 3;

  int get progressPercent => (progress.clamp(0.0, 1.0) * 100).round();

  factory AllDebridMagnet.fromJson(Map<String, dynamic> json) {
    final size = _asInt(json['size']);
    final downloaded = _asInt(json['downloaded']);
    final code = _asInt(json['statusCode']);
    double progress;
    if (code == 4) {
      progress = 1.0;
    } else if (size > 0) {
      progress = (downloaded / size).clamp(0.0, 1.0);
    } else {
      progress = 0.0;
    }
    return AllDebridMagnet(
      id: json['id']?.toString() ?? '',
      name: (json['filename'] ?? json['name'] ?? '').toString(),
      size: size,
      statusCode: code,
      statusText: (json['status'] ?? '').toString(),
      progress: progress,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
