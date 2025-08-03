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
      id: json['id']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      hash: json['hash']?.toString() ?? '',
      bytes: _parseInt(json['bytes']),
      host: json['host']?.toString() ?? '',
      split: _parseInt(json['split']),
      progress: _parseInt(json['progress']),
      status: json['status']?.toString() ?? '',
      added: json['added']?.toString() ?? '',
      links: _parseLinks(json['links']),
      ended: json['ended']?.toString(),
      speed: _parseInt(json['speed']),
      seeders: _parseInt(json['seeders']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static List<String> _parseLinks(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((item) => item?.toString() ?? '').toList();
    }
    return [];
  }

  bool get isDownloaded => status == 'downloaded';
} 