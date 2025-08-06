class DebridDownload {
  final String id;
  final String filename;
  final String mimeType;
  final int filesize;
  final String link;
  final String host;
  final String? hostIcon;
  final int chunks;
  final String download;
  final int streamable;
  final String generated;
  final String? type;

  DebridDownload({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.filesize,
    required this.link,
    required this.host,
    this.hostIcon,
    required this.chunks,
    required this.download,
    required this.streamable,
    required this.generated,
    this.type,
  });

  factory DebridDownload.fromJson(Map<String, dynamic> json) {
    return DebridDownload(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      mimeType: json['mimeType'] ?? '',
      filesize: json['filesize'] ?? 0,
      link: json['link'] ?? '',
      host: json['host'] ?? '',
      hostIcon: json['host_icon'],
      chunks: json['chunks'] ?? 0,
      download: json['download'] ?? '',
      streamable: json['streamable'] ?? 0,
      generated: json['generated'] ?? '',
      type: json['type'],
    );
  }
} 