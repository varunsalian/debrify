import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import '../../../../support/merged_detail_fixture.dart';

class ThrowingWatchlistStore extends InMemorySharedPreferencesStore {
  ThrowingWatchlistStore() : super.empty();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith('my_watchlist_v1')) {
      throw StateError('Original store failure');
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  testWidgets('watchlist toggles persist the presented row and remove it', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      await f.mount(t);
      expect(f.model.inMyWatchlist, false);
      f.model.onToggleMyWatchlist!();
      await f.until(t, () => f.model.inMyWatchlist);
      await t.runAsync(() async {
        expect(
          await WatchlistStorage.isInMyWatchlist(
            WatchlistStorage.withMyWatchlistSource(f.item, f.addon),
          ),
          true,
        );
        final saved = await WatchlistStorage.getMyWatchlistItems();
        expect(saved.single.id, f.item.id);
        expect(saved.single.name, f.model.item.name);
        expect(saved.single.sourceAddon?.id, f.addon.id);
      });
      await f.until(
        t,
        () =>
            find.textContaining('Added to My Watchlist').evaluate().isNotEmpty,
      );
      expect(find.textContaining('Added to My Watchlist'), findsOneWidget);
      f.model.onToggleMyWatchlist!();
      await f.until(t, () => !f.model.inMyWatchlist);
      await t.runAsync(() async {
        expect(await WatchlistStorage.getMyWatchlistItems(), isEmpty);
      });
    });
  });
  testWidgets('throwing watchlist store rolls back and reports the error', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      final store = ThrowingWatchlistStore();
      SharedPreferencesStorePlatform.instance = store;
      await f.mount(t);
      f.model.onToggleMyWatchlist!();
      await t.pump();
      await f.until(
        t,
        () => find.text("Couldn't update My Watchlist").evaluate().isNotEmpty,
      );
      expect(f.model.inMyWatchlist, false);
      await t.runAsync(() async {
        expect(
          (await store.getAll()).keys.where(
            (k) => k.endsWith('my_watchlist_v1'),
          ),
          isEmpty,
        );
      });
    });
  });
  testWidgets(
    'bound sources reload on opening playback return and management',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.item = const StremioMeta(
          id: 'merged-bound-movie',
          imdbId: 'tt0099991',
          type: 'movie',
          name: 'Bound Movie',
        );
        SeriesSource source(String hash) => SeriesSource(
          torrentHash: hash,
          torrentName: hash,
          debridService: 'realdebrid',
          debridTorrentId: hash,
          boundAt: 1,
        );
        await t.runAsync(
          () => SeriesSourceService.addSource(f.item.imdbId!, source('one')),
        );
        await f.mount(t);
        expect(f.model.boundSources.map((s) => s.torrentHash).toList(), [
          'one',
        ]);
        await t.runAsync(
          () => SeriesSourceService.addSource(f.item.imdbId!, source('two')),
        );
        MainPageBridge.notifyPlaybackReturned();
        await f.until(t, () => f.model.boundSources.length == 2);
        expect(f.model.boundSources.map((s) => s.torrentHash).toList(), [
          'one',
          'two',
        ]);
        f.onSelectSource = (_) =>
            SeriesSourceService.addSource(f.item.imdbId!, source('three'));
        f.model.onManageSources!();
        await f.until(t, () => f.model.boundSources.length == 3);
        expect(f.model.boundSources.map((s) => s.torrentHash).toList(), [
          'one',
          'two',
          'three',
        ]);
        expect(f.sourceItems.every((item) => identical(item, f.item)), true);
      });
    },
  );
  for (final confirm in [false, true]) {
    testWidgets(
      'merged rewatch ${confirm ? 'confirm' : 'cancel'} clears before restart and never resumes',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.item = const StremioMeta(
            id: 'tt0099913',
            imdbId: 'tt0099913',
            type: 'movie',
            name: 'Original Rewatch Movie',
          );
          await t.runAsync(
            () => MovieProgressStorage.markMovieAsFinished(f.item.id),
          );
          final finishedAtRestart = <bool>[];
          f.onRestart = () async {
            finishedAtRestart.add(
              await MovieProgressStorage.isMovieFinished(f.item.id),
            );
            f.calls.add('resetVerified');
          };
          await f.mount(t);
          await f.until(t, () => f.model.primaryLabel == 'Rewatch');
          expect(f.model.primaryLabel, 'Rewatch');
          f.calls.clear();
          f.model.onPrimary();
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text('Rewatch movie?'), findsOneWidget);
          expect(f.calls, isEmpty);
          await t.tap(
            find.text(confirm ? 'Clear progress and rewatch' : 'Cancel'),
          );
          await t.pump(const Duration(milliseconds: 400));
          if (confirm) {
            await f.until(t, () => f.calls.contains('resetVerified'));
            expect(
              f.calls
                  .where(
                    (c) =>
                        ['restart', 'resumePlay', 'resetVerified'].contains(c),
                  )
                  .toList(),
              ['restart', 'resetVerified'],
            );
            expect(f.model.primaryLabel, 'Play');
            expect(finishedAtRestart, [false]);
          } else {
            expect(f.calls, isEmpty);
            expect(f.model.primaryLabel, 'Rewatch');
            await t.runAsync(() async {
              expect(
                await MovieProgressStorage.isMovieFinished(f.item.id),
                true,
              );
            });
          }
          expect(f.promises, isEmpty);
        });
      },
    );
  }
  testWidgets(
    'without restart capability completed movie stays Play without resetting',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.item = const StremioMeta(
          id: 'tt0099914',
          imdbId: 'tt0099914',
          type: 'movie',
          name: 'No restart',
        );
        f.restart = false;
        await t.runAsync(
          () => MovieProgressStorage.markMovieAsFinished(f.item.id),
        );
        await f.mount(t);
        expect(f.model.primaryLabel, 'Play');
        // The no-restart branch is deliberately unreachable from the Play UI.
        // This direct probe characterizes its defensive early return only.
        await (f.access['rewatch'] as Future<void> Function())();
        await t.runAsync(() async {
          expect(await MovieProgressStorage.isMovieFinished(f.item.id), true);
        });
        expect(find.text('Rewatch movie?'), findsNothing);
        expect(f.promises, isEmpty);
      });
    },
  );
  for (final choice in ['Season pack sources', 'Episode sources']) {
    testWidgets(
      'series packs chooser routes $choice to the correct host callback',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.menus = true;
          await f.mount(t);
          f.next((season: 2, episode: 8, started: true), mutation: true);
          await t.pump();
          f.calls.clear();
          f.model.onPrimaryLongPress!();
          await f.until(
            t,
            () => find.text('Choose sources').evaluate().isNotEmpty,
          );
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text(choice));
          await t.pump(const Duration(milliseconds: 400));
          await f.until(
            t,
            () => f.calls.contains(
              choice == 'Episode sources'
                  ? 'episodeBrowse'
                  : 'traktAction:searchPacks',
            ),
          );
          expect(f.calls, [
            choice == 'Episode sources'
                ? 'episodeBrowse'
                : 'traktAction:searchPacks',
          ]);
          expect(
            f.promises,
            choice == 'Episode sources'
                ? [(started: true, season: 2, episode: 8)]
                : isEmpty,
          );
        });
      },
    );
  }
}
