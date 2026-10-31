// The drive chooser shown where the device has no system folder picker:
// what it lists, what each row returns, and that a remote can operate it.

import 'package:debrify/features/recording_output/models/storage_volume_choice.dart';
import 'package:debrify/features/recording_output/presentation/storage_drive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _usb = StorageVolumeChoice(
  path: '/storage/AAAA/Recordings',
  label: 'SanDisk USB',
  freeBytes: 8 * 1024 * 1024 * 1024,
  totalBytes: 32 * 1024 * 1024 * 1024,
);
const _sd = StorageVolumeChoice(path: '/storage/BBBB/Recordings');

/// Opens the dialog from a button and returns a getter for its result.
Future<StorageDriveChoice? Function()> _open(
  WidgetTester tester, {
  required List<StorageVolumeChoice> volumes,
  String? currentPath,
}) async {
  StorageDriveChoice? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showStorageDriveDialog(
              context,
              volumes: volumes,
              currentPath: currentPath,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('lists each drive with its space and says why', (tester) async {
    await _open(tester, volumes: const [_usb, _sd], currentPath: _usb.path);
    expect(find.textContaining('no folder picker'), findsOneWidget);
    expect(find.text('SanDisk USB'), findsOneWidget);
    expect(find.text('8.0 GB free of 32.0 GB'), findsOneWidget);
    expect(find.text('USB drive'), findsOneWidget);
    expect(find.textContaining('deletes that folder'), findsOneWidget);
    // The drive recordings already go to is marked.
    expect(
      find.descendant(
        of: find.byKey(Key('storage-drive-${_usb.path}')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('choosing a drive returns it', (tester) async {
    final result = await _open(tester, volumes: const [_usb, _sd]);
    await tester.tap(find.text('USB drive'));
    await tester.pumpAndSettle();
    expect(result(), isA<StorageDriveSelected>());
    expect((result()! as StorageDriveSelected).volume, _sd);
  });

  testWidgets('with no drive it says so and offers the network share', (
    tester,
  ) async {
    final result = await _open(tester, volumes: const []);
    expect(find.byKey(const Key('storage-drive-none')), findsOneWidget);
    expect(find.textContaining('deletes that folder'), findsNothing);
    // Nothing else to focus first: the share row takes it.
    final share = find.byKey(const Key('storage-drive-network-share'));
    expect(
      Focus.of(
        tester.element(find.text('Use a network share instead')),
      ).hasFocus,
      isTrue,
    );
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(result(), isA<StorageDriveNetworkShare>());
  });

  testWidgets('a remote moves down to the second drive and selects it', (
    tester,
  ) async {
    final result = await _open(tester, volumes: const [_usb, _sd]);
    bool focused(String text) =>
        Focus.of(tester.element(find.text(text))).hasFocus;
    expect(focused('SanDisk USB'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused('USB drive'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect((result()! as StorageDriveSelected).volume, _sd);
  });

  testWidgets('Back and Cancel close without a choice', (tester) async {
    var result = await _open(tester, volumes: const [_usb]);
    await tester.tap(find.byKey(const Key('storage-drive-cancel')));
    await tester.pumpAndSettle();
    expect(result(), isNull);
    expect(find.byType(StorageDriveDialog), findsNothing);

    result = await _open(tester, volumes: const [_usb]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(StorageDriveDialog), findsNothing);
    expect(result(), isNull);
  });
}
