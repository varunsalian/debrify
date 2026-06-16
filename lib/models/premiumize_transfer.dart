/// A transfer entry returned by Premiumize's `/transfer/list` endpoint.
///
/// Transfers represent magnets/links queued into the cloud that may still be
/// downloading. Once finished, their content shows up in the cloud browser
/// under [folderId] (or [fileId] for a single-file transfer).
class PremiumizeTransfer {
  final String id;
  final String name;

  /// Raw status string. Known values include: waiting, queued, running,
  /// deleted, banned, error, timeout, finished, seeding.
  final String status;

  /// Progress in the range 0.0–1.0 (0 when not reported).
  final double progress;

  /// Human-readable status line (e.g. "Loading 50.0% ...").
  final String? message;

  final String? folderId;
  final String? fileId;

  const PremiumizeTransfer({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    this.message,
    this.folderId,
    this.fileId,
  });

  bool get isFinished => status == 'finished' || status == 'seeding';
  bool get isError =>
      status == 'error' ||
      status == 'timeout' ||
      status == 'banned' ||
      status == 'deleted';
  bool get isRunning => !isFinished && !isError;

  int get progressPercent => (progress.clamp(0.0, 1.0) * 100).round();

  factory PremiumizeTransfer.fromJson(Map<String, dynamic> json) {
    final folder = json['folder_id']?.toString();
    final file = json['file_id']?.toString();
    final msg = json['message']?.toString();
    return PremiumizeTransfer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Transfer',
      status: json['status']?.toString() ?? '',
      progress: _asDouble(json['progress']),
      message: (msg != null && msg.isNotEmpty) ? msg : null,
      folderId: (folder != null && folder.isNotEmpty) ? folder : null,
      fileId: (file != null && file.isNotEmpty) ? file : null,
    );
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
