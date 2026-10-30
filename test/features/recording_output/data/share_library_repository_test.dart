// The share's recordings as the Recordings page lists them.
import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/data/share_library_repository.dart';
import 'package:debrify/features/recording_output/models/share_recording.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/smb_fakes.dart';

const _target = SmbTarget(
  enabled: true,
  host: 'nas',
  share: 'media',
  folder: 'TV/Rec',
);

void main() {
  late FakeShare share;
  late FakeSettings settings;
  late ShareLibraryRepository repository;

  setUp(() {
    share = FakeShare();
    settings = FakeSettings(target: _target, password: 'pw');
    repository = ShareLibraryRepository(connector: share, store: settings);
  });

  test('no share set up gives null and never connects', () async {
    settings.target = const SmbTarget(host: 'nas', share: 'media');
    expect(await repository.load(), isNull);
    settings.target = const SmbTarget(enabled: true, host: 'nas');
    expect(await repository.load(), isNull);
    expect(share.connects, 0);
  });

  test('lists video files newest first, nothing else', () async {
    share.files['TV/Rec/old.ts'] = [1, 2];
    share.files['TV/Rec/new.ts'] = [1, 2, 3];
    share.files['TV/Rec/clip.MP4'] = [1];
    share.files['TV/Rec/new.ts.part'] = [1];
    share.files['TV/Rec/.debrify_probe'] = [1];
    share.files['TV/Rec/notes.txt'] = [1];
    share.dirs.add('TV/Rec/Sub');
    share.modified['TV/Rec/old.ts'] = DateTime.utc(2026, 10, 1);
    share.modified['TV/Rec/new.ts'] = DateTime.utc(2026, 10, 30);
    share.modified['TV/Rec/clip.MP4'] = DateTime.utc(2026, 10, 15);

    final library = (await repository.load())!;
    expect(library.address, r'\\nas\media\TV\Rec');
    expect(library.recordsDirect, isTrue);
    expect(library.error, isNull);
    expect(library.recordings.map((r) => r.name), [
      'new.ts',
      'clip.MP4',
      'old.ts',
    ]);
    expect(library.recordings.first.path, 'TV/Rec/new.ts');
    expect(library.recordings.first.title, 'new');
    expect(library.totalBytes, 6);
    expect(share.closes, 1, reason: 'one short session');
  });

  test('a folder no recording has created yet is an empty list', () async {
    share.listError = const SmbException(SmbFailureKind.notFound, 'none');
    final library = (await repository.load())!;
    expect(library.recordings, isEmpty);
    expect(library.error, isNull);
  });

  test('an unreachable share explains itself instead of failing', () async {
    share.connectError = const SmbException(SmbFailureKind.network, 'down');
    final down = (await repository.load())!;
    expect(down.error, 'The share cannot be reached right now');
    expect(down.address, r'\\nas\media\TV\Rec');

    share
      ..connectError = null
      ..listError = const SmbException(SmbFailureKind.auth, 'no');
    expect(
      (await repository.load())!.error,
      'The share refused the user name or password',
    );
  });

  test('delete removes the file and logs off', () async {
    share.files['TV/Rec/a.ts'] = [1];
    final library = (await repository.load())!;
    await repository.delete(library.recordings.single);
    expect(share.files.containsKey('TV/Rec/a.ts'), isFalse);
    expect(share.closes, 2);
  });

  test('delete without a share set up refuses', () async {
    settings.target = const SmbTarget();
    await expectLater(
      repository.delete(
        ShareRecording(
          name: 'a.ts',
          path: 'a.ts',
          bytes: 1,
          modified: DateTime.utc(2026),
        ),
      ),
      throwsA(isA<SmbException>()),
    );
  });
}
