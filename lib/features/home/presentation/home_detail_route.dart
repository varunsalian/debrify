import 'package:flutter/material.dart';

/// Owns one detail route, including its return effects and targeted dismissal.
/// A covered or already-popped detail never dismisses a newer page.
class HomeDetailRoute {
  HomeDetailRoute({
    required this.name,
    required this.isOwnerCurrent,
    required this.onClosed,
  });

  final String name;
  final bool Function() isOwnerCurrent;
  final VoidCallback onClosed;
  MaterialPageRoute<void>? _route;

  bool get isActive => isOwnerCurrent() && (_route?.isActive ?? false);

  Future<void> push(NavigatorState navigator, WidgetBuilder builder) async {
    if (!isOwnerCurrent() || !navigator.mounted) return;
    if (_route != null) throw StateError('Detail route already opened');
    final route = _route = MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: builder,
    );
    await navigator.push<void>(route);
    if (isOwnerCurrent() && navigator.mounted) onClosed();
  }

  bool closeIfCurrent() {
    final route = _route;
    final navigator = route?.navigator;
    if (!isOwnerCurrent() ||
        route == null ||
        !route.isCurrent ||
        navigator == null ||
        !navigator.mounted) {
      return false;
    }
    navigator.pop();
    return true;
  }
}
