import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/application/smb_upload_providers.dart';
import 'package:debrify/features/recording_output/application/smb_upload_status_notifier.dart';
import 'package:debrify/features/recording_output/application/smb_upload_coordinator.dart';
import 'package:debrify/features/recording_output/application/smb_uploader.dart';
import 'package:debrify/features/recording_output/data/smb_settings_store.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:debrify/features/recording_output/presentation/smb_upload_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/smb_fakes.dart';

/// The section's store, built over the mocked preference store with plain
/// seal/open (the same shape as `_plainStore` in smb_settings_store_test.dart):
/// the real SecretVault needs key material a widget test does not have, and
/// the section must not need it either.
SmbSettingsStore storeWith({
  SmbTarget target = const SmbTarget(),
  String? password,
}) {
  SharedPreferences.setMockInitialValues({
    SmbSettingsStore.targetKey: target.encode(),
    if (password != null) SmbSettingsStore.passwordKey: 'sealed:$password',
  });
  return SmbSettingsStore(
    seal: (plain) async => 'sealed:$plain',
    open: (stored) async => stored != null && stored.startsWith('sealed:')
        ? stored.substring('sealed:'.length)
        : null,
  );
}

/// Reads back what the section persisted.
Future<({SmbTarget target, String? password})> savedState() async {
  final prefs = await SharedPreferences.getInstance();
  final sealed = prefs.getString(SmbSettingsStore.passwordKey);
  return (
    target: SmbTarget.decode(prefs.getString(SmbSettingsStore.targetKey)),
    password: sealed != null && sealed.startsWith('sealed:')
        ? sealed.substring('sealed:'.length)
        : null,
  );
}

