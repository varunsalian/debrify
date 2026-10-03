import 'package:flutter/material.dart';

typedef TorboxNotificationsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxNotifications {
  TorboxNotifications(this._deps);
  final TorboxNotificationsDeps _deps;

  /// Helper: Show snackbar
  void showSnackBar(String message, {bool isError = true}) {
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : null,
      ),
    );
  }
}
