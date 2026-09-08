import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TrackedClient extends MockClient {
  _TrackedClient(super.fn, this.onClose);
  final void Function() onClose;
  @override
  void close() {
    onClose();
    super.close();
  }
}

void main() {
  test(
    'queued requests for discarded cards do not consume network slots',
    () async {
      final release = Completer<void>();
      var requests = 0;
      var relevant = true;
      final repository = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          requests++;
          await release.future;
          return http.Response('{}', 200);
        }),
      );
      final futures = [
        for (var i = 0; i < 20; i++)
          repository
              .get('movie/$i', {}, () => relevant)
              .then<void>((_) {})
              .catchError((Object _) {}),
      ];
      final live = repository.get('movie/19', {}, () => true);
      relevant = false;
      release.complete();
      await Future.wait(futures);
      await live;
      expect(
        requests,
        5,
      ); // four already active, plus the still-visible shared request
    },
  );

  test('oversized responses are rejected before decoding', () async {
    final repository = TmdbMetadataRepository(
      token: 'test',
      clientFactory: () => MockClient(
        (request) async => http.Response('x' * (4 * 1024 * 1024 + 1), 200),
      ),
    );
    await expectLater(
      repository.get('movie/1'),
      throwsA(isA<TmdbMetadataException>()),
    );
  });

  test('unconfigured builds make no request', () async {
    final repository = TmdbMetadataRepository(
      token: '',
      clientFactory: () {
        fail('unexpected request');
      },
    );
    await expectLater(
      repository.get('movie/550'),
      throwsA(isA<TmdbMetadataException>()),
    );
  });

  test(
    'deduplicates concurrent reads and isolates languages and caller edits',
    () async {
      var requests = 0;
      final repository = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          requests++;
          await Future<void>.delayed(Duration.zero);
          return http.Response(
            jsonEncode({
              'title': request.url.queryParameters['language'],
              'nested': {'value': 1},
            }),
            200,
          );
        }),
      );
      final result = await Future.wait([
        repository.get('movie/550', {'language': 'en-US'}),
        repository.get('movie/550', {'language': 'en-US'}),
      ]);
      expect(requests, 1);
      (result[0]['nested'] as Map)['value'] = 9;
      expect((result[1]['nested'] as Map)['value'], 1);
      final hindi = await repository.get('movie/550', {'language': 'hi-IN'});
      expect(hindi['title'], 'hi-IN');
      expect(requests, 2);
    },
  );

  test(
    'identity resolution never guesses by title or swaps media type',
    () async {
      var requests = 0;
      final repository = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          requests++;
          return http.Response(
            '{"movie_results":[{"id":550}],"tv_results":[]}',
            200,
          );
        }),
      );
      expect(
        await repository.identify(
          const StremioMeta(id: 'custom:1', type: 'movie', name: 'Fight Club'),
        ),
        isNull,
      );
      expect(requests, 0);
      expect(
        await repository.identify(
          const StremioMeta(
            id: 'tt0137523',
            type: 'series',
            name: 'Fight Club',
          ),
        ),
        isNull,
      );
      expect(
        await repository.identify(
          const StremioMeta(id: 'tt0137523', type: 'movie', name: 'Fight Club'),
        ),
        (type: 'movie', id: 550),
      );
      expect(requests, 1);
    },
  );

  test('rate limiting prevents subsequent requests during cooldown', () async {
    var requests = 0;
    final repository = TmdbMetadataRepository(
      token: 'test',
      clientFactory: () => MockClient((request) async {
        requests++;
        return http.Response('', 429, headers: {'retry-after': '60'});
      }),
    );
    await expectLater(
      repository.get('movie/1'),
      throwsA(isA<TmdbMetadataException>()),
    );
    await expectLater(
      repository.get('movie/2'),
      throwsA(isA<TmdbMetadataException>()),
    );
    expect(requests, 1);
  });

  test(
    'request gate admits at most four requests and drains queued work',
    () async {
      var active = 0;
      var maximum = 0;
      final repository = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return http.Response('{}', 200);
        }),
      );
      await Future.wait(List.generate(15, (i) => repository.get('movie/$i')));
      expect(maximum, 4);
      expect(active, 0);
    },
  );
  test(
    'connection reset retries once after closing the failed client',
    () async {
      var clients = 0;
      var closes = 0;
      final repository = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () {
          final attempt = ++clients;
          if (attempt == 2) expect(closes, 1);
          return _TrackedClient((_) async {
            if (attempt == 1) throw http.ClientException('Connection reset');
            return http.Response('{"id":1}', 200);
          }, () => closes++);
        },
      );
      expect((await repository.get('movie/1'))['id'], 1);
      expect(clients, 2);
      expect(closes, 2);
      await repository.get('movie/1');
      expect(clients, 2);
    },
  );

  test(
    'connection errors stop after two attempts and discarded work never retries',
    () async {
      var calls = 0;
      var relevant = true;
      final repository = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((_) async {
          calls++;
          throw http.ClientException('Connection reset');
        }),
      );
      await expectLater(
        repository.get('movie/1'),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 2);
      final discarded = TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((_) async {
          calls++;
          relevant = false;
          throw http.ClientException('Connection reset');
        }),
      );
      await expectLater(
        discarded.get('movie/2', {}, () => relevant),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 3);
    },
  );
}
