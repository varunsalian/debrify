import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

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

/// "Press OK to do the thing, HOLD OK for its menu" — as a key state machine,
/// because on a remote it cannot be anything else.
///
/// `GestureDetector.onLongPress` is a POINTER gesture: a held DPAD centre
/// arrives as a key-down followed by key-repeats and never becomes a pointer
/// long-press, so a long-press callback is simply unreachable from a remote.
/// Every surface that wants the phone's long-press affordance on TV has to
/// recognise the hold itself, and this is that recogniser in one place so the
/// dwell and the haptic cannot drift between them.
///
/// Wire it into an `onKeyEvent` and let it see the OK key's full down/up pair:
///
///     if (isActivateOrSpaceKey(event.logicalKey)) return _hold.handle(event);
///
/// Reset it when focus leaves, or a key-up that arrives after the cursor has
/// moved on is read as a tap on whatever is focused now.
///
/// **[onHold] fires on RELEASE, not when the dwell elapses.** That is the
/// whole reason this class exists rather than a bare `Timer`, and it is worth
/// stating plainly because the obvious implementation is broken in a way that
/// looks like the feature was never wired up:
///
/// Opening a menu the instant the dwell elapses opens it UNDER A KEY THAT IS
/// STILL DOWN. The menu takes focus — TV menus autofocus their first item so
/// the remote has a live target — and Android is still auto-repeating the held
/// key. Flutter's default activation shortcut is
/// `SingleActivator(..., includeRepeats: true)`, so the next repeat activates
/// whatever the menu just focused. The user holds OK, and the options sheet
/// flashes open and immediately runs its first entry. On the episode cards
/// that first entry is Play, so a held OK looked exactly like a plain press
/// and the menu appeared not to exist at all.
///
/// Waiting for the key to come up costs nothing perceptible — the hand is
/// already lifting — and means the menu opens into a keyboard that is idle.
class TvHoldOk {
  TvHoldOk({
    required this.onTap,
    required this.onHold,
    this.dwell = const Duration(milliseconds: 600),
    this.hapticOnArm = true,
  });

  /// A plain press, fired on key-up when the press was short.
  final VoidCallback onTap;

  /// The long press, fired on key-up once [dwell] has elapsed under the key.
  final VoidCallback onHold;

  final Duration dwell;

  /// Buzz when the press becomes a hold, so a phone user knows they can let
  /// go. TV remotes have no motor; there the menu on release is the feedback.
  final bool hapticOnArm;

  Timer? _timer;
  bool _armed = false;

  /// Guards against a key-up whose key-down went to a different widget.
  bool _sawDown = false;

  /// True once the press has lasted long enough to count as a hold — the
  /// caller may use it to show that letting go will open the menu.
  bool get armed => _armed;

  KeyEventResult handle(KeyEvent event) {
    if (event is KeyDownEvent) {
      _sawDown = true;
      _armed = false;
      _timer?.cancel();
      _timer = Timer(dwell, _arm);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Swallowed, not ignored. These arrive under a held key, and letting
      // them through means every ancestor and shortcut sees an activation for
      // a press this widget has already claimed.
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _timer?.cancel();
      _timer = null;
      final ours = _sawDown;
      final armed = _armed;
      _sawDown = false;
      _armed = false;
      if (!ours) return KeyEventResult.handled;
      if (armed) {
        onHold();
      } else {
        onTap();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _arm() {
    _timer = null;
    if (_armed) return;
    _armed = true;
    if (hapticOnArm) HapticFeedback.mediumImpact();
  }

  /// Abandon an in-flight press — call from `onFocusChange(false)` and dispose.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _armed = false;
    _sawDown = false;
  }
}


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
