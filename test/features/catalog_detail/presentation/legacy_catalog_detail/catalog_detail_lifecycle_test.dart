import 'dart:async';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../support/catalog_detail_fixture.dart';

void main() {
  for (final signal in ['tracking', 'movie', 'mdblist']) {
    testWidgets('R $signal notifier rereads changed stored movie completion', (
      t,
    ) async {
      await catalogDetailCase(t, (f) async {
        await f.mount(t);
        expect(find.text('Play'), findsOneWidget);
        await t.runAsync(() async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('finished_movies_v1', [f.imdb]);
        });
        switch (signal) {
          case 'tracking':
            TrackingSourceStorage.trackingSourceRevision.value++;
          case 'movie':
            MovieProgressStorage.movieFinishedRevision.value++;
          case 'mdblist':
            MdblistService.instance.watchedRevision.value++;
        }
        await f.until(t, () => find.text('Rewatch').evaluate().isNotEmpty);
        expect(find.text('Rewatch'), findsOneWidget);
      });
    });
  }
  for (final kind in ['series', 'missing-id']) {
    testWidgets(
      'R $kind completion notifications leave rendering unchanged S reads uncounted',
      (t) async {
        await catalogDetailCase(t, (f) async {
          f.item = f.meta(
            type: kind == 'series' ? 'series' : 'movie',
            id: kind == 'missing-id' ? 'addon-no-imdb' : null,
          );
          await f.mount(t);
          final label = kind == 'series' ? 'Start Watching' : 'Play';
          expect(find.text(label), findsOneWidget);
          TrackingSourceStorage.trackingSourceRevision.value++;
          MovieProgressStorage.movieFinishedRevision.value++;
          MdblistService.instance.watchedRevision.value++;
          await f.finish(t);
          expect(find.text(label), findsOneWidget);
          expect(find.text('Rewatch'), findsNothing);
        });
      },
    );
  }
  for (final signal in ['return', 'data', 'pop']) {
    testWidgets(
      'R O current $signal refreshes resume and stored binding on widget item',
      (t) async {
        await catalogDetailCase(t, (f) async {
          await f.mount(t);
          expect(
            (t.widget(
                      find.byWidgetPredicate(
                        (w) => w.runtimeType.toString() == '_ActionRow',
                      ),
                    )
                    as dynamic)
                .hasBoundSource,
            false,
          );
          if (signal == 'pop') await f.cover(t);
          await t.runAsync(
            () => SeriesSourceService.addSource(
              f.imdb,
              SeriesSource(
                torrentHash: 'one',
                torrentName: 'one',
                debridService: 'realdebrid',
                debridTorrentId: 'one',
                boundAt: 1,
              ),
            ),
          );
          f.calls.clear();
          f.resume = (started: true, season: null, episode: null);
          if (signal == 'pop') {
            await f.uncover(t);
          } else if (signal == 'return') {
            MainPageBridge.notifyPlaybackReturned();
          } else {
            MainPageBridge.notifyPlaybackDataChanged();
          }
          await f.until(t, () => find.text('Resume').evaluate().isNotEmpty);
          expect(f.calls, ['resume']);
          expect(
            (t.widget(
                      find.byWidgetPredicate(
                        (w) => w.runtimeType.toString() == '_ActionRow',
                      ),
                    )
                    as dynamic)
                .hasBoundSource,
            true,
          );
        });
      },
    );
  }
  for (final signal in ['return', 'data']) {
    testWidgets('O covered $signal does not read and stop signal differs', (
      t,
    ) async {
      await catalogDetailCase(t, (f) async {
        await f.mount(t);
        await f.cover(t);
        f.calls.clear();
        var stopped = 0;
        void probe() => stopped++;
        MainPageBridge.addContentPlaybackStopListener(probe);
        try {
          MainPageBridge.notifyPlayerLaunching();
          if (signal == 'return') {
            MainPageBridge.notifyPlaybackReturned();
          } else {
            MainPageBridge.notifyPlaybackDataChanged();
          }
          await t.pump();
          expect(f.calls, isEmpty);
          expect(stopped, signal == 'return' ? 1 : 0);
        } finally {
          MainPageBridge.removeContentPlaybackStopListener(probe);
        }
      });
    });
  }
  testWidgets(
    'O post frame host loader order S remaining nine-load fan pinned',
    (t) async {
      await catalogDetailCase(t, (f) async {
        f.item = f.meta(rich: false);
        f.enricher = (id, type) async {
          f.calls.add('enrich:$id:$type');
          return null;
        };
        await f.mount(t);
        expect(f.calls.take(5), [
          'art',
          'enrich:${f.imdb}:movie',
          'resume',
          'simkl',
          'recommendations',
        ]);
      });
    },
  );
  testWidgets(
    'O after unmount notifiers and both playback signals make no host reads',
    (t) async {
      await catalogDetailCase(t, (f) async {
        await f.mount(t);
        await f.close(t);
        f.calls.clear();
        TrackingSourceStorage.trackingSourceRevision.value++;
        MovieProgressStorage.movieFinishedRevision.value++;
        MdblistService.instance.watchedRevision.value++;
        MetadataPreferencesService.revision.value++;
        ProfileRuntime.scope.value = ProfileScope(
          profileId: 'catalog-next',
          dataGeneration: 1,
          sessionEpoch: 1,
        );
        MainPageBridge.notifyPlaybackReturned();
        MainPageBridge.notifyPlaybackDataChanged();
        await t.pump();
        expect(f.calls, isEmpty);
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets('R held uncached loaders released after unmount publish nothing', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.heldResume = Completer<CatalogResume>();
      f.heldRecommendations = Completer();
      await f.mount(t, wait: false);
      expect(f.heldResume!.isCompleted, false);
      expect(f.calls.where((c) => c == 'resume'), ['resume']);
      // Unmount before the 12 s timeout. Release both genuinely pending reads.
      await f.close(t, drain: Duration.zero);
      f.calls.clear();
      f.heldResume!.complete((started: true, season: 1, episode: 2));
      f.heldRecommendations!.complete([
        f.meta(name: 'Unmounted Recommendation'),
      ]);
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
      expect(find.text('Unmounted Recommendation'), findsNothing);
      expect(f.calls, isEmpty);
      expect(t.takeException(), isNull);
    });
  });
}
