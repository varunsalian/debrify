class TVChannel {
  final String id;
  final String name;
  final List<String> keywords;
  final DateTime createdAt;
  final DateTime lastUpdated;

  TVChannel({
    required this.id,
    required this.name,
    required this.keywords,
    required this.createdAt,
    required this.lastUpdated,
  });

  factory TVChannel.fromJson(Map<String, dynamic> json) {
    return TVChannel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      keywords: List<String>.from(json['keywords'] ?? []),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: DateTime.parse(json['lastUpdated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keywords': keywords,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  TVChannel copyWith({
    String? id,
    String? name,
    List<String>? keywords,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return TVChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
} 