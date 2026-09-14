import 'package:debrify/widgets/pikpak_folder_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder folderFocus(String label) => find.byWidgetPredicate(
  (widget) => widget is Focus && widget.focusNode?.debugLabel == label,
);

Future<void> openPicker(WidgetTester tester, {int count = 60}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PikPakFolderPickerDialog(
          isTelevisionOverride: true,
          listFilesOverride: ({String? parentId, required int limit}) async => (
            files: [
              for (var i = 0; i < count; i++)
                <String, dynamic>{
                  'id': '$i',
                  'name': 'Folder ${i.toString().padLeft(2, '0')}',
                  'kind': 'drive#folder',
                },
            ],
            nextPageToken: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final footer in [
    'new-folder-button',
    'cancel-button',
    'confirm-button',
  ]) {
    testWidgets('UP from $footer mounts and reveals the last folder', (
      tester,
    ) async {
      await openPicker(tester);
      // Select a real folder so Confirm is enabled as it would be in use.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final button = tester.widget<Focus>(folderFocus(footer)).focusNode!;
      button.requestFocus();
      await tester.pumpAndSettle();
      expect(button.hasFocus, isTrue);
      expect(
        folderFocus('folder-item-59'),
        findsNothing,
        reason: 'The target starts outside the lazy list cache.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'folder-item-59');
      final last = tester.getRect(find.text('Folder 59'));
      final viewport = tester.getRect(find.byType(ListView));
      expect(last.top, greaterThanOrEqualTo(viewport.top));
      expect(last.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'new-folder-button',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('UP also focuses an already-mounted last folder', (tester) async {
    await openPicker(tester, count: 1);
    tester
        .widget<Focus>(folderFocus('cancel-button'))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'folder-item-0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pending handoff does not steal a newer focus choice', (
    tester,
  ) async {
    await openPicker(tester);
    tester
        .widget<Focus>(folderFocus('cancel-button'))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    tester
        .widget<Focus>(folderFocus('new-folder-button'))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'new-folder-button');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty folder list keeps footer navigation usable', (
    tester,
  ) async {
    await openPicker(tester, count: 0);
    expect(find.text('No folders found in your account'), findsOneWidget);
    final button = tester
        .widget<Focus>(folderFocus('new-folder-button'))
        .focusNode!;
    button.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pending last-folder handoff is safe when dismissed', (
    tester,
  ) async {
    await openPicker(tester);
    tester
        .widget<Focus>(folderFocus('cancel-button'))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
