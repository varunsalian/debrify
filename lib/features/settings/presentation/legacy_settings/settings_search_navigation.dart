import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsSearchNavigation {
  SettingsSearchNavigation(this._deps);
  final ({
    List<SettingsSearchEntry> Function() buildSearchIndex,
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;

  Future<void> openSettingsSearch() async {
    final context = _deps.context();
    await pushSettingsPage(
      context,
      SettingsSearchPage(entries: _deps.buildSearchIndex()),
    );
    if (!context.mounted) return;
    // A deep-linked page may have changed a connection/login; refresh so the
    // underlying settings surface is current when search closes.
    _deps.setState(() {});
  }
}
