import 'dart:convert';

import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

SmbUploadRecord _rec(String uri, int updatedAtMs, {SmbUploadState? state}) =>
    SmbUploadRecord(
      uri: uri,
      bytes: 10,
      state: state ?? SmbUploadState.uploaded,
      updatedAtMs: updatedAtMs,
    );

void main() {
  group('SmbUploadRecord json', () {
    test('round trip with every field', () {
      const r = SmbUploadRecord(
        uri: 'content://a',
        bytes: 99,
        state: SmbUploadState.failed,
        attempts: 2,
        failure: SmbFailureKind.network,
        message: 'down',
        remotePath: 'TV/a.ts',
        updatedAtMs: 5,
        nextAttemptAtMs: 9,
      );
      expect(SmbUploadRecord.fromJson(r.toJson()), r);
      expect(r.toJson()['state'], 'failed');
      expect(r.toJson()['failure'], 'network');
    });

    test('null fields are omitted', () {
      final json = _rec('u', 1).toJson();
      expect(json.containsKey('failure'), isFalse);
      expect(json.containsKey('message'), isFalse);
      expect(json.containsKey('remotePath'), isFalse);
      expect(json.containsKey('nextAttemptAtMs'), isFalse);
    });

    test('invalid input is null', () {
      expect(SmbUploadRecord.fromJson(null), isNull);
      expect(SmbUploadRecord.fromJson('x'), isNull);
      expect(SmbUploadRecord.fromJson({'bytes': 1}), isNull);
      expect(
        SmbUploadRecord.fromJson({
          'uri': 'u',
          'bytes': 1,
          'state': 'bogus',
          'updatedAtMs': 1,
        }),
        isNull,
      );
      expect(
        SmbUploadRecord.fromJson({'uri': 'u', 'bytes': 1, 'state': 'uploaded'}),
        isNull,
      );
    });

    test('unknown failure name is dropped, record kept', () {
      final r = SmbUploadRecord.fromJson({
        'uri': 'u',
        'bytes': 1,
        'state': 'failed',
        'updatedAtMs': 1,
        'failure': 'martian',
      });
      expect(r, isNotNull);
      expect(r!.failure, isNull);
    });
  });

  group('SmbUploadLedger', () {
    test('withRecord stores by uri and replaces', () {
      final l = const SmbUploadLedger()
          .withRecord(_rec('a', 1))
          .withRecord(_rec('a', 2, state: SmbUploadState.failed));
      expect(l.records.length, 1);
      expect(l['a']!.state, SmbUploadState.failed);
      expect(l['missing'], isNull);
    });

    test('caps at maxRecords dropping the oldest, never the new one', () {
      var l = const SmbUploadLedger();
      for (var i = 0; i < SmbUploadLedger.maxRecords; i++) {
        l = l.withRecord(_rec('u$i', 100 + i));
      }
      // The new record is the oldest by time but must survive.
      l = l.withRecord(_rec('new', 0));
      expect(l.records.length, SmbUploadLedger.maxRecords);
      expect(l['new'], isNotNull);
      expect(l['u0'], isNull);
      expect(l['u1'], isNotNull);
    });

    test('withRecord does not mutate the original', () {
      const empty = SmbUploadLedger();
      empty.withRecord(_rec('a', 1));
      expect(empty.records, isEmpty);
    });

    test('withoutFailures keeps only uploaded', () {
      final l = const SmbUploadLedger()
          .withRecord(_rec('a', 1))
          .withRecord(_rec('b', 1, state: SmbUploadState.failed))
          .withRecord(_rec('c', 1, state: SmbUploadState.gaveUp))
          .withoutFailures();
      expect(l.records.keys, ['a']);
    });

    test('encode is a JSON list and decodes back', () {
      final l = const SmbUploadLedger()
          .withRecord(_rec('a', 1))
          .withRecord(_rec('b', 2, state: SmbUploadState.gaveUp));
      expect(jsonDecode(l.encode()), isA<List<dynamic>>());
      final back = SmbUploadLedger.decode(l.encode());
      expect(back['a'], l['a']);
      expect(back['b'], l['b']);
    });

    test('decode is tolerant', () {
      expect(SmbUploadLedger.decode(null).records, isEmpty);
      expect(SmbUploadLedger.decode('{').records, isEmpty);
      expect(SmbUploadLedger.decode('{"a":1}').records, isEmpty);
      final mixed = jsonEncode([
        _rec('ok', 1).toJson(),
        {'junk': true},
        3,
      ]);
      expect(SmbUploadLedger.decode(mixed).records.keys, ['ok']);
    });
  });

  group('SmbUploadStatus', () {
    test('percent', () {
      expect(const SmbUploadStatus().percent, 0);
      expect(const SmbUploadStatus(sentBytes: 1, totalBytes: 3).percent, 33);
      expect(const SmbUploadStatus(sentBytes: 5, totalBytes: 3).percent, 100);
      expect(const SmbUploadStatus(sentBytes: -1, totalBytes: 3).percent, 0);
    });

    test('defaults and copyWith', () {
      const s = SmbUploadStatus();
      expect(s.phase, SmbUploadPhase.disabled);
      final u = s.copyWith(
        phase: SmbUploadPhase.uploading,
        currentName: 'a.ts',
        totalBytes: 10,
      );
      expect(u.phase, SmbUploadPhase.uploading);
      expect(u.currentName, 'a.ts');
      expect(u.copyWith(sentBytes: 5).currentName, 'a.ts');
      expect(s.copyWith(), s);
      expect(u == s, isFalse);
    });
  });

  test('SmbLocalRecording equality', () {
    const a = SmbLocalRecording(uri: 'u', name: 'n', bytes: 1, recordedAtMs: 2);
    expect(
      a,
      const SmbLocalRecording(uri: 'u', name: 'n', bytes: 1, recordedAtMs: 2),
    );
    expect(
      a ==
          const SmbLocalRecording(
            uri: 'u',
            name: 'n',
            bytes: 2,
            recordedAtMs: 2,
          ),
      isFalse,
    );
  });
}
