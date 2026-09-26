import 'dart:async';

import 'package:debrify/features/search/data/engine_keyword_search_repository.dart';
import 'package:debrify/features/search/data/keyword_search_repository.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../keyword_torrent_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  for (final (counts, errors, ran, failed) in <(Object?, Object?, bool, bool)>[
    ({}, {}, false, false),
    (null, null, false, false),
    ('invalid', 0, false, false),
    ({'engine': 0}, {}, true, false),
    ({}, {'engine': 'failed'}, true, true),
    ({'engine': 1}, {'other': 'failed'}, true, true),
  ]) {
    test('maps engine counts/errors: $counts / $errors', () async {
      final repo = EngineKeywordSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        searchEngines: (query, {onBatch}) async => {
          'torrents': <Torrent>[],
          'engineCounts': counts,
          'engineErrors': errors,
        },
      );
      final result = await repo.search('query', onBatch: (_, _) {});
      expect(result.anyEngineRan, ran);
      expect(result.hasEngineErrors, failed);
    });
  }

  test(
    'passes exact query and source, snapshots lists and uses existing merge',
    () async {
      final low = keywordTorrent('low', hash: 'a', seeders: 1);
      final high = keywordTorrent('high', hash: 'a', seeders: 20);
      final first = [low];
      final finalRows = [high];
      final queries = <String>[];
      final batches = <(String, List<Torrent>)>[];
      final repo = EngineKeywordSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        searchEngines: (query, {onBatch}) async {
          queries.add(query);
          onBatch!('first source', first);
          return {
            'torrents': finalRows,
            'engineCounts': {'engine': 1},
          };
        },
      );
      final result = await repo.search(
        '  exact query  ',
        onBatch: (source, rows) {
          batches.add((source, rows));
        },
      );
      first.clear();
      finalRows.clear();
      expect(queries, ['  exact query  ']);
      expect(batches.single.$1, 'first source');
      expect(batches.single.$2, [low]);
      expect(result.torrents, [high]);
      expect(() => result.torrents.clear(), throwsUnsupportedError);
      expect(() => batches.single.$2.clear(), throwsUnsupportedError);
      expect(repo.merge([batches.single.$2, result.torrents]), [high]);
    },
  );

  test(
    'delayed service reads stay in originating scope; late batches are rejected',
    () async {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final incoming = ProfileScope(
        profileId: 'incoming',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.initializeCommitted(origin);
      final gate = Completer<void>();
      final scopes = <ProfileScope>[];
      final batches = <List<Torrent>>[];
      var calls = 0;
      final repo = EngineKeywordSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        searchEngines: (query, {onBatch}) async {
          calls++;
          scopes.add(ProfileRuntime.capture());
          onBatch!('before switch', [keywordTorrent('before')]);
          await gate.future;
          scopes.add(ProfileRuntime.capture());
          onBatch('after switch', [keywordTorrent('after')]);
          return {'torrents': <Torrent>[]};
        },
      );
      final search = repo.search(
        'query',
        onBatch: (_, rows) => batches.add(rows),
      );
      ProfileRuntime.publish(incoming);
      gate.complete();
      await search;
      expect(scopes, [origin, origin]);
      expect(batches.map((rows) => rows.single.name), ['before']);
      expect(repo.isCurrent, isFalse);
      await expectLater(
        repo.search('retired', onBatch: (_, _) {}),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test('service error propagates once without retry', () async {
    var calls = 0;
    final error = StateError('fixture');
    final repo = EngineKeywordSearchRepository(
      owner: ProfileSessionMemory.captureOwner(),
      searchEngines: (query, {KeywordBatch? onBatch}) async {
        calls++;
        throw error;
      },
    );
    await expectLater(
      repo.search('query', onBatch: (_, _) {}),
      throwsA(same(error)),
    );
    expect(calls, 1);
  });
}
