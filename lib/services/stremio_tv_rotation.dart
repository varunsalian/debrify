import '../models/stremio_addon.dart';
import '../models/stremio_tv/stremio_tv_now_playing.dart';

/// Stable 31-bit DJB2 hash shared by daily catalog paging and slot selection.
int stremioTvStableHash(String input) {
  int hash = 5381;
  for (int i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.codeUnitAt(i); // hash * 33 + c
    hash = hash & 0x7FFFFFFF; // Keep positive 31-bit
  }
  return hash;
}

/// Per-channel time offset so each channel has independent slot boundaries.
/// Applies integer mixing after DJB2 to ensure good distribution even for
/// IDs that differ only in their suffix (e.g., genre years like 1975, 1976).
int _channelOffsetMs(String channelId, int slotDurationMs) {
  var h = stremioTvStableHash(channelId);
  // Murmur3-style finalizer for better bit distribution
  h = (((h >> 16) ^ h) * 0x45d9f3b) & 0x7FFFFFFF;
  h = (((h >> 16) ^ h) * 0x45d9f3b) & 0x7FFFFFFF;
  h = (h >> 16) ^ h;
  return (h % slotDurationMs).abs();
}

/// Selects one slot using the caller's clock, without reading service state.
StremioTvNowPlaying? stremioTvPlayingAt({
  required String channelId,
  required List<StremioMeta> items,
  required DateTime now,
  int slotOffset = 0,
  int rotationMinutes = 90,
  int salt = 0,
}) {
  if (items.isEmpty) return null;

  final slotDurationMs = rotationMinutes * 60 * 1000;
  final offset = _channelOffsetMs(channelId, slotDurationMs);
  final adjusted = now.millisecondsSinceEpoch - offset;
  final slotNumber = (adjusted ~/ slotDurationMs) + slotOffset;

  final seed = salt == 0
      ? '$channelId:$slotNumber'
      : '$channelId:$slotNumber:$salt';
  final hash = stremioTvStableHash(seed);
  final index = hash % items.length;

  final slotStartMs = slotNumber * slotDurationMs + offset;
  final slotStart = DateTime.fromMillisecondsSinceEpoch(slotStartMs);
  final slotEnd = DateTime.fromMillisecondsSinceEpoch(
    slotStartMs + slotDurationMs,
  );

  return StremioTvNowPlaying(
    item: items[index],
    itemIndex: index,
    slotStart: slotStart,
    slotEnd: slotEnd,
  );
}

/// Builds a schedule from one captured clock value.
List<StremioTvNowPlaying> stremioTvSchedule({
  required String channelId,
  required List<StremioMeta> items,
  required DateTime now,
  int count = 5,
  int rotationMinutes = 90,
  int salt = 0,
}) {
  if (items.isEmpty) return [];

  final slotDurationMs = rotationMinutes * 60 * 1000;
  final offset = _channelOffsetMs(channelId, slotDurationMs);
  final adjusted = now.millisecondsSinceEpoch - offset;
  final currentSlotNumber = adjusted ~/ slotDurationMs;

  final schedule = <StremioTvNowPlaying>[];
  for (int i = 0; i < count; i++) {
    final slotNumber = currentSlotNumber + i;
    final seed = salt == 0
        ? '$channelId:$slotNumber'
        : '$channelId:$slotNumber:$salt';
    final hash = stremioTvStableHash(seed);
    final index = hash % items.length;

    final slotStartMs = slotNumber * slotDurationMs + offset;
    final slotStart = DateTime.fromMillisecondsSinceEpoch(slotStartMs);
    final slotEnd = DateTime.fromMillisecondsSinceEpoch(
      slotStartMs + slotDurationMs,
    );

    schedule.add(
      StremioTvNowPlaying(
        item: items[index],
        itemIndex: index,
        slotStart: slotStart,
        slotEnd: slotEnd,
      ),
    );
  }

  return schedule;
}
