import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/storage_service.dart';
import '../utils/platform_util.dart';
import 'app_sound.dart';
import 'app_surfaces.dart';
import 'app_theme_controller.dart';

/// Turns focus changes into feedback — but only the ones a human caused.
///
/// ## Why this is not a `FocusManager` listener
///
/// It would be three lines, and it would be wrong. `FocusManager` notifies on
/// dialog autofocus, on route entry, on every one of the ~776 programmatic
/// `requestFocus` restorations this app performs (returning from the player,
/// rebuilding a shelf, restoring a remembered row), on IME focus and on
/// pointer focus. A tick on all of those is not "a bit noisy" — it is a burst
/// of clicks every time a screen appears, which is exactly the cheapness this
/// whole vocabulary exists to remove.
///
/// ## Causal attribution
///
/// A focus change may make a sound only if it can produce EVIDENCE that a
/// human moved the cursor:
///
/// * a root key handler mints a one-shot token for **directional key-down and
///   key-repeat only**. Key-up never mints. Select and back never mint — so a
///   select that pushes a route cannot authorise the new route's autofocus;
/// * a focus change consumes a token **younger than [_tokenLife]**, and each
///   token is consumed by **at most one** focus change. Programmatic focus
///   finds no token and stays silent;
/// * held-DPAD repeats DO mint (each repeat is a real traversal), so the
///   [_minGap] rate limiter is the stated defence against repeat-series spam
///   rather than an accident of timing;
/// * everything is muted while [AppSurfaceState] reports a frozen surface —
///   the player and the launch ident own the screen and their own audio.
///
/// Activation feedback is NOT inferred from focus. It is an explicit
/// [activate] call at the existing chokepoints, for the same reason: the only
/// thing that knows a button was pressed is the button.
///
/// The root-key-handler shape is precedented — `HardwareKeyboard.instance
/// .addHandler` already runs before the focus tree elsewhere in this app,
/// which is the ordering this design depends on.
class UiFeedback {
  UiFeedback._();

  static final UiFeedback instance = UiFeedback._();

  /// How stale a token may be and still authorise a tick.
  ///
  /// Long enough to cover a frame plus the focus traversal that follows the
  /// key, short enough that a key press cannot authorise an autofocus that
  /// happens after the route it opened has built.
  static const Duration _tokenLife = Duration(milliseconds: 100);

  /// Minimum gap between two ticks. A held DPAD repeats faster than this on
  /// every TV platform, so this is what stops a hold from becoming a buzz.
  static const Duration _minGap = Duration(milliseconds: 60);

  /// The one-shot token: when the last directional key arrived, or null if it
  /// has already been consumed.
  Duration? _token;

  /// When the last tick was emitted, for the rate limiter.
  Duration? _lastTick;

  bool _installed = false;

  final Stopwatch _stopwatch = Stopwatch();

  /// The clock, as a function so tests can drive it.
  ///
  /// A `Stopwatch` rather than `DateTime.now` because every comparison here is
  /// an elapsed duration, not a date — and injectable because `FakeAsync`
  /// (which is what `testWidgets` runs under) advances timers but NOT a real
  /// stopwatch. Without this seam every test would see zero elapsed time and
  /// the rate limiter would swallow everything after the first tick, which
  /// would look like a passing spam test and prove nothing.
  @visibleForTesting
  Duration Function() clock = () => Duration.zero;

  /// The thing that actually makes noise. Swapped in tests, which is the only
  /// way to assert silence — you cannot observe a `SystemSound` that did not
  /// happen.
  @visibleForTesting
  FeedbackBackend backend = const PlatformFeedbackBackend();

