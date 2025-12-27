import '../debrify_tv_channel_record.dart';

/// Represents a Debrify TV channel configuration.
///
/// This is an internal model used by the Debrify TV screen to manage
/// channel state. It can be converted to/from [DebrifyTvChannelRecord]
/// for persistence.
class DebrifyTvChannel {
  final String id;
  final String name;
  final List<String> keywords;
  final bool avoidNsfw; // Per-channel NSFW filter setting
  final int channelNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DebrifyTvChannel({
    required this.id,
    required this.name,
    required this.keywords,
    required this.avoidNsfw,
    required this.channelNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DebrifyTvChannel.fromJson(Map<String, dynamic> json) {
    final dynamic keywordsRaw = json['keywords'];
    final List<String> keywords;
    if (keywordsRaw is List) {
      keywords = keywordsRaw
          .map((e) => (e?.toString() ?? '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (keywordsRaw is String && keywordsRaw.isNotEmpty) {
      keywords = keywordsRaw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      keywords = const <String>[];
    }
    return DebrifyTvChannel(
      id: (json['id'] as String?)?.trim().isNotEmpty ?? false
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?)?.trim().isNotEmpty ?? false
          ? (json['name'] as String).trim()
          : 'Unnamed Channel',
      keywords: keywords,
      avoidNsfw: json['avoidNsfw'] is bool
          ? json['avoidNsfw'] as bool
          : true, // Default to enabled for backward compatibility
      channelNumber: json['channelNumber'] is int
          ? (json['channelNumber'] as int)
          : 0,
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.now(),
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : DateTime.now(),
    );
  }

  factory DebrifyTvChannel.fromRecord(DebrifyTvChannelRecord record) {
    return DebrifyTvChannel(
      id: record.channelId,
      name: record.name,
      keywords: record.keywords,
      avoidNsfw: record.avoidNsfw,
      channelNumber: record.channelNumber,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keywords': keywords,
      'avoidNsfw': avoidNsfw,
      'channelNumber': channelNumber,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  DebrifyTvChannel copyWith({
    String? id,
    String? name,
    List<String>? keywords,
    bool? avoidNsfw,
    int? channelNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DebrifyTvChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      avoidNsfw: avoidNsfw ?? this.avoidNsfw,
      channelNumber: channelNumber ?? this.channelNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  DebrifyTvChannelRecord toRecord() {
    return DebrifyTvChannelRecord(
      channelId: id,
      name: name,
      keywords: keywords,
      avoidNsfw: avoidNsfw,
      channelNumber: channelNumber,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
