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
