import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settings_hub_test_host.dart';

void main() {
  testWidgets('production index and leaf builders preserve exact host order', (
    tester,
  ) async {
    final host = Platform.isMacOS
        ? 'macos'
        : Platform.isLinux
        ? 'linux'
        : null;
    expect(
      host,
      isNotNull,
      reason: 'Add a reviewed fixture for a new CI host.',
    );
    final state = await pumpSettingsHub(tester);
    final access = settingsScreenTestAccess(state);
    List<List<String>> pairs(List<SettingsSearchEntry> entries) => [
      for (final entry in entries) [entry.category, entry.title],
    ];
    final actual = {
      'index': pairs(access.index()),
      'leaves': pairs(access.leaves()),
    };
    final expected = jsonDecode(
      File('test/fixtures/settings/search_order_$host.json').readAsStringSync(),
    );
    expect(actual['index'], expected['index']);
    expect(actual['leaves'], expected['leaves']);
    // A second fresh production call must produce the same complete order.
    expect(pairs(access.index()), expected['index']);
    expect(pairs(access.leaves()), expected['leaves']);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
