/// Protects a stored resume point from being overwritten by a shallow position
/// after a resume seek was requested but never landed.
///
/// The failure this exists for: the Flutter player commits a startup candidate
/// as soon as ~40ms of media decodes, then immediately seeks to the stored
/// position. On a freshly-opened remote (debrid) stream mpv can answer that
/// seek by flushing and restarting the stream at 0 instead of landing on the
/// target — playback then runs from the beginning, and the ordinary autosave
/// files that near-zero position over the good one. One failed resume
/// permanently destroyed the bookmark.
///
/// The rule is deliberately narrow and self-releasing. A write is blocked only
/// while a requested resume has neither landed nor been superseded:
///
/// * position reached the target (within [toleranceMs]) — the resume worked,
///   stop guarding;
/// * the user seeked — they own the position now, stop guarding;
/// * [settleWindow] elapsed since the request — they are watching from
///   wherever playback actually is, so let their progress be saved.
///
/// Everything else falls through to a normal save, so the guard can never
/// silently strand a session's progress.
class ResumeWriteGuard {
  ResumeWriteGuard({
    this.settleWindow = const Duration(seconds: 30),
    this.toleranceMs = 10000,
  });

  /// How long a requested-but-unlanded resume keeps blocking shallow writes.
  final Duration settleWindow;

  /// How close to the target counts as landed. Seeks resolve to the nearest
  /// keyframe, so an exact match is never guaranteed.
  final int toleranceMs;

  int? _targetMs;
  DateTime? _requestedAt;

  /// The resume position currently being protected, if any.
  int? get pendingTargetMs => _targetMs;

  /// Records that a seek to [targetMs] was requested. A non-positive target is
  /// not a resume (fresh start) and arms nothing.
  void arm(int targetMs, {DateTime? now}) {
    if (targetMs <= 0) {
      clear();
      return;
    }
    _targetMs = targetMs;
    _requestedAt = now ?? DateTime.now();
  }

  /// Stops guarding — the resume landed, was superseded, or the item changed.
  void clear() {
    _targetMs = null;
    _requestedAt = null;
  }

  /// The user took control of the position; their choice outranks the resume.
  void noteUserSeek() => clear();

  /// Whether [positionMs] may be written to the resume store.
  ///
  /// Self-releasing: a landed seek or an elapsed [settleWindow] clears the
  /// guard here, so callers need no separate bookkeeping.
  bool allowsPersist(int positionMs, {DateTime? now}) {
    final target = _targetMs;
    if (target == null) return true;
    if (positionMs >= target - toleranceMs) {
      clear();
      return true;
    }
    final requestedAt = _requestedAt;
    if (requestedAt != null &&
        (now ?? DateTime.now()).difference(requestedAt) >= settleWindow) {
      clear();
      return true;
    }
    return false;
  }

  /// Pure query: the target that would be written INSTEAD of [positionMs] if
  /// a write happened right now, or null when [positionMs] is fine as-is.
  /// Unlike [allowsPersist] this never releases the guard — use it when
  /// capturing a position for later (e.g. a source switch checkpoint) without
  /// consuming the protection.
  int? heldTargetIfBlocked(int positionMs, {DateTime? now}) {
    final target = _targetMs;
    if (target == null) return null;
    if (positionMs >= target - toleranceMs) return null;
    final requestedAt = _requestedAt;
    if (requestedAt != null &&
        (now ?? DateTime.now()).difference(requestedAt) >= settleWindow) {
      return null;
    }
    return target;
  }
}
