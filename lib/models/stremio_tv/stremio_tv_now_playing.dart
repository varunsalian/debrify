import '../stremio_addon.dart';

/// Represents the "now playing" state for a Stremio TV channel.
///
/// Contains the currently playing item, its time slot boundaries,
/// and a progress getter for UI display.
class StremioTvNowPlaying {
  /// The currently playing catalog item
  final StremioMeta item;

  /// Index of this item within the channel's items list
  final int itemIndex;

  /// When this time slot started
  final DateTime slotStart;

  /// When this time slot ends
  final DateTime slotEnd;

  const StremioTvNowPlaying({
    required this.item,
    required this.itemIndex,
    required this.slotStart,
    required this.slotEnd,
  });

  /// Progress through the current slot (0.0 to 1.0)
  double get progress {
    final now = DateTime.now();
    if (now.isBefore(slotStart)) return 0.0;
    if (now.isAfter(slotEnd)) return 1.0;
    final total = slotEnd.difference(slotStart).inMilliseconds;
    if (total <= 0) return 0.0;
    final elapsed = now.difference(slotStart).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// Formatted progress percentage string (e.g., "23% complete")
  String get progressText {
    final pct = (progress * 100).round();
    return '$pct% complete';
  }
}