  /// Install the root key handler and the focus listener. Idempotent, and
  /// called from `main()` after the theme controller has warmed.
  void install() {
    if (_installed) return;
    _installed = true;
    _stopwatch.start();
    clock = () => _stopwatch.elapsed;
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @visibleForTesting
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_onFocusChanged);
    _stopwatch.stop();
    _stopwatch.reset();
    _token = null;
    _lastTick = null;
  }

  /// Directional keys mint; nothing else does.
  ///
  /// Returns false always — this handler observes, it never consumes. A true
  /// return would swallow the key and break every DPAD screen in the app.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!_isDirectional(event.logicalKey)) return false;
    _token = clock();
    return false;
  }

  static bool _isDirectional(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.gameButtonLeft1 ||
      key == LogicalKeyboardKey.gameButtonRight1;

  void _onFocusChanged() {
    final token = _token;
    if (token == null) return;
    // One token, one tick. Consumed even if the tick is then suppressed, so a
    // single key press can never authorise a second focus change.
    _token = null;
    if (clock() - token > _tokenLife) return;
    _emit(activation: false);
  }

  /// Activation feedback — a select, a play, a confirm.
  ///
  /// Called explicitly at the chokepoints. Deliberately not rate-limited
  /// against traversal: a select immediately after a move is two different
  /// events and should sound like two.
  void activate() => _emit(activation: true, rateLimited: false);

  void _emit({required bool activation, bool rateLimited = true}) {
    // The player and the launch ident own the screen AND its audio; a UI tick
    // over a film is the single most annoying thing in this file.
    if (AppSurfaceState.instance.active == SurfaceKind.frozen) return;

    final tokens = AppThemeController.instance.theme.sound;
    if (tokens.isSilent) return;

    if (rateLimited) {
      final last = _lastTick;
      if (last != null && clock() - last < _minGap) return;
      _lastTick = clock();
    }

    // Two different questions, deliberately asked separately. A desktop
    // traverses with a keyboard and has no actuator; a phone has an actuator
    // and no cursor; a TV has a cursor and no actuator.
    final hasCursor = !PlatformUtil.isPhone;
    final hasActuator = PlatformUtil.isPhone;
    // The user's veto, applied last. The theme says what there is to play;
    // this says whether they want it. Read from the synchronous mirrors — a
    // focus listener and a key handler cannot await.
    final sound = !StorageService.uiSoundsCached
        ? SoundCharacter.silent
        : (activation ? tokens.activation : tokens.traversalFor(hasCursor));
    final haptic = !StorageService.uiHapticsCached
        ? HapticCharacter.none
        : tokens.hapticFor(hasActuator, activation: activation);
    if (sound == SoundCharacter.silent && haptic == HapticCharacter.none) {
      return;
    }
    backend.play(sound, haptic);
  }

  /// Test-only: back to process-start state without touching the handlers.
  @visibleForTesting
  void resetForTest() {
    _token = null;
    _lastTick = null;
  }

  /// Test-only: mint a token as if a directional key had arrived.
  @visibleForTesting
  void debugMintToken() => _token = clock();

  /// Test-only: install the listeners WITHOUT starting the real stopwatch, so
  /// [clock] stays under the test's control.
  @visibleForTesting
  void installForTest() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @visibleForTesting
  bool get debugHasToken => _token != null;
}

/// The seam between "decided to make a sound" and "made one".
///
/// Exists so the dispatcher's rules can be tested — silence is not observable
/// through the platform channels, so it has to be observable here.
abstract class FeedbackBackend {
  const FeedbackBackend();
  void play(SoundCharacter sound, HapticCharacter haptic);
}

/// The real one: the platform's own click and its own actuator.
///
/// No bundled audio assets, and that is a decision rather than a shortcut.
/// A per-theme sound font would add megabytes, a licensing question and a
/// tvOS packaging problem, and none of it changes the thing that actually
/// reads as quality — whether the tick lands on the right event. Themes
/// differ here by WHETHER and WHEN they tick, not by timbre.
class PlatformFeedbackBackend extends FeedbackBackend {
  const PlatformFeedbackBackend();

  @override
  void play(SoundCharacter sound, HapticCharacter haptic) {
    switch (sound) {
      case SoundCharacter.silent:
        break;
      case SoundCharacter.click:
        SystemSound.play(SystemSoundType.click);
      case SoundCharacter.soft:
        SystemSound.play(SystemSoundType.alert);
    }
    switch (haptic) {
      case HapticCharacter.none:
        break;
      case HapticCharacter.selection:
        HapticFeedback.selectionClick();
      case HapticCharacter.impact:
        HapticFeedback.lightImpact();
    }
  }
}
