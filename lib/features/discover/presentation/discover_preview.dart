import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/youtube_resolved_streams.dart';

/// One Discover view's presentation feed, shared by its detail rail and stage.
/// The rail still owns resolution and the stage owns native playback; both
/// borrow these signals. This owner coordinates visual resets and idle theater.
class DiscoverPreview {
  DiscoverPreview({required bool Function() isCurrent})
    : _isCurrent = isCurrent;

  final bool Function() _isCurrent;
  final streams = ValueNotifier<YoutubeResolvedStreams?>(null);
  final loading = ValueNotifier(false);
  final volume = ValueNotifier(0.0);
  final takeover = ValueNotifier(0.0);

  /// Enriched identity of the playing trailer, used by fullscreen takeover.
  final meta = ValueNotifier<StremioMeta?>(null);

  /// What the rail actually displays, including its accepted enrichment.
  final shown = ValueNotifier<StremioMeta?>(null);
  final showing = ValueNotifier(false);
  final theater = ValueNotifier(false);
  Timer? _theaterTimer;
  bool _observing = false;
  bool _disposed = false;

  /// The host enables this at the original TV Discover registration point.
  void observePlayback() {
    if (_disposed || _observing) return;
    _observing = true;
    showing.addListener(_showingChanged);
  }

  void stopObservingPlayback() {
    if (_observing) {
      showing.removeListener(_showingChanged);
      _observing = false;
    }
    _cancelTheater();
  }

  void _cancelTheater() {
    _theaterTimer?.cancel();
    _theaterTimer = null;
  }

  void _showingChanged() {
    if (_disposed) return;
    _cancelTheater();
    if (showing.value) {
      _theaterTimer = Timer(const Duration(seconds: 5), () {
        _theaterTimer = null;
        if (!_disposed && _isCurrent() && showing.value) theater.value = true;
      });
    } else {
      theater.value = false;
    }
  }

  /// Hover or a grid-boundary key can leave the same trailer playing. Restore
  /// controls now and rearm the idle dwell even without a playback change.
  void onActivity() {
    if (_disposed) return;
    if (theater.value) theater.value = false;
    _showingChanged();
  }

  /// Layout/source transitions tear down playback before rebuilding its tree.
  /// Keep notifier order: listeners may synchronously relay these changes.
  void resetPlayback() {
    if (_disposed) return;
    streams.value = null;
    meta.value = null;
    loading.value = false;
    showing.value = false;
    theater.value = false;
    _cancelTheater();
    takeover.value = 0;
  }

  bool get needsCompactReset =>
      takeover.value != 0 || showing.value || theater.value;

  /// The host calls this post-frame when a compact canvas unmounts the stage.
  /// Streams, enrichment and volume are deliberately retained.
  void clearCompactEffects() {
    if (_disposed) return;
    takeover.value = 0;
    showing.value = false;
    theater.value = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopObservingPlayback();
    streams.dispose();
    loading.dispose();
    volume.dispose();
    takeover.dispose();
    meta.dispose();
    shown.dispose();
    showing.dispose();
    theater.dispose();
  }
}
