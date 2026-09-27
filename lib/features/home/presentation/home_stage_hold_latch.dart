import 'package:flutter/services.dart';

/// Per-view hold suppression shared by Mosaic and Tonight. The view retains
/// keyboard registration/removal and resets this local presentation state at
/// the existing layout transition. No timers or focus nodes are owned here.
class HomeStageHoldLatch {
  /// A hold-jump fired: swallow the REST OF THAT HOLD. Without it a single
  /// long press would jump zones and then keep acting on the cell it landed
  /// on — repeats keep arriving, and the new cell never saw the key-down that
  /// started them.
  ///
  /// Latched to the specific key until its key-up rather than to a timer: a
  /// timer both let an uninterrupted hold resume once it expired AND ate a
  /// deliberate tap made inside the window. Other keys are never affected.
  LogicalKeyboardKey? _latchedKey;

  bool swallows(LogicalKeyboardKey key) => _latchedKey == key;

  /// Perform a zone jump and latch the key. [jump] reports whether it
  /// actually moved focus — a jump that found nothing mounted must NOT latch,
  /// or the rest of the hold is swallowed for a move that never happened.
  void jump(LogicalKeyboardKey key, bool Function() jump) {
    if (swallows(key)) return;
    if (jump()) _latchedKey = key;
  }

  /// Global observer (registered with the theater handler): releases the hold
  /// latch when the key is let go. Returns false — it never consumes the key.
  /// A fresh key-DOWN of the same key also clears it, so a dropped key-up
  /// (focus change, app backgrounded) can't latch it forever.
  bool handleKeyEvent(KeyEvent event) {
    final latched = _latchedKey;
    if (latched == null) return false;
    if (event.logicalKey != latched) return false;
    if (event is KeyUpEvent || event is KeyDownEvent) {
      _latchedKey = null;
    }
    return false;
  }

  void reset() => _latchedKey = null;
}
