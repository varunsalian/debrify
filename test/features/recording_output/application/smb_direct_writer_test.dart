// Recording straight to the share: what lands there, what a failed write
// hands back for the local fallback, and the cleanup of an empty capture.
import 'dart:typed_data';

import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/application/smb_direct_writer.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'smb_fakes.dart';

const _target = SmbTarget(
  enabled: true,
  host: 'nas',
  share: 'media',
  folder: 'TV/Recordings',
);

Uint8List _bytes(int count, [int value = 7]) =>
    Uint8List.fromList(List.filled(count, value));

void main() {
  late FakeShare share;

  setUp(() => share = FakeShare());

  Future<SmbDirectWriter> open({String fileName = 'News 2026-10-30.ts'}) =>
      SmbDirectWriter.open(
        connector: share,
        target: _target,
        password: 'pw',
        fileName: fileName,
      );

  test('creates the folder and streams every byte to one file', () async {
    final writer = await open();
    expect(writer.remotePath, 'TV/Recordings/News 2026-10-30.ts');
    expect(writer.label, r'\\nas\media\TV\Recordings\News 2026-10-30.ts');
    expect(share.dirs, containsAll(['TV', 'TV/Recordings']));

    for (var i = 0; i < 5; i++) {
      await writer.add(_bytes(400 * 1024));
    }
    await writer.close();

    expect(share.files[writer.remotePath], hasLength(5 * 400 * 1024));
    expect(writer.bytesWritten, 5 * 400 * 1024);
    expect(share.closes, 1);
  });

  test('small pieces are gathered into megabyte writes', () async {
    final writer = await open();
    for (var i = 0; i < 64; i++) {
      await writer.add(_bytes(32 * 1024));
    }
    expect(share.writes, 2, reason: '2 MB in 32 KB pieces');
    await writer.close();
    expect(share.writes, 2);
  });

  test('a taken name gets a numbered twin', () async {
    share.files['TV/Recordings/News.ts'] = [1];
    final writer = await open(fileName: 'News.ts');
    expect(writer.remotePath, 'TV/Recordings/News (2).ts');
    await writer.abandon();
  });

  test('a failed write keeps the unsent bytes for the local file', () async {
    final writer = await open();
    await writer.add(_bytes(SmbDirectWriter.flushBytes, 1));
    share.writeError = const SmbException(SmbFailureKind.network, 'dropped');
    await expectLater(
      writer.add(_bytes(SmbDirectWriter.flushBytes, 2)),
      throwsA(isA<SmbException>()),
    );

    final unsent = writer.takeUnsent();
    expect(unsent, hasLength(SmbDirectWriter.flushBytes));
    expect(unsent.every((b) => b == 2), isTrue);
    expect(writer.takeUnsent(), isEmpty, reason: 'taken once');
    await writer.abandon();
    // What reached the share before the drop stays there.
    expect(
      share.files[writer.remotePath],
      hasLength(SmbDirectWriter.flushBytes),
    );
    expect(share.closes, 1);
  });

  test('a failed last write on close also hands its bytes back', () async {
    final writer = await open();
    await writer.add(_bytes(1000));
    share.writeError = const SmbException(SmbFailureKind.network, 'dropped');
    await expectLater(writer.close(), throwsA(isA<SmbException>()));
    expect(writer.takeUnsent(), hasLength(1000));
    expect(share.closes, 1, reason: 'logged off anyway');
  });

  test('a capture that saved nothing leaves no empty file', () async {
    final writer = await open();
    await writer.close();
    expect(share.files.containsKey(writer.remotePath), isFalse);

    final abandoned = await open();
    await abandoned.abandon();
    expect(share.files.containsKey(abandoned.remotePath), isFalse);
  });

  test('a share that cannot be reached throws and holds no session', () async {
    share.connectError = const SmbException(SmbFailureKind.auth, 'denied');
    await expectLater(open(), throwsA(isA<SmbException>()));
    expect(share.closes, 0);
  });
}
