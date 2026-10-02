import 'package:flutter/material.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsSnacks {
  SettingsSnacks(this._deps);
  final ({BuildContext Function() context, bool Function() mounted}) _deps;

  void showSnack(String message) {
    if (!_deps.mounted()) return;
    final context = _deps.context();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
