import 'package:debrify/screens/settings/widgets/sync_device_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device rows fit a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var renamed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: AlertDialog(
              title: const Text('Connected devices'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: SyncDeviceTile(
                    name: 'Living room television with a long descriptive name',
                    status: 'This device · Last seen 9/14/2026 9:43 AM',
                    onRename: () => renamed = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Rename'));
    expect(renamed, isTrue);
    expect(find.text('Remove'), findsNothing);
  });
  testWidgets('rename validates input and submits a trimmed name', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<String>(
                  context: context,
                  builder: (_) => const SyncDeviceNameDialog(initialName: 'TV'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('1–60'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' Bedroom TV ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved, 'Bedroom TV');
    expect(tester.takeException(), isNull);
  });
}
