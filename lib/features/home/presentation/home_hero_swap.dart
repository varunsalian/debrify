import 'dart:async';

/// One view's focus-rest delay for replacing its displayed hero. The caller
/// retains immediate first-title display, selection and trailer/favourite policy.
class HomeHeroSwap {
  Timer? _timer;
  bool _disposed = false;

  void schedule({
    required bool Function() isCurrent,
    required void Function() apply,
  }) {
    if (_disposed) return;
    cancel();
    _timer = Timer(const Duration(milliseconds: 260), () {
      _timer = null;
      if (!_disposed && isCurrent()) apply();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
