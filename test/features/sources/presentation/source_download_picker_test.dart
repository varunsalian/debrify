import 'package:debrify/features/sources/presentation/source_download_picker.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const entries = [
    PlaylistEntry(url: 'one', title: 'first', sizeBytes: 100),
    PlaylistEntry(url: 'two', title: 'second', sizeBytes: 200),
  ];
  testWidgets(
    'picker preserves source order after deselect/reselect and All/None',
    (tester) async {
      List<PlaylistEntry>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showSourceDownloadPicker(context, entries);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result, entries);
    },
  );
  testWidgets('cancel returns no download selection', (tester) async {
    List<PlaylistEntry>? result = entries;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showSourceDownloadPicker(context, entries);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
