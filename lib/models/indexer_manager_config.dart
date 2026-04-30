enum IndexerManagerType {
  jackett('jackett', 'Jackett'),
  prowlarr('prowlarr', 'Prowlarr');

  const IndexerManagerType(this.value, this.label);

  final String value;
  final String label;

  static IndexerManagerType fromValue(String? value) {
    return IndexerManagerType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => IndexerManagerType.jackett,
    );
  }
}

class IndexerManagerConfig {
  static const String enginePrefix = 'indexer_manager_';

  final String id;
  final String name;
  final IndexerManagerType type;
  final String baseUrl;
  final String apiKey;
  final bool enabled;
  final int maxResults;
  final int timeoutSeconds;
  final String jackettIndexerId;
  final List<int> categories;

  const IndexerManagerConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.apiKey,
    this.enabled = true,
    this.maxResults = 50,
    this.timeoutSeconds = 20,
    this.jackettIndexerId = 'all',
    this.categories = const [],
  });

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? type.label : trimmed;
  }

  String get normalizedBaseUrl =>
      baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  String get engineId => '$enginePrefix${_slug(displayName)}_$id';

  IndexerManagerConfig copyWith({
    String? id,
    String? name,
    IndexerManagerType? type,
    String? baseUrl,
    String? apiKey,
    bool? enabled,
    int? maxResults,
    int? timeoutSeconds,
    String? jackettIndexerId,
    List<int>? categories,
  }) {
    return IndexerManagerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
      maxResults: maxResults ?? this.maxResults,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      jackettIndexerId: jackettIndexerId ?? this.jackettIndexerId,
      categories: categories ?? this.categories,
    );
  }

  factory IndexerManagerConfig.fromJson(Map<String, dynamic> json) {
    return IndexerManagerConfig(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? '',
      type: IndexerManagerType.fromValue(json['type']?.toString()),
      baseUrl: json['base_url']?.toString() ?? '',
      apiKey: json['api_key']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? true,
      maxResults: (json['max_results'] as num?)?.toInt() ?? 50,
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt() ?? 20,
      jackettIndexerId: json['jackett_indexer_id']?.toString() ?? 'all',
      categories:
          (json['categories'] as List<dynamic>?)
              ?.map((item) => int.tryParse(item.toString()))
              .whereType<int>()
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.value,
      'base_url': baseUrl,
      'api_key': apiKey,
      'enabled': enabled,
      'max_results': maxResults,
      'timeout_seconds': timeoutSeconds,
      'jackett_indexer_id': jackettIndexerId,
      'categories': categories,
    };
  }

  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  static bool isIndexerManagerEngine(String engineId) {
    return engineId.startsWith(enginePrefix);
  }

  static String displayNameFromEngineId(String engineId) {
    if (!isIndexerManagerEngine(engineId)) return engineId;
    var value = engineId.substring(enginePrefix.length);
    value = value.replaceFirst(RegExp(r'_\d+$'), '');
    if (value.isEmpty) return 'Indexer Manager';
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static String _slug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'indexer' : slug;
  }
}
