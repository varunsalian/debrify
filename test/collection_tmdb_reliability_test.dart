import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/collection_native_source_service.dart';

final source = CollectionCatalogSource.fromJson({
  'provider': 'tmdb',
  'tmdbSourceType': 'DISCOVER',
  'mediaType': 'MOVIE',
})!;
http.Response catalog() => http.Response(
  jsonEncode({
    'results': [
      {'id': 42, 'title': 'Film'},
    ],
    'total_pages': 1,
  }),
  200,
);

class ClosingClient extends MockClient {
  ClosingClient(super.fn, this.onClose);
  final void Function() onClose;
  @override
  void close() {
    onClose();
    super.close();
  }
}

void main() {
  test('retry does not borrow another pooled keep-alive connection', () async {
    final warmed = Completer<void>();
    var clients = 0;
    final retryTransports = <int>[];
    final service = CollectionNativeSourceService(
      tmdbToken: 'test',
      resolveIds: false,
      retryDelay: Duration.zero,
      tmdbClientFactory: () {
        final id = clients++;
        return MockClient((request) async {
          if (request.url.queryParameters['page'] != '3') {
            await warmed.future;
            return catalog();
          }
          retryTransports.add(id);
          if (id < 2) throw http.ClientException('stale connection');
          return catalog();
        });
      },
    );
    addTearDown(service.close);
    final a = service.fetchPreview(source, 1);
    final b = service.fetchPreview(source, 2);
    await Future<void>.delayed(Duration.zero);
    expect(clients, 2);
    warmed.complete();
    await Future.wait([a, b]);
    expect((await service.fetchPreview(source, 3)).items, hasLength(1));
    expect(retryTransports, hasLength(2));
    expect(retryTransports.first, lessThan(2));
    expect(retryTransports.last, 2);
  });
  test(
    'background identities wait for active catalogs without blocking previews',
    () async {
      final slowCatalog = Completer<http.Response>();
      final identityStarted = Completer<void>();
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/external_ids')) {
            if (!identityStarted.isCompleted) identityStarted.complete();
            return http.Response('{"imdb_id":"tt42"}', 200);
          }
          if (request.url.queryParameters['page'] == '2')
            return slowCatalog.future;
          return catalog();
        }),
      );
      addTearDown(service.close);
      final pending = service.fetchPreview(source, 2);
      final first = await service.fetchPreview(source, 1);
      expect(first.items, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(identityStarted.isCompleted, isFalse);
      slowCatalog.complete(catalog());
      await pending;
      await identityStarted.future.timeout(const Duration(seconds: 1));
    },
  );
  test(
    'catalog survives three consecutive transient resets automatically',
    () async {
      var calls = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        resolveIds: false,
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          if (++calls <= 3) throw http.ClientException('reset');
          return catalog();
        }),
      );
      addTearDown(service.close);
      expect((await service.fetchPreview(source, 1)).items, hasLength(1));
      expect(calls, 4);
    },
  );
  test(
    'hydrated preview objects stay identical across repeated reads',
    () async {
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        client: MockClient(
          (_) async => http.Response('{"imdb_id":"tt1234567"}', 200),
        ),
      );
      addTearDown(service.close);
      const item = StremioMeta(id: 'tmdb:42', type: 'movie', name: 'Film');
      await service.resolveIdentity(item);
      final hydrated = service.withCachedIdentity(item);
      expect(hydrated.id, item.id);
      expect(hydrated.imdbId, 'tt1234567');
      for (var i = 0; i < 20; i++) {
        expect(identical(service.withCachedIdentity(item), hydrated), isTrue);
      }
    },
  );

  test(
    'loaded cards finish background hydration once beyond the ID cache limit',
    () async {
      final items = [
        for (var id = 1; id <= 2010; id++)
          StremioMeta(id: 'tmdb:$id', type: 'movie', name: 'Film $id'),
      ];
      final calls = <String, int>{};
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        client: MockClient((request) async {
          final id = request.url.path.split('/')[3];
          calls[id] = (calls[id] ?? 0) + 1;
          return http.Response(jsonEncode({'imdb_id': 'tt$id'}), 200);
        }),
      );
      addTearDown(service.close);
      final finished = Completer<void>();
      var completions = 0;
      StremioMeta? firstHydrated;
      var churn = false;
      service.identityChanges.addListener(() {
        // Model repeated screen rebuilds while more than 2,000 cards stay loaded.
        final first = service.withCachedIdentity(items.first);
        if (first.imdbId != null) {
          firstHydrated ??= first;
          churn |= !identical(firstHydrated, first);
        }
        if (++completions == items.length) finished.complete();
        if (completions <= items.length) service.prefetchIdentities(items);
      });
      service.prefetchIdentities(items);
      await finished.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero);
      for (var frame = 0; frame < 5; frame++) {
        service.prefetchIdentities(items);
        await Future<void>.delayed(Duration.zero);
      }
      expect(calls.length, items.length);
      expect(calls.values.every((n) => n == 1), isTrue);
      expect(churn, isFalse);
      expect(service.withCachedIdentity(items.first).imdbId, 'tt1');
      expect(
        identical(service.withCachedIdentity(items.first), firstHydrated),
        isTrue,
      );
    },
  );

  test(
    'known missing IMDb IDs are not requeued when the shared cache evicts them',
    () async {
      var missingLookups = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        client: MockClient((request) async {
          final id = request.url.path.split('/')[3];
          if (id == '999999') missingLookups++;
          return http.Response(
            jsonEncode({'imdb_id': id == '999999' ? null : 'tt$id'}),
            200,
          );
        }),
      );
      addTearDown(service.close);
      const missing = StremioMeta(
        id: 'tmdb:999999',
        type: 'movie',
        name: 'Unmapped',
      );
      await service.resolveIdentity(missing);
      for (var id = 1; id <= 2001; id++) {
        await service.resolveIdentity(
          StremioMeta(id: 'tmdb:$id', type: 'movie', name: 'Film'),
        );
      }
      service.prefetchIdentities([missing]);
      await Future<void>.delayed(Duration.zero);
      expect(missingLookups, 1);
      expect(identical(service.withCachedIdentity(missing), missing), isTrue);
    },
  );

  for (final resetFirst in [false, true]) {
    test(
      'two-second identity response fits its budget (reset first: $resetFirst)',
      () async {
        var calls = 0;
        final service = CollectionNativeSourceService(
          tmdbToken: 'test',
          client: MockClient((request) async {
            calls++;
            if (resetFirst && calls == 1) throw http.ClientException('reset');
            await Future<void>.delayed(const Duration(seconds: 2));
            return http.Response('{"imdb_id":"tt1234567"}', 200);
          }),
        );
        addTearDown(service.close);
        final result = await service.resolveIdentity(
          const StremioMeta(id: 'tmdb:42', type: 'movie', name: 'Film'),
        );
        expect(result.id, 'tt1234567');
        expect(calls, resetFirst ? 2 : 1);
      },
    );
  }
  test(
    'previews render before identity completes and keep stable IDs',
    () async {
      final identity = Completer<http.Response>();
      final updated = Completer<void>();
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        client: MockClient(
          (r) async => r.url.path.endsWith('/external_ids')
              ? identity.future
              : catalog(),
        ),
      );
      addTearDown(service.close);
      service.identityChanges.addListener(() {
        if (!updated.isCompleted) updated.complete();
      });
      final page = await service
          .fetchPreview(source, 1)
          .timeout(const Duration(milliseconds: 200));
      expect(page.items.single.id, 'tmdb:42');
      expect(page.items.single.imdbId, isNull);
      identity.complete(http.Response('{"imdb_id":"tt1234567"}', 200));
      await updated.future;
      final hydrated = service.withCachedIdentity(page.items.single);
      expect(hydrated.id, 'tmdb:42');
      expect(hydrated.effectiveImdbId, 'tt1234567');
      expect(
        (await service.resolveIdentity(page.items.single)).id,
        'tt1234567',
      );
    },
  );

  for (final failure in ['reset', '503', 'timeout']) {
    test(
      '$failure retries on a fresh transport and closes every attempt',
      () async {
        var calls = 0;
        var closes = 0;
        final service = CollectionNativeSourceService(
          tmdbToken: 'test',
          resolveIds: false,
          requestBudget: const Duration(milliseconds: 300),
          retryDelay: Duration.zero,
          tmdbClientFactory: () {
            final attempt = ++calls;
            if (attempt == 2) expect(closes, 1);
            return ClosingClient((r) async {
              if (attempt == 1) {
                if (failure == 'reset') {
                  throw http.ClientException('Connection reset');
                }
                if (failure == '503') return http.Response('{}', 503);
                return Completer<http.Response>().future;
              }
              return catalog();
            }, () => closes++);
          },
        );
        addTearDown(service.close);
        expect(
          (await service.fetchPreview(source, 1)).items.single.id,
          'tmdb:42',
        );
        expect(calls, 2);
        expect(closes, 1);
        service.close();
        expect(closes, 2);
      },
    );
  }

  test(
    'persistent resets stop after four attempts; failures are not cached',
    () async {
      var calls = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        resolveIds: false,
        retryDelay: Duration.zero,
        client: MockClient((r) async {
          calls++;
          if (calls <= 4) throw http.ClientException('reset');
          return catalog();
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetchPreview(source, 1),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 4);
      expect((await service.fetchPreview(source, 1)).items, hasLength(1));
      expect(calls, 5);
    },
  );

  for (final status in [401, 403, 404, 429]) {
    test('$status is not blindly retried', () async {
      var calls = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        resolveIds: false,
        retryDelay: Duration.zero,
        client: MockClient((r) async {
          calls++;
          return http.Response('{}', status, headers: {'retry-after': '60'});
        }),
      );
      addTearDown(service.close);
      await expectLater(service.fetchPreview(source, 1), throwsException);
      expect(calls, 1);
      if (status == 429) {
        await expectLater(service.fetchPreview(source, 2), throwsException);
        expect(calls, 1);
      }
    });
  }

  test(
    'identical loads coalesce and warm catalog cache avoids network',
    () async {
      var calls = 0;
      final ready = Completer<http.Response>();
      final service = CollectionNativeSourceService(
        tmdbToken: 'test',
        resolveIds: false,
        client: MockClient((r) async {
          calls++;
          return ready.future;
        }),
      );
      addTearDown(service.close);
      final first = service.fetchPreview(source, 1);
      final second = service.fetchPreview(source, 1);
      ready.complete(catalog());
      final pages = await Future.wait([first, second]);
      expect(pages.every((p) => p.items.length == 1), isTrue);
      expect(calls, 1);
      await service.fetchPreview(source, 1);
      expect(calls, 1);
      await service.fetchPreview(source, 2);
      expect(calls, 2);
    },
  );
}
