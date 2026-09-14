import 'package:flutter/foundation.dart';

/// The most recently activated folder preview temporarily owns ambient video.
/// Keyboard focus can remain while another tile is hovered: releasing the hover
/// restores the focused tile, and releasing an older tile cannot steal playback.
class CollectionFocusPlayback {
  static final owner = ValueNotifier<Object?>(null);
  static final List<Object> _claims = [];

  static void claim(Object token) {
    if (_claims.contains(token)) return;
    _claims.add(token);
    owner.value = token;
  }

  static void release(Object token) {
    _claims.remove(token);
    owner.value = _claims.lastOrNull;
  }

  static bool allows(Object? token) => identical(owner.value, token);

  @visibleForTesting
  static void reset() {
    _claims.clear();
    owner.value = null;
  }
}
