import 'dart:async';

import 'package:debrify/features/search/application/keyword_cache_controller.dart';
import 'package:debrify/features/search/application/keyword_cache_dependencies.dart';
import 'package:debrify/features/search/data/keyword_cache_repository.dart';
import 'package:debrify/features/search/models/keyword_cache_state.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_keyword_cache_repository.dart';
import '../keyword_torrent_fixture.dart';

void main() {
  late FakeKeywordCacheRepository repository;
  late ProviderContainer container;
  late SearchSession key;
  late KeywordCacheController controller;
  late ProviderSubscription<KeywordCacheState> subscription;
  KeywordCacheState current() => subscription.read();
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repository = FakeKeywordCacheRepository();
    key = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        keywordCacheRepositoryProvider.overrideWith(
          (ref, session) => repository,
        ),
      ],
    );
    subscription = container.listen(keywordCacheProvider(key), (_, _) {});
    controller = container.read(keywordCacheProvider(key).notifier);
  });

  test(
    'construction and state reads do not load credentials or call providers',
    () {
      expect(current().badges, isEmpty);
      expect(repository.opens, 0);
      expect(repository.session.torboxCalls, isEmpty);
    },
  );

  test(
    'batch badges arrive before cached-only mode and final sweep skips confirmed hashes',
    () async {
      await controller.begin(1);
      controller.checkBatch([keywordTorrent('ABC')], 1);
      await settle();
      expect(current().badges, {
        'abc': ['TB'],
      });
      expect(current().cachedOnly, isFalse);
      expect(await controller.finish([keywordTorrent('ABC')], 1), isTrue);
      expect(current().cachedOnly, isTrue);
      expect(repository.session.torboxCalls, [
        ['abc'],
      ]);
      expect(repository.opens, 1);
    },
  );

  test(
    'completion waits for every batch before filtering and sweeps stragglers',
    () async {
      final pending = Completer<Set<String>>();
      repository.session.tb = (hashes) =>
          hashes.contains('a') ? pending.future : Future.value(hashes.toSet());
      await controller.begin(1);
      controller.checkBatch([keywordTorrent('a')], 1);
      var completed = false;
      final finishing = controller.finish([
        keywordTorrent('a'),
        keywordTorrent('b'),
      ], 1)..then((_) => completed = true);
      await settle();
      expect(completed, isFalse);
      expect(current().cachedOnly, isFalse);
      pending.complete({'a'});
      expect(await finishing, isTrue);
      expect(repository.session.torboxCalls, [
        ['a'],
        ['b'],
      ]);
      expect(current().badges, {
        'a': ['TB'],
        'b': ['TB'],
      });
    },
  );

  test(
    'failed providers are retryable and PM response length is bounded',
    () async {
      repository.session.premiumizeEnabled = true;
      repository.session.otherProviderActive = true;
      var attempt = 0;
      repository.session.pm = (_) async {
        if (attempt++ == 0) throw StateError('temporary');
        return [true];
      };
      await controller.begin(1);
      final torrents = [keywordTorrent('a'), keywordTorrent('b')];
      controller.checkBatch(torrents, 1);
      await settle();
      expect(current().badges, {
        'a': ['TB'],
        'b': ['TB'],
      });
      expect(await controller.finish(torrents, 1), isFalse);
      expect(repository.session.torboxCalls.length, 2);
      expect(repository.session.premiumizeCalls.length, 2);
      expect(current().badges, {
        'a': ['TB', 'PM'],
        'b': ['TB'],
      });
      expect(current().cachedOnly, isFalse);
      await controller.check(torrents, 1);
      expect(repository.session.torboxCalls.length, 2);
    },
  );

  test('a failed TorBox check never enables cached-only filtering', () async {
    repository.session.tb = (_) async => throw StateError('offline');
    await controller.begin(1);
    controller.checkBatch([keywordTorrent('a')], 1);
    expect(await controller.finish([keywordTorrent('a')], 1), isFalse);
    expect(current().cachedOnly, isFalse);
    expect(repository.session.torboxCalls.length, 2);
  });

  test('a successful empty TorBox response enables cached-only mode', () async {
    repository.session.tb = (_) async => {};
    await controller.begin(1);
    expect(await controller.finish([keywordTorrent('a')], 1), isTrue);
    expect(current().badges, isEmpty);
    expect(current().cachedOnly, isTrue);
  });

  test(
    'another active provider prevents narrowing even without its own cache check',
    () async {
      repository.session.otherProviderActive = true;
      await controller.begin(1);
      expect(await controller.finish([keywordTorrent('a')], 1), isFalse);
      expect(current().badges, {
        'a': ['TB'],
      });
      expect(current().cachedOnly, isFalse);
      expect(repository.session.premiumizeCalls, isEmpty);
    },
  );

  test('disabled providers and empty hashes do not issue requests', () async {
    repository.session.torboxEnabled = false;
    await controller.begin(1);
    await controller.finish([
      keywordTorrent('a'),
      keywordTorrent('empty', hash: ''),
    ], 1);
    expect(repository.session.torboxCalls, isEmpty);
    expect(repository.session.premiumizeCalls, isEmpty);
    expect(current().cachedOnly, isFalse);
  });

  test(
    'legacy lowercasing, whitespace and duplicate dispatch are preserved',
    () async {
      await controller.begin(1);
      await controller.check([
        keywordTorrent(' A '),
        keywordTorrent('A'),
        keywordTorrent('a'),
      ], 1);
      expect(repository.session.torboxCalls, [
        [' a ', 'a', 'a'],
      ]);
    },
  );

  test('old cache work cannot stamp or memoize a newer query', () async {
    final old = Completer<Set<String>>();
    final oldSession = repository.session;
    oldSession.tb = (_) => old.future;
    await controller.begin(1);
    final oldCheck = controller.check([keywordTorrent('a')], 1);
    repository.session = FakeKeywordCacheSession();
    await controller.begin(2);
    old.complete({'a'});
    await oldCheck;
    expect(current().badges, isEmpty);
    await controller.finish([keywordTorrent('a')], 2);
    expect(repository.session.torboxCalls, [
      ['a'],
    ]);
    expect(current().badges, {
      'a': ['TB'],
    });
  });

  test('a late configuration cannot replace the new query session', () async {
    final old = Completer<KeywordCacheSession>();
    final active = FakeKeywordCacheSession()..otherProviderActive = true;
    repository.configure = () =>
        repository.opens == 1 ? old.future : Future.value(active);
    final first = controller.begin(1);
    expect(await controller.begin(2), isTrue);
    old.complete(FakeKeywordCacheSession());
    expect(await first, isFalse);
    expect(await controller.finish([keywordTorrent('a')], 2), isFalse);
    expect(active.torboxCalls, [
      ['a'],
    ]);
    expect(current().cachedOnly, isFalse);
  });

  for (final cancel in ['clear', 'profile', 'dispose']) {
    test('$cancel rejects late provider completion', () async {
      final pending = Completer<Set<String>>();
      repository.session.tb = (_) => pending.future;
      await controller.begin(1);
      controller.checkBatch([keywordTorrent('a')], 1);
      final finishing = controller.finish([keywordTorrent('a')], 1);
      if (cancel == 'clear') controller.clear(2);
      if (cancel == 'profile') repository.isCurrent = false;
      if (cancel == 'dispose') {
        subscription.close();
        await container.pump();
        expect(container.exists(keywordCacheProvider(key)), isFalse);
      }
      pending.complete({'a'});
      expect(await finishing, isFalse);
      if (cancel != 'dispose') expect(current().badges, isEmpty);
    });
  }

  test('restore publishes a deep snapshot and performs no cache requests', () {
    final labels = ['TB'];
    final badges = {'a': labels};
    final restoredKey = SearchSession(
      owner: key.owner,
      viewIdentity: Object(),
      initialKeywordCache: KeywordCacheState(badges: badges, cachedOnly: true),
    );
    subscription = container.listen(
      keywordCacheProvider(restoredKey),
      (_, _) {},
    );
    labels.add('PM');
    badges.clear();
    expect(current().badges, {
      'a': ['TB'],
    });
    expect(() => current().badges.clear(), throwsUnsupportedError);
    expect(() => current().badges['a']!.clear(), throwsUnsupportedError);
    expect(current().cachedOnly, isTrue);
    expect(repository.opens, 0);
  });
}
