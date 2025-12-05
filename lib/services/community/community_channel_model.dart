import 'dart:convert';

/// Represents a community channel from the manifest.json
class CommunityChannel {
  final String id;
  final String name;
  final String description;
  final String category;
  final String url;
  final String updated;
  bool isSelected;

  CommunityChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.url,
    required this.updated,
    this.isSelected = false,
  });

  factory CommunityChannel.fromJson(Map<String, dynamic> json) {
    return CommunityChannel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Channel',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'Uncategorized',
      url: json['url'] as String? ?? '',
      updated: json['updated'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'url': url,
      'updated': updated,
    };
  }
}

/// Represents the complete manifest from the community channels repository
class CommunityChannelManifest {
  final String version;
  final String lastUpdated;
  final List<CommunityChannel> channels;

  CommunityChannelManifest({
    required this.version,
    required this.lastUpdated,
    required this.channels,
  });

  factory CommunityChannelManifest.fromJson(Map<String, dynamic> json) {
    final channelsList = json['channels'] as List<dynamic>? ?? [];
    return CommunityChannelManifest(
      version: json['version'] as String? ?? '1.0',
      lastUpdated: json['last_updated'] as String? ?? '',
      channels: channelsList
          .map((channelJson) => CommunityChannel.fromJson(
                channelJson as Map<String, dynamic>,
              ))
          .toList(),
    );
  }

  static CommunityChannelManifest fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CommunityChannelManifest.fromJson(json);
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'last_updated': lastUpdated,
      'channels': channels.map((c) => c.toJson()).toList(),
    };
  }

  /// Creates a copy with selected states preserved
  CommunityChannelManifest copyWith({
    String? version,
    String? lastUpdated,
    List<CommunityChannel>? channels,
  }) {
    return CommunityChannelManifest(
      version: version ?? this.version,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      channels: channels ?? this.channels,
    );
  }
}