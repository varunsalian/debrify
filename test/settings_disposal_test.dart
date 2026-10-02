import 'dart:async';

import 'package:debrify/screens/settings_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settings_hub_test_host.dart';

void main() {
  testWidgets(
    'a snack completion after Settings disposal never reads context',
    (tester) async {
      final state = await pumpSettingsHub(tester);
      final snack = settingsScreenTestAccess(state).snack;
      snack('Mounted completion');
      await tester.pump();
      expect(find.text('Mounted completion'), findsOneWidget);

      final completion = Completer<void>();
      final action = completion.future.then((_) => snack('Retired completion'));
      await tester.pumpWidget(const SizedBox());
      expect(state.mounted, isFalse);
      completion.complete();
      await action;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Retired completion'), findsNothing);
    },
  );
}
