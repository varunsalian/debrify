import 'dart:async';
import 'package:flutter/services.dart';

/// Per-view visual theater dwell. Shelves stay mounted; the caller rebuilds
/// their opacity/slide presentation when [active] changes.
class HomeStageTheater {
  HomeStageTheater({
    required bool Function() isCurrent,
    required bool Function() isEligible,
    required bool Function() isShowing,
    required void Function() onChanged,
  }) : _isCurrent = isCurrent,
       _isEligible = isEligible,
       _isShowing = isShowing,
       _onChanged = onChanged;

  final bool Function() _isCurrent;
  final bool Function() _isEligible;
  final bool Function() _isShowing;
  final void Function() _onChanged;
  Timer? _timer;
  bool _active = false;
  bool _disposed = false;
  bool get active => _active;

  void showingChanged() {
    if (_disposed || !_isCurrent()) return;
    if (!_isEligible() || !_isShowing()) {
      _timer?.cancel();
      if (_active) {
        _active = false;
        _onChanged();
      }
      return;
    }
    _arm();
  }

  void _arm() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      _timer = null;
      if (_disposed || !_isCurrent() || !_isEligible() || !_isShowing()) return;
      _active = true;
      _onChanged();
    });
  }

  /// Observe only: the waking key must still perform its normal action.
  bool handleKey(KeyEvent event) {
    if (_disposed || !_active || event is! KeyDownEvent) return false;
    if (_isCurrent()) {
      _active = false;
      _onChanged();
    }
    _arm();
    return false;
  }

  /// Layout transitions already rebuild; clear their old visual state silently.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _active = false;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
