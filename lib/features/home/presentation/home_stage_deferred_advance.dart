import 'package:flutter/widgets.dart';

/// An accepted DOWN move. The caller resolves layout-specific destination focus;
/// the originating focus node is borrowed and is checked again in that frame.
class HomeStageAdvanceMove {
  const HomeStageAdvanceMove({
    required this.railKey,
    required this.origin,
    required this.fillsLower,
  });

  final String railKey;
  final FocusNode? origin;
  final bool fillsLower;
}

/// Owns a view's DOWN waiting for another rail, including partial arrivals,
/// expiry and origin checks. Does not own focus nodes or layout selection.
class HomeStageDeferredAdvance {
  HomeStageDeferredAdvance({
    required bool Function() stageActive,
    required Duration maxAge,
    FocusNode? Function()? primaryFocus,
    DateTime Function()? now,
  }) : _stageActive = stageActive,
       _maxAge = maxAge,
       _primaryFocus =
           primaryFocus ?? (() => FocusManager.instance.primaryFocus),
       _now = now ?? DateTime.now;

  final bool Function() _stageActive;
  final Duration _maxAge;
  final FocusNode? Function() _primaryFocus;
  final DateTime Function() _now;
  String? _key;
  DateTime? _at;
  FocusNode? _origin;
  bool _fillsLower = false;

  /// Anchor the move to the node that pressed DOWN. A different cell on the
  /// same rail must not inherit it. Atrium can fill an empty lower window row.
  void defer(String railKey, {bool fillsLower = false}) {
    final origin = _primaryFocus();
    if (origin == null) return;
    _key = railKey;
    _at = _now();
    _fillsLower = fillsLower;
    _origin = origin;
  }

  bool _valid(DateTime at, FocusNode? origin) =>
      _stageActive() &&
      origin != null &&
      identical(_primaryFocus(), origin) &&
      _now().difference(at) <= _maxAge;

  /// Inspect the current rail snapshot only when a move exists. A partial
  /// arrival above its rail leaves a still-valid move pending. Otherwise consume
  /// it before rechecking validity, matching the original completion ordering.
  HomeStageAdvanceMove? take({
    required bool Function(String railKey) waitingForMore,
  }) {
    final key = _key;
    final at = _at;
    final fillsLower = _fillsLower;
    final origin = _origin;
    if (key == null || at == null) return null;
    if (waitingForMore(key) && _valid(at, origin)) return null;
    reset();
    if (!_valid(at, origin)) return null;
    return HomeStageAdvanceMove(
      railKey: key,
      origin: origin,
      fillsLower: fillsLower,
    );
  }

  /// A nonincremental board reseed invalidates the request marker. Preserve the
  /// legacy retention of its borrowed origin/flag until the next defer/reset.
  void invalidateForBoardReseed() {
    _key = null;
    _at = null;
  }

  /// Layout changes and covered routes fully clear the pending move.
  void reset() {
    _key = null;
    _at = null;
    _fillsLower = false;
    _origin = null;
  }
}
