import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/application/smb_upload_coordinator.dart';
import 'package:debrify/features/recording_output/application/smb_upload_providers.dart';
import 'package:debrify/features/recording_output/application/smb_uploader.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:debrify/features/recording_output/presentation/smb_upload_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/smb_fakes.dart';

final class _Settings implements SmbUploadSettings {
  int targetReads = 0;
  @override
  Future<SmbTarget> readTarget() async {
    targetReads++;
    return const SmbTarget();
  }

  @override
  Future<String?> readPassword() async => null;
  @override
  Future<SmbUploadLedger> readLedger() async => const SmbUploadLedger();
  @override
  Future<void> writeLedger(SmbUploadLedger ledger) async {}
}

void main() {
  late SmbUploadCoordinator coordinator;

  Future<_Settings> pump(WidgetTester tester, {required bool supported}) async {
    final settings = _Settings();
    coordinator = SmbUploadCoordinator(
      settings: settings,
      uploader: SmbUploader(connector: FakeShare(), source: memorySource({})),
      listRecordings: () async => const [],
      activeUris: () async => const {},
      deleteLocal: (_) async => true,
      nowMs: () => 0,
      scopeId: () => 'p',
      onStatus: (_) {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smbUploadSupportedProvider.overrideWithValue(supported),
          smbUploadCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const SmbUploadHost(
          child: Text('app', textDirection: TextDirection.ltr),
        ),
      ),
    );
    return settings;
  }

  testWidgets('starts the upload passes after the first delay', (tester) async {
    final settings = await pump(tester, supported: true);
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 29));
    expect(settings.targetReads, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(settings.targetReads, 1);
    coordinator.stop();
  });

  testWidgets('does nothing where recording is unsupported', (tester) async {
    final settings = await pump(tester, supported: false);
    await tester.pump(const Duration(minutes: 5));
    expect(settings.targetReads, 0);
  });
}
