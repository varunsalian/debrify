import 'package:flutter/foundation.dart';

/// A screen's brain: everything it decides, with nothing it draws.
///
/// Extend this instead of putting logic in a `State`.
///
/// [S] is everything the view renders from; [E] is the one-shot things it has
/// to *do* — show a message, open a player, pop a route. Splitting them is what
/// lets a test assert "this failure tells the user X" without pumping a widget
/// tree, and it is why a controller can be written against `foundation` alone.
///
/// The rule that makes the rest work: **a controller never imports
/// `material.dart`**. That mechanically excludes `BuildContext`, `Navigator`,
/// `showDialog` and `ScaffoldMessenger`, which is the difference between logic
/// you can run in a plain `test()` and logic you can only reach through a
/// widget.
///
/// The view owns the view model's lifetime — construct it in `initState`,
/// `dispose` it in `dispose` — and owns everything the framework owns:
/// `FocusNode`, `ScrollController`, `TextEditingController`, animations. None
/// of those belong here.
abstract base class ViewModel<S, E> extends ChangeNotifier {
  ViewModel(this._state);

  S _state;

  /// What the view renders. Replaced wholesale by [emit], never mutated.
  S get state => _state;

  bool _disposed = false;
  void Function(E)? _onEffect;
  final List<E> _pending = [];

  /// True once [dispose] has run. Long async work should check it between
  /// awaits — [emit] and [effect] already do.
  @protected
  bool get isDisposed => _disposed;

  /// Publish new state.
  ///
  /// The disposal guard lives here rather than at every call site, which is
  /// what replaces the `if (!mounted) return` after each await. States that
  /// compare equal are dropped, so a state class with a real `==` gets
  /// rebuild filtering for free; one without falls back to always notifying,
  /// which is what a `setState` screen did anyway.
  @protected
  void emit(S next) {
    if (_disposed || next == _state) return;
    _state = next;
    if (kDebugMode) debugPrint('$runtimeType → $next');
    notifyListeners();
  }

  /// Ask the view to do something. Delivered in order, once.
  ///
  /// Effects raised before the view attaches are held rather than dropped —
  /// a controller whose first `load()` fails during `initState` still gets to
  /// report it.
  @protected
  void effect(E event) {
    if (_disposed) return;
    final handler = _onEffect;
    if (handler == null) {
      _pending.add(event);
      return;
    }
    handler(event);
  }

  /// Called by the view in `initState`. Drains anything raised before now.
  void listenForEffects(void Function(E) handler) {
    if (_disposed) return;
    _onEffect = handler;
    for (final event in List<E>.from(_pending)) {
      handler(event);
    }
    _pending.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _onEffect = null;
    _pending.clear();
    super.dispose();
  }
}
