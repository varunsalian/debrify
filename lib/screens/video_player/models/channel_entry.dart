/// Represents a channel entry in the channel guide.
class ChannelEntry {
  final String id;
  final String name;
  final int? number;
  final bool isCurrent;
  final int order;

  const ChannelEntry({
    required this.id,
    required this.name,
    this.number,
    this.isCurrent = false,
    this.order = 0,
  });

  /// Create from a map (e.g., from JSON or method channel)
  factory ChannelEntry.fromMap(Map<String, dynamic> map, {int order = 0}) {
    return ChannelEntry(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      number: map['channelNumber'] is int
          ? map['channelNumber'] as int
          : map['number'] is int
              ? map['number'] as int
              : null,
      isCurrent: map['isCurrent'] == true,
      order: order,
    );
  }

  /// Convert to map
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'channelNumber': number,
        'isCurrent': isCurrent,
      };

  /// Check if this channel matches a search query
  bool matches(String query) {
    if (query.isEmpty) return true;

    final lowerQuery = query.toLowerCase().trim();
    final lowerName = name.toLowerCase();

    // Match by name
    if (lowerName.contains(lowerQuery)) return true;

    // Match by number (if query is numeric)
    if (number != null) {
      final plainNumber = number.toString();
      final paddedNumber = number.toString().padLeft(2, '0');
      final digitsOnly = query.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isNotEmpty) {
        if (plainNumber.contains(digitsOnly) ||
            paddedNumber.contains(digitsOnly)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Get formatted display number (zero-padded)
  String get displayNumber =>
      number != null ? number.toString().padLeft(2, '0') : '--';

  /// Get uppercase name for display
  String get displayName => name.toUpperCase();

  /// Create a copy with updated isCurrent
  ChannelEntry copyWith({bool? isCurrent}) {
    return ChannelEntry(
      id: id,
      name: name,
      number: number,
      isCurrent: isCurrent ?? this.isCurrent,
      order: order,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
