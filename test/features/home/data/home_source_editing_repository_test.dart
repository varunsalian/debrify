import 'dart:async';

import 'package:debrify/features/home/data/home_source_editing_repository.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SeriesSource source(String id) => SeriesSource(
  torrentHash: id,
  torrentName: id,
  debridService: 'rd',
  debridTorrentId: id,
  boundAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'series append/dedupe, movie replacement, reorder and exact removal persist',
    () async {
      final repository = HomeSourceEditingRepository(
        ProfileSessionMemory.captureOwner(),
      );
      Future<List<String>> names() async => (await repository.load(
        'tt1',
        isCurrent: () => true,
      ))!.map((s) => s.torrentName).toList();
      await repository.save(
        'tt1',
        source('one'),
        isMovie: false,
        isCurrent: () => true,
      );
      await repository.save(
        'tt1',
        source('two'),
        isMovie: false,
        isCurrent: () => true,
      );
      await repository.save(
        'tt1',
        source('one'),
        isMovie: false,
        isCurrent: () => true,
      );
      expect(await names(), ['one', 'two']);
      await repository.replace('tt1', [
        source('two'),
        source('one'),
      ], isCurrent: () => true);
      expect(await names(), ['two', 'one']);
      await repository.remove('tt1', source('two'), isCurrent: () => true);
      expect(await names(), ['one']);
      await repository.save(
        'tt1',
        source('movie'),
        isMovie: true,
        isCurrent: () => true,
      );
      expect(await names(), ['movie']);
      await repository.replace('tt1', [], isCurrent: () => true);
      expect(await names(), isEmpty);
    },
  );

  for (final retire in ['view', 'profile']) {
    test(
      '$retire retirement while save waits on mutation barrier leaves storage unchanged',
      () async {
        final repository = HomeSourceEditingRepository(
          ProfileSessionMemory.captureOwner(),
        );
        await SeriesSourceService.setSources('tt1', [source('original')]);
        final prefs = await SharedPreferences.getInstance();
        final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        final entered = Completer<void>(), release = Completer<void>();
        final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var current = true;
        final pending = repository.save(
          'tt1',
          source('new'),
          isMovie: true,
          isCurrent: () => current,
        );
        await Future<void>.delayed(Duration.zero);
        if (retire == 'view') {
          current = false;
        } else {
          ProfileSessionMemory.clearAll();
        }
        release.complete();
        await barrier;
        expect(await pending, isFalse);
        expect({
          for (final key in prefs.getKeys()) key: prefs.get(key),
        }, before);
      },
    );
  }

  test(
    'retired owner cannot load, discover providers or modify sources',
    () async {
      final repository = HomeSourceEditingRepository(
        ProfileSessionMemory.captureOwner(),
      );
      ProfileSessionMemory.clearAll();
      expect(await repository.load('tt1', isCurrent: () => true), isNull);
      expect(await repository.providers(isCurrent: () => true), isNull);
      expect(
        await repository.remove('tt1', source('one'), isCurrent: () => true),
        isFalse,
      );
      expect(
        await repository.replace('tt1', [], isCurrent: () => true),
        isFalse,
      );
    },
  );
}
