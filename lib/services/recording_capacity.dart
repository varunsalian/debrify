import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'desktop_recording_service.dart';
import 'desktop_schedule_service.dart';
import 'live_recording_service.dart';

/// Capacity math + conflict discovery for the simultaneous-recordings limit.
///
/// Every record/schedule entry point asks here BEFORE committing, so the
/// user hears "this conflicts with X and Y" while they can still do
/// something about it (raise the limit, cancel something) instead of a
/// recording silently losing at fire time.

/// A capacity conflict: what the limit is, and which existing items occupy
/// the slots inside the contested window.
class RecordingCapacityConflict {
  final int limit;

  /// Display labels of the occupying items (live captures and/or schedules),
  /// deduplicated, in encounter order.
  final List<String> busyLabels;

  const RecordingCapacityConflict({
    required this.limit,
    required this.busyLabels,
  });
}

/// Peak number of [intervals] simultaneously active anywhere inside
/// [startMs, endMs) — the candidate window itself is NOT counted. Intervals
/// are half-open `[start, stop)`, so back-to-back items (one ending exactly
/// when the next starts) never overlap.
int peakOverlap(List<(int, int)> intervals, int startMs, int endMs) {
  final events = <(int, int)>[];
  for (final (start, stop) in intervals) {
    final s = start < startMs ? startMs : start;
    final e = stop > endMs ? endMs : stop;
    if (e <= s) continue; // outside (or degenerate inside) the window
    events.add((s, 1));
    events.add((e, -1));
  }
  // Ends before starts at the same timestamp: adjacency is not overlap.
  events.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  var current = 0;
  var peak = 0;
  for (final (_, delta) in events) {
    current += delta;
    if (current > peak) peak = current;
  }
  return peak;
}

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

/// Would starting a recording RIGHT NOW exceed the limit? Null = no
/// conflict, go ahead.
Future<RecordingCapacityConflict?> checkRecordNowCapacity() async {
  final limit = await LiveRecordingService.maxConcurrent();
  final labels = <String>[];
  if (_isAndroid) {
    final live = await LiveRecordingService.query();
    for (final r in live) {
      if (r.isRecording) {
        labels.add(r.channelName.isEmpty ? r.fileName : r.channelName);
      }
    }
  } else if (DesktopRecordingService.instance.isSupported) {
    for (final c in DesktopRecordingService.instance.captures) {
      labels.add(c.channelName);
    }
  } else {
    return null;
  }
  if (labels.length < limit) return null;
  return RecordingCapacityConflict(limit: limit, busyLabels: labels);
}

/// Would a schedule over [startMs, endMs) push some moment past the limit?
/// Counts existing schedules that overlap the window and — when the window
/// includes "now" (a record-the-rest / starts-immediately schedule) — the
/// currently-live captures, whose end nobody knows, as occupying the whole
/// window. Null = no conflict.
///
/// [candidateUrl] excludes an exact duplicate (same url + start) of the
/// candidate from the count: re-scheduling an already-scheduled programme is
/// the backend's `duplicate` answer, not a capacity conflict — without this,
/// the conflict dialog would name the very programme the user clicked and
/// coach them into raising the limit for a no-op.
Future<RecordingCapacityConflict?> checkScheduleCapacity({
  required int startMs,
  required int endMs,
  String? candidateUrl,
}) async {
  final limit = await LiveRecordingService.maxConcurrent();
  final intervals = <(int, int)>[];
  final labels = <String>[];

  void add(int start, int stop, String label) {
    final s = start < startMs ? startMs : start;
    final e = stop > endMs ? endMs : stop;
    if (e <= s) return;
    intervals.add((start, stop));
    if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
  }

  final schedules = _isAndroid
      ? await LiveRecordingService.listSchedules()
      : DesktopScheduleService.instance.isSupported
      ? (await DesktopScheduleService.instance.list())
            .map((s) => s.toScheduledRecording())
            .toList(growable: false)
      : const <ScheduledRecording>[];
  for (final s in schedules) {
    if (candidateUrl != null &&
        s.url == candidateUrl &&
        s.startMs == startMs) {
      continue;
    }
    add(
      s.startMs,
      s.endMs,
      s.programmeTitle.isEmpty ? s.channelName : s.programmeTitle,
    );
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  if (startMs <= now && endMs > now) {
    if (_isAndroid) {
      for (final r in await LiveRecordingService.query()) {
        if (r.isRecording) {
          add(
            startMs,
            endMs,
            r.channelName.isEmpty ? r.fileName : r.channelName,
          );
        }
      }
    } else if (DesktopRecordingService.instance.isSupported) {
      for (final c in DesktopRecordingService.instance.captures) {
        add(startMs, endMs, c.channelName);
      }
    }
  }

  if (peakOverlap(intervals, startMs, endMs) + 1 <= limit) return null;
  return RecordingCapacityConflict(limit: limit, busyLabels: labels);
}
