import 'package:debrify/features/recording_output/application/smb_upload_policy.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

SmbLocalRecording _r(String uri, {int bytes = 100, int at = 0}) =>
    SmbLocalRecording(
      uri: uri,
      name: '$uri.ts',
      bytes: bytes,
      recordedAtMs: at,
    );

SmbUploadLedger _ledger(List<SmbUploadRecord> records) =>
    records.fold(const SmbUploadLedger(), (l, r) => l.withRecord(r));

List<String> _ready({
  required List<SmbLocalRecording> current,
  Map<String, int>? previous,
  Set<String> active = const {},
  SmbUploadLedger ledger = const SmbUploadLedger(),
  int nowMs = 1000,
}) => smbReadyForUpload(
  current: current,
  previousBytes: previous ?? {for (final r in current) r.uri: r.bytes},
  activeUris: active,
  ledger: ledger,
  nowMs: nowMs,
).map((r) => r.uri).toList();

void main() {
  test('retry delay ladder', () {
    expect(smbRetryDelay(0), const Duration(minutes: 1));
    expect(smbRetryDelay(1), const Duration(minutes: 1));
    expect(smbRetryDelay(2), const Duration(minutes: 5));
    expect(smbRetryDelay(3), const Duration(minutes: 15));
    expect(smbRetryDelay(4), const Duration(minutes: 60));
    expect(smbRetryDelay(40), const Duration(minutes: 60));
  });

  test('permanent and run-stopping failures', () {
    final permanent = {
      SmbFailureKind.auth,
      SmbFailureKind.notFound,
      SmbFailureKind.accessDenied,
    };
    final stopping = {
      ...permanent,
      SmbFailureKind.network,
      SmbFailureKind.noSpace,
    };
    for (final k in SmbFailureKind.values) {
      expect(isPermanentSmbFailure(k), permanent.contains(k), reason: k.name);
      expect(stopsSmbRun(k), stopping.contains(k), reason: k.name);
    }
  });

  group('smbReadyForUpload', () {
    test('stable new recordings, oldest first, ties by uri', () {
      expect(
        _ready(current: [_r('c', at: 5), _r('b', at: 1), _r('a', at: 5)]),
        ['b', 'a', 'c'],
      );
    });

    test('size must match the previous scan', () {
      expect(_ready(current: [_r('a')], previous: {}), isEmpty);
      expect(_ready(current: [_r('a')], previous: {'a': 50}), isEmpty);
    });

    test('empty and active files are skipped', () {
      expect(_ready(current: [_r('a', bytes: 0)]), isEmpty);
      expect(_ready(current: [_r('a')], active: {'a'}), isEmpty);
    });

    test('uploaded and gaveUp with same size are never ready', () {
      final ledger = _ledger([
        const SmbUploadRecord(
          uri: 'a',
          bytes: 100,
          state: SmbUploadState.uploaded,
          updatedAtMs: 1,
        ),
        const SmbUploadRecord(
          uri: 'b',
          bytes: 100,
          state: SmbUploadState.gaveUp,
          updatedAtMs: 1,
        ),
      ]);
      expect(_ready(current: [_r('a'), _r('b')], ledger: ledger), isEmpty);
    });

    test('a changed file starts over', () {
      final ledger = _ledger([
        const SmbUploadRecord(
          uri: 'a',
          bytes: 50,
          state: SmbUploadState.gaveUp,
          updatedAtMs: 1,
        ),
      ]);
      expect(_ready(current: [_r('a')], ledger: ledger), ['a']);
    });

    test('failed waits for nextAttemptAtMs', () {
      SmbUploadLedger failed(int? next) => _ledger([
        SmbUploadRecord(
          uri: 'a',
          bytes: 100,
          state: SmbUploadState.failed,
          attempts: 1,
          updatedAtMs: 1,
          nextAttemptAtMs: next,
        ),
      ]);
      expect(_ready(current: [_r('a')], ledger: failed(2000)), isEmpty);
      expect(_ready(current: [_r('a')], ledger: failed(1000)), ['a']);
      expect(_ready(current: [_r('a')], ledger: failed(null)), ['a']);
    });
  });

  group('smbFailedRecord', () {
    final rec = _r('a');

    test('first failure', () {
      final r = smbFailedRecord(
        previous: null,
        recording: rec,
        kind: SmbFailureKind.network,
        message: 'down',
        nowMs: 1000,
      );
      expect(r.uri, 'a');
      expect(r.bytes, 100);
      expect(r.attempts, 1);
      expect(r.state, SmbUploadState.failed);
      expect(r.failure, SmbFailureKind.network);
      expect(r.message, 'down');
      expect(r.updatedAtMs, 1000);
      expect(
        r.nextAttemptAtMs,
        1000 + const Duration(minutes: 1).inMilliseconds,
      );
    });

    test('attempts grow and give up at the maximum', () {
      final prev = SmbUploadRecord(
        uri: 'a',
        bytes: 100,
        state: SmbUploadState.failed,
        attempts: maxSmbUploadAttempts - 1,
        updatedAtMs: 1,
      );
      final r = smbFailedRecord(
        previous: prev,
        recording: rec,
        kind: SmbFailureKind.other,
        nowMs: 5,
      );
      expect(r.attempts, maxSmbUploadAttempts);
      expect(r.state, SmbUploadState.gaveUp);
      expect(r.nextAttemptAtMs, isNull);
    });

    test('second attempt uses the 5 minute delay', () {
      final prev = const SmbUploadRecord(
        uri: 'a',
        bytes: 100,
        state: SmbUploadState.failed,
        attempts: 1,
        updatedAtMs: 1,
      );
      final r = smbFailedRecord(
        previous: prev,
        recording: rec,
        kind: SmbFailureKind.other,
        nowMs: 0,
      );
      expect(r.attempts, 2);
      expect(r.nextAttemptAtMs, const Duration(minutes: 5).inMilliseconds);
    });

    test('permanent failure gives up at once', () {
      final r = smbFailedRecord(
        previous: null,
        recording: rec,
        kind: SmbFailureKind.auth,
        nowMs: 0,
      );
      expect(r.state, SmbUploadState.gaveUp);
      expect(r.nextAttemptAtMs, isNull);
    });

    test('previous record for different bytes resets attempts', () {
      final prev = const SmbUploadRecord(
        uri: 'a',
        bytes: 7,
        state: SmbUploadState.failed,
        attempts: 5,
        updatedAtMs: 1,
      );
      final r = smbFailedRecord(
        previous: prev,
        recording: rec,
        kind: SmbFailureKind.other,
        nowMs: 0,
      );
      expect(r.attempts, 1);
      expect(r.state, SmbUploadState.failed);
    });
  });
}
