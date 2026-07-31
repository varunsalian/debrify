import 'package:debrify/widgets/not_cached_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(ValueChanged<bool> onResult) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              onResult(await showNotCachedDialog(context, 'TorBox'));
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  testWidgets('Add Anyway returns true with the provider-specific message', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(harness((value) => result = value));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Torrent Not Cached'), findsOneWidget);
    expect(
      find.textContaining('This torrent is not cached on TorBox'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add Anyway'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Cancel returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(harness((value) => result = value));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
