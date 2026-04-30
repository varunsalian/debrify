class WebDavConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String password;

  const WebDavConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  bool get isComplete => baseUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
  };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) {
    final baseUrl = (json['baseUrl'] ?? '').toString();
    final id = (json['id'] ?? '').toString().trim();
    return WebDavConfig(
      id: id.isNotEmpty ? id : DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] ?? '').toString().trim().isNotEmpty
          ? json['name'].toString().trim()
          : _defaultNameForUrl(baseUrl),
      baseUrl: baseUrl,
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }

  static String _defaultNameForUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return host;
    return baseUrl.isNotEmpty ? baseUrl : 'WebDAV';
  }
}

class WebDavItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? contentType;

  const WebDavItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
    this.modifiedAt,
    this.contentType,
  });

  String get id => path;

  WebDavItem copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    int? sizeBytes,
    DateTime? modifiedAt,
    String? contentType,
  }) {
    return WebDavItem(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      contentType: contentType ?? this.contentType,
    );
  }
}
