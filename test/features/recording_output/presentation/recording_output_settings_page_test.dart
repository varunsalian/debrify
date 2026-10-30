import 'package:debrify/features/recording_output/application/smb_upload_coordinator.dart';
import 'package:debrify/features/recording_output/application/smb_upload_providers.dart';
import 'package:debrify/features/recording_output/application/smb_uploader.dart';
import 'package:debrify/features/recording_output/data/smb_settings_store.dart';
import 'package:debrify/features/recording_output/models/recording_output_settings.dart';
import 'package:debrify/features/recording_output/presentation/recording_output_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/smb_fakes.dart';

Future<({String? treeUri, String? displayName, String? path})?>
_cancelPick() async => null;

class FakeStore implements RecordingOutputStoreApi {
  FakeStore(this.settings);

  RecordingOutputSettings settings;
  final List<RecordingOutputSettings> writes = [];

  @override
  Future<RecordingOutputSettings> read() async => settings;

  @override
  Future<void> write(RecordingOutputSettings s) async {
    writes.add(s);
    settings = s;
  }
}

/// The page now hosts the SMB section, which reads the SMB providers. These
/// overrides keep it off the network, off SecretVault (no key material here)
/// and off a real upload pass.
List<Override> _smbOverrides() {
  final share = FakeShare();
  final store = SmbSettingsStore(
    seal: (plain) async => 'sealed:$plain',
    open: (stored) async => stored != null && stored.startsWith('sealed:')
        ? stored.substring(7)
        : null,
  );
  return [
    smbSettingsStoreProvider.overrideWithValue(store),
    smbUploaderProvider.overrideWithValue(
      SmbUploader(connector: share, source: (_) => const Stream.empty()),
    ),
    smbUploadCoordinatorProvider.overrideWithValue(
      SmbUploadCoordinator(
        settings: store,
        uploader: SmbUploader(
          connector: share,
          source: (_) => const Stream.empty(),
        ),
        listRecordings: () async => const [],
        activeUris: () async => const {},
        deleteLocal: (_) async => true,
        nowMs: () => 0,
        scopeId: () => 'page-test',
        onStatus: (_) {},
      ),
    ),
  ];
}

