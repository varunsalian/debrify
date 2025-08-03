class RDTorrent {
  final String id;
  final String filename;
  final String hash;
  final int bytes;
  final String host;
  final int split;
  final int progress;
  final String status;
  final String added;
  final List<String> links;
  final String? ended;
  final int? speed;
  final int? seeders;

  RDTorrent({
    required this.id,
    required this.filename,
    required this.hash,
    required this.bytes,
    required this.host,
    required this.split,
    required this.progress,
    required this.status,
    required this.added,
    required this.links,
    this.ended,
    this.speed,
    this.seeders,
  });

  factory RDTorrent.fromJson(Map<String, dynamic> json) {
    return RDTorrent(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      hash: json['hash'] ?? '',
      bytes: json['bytes'] ?? 0,
      host: json['host'] ?? '',
      split: json['split'] ?? 0,
      progress: json['progress'] ?? 0,
      status: json['status'] ?? '',
      added: json['added'] ?? '',
      links: List<String>.from(json['links'] ?? []),
      ended: json['ended'],
      speed: json['speed'],
      seeders: json['seeders'],
    );
  }

  bool get isDownloaded => status == 'downloaded';
} 