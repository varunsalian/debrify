import 'package:flutter/widgets.dart';

/// Per-view deferred focus requests. The caller owns layout selection, mounted
/// state, target resolution and focus nodes; this owner only retires old requests.
class HomeStageFocusRequests {
  HomeStageFocusRequests({
    required bool Function() isMounted,
    required String Function() readStyle,
  }) : _isMounted = isMounted,
       _readStyle = readStyle;

  final bool Function() _isMounted;
  final String Function() _readStyle;

  /// Bumped by every layout transition and every board reseed. Post-frame
  /// focus callbacks capture it (with the style) and bail if either moved —
  /// a callback posted by Canvas must never land focus inside Mosaic.
  int _generation = 0;

  /// A post-frame focus request that is only honoured if BOTH the layout and
  /// the stage generation are unchanged when the frame lands. Without this a
  /// callback posted by one layout can grab focus inside the next one (style
  /// switches and board reseeds both bump the generation).
  void schedule(FocusNode? Function() resolve) {
    final style = _readStyle();
    final gen = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      if (_readStyle() != style || _generation != gen) return;
      resolve()?.requestFocus();
    });
  }

  void invalidate() => _generation++;
}
