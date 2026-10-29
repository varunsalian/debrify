import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/application/smb_uploader.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'smb_fakes.dart';

const _target = SmbTarget(
  enabled: true,
  host: 'nas',
  share: 'rec',
  folder: 'TV/Live',
  user: 'me',
);

SmbLocalRecording _rec(String uri, String name, int bytes) =>
    SmbLocalRecording(uri: uri, name: name, bytes: bytes, recordedAtMs: 1);

void main() {
  late FakeShare share;
  late Map<String, List<int>> local;

  setUp(() {
    share = FakeShare();
    local = {'content://1': bytesOf(2500)};
  });

  SmbUploader uploader({int piece = 1000, Set<String> failing = const {}}) =>
      SmbUploader(
        connector: share,
        source: memorySource(local, pieceBytes: piece, failing: failing),
      );

  test('uploads via a .part file into the folder, then renames', () async {
    final progress = <int>[];
    final outcome = await uploader().upload(
      target: _target,
      password: 'pw',
      recording: _rec('content://1', 'News 20:00.ts', 2500),
      onProgress: (sent, total) {
        expect(total, 2500);
        progress.add(sent);
      },
    );
    expect(outcome, isA<SmbUploaded>());
    expect((outcome as SmbUploaded).remotePath, 'TV/Live/News 20_00.ts');
    expect(share.files['TV/Live/News 20_00.ts'], local['content://1']);
    expect(share.files.containsKey('TV/Live/News 20_00.ts.part'), isFalse);
    expect(share.dirs, containsAll(['TV', 'TV/Live']));
    expect(share.lastPassword, 'pw');
    expect(share.lastTarget, _target);
    expect(progress.last, 2500);
    expect(share.closes, 1);
    expect(
      share.log.indexOf('open TV/Live/News 20_00.ts.part'),
      lessThan(
        share.log.indexOf(
          'rename TV/Live/News 20_00.ts.part -> TV/Live/News 20_00.ts',
        ),
      ),
    );
  });

  test('re-chunks small source pieces into chunkBytes writes', () async {
    expect(SmbUploader.chunkBytes, 1024 * 1024);
    final big = SmbUploader.chunkBytes * 2 + 10;
    local['content://big'] = bytesOf(big);
    final outcome = await uploader(piece: 64 * 1024).upload(
      target: _target,
      password: null,
      recording: _rec('content://big', 'big.ts', big),
    );
    expect(outcome, isA<SmbUploaded>());
    expect(share.writes, 3);
    expect(share.files['TV/Live/big.ts']!.length, big);
  });

  test('sanitises names and falls back for empty ones', () async {
    final a = await uploader().upload(
      target: const SmbTarget(host: 'nas', share: 'rec'),
      password: null,
      recording: _rec('content://1', 'a/b\\c:*?"<>|\u0001.ts', 2500),
    );
    expect((a as SmbUploaded).remotePath, 'a_b_c________.ts');
    final b = await uploader().upload(
      target: const SmbTarget(host: 'nas', share: 'rec'),
      password: null,
      recording: _rec('content://1', '', 2500),
    );
    expect((b as SmbUploaded).remotePath, 'recording.ts');
  });

  test('never overwrites: picks (2), (3)', () async {
    share.files['TV/Live/show.ts'] = [1];
    share.files['TV/Live/show (2).ts'] = [1];
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'show.ts', 2500),
    );
    expect((outcome as SmbUploaded).remotePath, 'TV/Live/show (3).ts');
    expect(share.files['TV/Live/show.ts'], [1]);
  });

  test('names without an extension get the counter at the end', () async {
    share.files['TV/Live/show'] = [1];
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'show', 2500),
    );
    expect((outcome as SmbUploaded).remotePath, 'TV/Live/show (2)');
  });

  test('no free name after (99)', () async {
    share.files['TV/Live/x.ts'] = [1];
    for (var i = 2; i <= 99; i++) {
      share.files['TV/Live/x ($i).ts'] = [1];
    }
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'x.ts', 2500),
    );
    expect(outcome, isA<SmbUploadFailed>());
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.other);
    expect(share.closes, 1);
  });

  test('a stale .part is removed first', () async {
    share.files['TV/Live/a.ts.part'] = [9, 9];
    await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect(share.log, contains('delete TV/Live/a.ts.part'));
    expect(share.files['TV/Live/a.ts']!.length, 2500);
  });

  test('connect failure maps its kind and never closes', () async {
    share.connectError = const SmbException(SmbFailureKind.auth, 'bad login');
    final outcome = await uploader().upload(
      target: _target,
      password: 'x',
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect(outcome, isA<SmbUploadFailed>());
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.auth);
    expect(outcome.message, 'bad login');
    expect(share.closes, 0);
  });

  test('write failure cleans the .part and closes', () async {
    share.writeError = const SmbException(SmbFailureKind.network, 'reset');
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.network);
    expect(share.files.keys, isNot(contains('TV/Live/a.ts.part')));
    expect(share.files.keys, isNot(contains('TV/Live/a.ts')));
    expect(share.closes, 1);
  });

  test('non-SMB errors map to other', () async {
    share.writeError = StateError('boom');
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.other);
    expect(share.closes, 1);
  });

  test('unreadable local file is readFailed', () async {
    final outcome = await uploader(failing: {'content://1'}).upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.readFailed);
    expect(share.files.keys, isNot(contains('TV/Live/a.ts.part')));
    expect(share.closes, 1);
  });

  test('local size differs from the library entry: sizeMismatch', () async {
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 3000),
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.sizeMismatch);
    expect(share.files.keys, isNot(contains('TV/Live/a.ts.part')));
    expect(share.files.keys, isNot(contains('TV/Live/a.ts')));
  });

  test('remote size differs: sizeMismatch', () async {
    share.sizeSkew = -1;
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.sizeMismatch);
    expect(share.files.keys, isNot(contains('TV/Live/a.ts')));
  });

  test('rename failure cleans up', () async {
    share.renameFails.add('TV/Live/a.ts.part');
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.accessDenied);
    expect(share.files.keys, isNot(contains('TV/Live/a.ts.part')));
    expect(share.closes, 1);
  });

  test('cancel stops before the next write and cleans up', () async {
    local['content://big'] = bytesOf(SmbUploader.chunkBytes * 3);
    final token = SmbCancelToken();
    share.beforeWrite = (path, writes) {
      if (writes == 1) token.cancel();
    };
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://big', 'a.ts', SmbUploader.chunkBytes * 3),
      cancel: token,
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.cancelled);
    expect(share.writes, 2);
    expect(share.files.keys, isNot(contains('TV/Live/a.ts.part')));
    expect(share.closes, 1);
  });

  test('already cancelled token writes nothing', () async {
    final token = SmbCancelToken()..cancel();
    final outcome = await uploader().upload(
      target: _target,
      password: null,
      recording: _rec('content://1', 'a.ts', 2500),
      cancel: token,
    );
    expect((outcome as SmbUploadFailed).kind, SmbFailureKind.cancelled);
    expect(share.writes, 0);
  });

  group('probe', () {
    test('success writes and removes the probe file', () async {
      final result = await uploader().probe(target: _target, password: 'pw');
      expect(result, isNull);
      expect(share.log, contains('open TV/Live/.debrify_probe'));
      expect(share.log, contains('delete TV/Live/.debrify_probe'));
      expect(share.files, isEmpty);
      expect(share.closes, 1);
    });

    test('probe at the share root', () async {
      await uploader().probe(
        target: const SmbTarget(host: 'nas', share: 'rec'),
        password: null,
      );
      expect(share.log, contains('open .debrify_probe'));
    });

    test('failures are returned', () async {
      share.connectError = const SmbException(
        SmbFailureKind.notFound,
        'no share',
      );
      final result = await uploader().probe(target: _target, password: null);
      expect(result!.kind, SmbFailureKind.notFound);
      expect(result.message, 'no share');
    });

    test('write failure still closes', () async {
      share.writeError = const SmbException(
        SmbFailureKind.accessDenied,
        'read only',
      );
      final result = await uploader().probe(target: _target, password: null);
      expect(result!.kind, SmbFailureKind.accessDenied);
      expect(share.closes, 1);
    });
  });
}