Future<FakeStore> pumpPage(
  WidgetTester tester, {
  RecordingPlatform platform = RecordingPlatform.desktop,
  RecordingFolderPick? folderPicker,
  RecordingOutputSettings? initial,
}) async {
  final store = FakeStore(initial ?? const RecordingOutputSettings());
  await tester.pumpWidget(
    ProviderScope(
      overrides: _smbOverrides(),
      child: MaterialApp(
        home: RecordingOutputSettingsPage(
          platform: platform,
          folderPicker: folderPicker,
          store: store,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the four rows when a custom folder exists', (
    tester,
  ) async {
    await pumpPage(
      tester,
      folderPicker: _cancelPick,
      initial: const RecordingOutputSettings(
        directoryPath: '/media/videos',
        startPadMinutes: 2,
      ),
    );
    expect(find.text('Save recordings to'), findsOneWidget);
    expect(find.text('Use default folder'), findsOneWidget);
    expect(find.text('Start recording early'), findsOneWidget);
    expect(find.text('Keep recording after the end'), findsOneWidget);
    expect(find.text('/media/videos'), findsOneWidget);
    for (final title in [
      'Save recordings to',
      'Use default folder',
      'Start recording early',
      'Keep recording after the end',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(title))).height,
        greaterThanOrEqualTo(56),
      );
    }
  });

  testWidgets('picking a start pad writes it to the store', (tester) async {
    final store = await pumpPage(tester, folderPicker: _cancelPick);
    await tester.tap(find.text('Start recording early'));
    await tester.pumpAndSettle();
    expect(find.text('Start recording early'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(SimpleDialogOption, '5 min'));
    await tester.pumpAndSettle();
    expect(store.writes, hasLength(1));
    expect(store.writes.single.startPadMinutes, 5);
    expect(find.text('5 min'), findsOneWidget);
  });

  testWidgets('folder row is hidden without a picker', (tester) async {
    await pumpPage(
      tester,
      initial: const RecordingOutputSettings(directoryPath: '/videos'),
    );
    expect(find.text('Save recordings to'), findsNothing);
    expect(find.text('Use default folder'), findsNothing);
    expect(find.text('Start recording early'), findsOneWidget);
    expect(find.text('Keep recording after the end'), findsOneWidget);
  });

  testWidgets('picker result is stored and its label is shown', (tester) async {
    var picked = true;
    final store = await pumpPage(
      tester,
      platform: RecordingPlatform.android,
      folderPicker: () async {
        if (!picked) return null;
        picked = false;
        return (
          treeUri: 'content://tree',
          displayName: 'Mixtape Drive',
          path: null,
        );
      },
    );
    await tester.tap(find.text('Save recordings to'));
    await tester.pumpAndSettle();
    expect(store.writes, hasLength(1));
    expect(store.writes.single.treeUri, 'content://tree');
    expect(store.writes.single.treeDisplayName, 'Mixtape Drive');
    expect(find.text('Mixtape Drive'), findsOneWidget);
    expect(find.text('Use default folder'), findsOneWidget);
  });

  testWidgets('use default folder clears the folder fields', (tester) async {
    final store = await pumpPage(
      tester,
      folderPicker: _cancelPick,
      initial: const RecordingOutputSettings(
        treeUri: 'content://tree',
        treeDisplayName: 'Old name',
        startPadMinutes: 3,
      ),
    );
    await tester.tap(find.text('Use default folder'));
    await tester.pumpAndSettle();
    expect(store.writes, hasLength(1));
    expect(store.writes.single.treeUri, isNull);
    expect(store.writes.single.treeDisplayName, isNull);
    expect(store.writes.single.directoryPath, isNull);
    expect(store.writes.single.startPadMinutes, 3);
    expect(find.text('Use default folder'), findsNothing);
    expect(find.text('Downloads/Debrify/Recordings'), findsOneWidget);
  });

  testWidgets('arrow-down moves focus from the first row to the second', (
    tester,
  ) async {
    final store = FakeStore(
      const RecordingOutputSettings(directoryPath: '/videos', endPadMinutes: 5),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _smbOverrides(),
        child: MaterialApp(
          home: RecordingOutputSettingsPage(
            platform: RecordingPlatform.android,
            folderPicker: _cancelPick,
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    bool rowFocused(String title) =>
        Focus.of(tester.element(find.text(title))).hasFocus;
    expect(
      rowFocused('Save recordings to'),
      isTrue,
      reason: 'first row starts focused',
    );
    expect(rowFocused('Use default folder'), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      rowFocused('Use default folder'),
      isTrue,
      reason: 'arrow-down reaches row two',
    );
    expect(rowFocused('Save recordings to'), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      rowFocused('Save recordings to'),
      isTrue,
      reason: 'arrow-up returns to row one',
    );
  });

  testWidgets('the network share has its own page under the timing rows', (
    tester,
  ) async {
    // A tall surface so nothing sits below the fold: what this checks is the
    // page's shape, not its pixels.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester);

    expect(find.text('Start recording early'), findsOneWidget);
    expect(find.text('Keep recording after the end'), findsOneWidget);
    expect(find.text('Network share (SMB)'), findsOneWidget);
    expect(find.text('Copy recordings to a network share (SMB)'), findsNothing);

    // The timing dialog still opens on top.
    await tester.tap(find.text('Start recording early'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialogOption), findsNWidgets(5));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Network share (SMB)'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Network share'), findsOneWidget);
    expect(
      find.text('Copy recordings to a network share (SMB)'),
      findsOneWidget,
    );
  });
}
