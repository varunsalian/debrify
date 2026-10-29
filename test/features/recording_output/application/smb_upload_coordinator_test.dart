import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/application/smb_upload_coordinator.dart';
import 'package:debrify/features/recording_output/application/smb_upload_status_notifier.dart';
import 'package:debrify/features/recording_output/application/smb_uploader.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'smb_fakes.dart';

final class _Settings implements SmbUploadSettings {
  SmbTarget target = const SmbTarget(enabled: true, host: 'nas', share: 'rec');
  String? password = 'pw';
  SmbUploadLedger ledger = const SmbUploadLedger();
  int ledgerWrites = 0;

  @override
  Future<SmbTarget> readTarget() async => target;
  @override
  Future<String?> readPassword() async => password;
  @override
  Future<SmbUploadLedger> readLedger() async => ledger;
  @override
  Future<void> writeLedger(SmbUploadLedger l) async {
    ledgerWrites++;
    ledger = l;
  }
}

void main() {
  late FakeShare share;
  late _Settings settings;
  late Map<String, List<int>> local;
  late List<SmbLocalRecording> library;
  late Set<String> active;
  late List<String> deleted;
  late List<SmbUploadStatus> published;
  late int now;
  late String scope;
  late int listCalls;
  Object? listError;
  Object? deleteError;

  SmbLocalRecording rec(String uri, int bytes, int at) => SmbLocalRecording(
    uri: uri,
    name: '$uri.ts',
    bytes: bytes,
    recordedAtMs: at,
  );

  setUp(() {
    share = FakeShare();
    settings = _Settings();
    local = {'a': bytesOf(100), 'b': bytesOf(200)};
    library = [rec('b', 200, 2), rec('a', 100, 1)];
    active = {};
    deleted = [];
    published = [];
    now = 1000;
    scope = 'p1';
    listCalls = 0;
    listError = null;
    deleteError = null;
  });

  SmbUploadCoordinator make() => SmbUploadCoordinator(
    settings: settings,
    uploader: SmbUploader(connector: share, source: memorySource(local)),
    listRecordings: () async {
      listCalls++;
      if (listError != null) throw listError!;
      return List.of(library);
    },
    activeUris: () async => active,
    deleteLocal: (uri) async {
      if (deleteError != null) throw deleteError!;
      deleted.add(uri);
      return true;
    },
    nowMs: () => now,
    scopeId: () => scope,
    onStatus: published.add,
  );

  test('disabled or incomplete target does nothing', () async {
    final c = make();
    settings.target = const SmbTarget(host: 'nas', share: 'rec');
    await c.runOnce();
    expect(c.status.phase, SmbUploadPhase.disabled);
    expect(published.last.phase, SmbUploadPhase.disabled);
    settings.target = const SmbTarget(enabled: true, host: 'nas');
    await c.runOnce();
    expect(listCalls, 0);
    expect(share.connects, 0);
  });

  test(
    'first scan only remembers sizes; second uploads oldest first',
    () async {
      final c = make();
      await c.runOnce();
      expect(share.connects, 0);
      expect(c.status.phase, SmbUploadPhase.idle);
      expect(c.status.lastRunAtMs, 1000);

      now = 2000;
      await c.runOnce();
      expect(share.files['a.ts'], local['a']);
      expect(share.files['b.ts'], local['b']);
      expect(share.log.where((l) => l.startsWith('rename')).toList(), [
        'rename a.ts.part -> a.ts',
        'rename b.ts.part -> b.ts',
      ]);
      expect(settings.ledger['a']!.state, SmbUploadState.uploaded);
      expect(settings.ledger['a']!.remotePath, 'a.ts');
      expect(settings.ledger['a']!.updatedAtMs, 2000);
      expect(settings.ledgerWrites, 2);
      expect(share.lastPassword, 'pw');
      expect(c.status.phase, SmbUploadPhase.idle);
      expect(c.status.lastUploadedName, 'b.ts');
      expect(c.status.waiting, 0);
      expect(c.status.lastRunAtMs, 2000);
      expect(deleted, isEmpty);

      final connects = share.connects;
      await c.runOnce();
      expect(share.connects, connects);
    },
  );

  test('uploading status names the file and counts what is waiting', () async {
    final c = make();
    await c.runOnce();
    await c.runOnce();
    final uploading = published
        .where((s) => s.phase == SmbUploadPhase.uploading)
        .toList();
    expect(uploading.first.currentName, 'a.ts');
    expect(uploading.first.totalBytes, 100);
    expect(uploading.first.waiting, 2);
    final forB = uploading.firstWhere((s) => s.currentName == 'b.ts');
    expect(forB.waiting, 1);
  });

  test('progress publishes only when the percent changes', () async {
    final size = SmbUploader.chunkBytes * 3;
    local = {'big': bytesOf(size)};
    library = [rec('big', size, 1)];
    final c = make();
    await c.runOnce();
    published.clear();
    await c.runOnce();
    final percents = published
        .where((s) => s.phase == SmbUploadPhase.uploading)
        .map((s) => s.percent)
        .toList();
    expect(percents, [0, 33, 66, 100]);
  });

  test('active and still-growing files wait', () async {
    final c = make();
    await c.runOnce();
    active = {'a'};
    library = [rec('b', 250, 2), rec('a', 100, 1)];
    local['b'] = bytesOf(250);
    await c.runOnce();
    expect(share.connects, 0);
    active = {};
    await c.runOnce();
    expect(share.files.keys, containsAll(['a.ts', 'b.ts']));
  });

  test('a network failure stops the run and retries after the delay', () async {
    final c = make();
    await c.runOnce();
    share.connectError = const SmbException(SmbFailureKind.network, 'down');
    await c.runOnce();
    expect(share.connects, 1);
    final rec = settings.ledger['a']!;
    expect(rec.state, SmbUploadState.failed);
    expect(rec.attempts, 1);
    expect(rec.nextAttemptAtMs, 1000 + 60000);
    expect(settings.ledger['b'], isNull);
    expect(c.status.lastFailure, SmbFailureKind.network);
    expect(c.status.lastMessage, 'down');

    share.connectError = null;
    now = 1000 + 59999;
    await c.runOnce();
    // 'a' waits for its retry time; 'b' (never tried) goes now.
    expect(share.files.keys, ['b.ts']);
    now = 1000 + 60000;
    await c.runOnce();
    expect(share.files.keys, containsAll(['a.ts', 'b.ts']));
    expect(settings.ledger['a']!.state, SmbUploadState.uploaded);
    expect(settings.ledger['a']!.attempts, 1);
    expect(c.status.lastFailure, isNull);
    expect(c.status.lastMessage, isNull);
    expect(c.status.lastUploadedName, 'a.ts');
  });

  test('a per-file failure does not stop the run', () async {
    final c = SmbUploadCoordinator(
      settings: settings,
      uploader: SmbUploader(
        connector: share,
        source: memorySource(local, failing: {'a'}),
      ),
      listRecordings: () async => library,
      activeUris: () async => const {},
      deleteLocal: (uri) async => true,
      nowMs: () => now,
      scopeId: () => scope,
      onStatus: published.add,
    );
    await c.runOnce();
    await c.runOnce();
    expect(settings.ledger['a']!.failure, SmbFailureKind.readFailed);
    expect(settings.ledger['b']!.state, SmbUploadState.uploaded);
  });

  test('auth failure gives up until the target changes', () async {
    final c = make();
    await c.runOnce();
    share.connectError = const SmbException(SmbFailureKind.auth, 'bad login');
    await c.runOnce();
    expect(settings.ledger['a']!.state, SmbUploadState.gaveUp);
    now += 10 * 3600 * 1000;
    final connects = share.connects;
    await c.runOnce();
    // 'b' was never tried, so it is attempted (and fails) once.
    expect(share.connects, connects + 1);
    expect(settings.ledger['b']!.state, SmbUploadState.gaveUp);

    share.connectError = null;
    await c.targetChanged();
    expect(share.files.keys, containsAll(['a.ts', 'b.ts']));
  });

  test('targetChanged keeps uploaded records', () async {
    final c = make();
    await c.runOnce();
    await c.runOnce();
    final writes = share.writes;
    await c.targetChanged();
    expect(settings.ledger['a']!.state, SmbUploadState.uploaded);
    expect(share.writes, writes);
  });

  test('deletes the local copy only after a verified upload', () async {
    settings.target = settings.target.copyWith(deleteLocalAfterUpload: true);
    share.sizeSkew = 0;
    final c = make();
    await c.runOnce();
    await c.runOnce();
    expect(deleted, ['a', 'b']);
  });

  test('no delete when the upload failed', () async {
    settings.target = settings.target.copyWith(deleteLocalAfterUpload: true);
    share.sizeSkew = -1;
    final c = make();
    await c.runOnce();
    await c.runOnce();
    expect(deleted, isEmpty);
    expect(settings.ledger['a']!.failure, SmbFailureKind.sizeMismatch);
  });

  test('a throwing delete is ignored', () async {
    settings.target = settings.target.copyWith(deleteLocalAfterUpload: true);
    deleteError = StateError('nope');
    final c = make();
    await c.runOnce();
    await c.runOnce();
    expect(settings.ledger['b']!.state, SmbUploadState.uploaded);
  });

  test('a profile switch ends the run after the current file', () async {
    settings.target = settings.target.copyWith(deleteLocalAfterUpload: true);
    final c = make();
    await c.runOnce();
    share.beforeWrite = (path, writes) => scope = 'p2';
    await c.runOnce();
    expect(share.files.keys, ['a.ts']);
    expect(settings.ledger['a']!.state, SmbUploadState.uploaded);
    expect(deleted, isEmpty);
  });

  test('stop cancels the running upload and leaves the ledger alone', () async {
    final size = SmbUploader.chunkBytes * 3;
    local = {'big': bytesOf(size)};
    library = [rec('big', size, 1)];
    final c = make();
    await c.runOnce();
    share.beforeWrite = (path, writes) {
      if (writes == 0) c.stop();
    };
    await c.runOnce();
    expect(settings.ledger['big'], isNull);
    expect(share.files, isEmpty);
  });

  test('overlapping runOnce calls share one pass', () async {
    final c = make();
    await c.runOnce();
    final first = c.runOnce();
    final second = c.runOnce();
    await Future.wait([first, second]);
    expect(share.connects, 2);
    expect(listCalls, 2);
  });

  test('listing errors are reported, not thrown', () async {
    final c = make();
    listError = StateError('channel gone');
    await c.runOnce();
    expect(c.status.phase, SmbUploadPhase.idle);
    expect(c.status.lastFailure, SmbFailureKind.other);
    expect(c.status.lastMessage, contains('channel gone'));
  });

  test('start runs after the first delay, then on the interval', () {
    fakeAsync((async) {
      final c = make();
      c.start(
        firstDelay: const Duration(seconds: 30),
        interval: const Duration(minutes: 3),
      );
      c.start();
      async.elapse(const Duration(seconds: 29));
      expect(listCalls, 0);
      async.elapse(const Duration(seconds: 1));
      expect(listCalls, 1);
      async.elapse(const Duration(minutes: 3));
      expect(listCalls, 2);
      async.elapse(const Duration(minutes: 3));
      expect(listCalls, 3);
      c.stop();
      async.elapse(const Duration(minutes: 30));
      expect(listCalls, 3);
    });
  });

  test('status notifier publishes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(smbUploadStatusProvider), const SmbUploadStatus());
    const s = SmbUploadStatus(
      phase: SmbUploadPhase.idle,
      lastUploadedName: 'x',
    );
    container.read(smbUploadStatusProvider.notifier).publish(s);
    expect(container.read(smbUploadStatusProvider), s);
  });
}
