import 'package:flutter/widgets.dart';

/// One view's RIGHT at a paginated rail boundary. Borrows focus nodes and the
/// stage's frame scheduler; neither resources nor layout state are owned here.
class HomeStageDeferredRight {
  HomeStageDeferredRight({
    required String? Function() currentRail,
    required bool Function() stageActive,
    required void Function(FocusNode? Function()) scheduleFocus,
    required Duration maxAge,
    FocusNode? Function()? primaryFocus,
    DateTime Function()? now,
  }) : _currentRail = currentRail,
       _stageActive = stageActive,
       _scheduleFocus = scheduleFocus,
       _maxAge = maxAge,
       _primaryFocus =
           primaryFocus ?? (() => FocusManager.instance.primaryFocus),
       _now = now ?? DateTime.now;

  final String? Function() _currentRail;
  final bool Function() _stageActive;
  final void Function(FocusNode? Function()) _scheduleFocus;
  final Duration _maxAge;
  final FocusNode? Function() _primaryFocus;
  final DateTime Function() _now;
  String? _key;
  int _column = -1;
  DateTime? _at;
  FocusNode? _origin;

  /// Mosaic leaves a rail on DOWN, so deferred RIGHT must let the user cross
  /// a page boundary. A keypress without primary focus preserves the old move.
  void defer(String railKey, int column) {
    final origin = _primaryFocus();
    if (origin == null) return;
    _key = railKey;
    _column = column;
    _at = _now();
    _origin = origin;
  }

  /// Consume once when a row page arrives. Resolve the next column only inside
  /// the scheduled frame: both focus and the rail's nodes can change meanwhile.
  void complete(FocusNode? Function(String railKey, int column) resolve) {
    final key = _key;
    final at = _at;
    final column = _column;
    final origin = _origin;
    if (key == null || at == null) return;
    reset();
    if (_currentRail() != key) return;
    if (!(_stageActive() &&
        origin != null &&
        identical(_primaryFocus(), origin) &&
        _now().difference(at) <= _maxAge)) {
      return;
    }
    _scheduleFocus(() {
      if (!identical(_primaryFocus(), origin)) return null;
      return resolve(key, column + 1);
    });
  }

  /// Layout transitions clear pending moves. Board reseeds retain the original
  /// policy: the shared frame scheduler invalidates already scheduled focus.
  void reset() {
    _key = null;
    _at = null;
    _column = -1;
    _origin = null;
  }
}
