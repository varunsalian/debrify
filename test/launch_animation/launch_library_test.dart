import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/services/launch_animation/launch_package.dart';
import 'launch_package_test.dart' show packageBytes, animation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LaunchAnimationLibrary library;
  late File source;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('launch-library-test-');
    library = LaunchAnimationLibrary(
      directory: () async => Directory('${root.path}/library'),
    );
    source = await File(
      '${root.path}/source.lottie',
    ).writeAsBytes(packageBytes());
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'installs, loads offline, restarts and deletes only requested content',
    () async {
      final a = await library.install(source);
      final b = await library.install(source);
      await source.delete();
      final restarted = LaunchAnimationLibrary(
        directory: () async => Directory('${root.path}/library'),
      );
      final loaded = await restarted.load(a.id);
      expect(loaded.composition.duration.inMilliseconds, greaterThan(1900));
      loaded.dispose();
      await restarted.delete(b.id);
      expect((await restarted.list()).map((e) => e.id), [a.id]);
      expect(await (await restarted.originalFile(a.id)).exists(), isTrue);
    },
  );
  test('concurrent imports preserve both index entries', () async {
    final entries = await Future.wait([
      library.install(source),
      library.install(source),
    ]);
    expect(
      (await library.list()).map((e) => e.id).toSet(),
      entries.map((e) => e.id).toSet(),
    );
  });
  test('failed import and revoked commit preserve existing library', () async {
    final entry = await library.install(source);
    await expectLater(
      library.install(source, animationId: 'missing'),
      throwsA(isA<LaunchImportException>()),
    );
    await expectLater(
      library.install(
        source,
        beforeCommit: () async => throw StateError('revoked'),
      ),
      throwsStateError,
    );
    expect((await library.list(clean: true)).single.id, entry.id);
  });
  test(
    'corrupt index is preserved and never used for orphan cleanup',
    () async {
      final entry = await library.install(source);
      await File('${root.path}/library/index.json').writeAsString('broken');
      await expectLater(
        library.list(clean: true),
        throwsA(isA<LaunchImportException>()),
      );
      expect(
        await Directory('${root.path}/library/${entry.id}').exists(),
        isTrue,
      );
      await library.resetDamagedIndex();
      expect(await library.list(), isEmpty);
      expect(
        await Directory(
          '${root.path}/library',
        ).list().any((f) => f.path.contains('index-damaged-')),
        isTrue,
      );
    },
  );
  test('revalidates persisted JSON before loading renderer objects', () async {
    final entry = await library.install(source);
    await File(
      '${root.path}/library/${entry.id}/animation.json',
    ).writeAsString(jsonEncode(animation(frames: 900)));
    await expectLater(
      library.load(entry.id),
      throwsA(isA<LaunchImportException>()),
    );
    expect((await library.list()).single.id, entry.id);
  });
  test(
    'settings cleanup recovers interrupted publication without losing imports',
    () async {
      final entry = await library.install(source);
      final pending = Directory('${root.path}/library/pending-${'b' * 32}');
      final unpublished = Directory('${root.path}/library/${'c' * 32}');
      await pending.create();
      await unpublished.create();
      await File(
        '${root.path}/library/index.tmp',
      ).writeAsString('interrupted write');
      final entries = await library.list(clean: true);
      expect(entries.single.id, entry.id);
      expect(await pending.exists(), isFalse);
      expect(await unpublished.exists(), isFalse);
      final loaded = await library.load(entry.id);
      loaded.dispose();
    },
  );
  test('missing prepared files fail without damaging index', () async {
    final entry = await library.install(source);
    await File('${root.path}/library/${entry.id}/animation.json').delete();
    await expectLater(
      library.load(entry.id),
      throwsA(isA<FileSystemException>()),
    );
    expect((await library.list()).single.id, entry.id);
  });
}
