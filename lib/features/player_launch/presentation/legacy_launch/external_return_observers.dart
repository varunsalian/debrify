import 'package:flutter/material.dart';

/// Fires [onCovered] on the first lifecycle change away from resumed — i.e.
/// when the launched activity (native TV player / external app) takes the
/// foreground. One-shot; the caller removes it via the callback.
class AppCoverObserver with WidgetsBindingObserver {
  AppCoverObserver({required this.onCovered});
  final VoidCallback onCovered;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) onCovered();
  }
}

/// Fires [onReturned] on the first resume AFTER the app was covered — i.e. the
/// launched activity finished and handed the screen back. The cover→resume
/// pairing is the point: a resume without a preceding cover means the launch
/// never happened, not that playback ended. One-shot; the caller removes it.
class AppReturnObserver with WidgetsBindingObserver {
  AppReturnObserver({required this.onReturned});
  final VoidCallback onReturned;

  /// Whether the launched activity ever actually took the foreground — read by
  /// the arm timeout to tell "still launching" from "launch died".
  bool wasCovered = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      wasCovered = true;
      return;
    }
    if (wasCovered) onReturned();
  }
}
