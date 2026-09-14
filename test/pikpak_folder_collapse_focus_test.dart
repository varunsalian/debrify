import 'package:debrify/widgets/pikpak_folder_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pikpak_last_folder_reveal_test.dart' as fixture;

void main() {
  testWidgets('footer UP survives pointer collapse of loaded children', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PikPakFolderPickerDialog(
            isTelevisionOverride: true,
            listFilesOverride: ({String? parentId, required int limit}) async =>
                (
                  files: [
                    for (var i = 0; i < 2; i++)
                      <String, dynamic>{
                        'id': parentId == null
                            ? 'root-$i'
                            : '$parentId-child-$i',
                        'name': parentId == null ? 'Root $i' : 'Child $i',
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(fixture.folderFocus('folder-item-3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();
    expect(fixture.folderFocus('folder-item-3'), findsNothing);
    final cancel = tester
        .widget<Focus>(fixture.folderFocus('cancel-button'))
        .focusNode!;
    cancel.requestFocus();
    await tester.pumpAndSettle();
    expect(cancel.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'folder-item-1');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
