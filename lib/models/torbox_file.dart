class TorboxFile {
  final int id;
  final String? md5;
  final String hash;
  final String name;
  final int size;
  final bool zipped;
  final String? mimetype;
  final String shortName;
  final String? absolutePath;

  TorboxFile({
    required this.id,
    required this.md5,
    required this.hash,
    required this.name,
    required this.size,
    required this.zipped,
    required this.mimetype,
    required this.shortName,
    required this.absolutePath,
  });

  factory TorboxFile.fromJson(Map<String, dynamic> json) {
    return TorboxFile(
      id: _asInt(json['id']),
      md5: json['md5'] as String?,
      hash: json['hash'] as String? ?? '',
      name: json['name'] as String? ?? '',
      size: _asInt(json['size']),
      zipped: json['zipped'] as bool? ?? false,
      mimetype: json['mimetype'] as String?,
      shortName: json['short_name'] as String? ?? '',
      absolutePath: json['absolute_path'] as String?,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }
}
