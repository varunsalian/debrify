import 'package:debrify/screens/profiles/linux_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final automatic in [true, false]) {
    testWidgets('existing unlock submits automatic=$automatic', (tester) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? submitted;
      bool? autoUnlock;
      await tester.pumpWidget(
        MaterialApp(
          home: LinuxVaultScreen(
            existingVault: true,
            onSubmit: (secret, auto) async {
              submitted = secret;
              autoUnlock = auto;
            },
          ),
        ),
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      if (!automatic) {
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField), 'existing passphrase');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(submitted, 'existing passphrase');
      expect(autoUnlock, automatic);
      expect(tester.takeException(), isNull);
    });
  }
}
