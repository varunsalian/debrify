import 'package:flutter/foundation.dart';

/// Presentation lifetime, independent of playing/paused state and sync gates.
/// Owners keep overlapping player handoffs hidden until both have closed.
abstract final class PlayerVisibility {
  static final Set<Object> _owners = {};
  static final ValueNotifier<bool> _visible = ValueNotifier(false);
  static ValueListenable<bool> get visible => _visible;

  static void opened(Object owner) {
    _owners.add(owner);
    _visible.value = _owners.isNotEmpty;
  }

  static void closed(Object owner) {
    _owners.remove(owner);
    _visible.value = _owners.isNotEmpty;
  }
}
