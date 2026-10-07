import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/material.dart';

class RecordingsHubFormat {
  RecordingsHubFormat(this._deps);
  final RecordingsHubDependencies _deps;
  // ── Formatting ────────────────────────────────────────────────────────────
  String fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String fmtCountdown(Duration untilStart) {
    if (untilStart.inSeconds <= 60) return 'starting…';
    if (untilStart.inMinutes < 60) return 'in ${untilStart.inMinutes}m';
    final h = untilStart.inHours;
    final m = untilStart.inMinutes.remainder(60);
    if (h < 24) return m == 0 ? 'in ${h}h' : 'in ${h}h ${m}m';
    return 'in ${untilStart.inDays}d ${h.remainder(24)}h';
  }

  String fmtDuration(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }

  String clock(int ms) =>
      MaterialLocalizations.of(_deps.context()).formatTimeOfDay(
        TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms)),
      );

  String dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d == today) return 'Today';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]} ${d.day}/${d.month}';
  }

  static final RegExp _stampSuffix = RegExp(
    r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(?:_\d+)?$',
  );

  /// Presentation facts for a library entry, derived once per build:
  /// title (file name minus stamp/extension, or the channel name), the best
  /// recorded-at moment (embedded stamp beats file mtime — mtime is the END
  /// of a capture), and a duration (store truth, else mtime − stamp).
  ({String title, String? channel, DateTime recordedAt, int? durationMs})
  displayFor(RecordingLibraryEntry entry) {
    var base = entry.name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    DateTime? stamp;
    final match = _stampSuffix.firstMatch(base);
    if (match != null) {
      base = base.substring(0, match.start);
      stamp = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }
    final title = base.replaceAll('_', ' ').trim();
    final fallback = DateTime.fromMillisecondsSinceEpoch(entry.recordedAtMs);
    final recordedAt = stamp ?? fallback;
    var durationMs = entry.durationMs;
    if (durationMs == null && stamp != null) {
      final gap = fallback.difference(stamp).inMilliseconds;
      // Only when mtime is plausibly the capture's end.
      if (gap > 1000 && gap < 12 * 60 * 60 * 1000) durationMs = gap;
    }
    return (
      title: title.isEmpty ? 'Recording' : title,
      channel: entry.channelName,
      recordedAt: recordedAt,
      durationMs: durationMs,
    );
  }
}
