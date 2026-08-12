import 'dart:async';

import 'package:flutter/material.dart';

import '../tv_keyboard.dart';

/// A measured home for the keyboard owned by a descendant [TvTextField].
///
/// Outside onboarding a field keeps using its historical root-overlay path.
class TvKeyboardSlot extends InheritedWidget {
  const TvKeyboardSlot({
    super.key,
    required this.session,
    required super.child,
  });

  final TvKeyboardSession session;

  static TvKeyboardSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvKeyboardSlot>()?.session;

  @override
  bool updateShouldNotify(TvKeyboardSlot oldWidget) =>
      !identical(session, oldWidget.session);
}

/// Coordinates a field's editing lifecycle with an in-tree keyboard panel.
class TvKeyboardSession {
  final ValueNotifier<TvKeyboardController?> panel =
      ValueNotifier<TvKeyboardController?>(null);

  Timer? _backTimer;
  bool _holdsBack = false;
  bool _disposed = false;

  /// True while a panel is attached and for the guard window belonging to the
  /// physical Back press that just detached it.
  bool get ownsBack => panel.value != null || _holdsBack;

  void attach(TvKeyboardController controller) {
    if (_disposed) return;
    if (identical(panel.value, controller)) return;
    panel.value = controller;
  }

  /// Identity checked so a late teardown cannot clear a newer field session.
  void detach(TvKeyboardController controller) {
    if (_disposed) return;
    if (!identical(panel.value, controller)) return;
    panel.value = null;
  }

  /// Widget disposal can happen during a parent's build. Defer the notifier
  /// mutation, and dispose the controller immediately after it is unmounted.
  void detachDeferred(
    TvKeyboardController controller, {
    required VoidCallback afterDetach,
  }) {
    if (!identical(panel.value, controller)) {
      afterDetach();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && identical(panel.value, controller)) panel.value = null;
      afterDetach();
    });
  }

  /// Mirrors TvTextField's 300 ms pop guard. The stage uses this signal to
  /// avoid processing the navigation-channel half of the same Back press.
  void holdBack() {
    if (_disposed) return;
    _holdsBack = true;
    _backTimer?.cancel();
    _backTimer = Timer(const Duration(milliseconds: 300), () {
      _holdsBack = false;
    });
  }

  void dispose() {
    _disposed = true;
    _backTimer?.cancel();
    panel.dispose();
  }
}