/// Pumps the section over the given fakes. [target]/[password] are what the
/// store holds, [share] is the SMB server and [status] the status the
/// coordinator last published. Returns the widget-keyed finders' owner so a
/// test can read the container back if it needs to.
Future<void> pumpSection(
  WidgetTester tester, {
  SmbTarget target = const SmbTarget(),
  String? password,
  FakeShare? share,
  SmbUploadStatus? status,
  Size size = const Size(1200, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fakeShare = share ?? FakeShare();
  final container = ProviderContainer(
    overrides: [
      smbSettingsStoreProvider.overrideWithValue(
        storeWith(target: target, password: password),
      ),
      smbUploaderProvider.overrideWithValue(
        SmbUploader(connector: fakeShare, source: (_) => const Stream.empty()),
      ),
      smbUploadCoordinatorProvider.overrideWithValue(
        SmbUploadCoordinator(
          settings: storeWith(target: target, password: password),
          uploader: SmbUploader(
            connector: fakeShare,
            source: (_) => const Stream.empty(),
          ),
          listRecordings: () async => const [],
          activeUris: () async => const {},
          deleteLocal: (_) async => true,
          nowMs: () => 0,
          scopeId: () => 'section-test',
          onStatus: (_) {},
        ),
      ),
    ],
  );
  if (status != null) {
    container.read(smbUploadStatusProvider.notifier).publish(status);
  }
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: ListView(children: const [SmbUploadSection()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The key sits on the TvTextField wrapper, so it is excluded: this reaches
/// the real editor inside it (there is exactly one per field).
String _fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find
          .descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          )
          .first,
    )
    .controller
    .text;

bool _switchValue(WidgetTester tester, String key) => tester
    .widget<Switch>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Switch)),
    )
    .value;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a switched-off share shows nothing but the switch', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(
      find.text('Copy recordings to a network share (SMB)'),
      findsOneWidget,
    );
    expect(find.text('Off'), findsOneWidget);
    expect(find.byKey(Key('smb-address')), findsNothing);
    expect(find.byKey(Key('smb-user')), findsNothing);
    expect(find.byKey(Key('smb-password')), findsNothing);
    expect(find.byKey(Key('smb-domain')), findsNothing);
    expect(find.byKey(Key('smb-delete-local')), findsNothing);
    expect(find.byKey(Key('smb-test')), findsNothing);
    expect(find.byKey(Key('smb-save')), findsNothing);
  });

  testWidgets('a saved share shows its address and refills the form', (
    tester,
  ) async {
    const saved = SmbTarget(
      enabled: true,
      host: 'nas',
      share: 'recordings',
      user: 'tv',
      domain: 'WORKGROUP',
      deleteLocalAfterUpload: true,
    );
    await pumpSection(tester, target: saved, password: 'hunter2');

    // The address appears twice on purpose: the switch subtitle and the field.
    expect(find.text(r'\\nas\recordings'), findsNWidgets(2));
    expect(_fieldText(tester, 'smb-address'), r'\\nas\recordings');
    expect(_fieldText(tester, 'smb-user'), 'tv');
    expect(_fieldText(tester, 'smb-password'), 'hunter2');
    expect(_fieldText(tester, 'smb-domain'), 'WORKGROUP');
    expect(_switchValue(tester, 'smb-delete-local'), isTrue);
    expect(_switchValue(tester, 'smb-record-direct'), isTrue);
  });

  testWidgets('recording straight to the share can be turned off', (
    tester,
  ) async {
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true, host: 'nas', share: 'tv'),
    );
    expect(_switchValue(tester, 'smb-record-direct'), isTrue);

    await tester.ensureVisible(find.byKey(Key('smb-record-direct')));
    await tester.tap(find.byKey(Key('smb-record-direct')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(Key('smb-save')));
    await tester.tap(find.byKey(Key('smb-save')));
    await tester.pumpAndSettle();

    final saved = await savedState();
    expect(saved.target.recordDirect, isFalse);
    expect(saved.target.writesDirect, isFalse);
  });

  testWidgets('save persists the form and reruns the upload pass', (
    tester,
  ) async {
    await pumpSection(tester, target: const SmbTarget(enabled: true));

    await tester.enterText(find.byKey(Key('smb-address')), r'\\nas\videos');
    await tester.enterText(find.byKey(Key('smb-user')), 'tv');
    await tester.enterText(find.byKey(Key('smb-password')), 'secret');
    await tester.tap(find.byKey(Key('smb-save')));
    await tester.pumpAndSettle();

    final saved = await savedState();
    expect(saved.target.host, 'nas');
    expect(saved.target.share, 'videos');
    expect(saved.target.user, 'tv');
    expect(saved.target.enabled, isTrue);
    expect(saved.target.deleteLocalAfterUpload, isFalse);
    expect(saved.target.recordDirect, isTrue, reason: 'on by default');
    expect(saved.password, 'secret');
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('an invalid address shows an error and saves nothing', (
    tester,
  ) async {
    await pumpSection(tester, target: const SmbTarget(enabled: true));

    await tester.enterText(find.byKey(Key('smb-address')), 'nonsense');
    await tester.tap(find.byKey(Key('smb-save')));
    await tester.pumpAndSettle();

    expect(find.text(r'Enter an address like \\nas\share'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    final saved = await savedState();
    expect(saved.target, const SmbTarget(enabled: true));
    expect(saved.password, isNull);
  });

  testWidgets('switching the share off saves at once', (tester) async {
    const saved = SmbTarget(
      enabled: true,
      host: 'nas',
      share: 'recordings',
      deleteLocalAfterUpload: true,
    );
    await pumpSection(tester, target: saved, password: 'x');

    await tester.tap(find.text('Copy recordings to a network share (SMB)'));
    await tester.pumpAndSettle();

    final after = await savedState();
    expect(after.target.enabled, isFalse);
    expect(after.password, isNull, reason: 'the cleared password is removed');
    expect(
      find.text(r'\\nas\recordings'),
      findsOneWidget,
      reason: 'the subtitle keeps the last known address',
    );
    expect(find.byKey(Key('smb-address')), findsNothing);
  });

  testWidgets('test connection reports a working share', (tester) async {
    final share = FakeShare();
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true),
      share: share,
    );

    await tester.enterText(find.byKey(Key('smb-address')), r'\\nas\videos');
    await tester.tap(find.byKey(Key('smb-test')));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(share.lastTarget?.host, 'nas');
    expect(share.lastTarget?.share, 'videos');
  });

  testWidgets('test connection names a login failure', (tester) async {
    final share = FakeShare()
      ..connectError = const SmbException(
        SmbFailureKind.auth,
        'NT_STATUS_LOGON_FAILURE',
      );
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true),
      share: share,
    );

    await tester.enterText(find.byKey(Key('smb-address')), r'\\nas\videos');
    await tester.enterText(find.byKey(Key('smb-user')), 'tv');
    await tester.tap(find.byKey(Key('smb-test')));
    await tester.pumpAndSettle();

    expect(find.text('Wrong user name or password'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
  });

  testWidgets('a failing follow-up pass leaves the saved form usable', (
    tester,
  ) async {
    await pumpSection(tester, target: const SmbTarget(enabled: true));

    await tester.enterText(find.byKey(Key('smb-address')), r'\\nas\videos');
    await tester.tap(find.byKey(Key('smb-save')));
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final saved = await savedState();
    expect(saved.target.share, 'videos');
  });

  testWidgets('the status line reports the upload in flight', (tester) async {
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true, host: 'nas', share: 'recordings'),
      status: const SmbUploadStatus(
        phase: SmbUploadPhase.uploading,
        currentName: 'ep1.mp4',
        sentBytes: 50,
        totalBytes: 200,
      ),
    );

    expect(find.text('Uploading ep1.mp4 · 25%'), findsOneWidget);
  });

  testWidgets('the status line reports the last failure', (tester) async {
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true, host: 'nas', share: 'recordings'),
      status: const SmbUploadStatus(
        phase: SmbUploadPhase.idle,
        lastFailure: SmbFailureKind.network,
        lastMessage: 'timed out',
      ),
    );

    expect(find.text('Last upload failed: timed out'), findsOneWidget);
  });

  testWidgets('the status line reports the last upload when idle', (
    tester,
  ) async {
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true, host: 'nas', share: 'recordings'),
      status: const SmbUploadStatus(
        phase: SmbUploadPhase.idle,
        lastUploadedName: 'ep0.mp4',
      ),
    );

    expect(find.text('Last uploaded: ep0.mp4'), findsOneWidget);
  });

  testWidgets('an idle status with nothing to report shows no line', (
    tester,
  ) async {
    await pumpSection(
      tester,
      target: const SmbTarget(enabled: true, host: 'nas', share: 'recordings'),
      status: const SmbUploadStatus(phase: SmbUploadPhase.idle),
    );

    expect(find.byKey(Key('smb-status')), findsNothing);
  });
}
