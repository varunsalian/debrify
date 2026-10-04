import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/catalog_detail_fixture.dart';

bool enrichment(http.Request r) =>
    r.url.host == 'graphql.imdb.com' &&
    (jsonDecode(r.body)['query'] as String).contains('query Enrich');
bool guide(http.Request r) =>
    r.url.host == 'graphql.imdb.com' &&
    (jsonDecode(r.body)['query'] as String).contains('query ParentsGuide');
http.Response extra(String certificate) => http.Response(
  jsonEncode({
    'data': {
      'title': {
        'certificate': {'rating': certificate},
        'metacritic': {
          'metascore': {'score': 87},
        },
        'ratingsSummary': {'aggregateRating': 8.7, 'voteCount': 123},
        'runtime': {
          'seconds': 6000,
          'displayableProperty': {
            'value': {'plainText': '100 min'},
          },
        },
      },
    },
  }),
  200,
);
void change(bool profile) {
  if (profile) {
    ProfileRuntime.scope.value = ProfileScope(
      profileId: 'catalog-metadata-next',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
  } else {
    MetadataPreferencesService.revision.value++;
  }
}

void main() {
  for (final profile in [false, true]) {
    testWidgets(
      'R O ${profile ? 'profile' : 'policy'} held uncached IMDb reload and recommendations only',
      (t) async {
        await catalogDetailCase(t, (f) async {
          // Original failures are not cached. Change to an uncached held response
          // so the absence while pending is rendered evidence of reset, not a
          // cached answer immediately republishing the old value.
          var stage = 0;
          final held = Completer<http.Response>();
          f.onRequest = (r) async => enrichment(r)
              ? (stage == 0 ? http.Response('{}', 404) : held.future)
              : http.Response('{}', 404);
          await f.mount(t);
          final oldRequests = f.requests.where(enrichment).length;
          expect(oldRequests, 1);
          f.requests.clear();
          f.calls.clear();
          stage = 1;
          change(profile);
          await f.until(t, () => f.requests.where(enrichment).isNotEmpty);
          expect(f.requests.where(enrichment).length, 1);
          expect(f.calls, ['recommendations']);
          expect(f.requests.where(guide), isEmpty);
          expect(find.text('PG-13'), findsNothing);
          held.complete(extra('PG-13'));
          await f.until(t, () => find.text('PG-13').evaluate().isNotEmpty);
          expect(find.text('PG-13'), findsOneWidget);
        });
      },
    );
    testWidgets(
      'R O ${profile ? 'profile' : 'policy'} rejects held uncached stale IMDb answer',
      (t) async {
        await catalogDetailCase(t, (f) async {
          final stale = Completer<http.Response>(),
              fresh = Completer<http.Response>();
          var count = 0;
          f.onRequest = (r) async {
            if (!enrichment(r)) return http.Response('{}', 404);
            return ++count == 1 ? stale.future : fresh.future;
          };
          await f.mount(t, wait: false);
          await f.until(t, () => count == 1);
          f.calls.clear();
          change(profile);
          await f.until(t, () => count == 2);
          fresh.complete(http.Response('{}', 404));
          await f.finish(t);
          stale.complete(extra('STALE-R'));
          await f.finish(t);
          expect(find.text('STALE-R'), findsNothing);
          expect(f.calls, ['recommendations', 'art']);
          expect(count, 2);
        });
      },
    );
    testWidgets(
      'R O ${profile ? 'profile' : 'policy'} rejects held stale recommendation batch',
      (t) async {
        await catalogDetailCase(t, (f) async {
          final stale = Completer<List<StremioMeta>>(),
              fresh = Completer<List<StremioMeta>>();
          f.heldRecommendations = stale;
          await f.mount(t, wait: false);
          await f.until(t, () => f.calls.contains('recommendations'));
          f.calls.clear();
          f.heldRecommendations = fresh;
          change(profile);
          await f.until(t, () => f.calls.contains('recommendations'));
          fresh.complete([
            f.meta(id: 'fresh-rec', name: 'Fresh Recommendation'),
          ]);
          await f.until(
            t,
            () => find.text('Fresh Recommendation').evaluate().isNotEmpty,
          );
          stale.complete([
            f.meta(id: 'stale-rec', name: 'Stale Recommendation'),
          ]);
          await f.finish(t);
          expect(find.text('Stale Recommendation'), findsNothing);
          expect(find.text('Fresh Recommendation'), findsNWidgets(2));
          expect(f.calls, ['recommendations', 'art']);
        });
      },
    );
    testWidgets(
      'O ${profile ? 'profile' : 'policy'} cached IMDb immediately republishes without HTTP S reset',
      (t) async {
        await catalogDetailCase(t, (f) async {
          f.onRequest = (r) async =>
              enrichment(r) ? extra('PG') : http.Response('{}', 404);
          await f.mount(t);
          await f.until(t, () => find.text('PG').evaluate().isNotEmpty);
          expect(f.requests.where(enrichment).length, 1);
          f.requests.clear();
          f.calls.clear();
          change(profile);
          await f.finish(t);
          expect(find.text('PG'), findsOneWidget);
          expect(f.requests, isEmpty);
          expect(f.calls, ['recommendations', 'art']);
        });
      },
    );
  }
  testWidgets('R O held successful enrichment after unmount is not published', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      final held = Completer<http.Response>();
      f.onRequest = (r) async =>
          enrichment(r) ? held.future : http.Response('{}', 404);
      await f.mount(t, wait: false);
      await f.until(t, () => f.requests.where(enrichment).length == 1);
      await f.close(t);
      f.calls.clear();
      held.complete(extra('UNMOUNTED'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
      expect(find.text('UNMOUNTED'), findsNothing);
      expect(f.calls, isEmpty);
      expect(t.takeException(), isNull);
    });
  });
  testWidgets(
    'O rich metadata skips host enricher and unconfigured TMDB transport',
    (t) async {
      await catalogDetailCase(t, (f) async {
        await MetadataPreferencesService.save(
          MetadataPreferences(
            providers: {MetadataCategory.credits: MetadataPreferences.tmdb},
          ),
        );
        f.enricher = (id, type) async {
          f.calls.add('unexpected-enrich');
          return null;
        };
        await f.mount(t);
        expect(f.calls.contains('unexpected-enrich'), false);
        expect(
          f.requests.where((r) => r.url.host == 'api.themoviedb.org'),
          isEmpty,
        );
      });
    },
  );
  testWidgets(
    'R O sparse enrichment emits loader art at original resolution points',
    (t) async {
      await catalogDetailCase(t, (f) async {
        f.item = f.meta(rich: false);
        f.enricher = (id, type) async {
          f.calls.add('enrich:$id:$type');
          return f.meta(name: 'Enriched Catalog');
        };
        await f.mount(t);
        expect(find.text('Enriched Catalog'), findsOneWidget);
        expect(f.calls.where((x) => x.startsWith('enrich:')), [
          'enrich:${f.imdb}:movie',
        ]);
        expect(f.artwork, isNotEmpty);
        expect(f.artwork.first.yearLabel, null);
        expect(f.artwork.last.yearLabel, '2026');
      });
    },
  );
  testWidgets(
    'R O recommendation taps retain original object identity FAB raw callback',
    (t) async {
      await catalogDetailCase(t, (f) async {
        final a = f.meta(id: 'one', name: 'First Recommendation'),
            b = f.meta(id: 'one', name: 'Second Recommendation');
        // A non-current presentation policy produces new display objects even
        // when its unconfigured provider falls back to the original fields.
        await MetadataPreferencesService.save(
          MetadataPreferences(
            providers: {MetadataCategory.posters: MetadataPreferences.tmdb},
          ),
        );
        f.recommendations = [a, b];
        await f.mount(t);
        final fab = t.widget<MetadataExploreButton>(
          find.byType(MetadataExploreButton),
        );
        // The public widget is the host contract; compare the actual FAB handoff.
        final host =
            t.widget(
                  find.byWidgetPredicate(
                    (w) =>
                        w.runtimeType.toString() == 'CatalogItemDetailScreen',
                  ),
                )
                as dynamic;
        expect(fab.onOpen, same(host.onRecommendationTap));
        await f.tap(t, 'First Recommendation');
        await f.until(t, () => f.opened.isNotEmpty);
        await f.tap(t, 'Second Recommendation');
        await f.until(t, () => f.opened.length == 2);
        expect(f.opened, [same(a), same(b)]);
        expect(identical(a, b), false);
      });
    },
  );
}
