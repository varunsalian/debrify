/// Per-view preview intent: playback suppression and once-per-rest attempts.
/// This is local navigation state; it does not own services, timers or UI signals.
class HomeHeroPreviewPolicy {
  bool _suppressed = false;
  String? _scheduledItemId;
  String? _attemptedItemId;

  /// A new applied hero or a nonempty board reseed is fresh viewing context.
  /// Keep the attempt marker: its reset points are deliberately independent.
  void allowNewHero() => _suppressed = false;

  /// Moving focus elsewhere permits another attempt; returning to the same
  /// title without leaving does not repeatedly resolve an unavailable trailer.
  void focus(String itemId) {
    if (_attemptedItemId != itemId) _attemptedItemId = null;
  }

  void resetAttempt() => _attemptedItemId = null;
  bool hasAttempted(String itemId) => _attemptedItemId == itemId;
  void recordAttempt(String itemId) => _attemptedItemId = itemId;

  /// Off-TV Spotlight has its own cadence and may lift suppression for a new
  /// title here. Evaluate the existing render/settings gate in its original
  /// position, before suppression rejection, then remember the admitted id.
  /// Layout/favourite/attempt gates intentionally run later in the caller.
  bool admitSchedule(
    String itemId, {
    required bool fromSpotlight,
    required bool Function() renderableAndEnabled,
  }) {
    if (_suppressed && fromSpotlight && itemId != _scheduledItemId) {
      _suppressed = false;
    }
    if (!renderableAndEnabled() || _suppressed) return false;
    _scheduledItemId = itemId;
    return true;
  }

  /// Playback can start before a dwell, or after A→B while B is still pending.
  /// Capture the visible hero after setting suppression, matching launch order;
  /// a missing visible id preserves the previous schedule baseline.
  void suppressForPlayback(String? Function() currentHeroId) {
    _suppressed = true;
    final showing = currentHeroId();
    if (showing != null) _scheduledItemId = showing;
  }
}
