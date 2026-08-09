import 'package:flutter/foundation.dart';

import '../../../services/skip_segment_service.dart';

/// Publishes only skip-overlay boundary changes, never playback-position ticks.
class SkipSegmentUiController extends ValueNotifier<SkipSegment?> {
  SkipSegmentUiController() : super(null);

  void update(SkipSegment? next) {
    final current = value;
    final unchanged =
        identical(next, current) ||
        (next != null &&
            current != null &&
            next.type == current.type &&
            next.start == current.start &&
            next.end == current.end);
    if (!unchanged) value = next;
  }

  void clear() => update(null);
}
