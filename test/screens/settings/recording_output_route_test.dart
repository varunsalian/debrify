// "Save recordings to" on Android: the system folder picker where the device
// has one, the drive chooser where it has none (the button used to do
// nothing on such TV boxes).

import 'package:debrify/features/recording_output/models/recording_output_settings.dart';
import 'package:debrify/features/recording_output/models/storage_volume_choice.dart';
import 'package:debrify/screens/settings/recording_output_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _usb = StorageVolumeChoice(
  path: '/storage/AAAA/Android/data/com.debrify.app/files/Recordings',
  label: 'SanDisk USB',
);

/// Runs the pick from a button; returns a getter for its result.
Future<RecordingFolderPickResult? Function()> _pick(
  WidgetTester tester, {
  required bool canPick,
  required List<String> calls,
  RecordingOutputSettings current = const RecordingOutputSettings(),
}) async {
  RecordingFolderPickResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await pickAndroidRecordingFolder(
              context,
              current,
              canPickFolders: () async => canPick,
              systemPicker: () async {
                calls.add('picker');
                return (
                  treeUri: 'content://tree',
                  displayName: 'Picked',
                  path: null,
                );
              },
              listVolumes: () async {
                calls.add('volumes');
                return const [_usb];
              },
            );
          },
          child: const Text('pick'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('pick'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('a device with a folder picker uses it as before', (
    tester,
  ) async {
    final calls = <String>[];
    final result = await _pick(tester, canPick: true, calls: calls);
    expect(calls, ['picker']);
    expect(result()?.treeUri, 'content://tree');
    expect(find.text('SanDisk USB'), findsNothing);
  });

  testWidgets('without a picker the drive chooser opens instead', (
    tester,
  ) async {
    final calls = <String>[];
    final result = await _pick(tester, canPick: false, calls: calls);
    expect(calls, ['volumes']);
    expect(find.textContaining('no folder picker'), findsOneWidget);
    await tester.tap(find.text('SanDisk USB'));
    await tester.pumpAndSettle();
    expect(result(), (
      treeUri: null,
      displayName: 'SanDisk USB',
      path: _usb.path,
    ));
  });

  testWidgets('dismissing the chooser changes nothing', (tester) async {
    final calls = <String>[];
    final result = await _pick(
      tester,
      canPick: false,
      calls: calls,
      current: RecordingOutputSettings(
        directoryPath: _usb.path,
        treeDisplayName: 'SanDisk USB',
      ),
    );
    // The drive in use is marked.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
