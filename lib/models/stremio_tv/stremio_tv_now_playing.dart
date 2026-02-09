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

  /// Formatted text showing when the slot ends (e.g., "Ends at 2:30 PM")
  String get progressText {
    final now = DateTime.now();
    if (now.isAfter(slotEnd)) return 'Ended';
    return 'Ends at ${formatTime(slotEnd)}';
  }

  /// Format a DateTime as "2:30 PM" (12-hour with AM/PM).
  static String formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final mm = minute.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }
}
