import 'dart:io';

import 'package:debrify/services/cache_scratch_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  // A future clock makes newly created directories old without OS-specific
  // directory timestamp mutation. Active files are explicitly dated `now`.
  final now = DateTime.now().add(const Duration(days: 3));
  final old = now.subtract(const Duration(days: 2));
  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('debrify-cleanup-test-');
    root = Directory(await temp.resolveSymbolicLinks());
  });
  tearDown(() async => root.delete(recursive: true));

  Future<File> file(String name, {bool aged = true}) async {
    final result = File(p.join(root.path, name));
    await result.parent.create(recursive: true);
    await result.writeAsString('fixture');
    await result.setLastModified(aged ? old : now);
    return result;
  }

  test(
    'removes old owned scratch but retains recent and unrelated files',
    () async {
      final stale = await file('xmltv_123.tmp');
      final recent = await file('xmltv_456.tmp', aged: false);
      final unrelated = await file('movie.mkv');
      final remote = await file('remote-transfers/transfer.part');
      final image = await file('debrifyImageCache/art.jpg');
      await CacheScratchCleanup.clean(root, now: now);
      expect(await stale.exists(), isFalse);
      for (final kept in [recent, unrelated, remote, image]) {
        expect(await kept.exists(), isTrue);
      }
    },
  );

  test('reclaims old picker copies and generated files', () async {
    final picker = await file('file_picker/123/backup.zip');
    final generated = await file('generated_downloads/123-list.json');
    await CacheScratchCleanup.clean(root, now: now);
    expect(await picker.exists(), isFalse);
    expect(await generated.exists(), isFalse);
    expect(await picker.parent.parent.exists(), isTrue);
  });

  test('preserves a scratch directory with a recent active child', () async {
    final active = await file('debrify-iptv-abc/playlist.m3u', aged: false);
    await CacheScratchCleanup.clean(root, now: now);
    expect(await active.exists(), isTrue);
  });

  test('never follows scratch or picker symlinks', () async {
    final original = await file('saved/original.zip');
    await Link(
      p.join(root.path, 'debrify-iptv-link'),
    ).create(original.parent.path);
    final picker = Directory(p.join(root.path, 'file_picker'));
    await picker.create();
    final link = Link(p.join(picker.path, 'linked'));
    await link.create(original.parent.path);
    await CacheScratchCleanup.clean(root, now: now);
    await CacheScratchCleanup.deletePickerCopy(
      root,
      p.join(link.path, 'original.zip'),
    );
    expect(await original.exists(), isTrue);
    expect(await link.exists(), isTrue);
  });

  test('explicit picker cleanup cannot remove a user original', () async {
    final selected = await file('file_picker/123/picture.jpg');
    final original = await file('pictures/picture.jpg');
    await CacheScratchCleanup.deletePickerCopy(root, original.path);
    expect(await original.exists(), isTrue);
    await CacheScratchCleanup.deletePickerCopy(root, selected.path);
    expect(await selected.exists(), isFalse);
  });
}
