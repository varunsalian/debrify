import 'package:flutter/services.dart';

/// Returns `true` when [key] is a D-pad / remote "OK" (activation) key.
///
/// Android TV remotes are inconsistent about which keycode the center / OK
/// button emits: some send `KEYCODE_DPAD_CENTER` (-> [LogicalKeyboardKey.select]),
/// others send `KEYCODE_ENTER` (-> [LogicalKeyboardKey.enter]),
/// `KEYCODE_NUMPAD_ENTER` (-> [LogicalKeyboardKey.numpadEnter]) or
/// `KEYCODE_BUTTON_A` (-> [LogicalKeyboardKey.gameButtonA], common on gamepad-
/// style remotes). Routing every `onKeyEvent` activation check through this
/// helper guarantees the OK button works regardless of which keycode a given
/// remote happens to send.
///
/// Note: [LogicalKeyboardKey.space] is intentionally NOT included here. Some
/// screens treat space as activation and others do not; callers that already
/// handle space keep handling it explicitly so this helper stays purely
/// additive (it only ever broadens coverage to the remote OK keycodes).
bool isActivateKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA;

/// [isActivateKey] plus the space bar — for custom widgets that replace
/// Material controls (InkWell, PopupMenuButton, buttons), which accepted
/// space through ActivateIntent, so keyboard users keep it.
bool isActivateOrSpaceKey(LogicalKeyboardKey key) =>
    isActivateKey(key) || key == LogicalKeyboardKey.space;


/// A one-shot signal that an in-player overlay closed itself in response to a
/// BACK/ESCAPE key.
///
/// Those overlays listen through a `KeyboardListener`, which cannot consume an
/// event — so the same press bubbles on to the player, which would then pop the
/// whole screen. The player consumes this signal to ignore that tail. Scoped to
/// key-driven closes only: a close by OK, tap or selection must NOT swallow the
/// user's next deliberate BACK.
class TvOverlayBack {
  TvOverlayBack._();

  static bool _pending = false;

  /// Called by an overlay just before it closes itself from a BACK key.
  static void mark() => _pending = true;

  /// True once, for the press that closed an overlay.
  static bool consume() {
    final was = _pending;
    _pending = false;
    return was;
  }
}
