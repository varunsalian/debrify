import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
/// [onHold] fires the moment [dwell] elapses, WHILE the key is still down —
/// the menu should appear under your thumb, not after you let go, which is
/// what a long press means everywhere else and what the app's other held-OK
/// surfaces already do.
///
/// **That puts one obligation on whatever [onHold] opens: wrap it in a
/// [TvHeldKeyGuard].** The menu arrives under a key that is still held, and
/// Android keeps auto-repeating it. Flutter's default activation shortcut is
/// `SingleActivator(..., includeRepeats: true)`, so if the menu autofocuses an
/// entry — TV menus do, so the remote has a live target — the next repeat
/// activates it. The episode sheet autofocuses Play, so a held OK opened the
/// sheet and instantly played the episode: indistinguishable from a plain
/// press, which is why the gesture looked like it had never been wired up.
/// The app's other hold menus survive only because they autofocus nothing.
class TvHoldOk {
  TvHoldOk({
    required this.onTap,
    required this.onHold,
    this.dwell = const Duration(milliseconds: 600),
    this.haptic = true,
  });

  /// A plain press, fired on key-up when the press was short.
  final VoidCallback onTap;

  /// The long press, fired under the key once [dwell] has elapsed.
  final VoidCallback onHold;

  final Duration dwell;

  /// Buzz when the hold fires. A TV remote has no motor; there the menu
  /// appearing is the feedback.
  final bool haptic;

  Timer? _timer;
  bool _fired = false;

  /// Guards against a key-up whose key-down went to a different widget.
  bool _sawDown = false;

  /// Whether this press has already become a hold.
  bool get holdFired => _fired;

  KeyEventResult handle(KeyEvent event) {
    if (event is KeyDownEvent) {
      _sawDown = true;
      _fired = false;
      _timer?.cancel();
      _timer = Timer(dwell, _fire);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Swallowed, not ignored: these arrive under a key this widget has
      // already claimed, and passing them on hands the shortcut layer an
      // activation for a press that is spoken for.
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _timer?.cancel();
      _timer = null;
      final ours = _sawDown;
      final fired = _fired;
      _sawDown = false;
      _fired = false;
      if (!ours) return KeyEventResult.handled;
      // The hold already did its work; the release is just the end of it.
      if (!fired) onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _fire() {
    _timer = null;
    if (_fired) return;
    _fired = true;
    if (haptic) HapticFeedback.mediumImpact();
    onHold();
  }

  /// Abandon an in-flight press — call from `onFocusChange(false)` and dispose.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _fired = false;
    _sawDown = false;
  }
}

/// Eats the tail of the press that opened this subtree.
///
/// Wrap the content of any menu, sheet or dialog opened by [TvHoldOk.onHold].
/// The menu appears while the key is still down and Android keeps repeating
/// it; without this the first repeat activates whatever the menu autofocused,
/// closing it again before the user has let go. Swallowing activation REPEATS
/// is right for a menu regardless — a held OK should never machine-gun the
/// entry under the cursor.
///
/// It sits between the menu's focused entry and the app-level `Shortcuts`, so
/// it sees the repeat first. A nested `Shortcuts` cannot do this job: an
/// activator that declines an event does not block it, it just lets it travel
/// on to the app-level binding that accepts it.
class TvHeldKeyGuard extends StatelessWidget {
  const TvHeldKeyGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) =>
            event is KeyRepeatEvent && isActivateOrSpaceKey(event.logicalKey)
                ? KeyEventResult.handled
                : KeyEventResult.ignored,
        child: child,
      );
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
