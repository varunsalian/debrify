import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/platform_util.dart';
import 'app_ambience.dart';
import 'app_surfaces.dart';
import 'app_theme_controller.dart';

/// What the app does when you stop touching it, as one number.
///
/// ## Why a compositor and not a timer per screen
///
/// Two things want to dim the room: going idle, and a trailer starting. If
/// each owned its own opacity the two would fight — a trailer that starts
/// while the idle fade is halfway through would either snap the chrome back
/// or leave it stuck at 0.4 forever. So there is ONE effective value,
/// `max(trailerDim, idleDim)`, and each producer owns only its own input.
///
/// ## The transition table (plan §3.7)
///
/// | Event | Behaviour |
/// | --- | --- |
/// | Any input | `idleDim` → 0; the timer restarts **from zero**, never resumes |
/// | A producer suspends (trailer, frozen surface) | `idleDim` forced 0, timer suspended |
/// | The last producer resumes | timer restarts from zero |
/// | Producer disposal | resets only its OWN registration |
///
/// "Restarts from zero" is the part that is easy to get wrong: resuming an
/// elapsed timer means a trailer that ends at 29 seconds dims the room one
/// second later, which reads as a bug even though it is arithmetic.
///
/// ## v1 is TV only
///
/// Not a policy choice — a phone in a pocket already has a screen timeout,
/// and a desktop window that dims itself is a bug report. The gate is in
/// [_policy] so no producer has to remember it.
class IdleDim {
  IdleDim._();

  static final IdleDim instance = IdleDim._();

  /// The idle contribution, 0..1. Read through [effective], never directly by
  /// a widget — a widget that reads this one is a widget that will fight the
  /// trailer.
  final ValueNotifier<double> idleDim = ValueNotifier<double>(0);

  /// The trailer contribution, published by whichever stage is playing.
  final ValueNotifier<double> trailerDim = ValueNotifier<double>(0);

  /// What the shell actually paints. One listenable so a consumer rebuilds
  /// once per change rather than twice.
  late final ValueNotifier<double> effective = ValueNotifier<double>(0);

  /// Everything currently holding the timer down. A SET of owners rather than
  /// a counter: a producer that disposes twice, or disposes without having
  /// suspended, must not decrement someone else's hold.
  final Set<Object> _holds = <Object>{};

  Timer? _timer;
  bool _installed = false;

  void _recompute() {
    final v = idleDim.value > trailerDim.value
        ? idleDim.value
        : trailerDim.value;
    if (effective.value != v) effective.value = v;
  }

  /// Start listening. Called from `main()` after the theme controller warms.
  void install() {
    if (_installed) return;
    _installed = true;
    idleDim.addListener(_recompute);
    trailerDim.addListener(_recompute);
    // A frozen surface is the player or the launch ident — both own the
    // screen, and neither wants the shell dimming underneath them.
    AppSurfaceState.instance.addListener(_onSurfaceChanged);
    AppThemeController.instance.addListener(_onThemeChanged);
    // Every key, not just the directional ones: pressing PLAY or BACK is a
    // person being present, which is the only thing this timer measures.
    // Installed at the root rather than per-screen for the same reason the
    // feedback dispatcher is — a per-screen listener misses every key a
    // screen chooses to handle itself.
    HardwareKeyboard.instance.addHandler(_onKey);
    _onSurfaceChanged();
  }

  @visibleForTesting
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    idleDim.removeListener(_recompute);
    trailerDim.removeListener(_recompute);
    AppSurfaceState.instance.removeListener(_onSurfaceChanged);
    AppThemeController.instance.removeListener(_onThemeChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    _timer = null;
    _holds.clear();
    idleDim.value = 0;
    trailerDim.value = 0;
    effective.value = 0;
  }

  /// Observes; never consumes. A `true` here would swallow every key in the
  /// app.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) noteInput();
    return false;
  }

  static const Object _frozenSurface = Object();

  void _onSurfaceChanged() {
    if (AppSurfaceState.instance.active == SurfaceKind.frozen) {
      suspend(_frozenSurface);
    } else {
      resume(_frozenSurface);
    }
  }

  void _onThemeChanged() {
    // A theme with no idle policy must not leave a stale dim on screen, and a
    // theme that gains one must not inherit a timer armed under the old
    // duration.
    idleDim.value = 0;
    _rearm();
  }

  IdlePolicy get _policy => AppThemeController.instance.theme.idle
      .policyFor(PlatformUtil.isTelevision);

  Duration get _after => AppThemeController.instance.theme.idle.after;

  double get _depth => AppThemeController.instance.theme.idle.depth;

  /// Any key, any pointer. Called from the root input handlers.
  void noteInput() {
    if (idleDim.value != 0) idleDim.value = 0;
    _rearm();
  }

  /// Hold the timer down while [owner] is doing something the user is
  /// watching. Idempotent per owner.
  void suspend(Object owner) {
    if (!_holds.add(owner)) return;
    _timer?.cancel();
    _timer = null;
    if (idleDim.value != 0) idleDim.value = 0;
  }

  /// Release [owner]'s hold. The timer restarts from zero only when the last
  /// hold is gone.
  void resume(Object owner) {
    if (!_holds.remove(owner)) return;
    _rearm();
  }

  void _rearm() {
    _timer?.cancel();
    _timer = null;
    if (_holds.isNotEmpty) return;
    if (_policy == IdlePolicy.none) return;
    _timer = Timer(_after, _fire);
  }

  void _fire() {
    _timer = null;
    if (_holds.isNotEmpty) return;
    if (_policy == IdlePolicy.none) return;
    idleDim.value = _depth;
  }

  @visibleForTesting
  bool get debugArmed => _timer != null;

  @visibleForTesting
  Set<Object> get debugHolds => _holds;

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _holds.clear();
    idleDim.value = 0;
    trailerDim.value = 0;
    effective.value = 0;
  }
}

/// Chrome that recedes when the room goes idle.
///
/// Wraps whatever a look would call furniture — a sidebar, a top bar, a row
/// of metadata. Under [IdlePolicy.none], which is legacy and three of the five
/// looks, this is `child` and nothing else: no listenable, no animation, no
/// wrapper widget in the tree.
class IdleChrome extends StatelessWidget {
  final Widget child;

  /// How much of the dim this element takes. A sidebar can go most of the way
  /// out; a row of controls the user might still be aiming at should not.
  final double weight;

  const IdleChrome({super.key, required this.child, this.weight = 1});

  @override
  Widget build(BuildContext context) {
    // The policy is read from the controller rather than the scope: this must
    // be able to short-circuit to `child` BEFORE establishing any dependency,
    // or a look with no idle policy would still rebuild on every dim change.
    if (AppThemeController.instance.theme.idle
            .policyFor(PlatformUtil.isTelevision) ==
        IdlePolicy.none) {
      return child;
    }
    return ValueListenableBuilder<double>(
      valueListenable: IdleDim.instance.effective,
      builder: (context, dim, child) => AnimatedOpacity(
        // Slow on the way out and quick on the way back: the fade is ambient,
        // the recovery is a response to a key press and must feel immediate.
        duration: dim > 0
            ? const Duration(milliseconds: 900)
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: (1 - dim * weight).clamp(0.0, 1.0),
        child: child,
      ),
      child: child,
    );
  }
}
