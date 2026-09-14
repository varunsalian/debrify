import '../../../models/stremio_subtitle.dart';
import '../../../models/subtitle_source_priority.dart';

class SubtitlePriorityUpdate {
  final int token;
  final List<AddonSubtitleSlot> slots;
  final bool discoveryReady;

  const SubtitlePriorityUpdate(
    this.token,
    this.slots, {
    this.discoveryReady = true,
  });
}

/// Serialize player writes without losing updates that arrive during an apply.
/// A new media generation can proceed independently of stale downloads.
class SubtitlePrioritySelectionQueue {
  int? _token;
  SubtitlePriorityUpdate? _pending;
  Future<void>? _running;

  Future<void> submit(
    SubtitlePriorityUpdate update,
    Future<void> Function(SubtitlePriorityUpdate) apply,
  ) {
    if (_token != update.token) {
      _token = update.token;
      _running = null;
    }
    _pending = update;
    return _running ??= Future.microtask(() async {
      try {
        while (_token == update.token && _pending != null) {
          final next = _pending!;
          _pending = null;
          await apply(next);
        }
      } finally {
        if (_token == update.token) _running = null;
      }
    });
  }
}

class SubtitlePriorityResult {
  final StremioSubtitle? addon;
  final bool provisional;

  const SubtitlePriorityResult.embedded({this.provisional = false})
    : addon = null;
  const SubtitlePriorityResult.addon(this.addon) : provisional = false;
}

/// Only an unresolved source ABOVE the current candidate can delay selection.
Future<SubtitlePriorityResult?> selectSubtitleBySourcePriority({
  required List<String> saved,
  required String? language,
  required List<AddonSubtitleSlot> slots,
  required bool discoveryReady,
  required bool Function() isCurrent,
  required Future<bool> Function() tryEmbedded,
  required Future<bool> Function(StremioSubtitle) tryAddon,
}) async {
  if (!isCurrent() || language == 'off') return null;
  if (!discoveryReady) {
    // Metadata may still discover addon candidates. Keep subtitles usable now,
    // but do not let this provisional embedded choice block later discovery.
    final applied = await tryEmbedded();
    if (!isCurrent() || !applied) return null;
    return SubtitlePriorityResult.embedded(
      provisional:
          SubtitleSourcePriority.normalize(saved).first !=
          SubtitleSourcePriority.embedded,
    );
  }
  final order = SubtitleSourcePriority.effective(
    saved,
    slots.map((s) => s.priorityId),
  );
  final triedUrls = <String>{};
  for (final source in order) {
    if (!isCurrent()) return null;
    if (source == SubtitleSourcePriority.embedded) {
      final applied = await tryEmbedded();
      if (!isCurrent()) return null;
      if (applied) return const SubtitlePriorityResult.embedded();
      continue;
    }
    for (final slot in slots.where(
      (s) => SubtitleSourcePriority.addon(s.priorityId) == source,
    )) {
      if (slot.status == AddonSubtitleStatus.loading) return null;
      for (final sub in SubtitleSourcePriority.matching(
        slot.subtitles,
        language,
      )) {
        if (!triedUrls.add(sub.url)) continue;
        final applied = await tryAddon(sub);
        if (!isCurrent()) return null;
        if (applied) return SubtitlePriorityResult.addon(sub);
      }
    }
  }
  return null;
}
