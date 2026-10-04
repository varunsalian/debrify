import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import '../../../../support/catalog_detail_fixture.dart';

class CatalogThrowingStore extends InMemorySharedPreferencesStore {
  CatalogThrowingStore() : super.empty();
  bool watchlist = false, reset = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (watchlist && key.endsWith('my_watchlist_v1')) {
      throw StateError('Original watchlist failure');
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (reset && key.endsWith('finished_movies_v1')) {
      throw StateError('Original reset failure');
    }
    return super.remove(key);
  }
}

void main() {
  for (final confirm in [false, true]) {
    testWidgets(
      'R O rewatch ${confirm ? 'confirm' : 'cancel'} resets before restart',
      (t) async {
        await catalogDetailCase(t, (f) async {
          await t.runAsync(
            () => MovieProgressStorage.markMovieAsFinished(f.imdb),
          );
          final finishedAtRestart = <bool>[];
          f.onRestart = () async {
            finishedAtRestart.add(
              await MovieProgressStorage.isMovieFinished(f.imdb),
            );
            f.calls.add('verified');
          };
          await f.mount(t);
          expect(find.text('Rewatch'), findsOneWidget);
          f.calls.clear();
          await f.tap(t, 'Rewatch');
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text('Rewatch movie?'), findsOneWidget);
          expect(f.calls, isEmpty);
          await f.tap(t, confirm ? 'Clear progress and rewatch' : 'Cancel');
          await t.pump(const Duration(milliseconds: 400));
          if (confirm) {
            await f.until(t, () => f.calls.contains('verified'));
            expect(f.calls, ['restart', 'verified']);
            expect(finishedAtRestart, [false]);
            expect(find.text('Play'), findsOneWidget);
          } else {
            expect(f.calls, isEmpty);
            expect(find.text('Rewatch'), findsOneWidget);
            await t.runAsync(() async {
              expect(await MovieProgressStorage.isMovieFinished(f.imdb), true);
            });
          }
        });
      },
    );
  }
  testWidgets(
    'R O busy rewatch accepts one action while confirmation is open',
    (t) async {
      await catalogDetailCase(t, (f) async {
        await t.runAsync(
          () => MovieProgressStorage.markMovieAsFinished(f.imdb),
        );
        await f.mount(t);
        final target = find
            .ancestor(
              of: find.text('Rewatch'),
              matching: find.byType(GestureDetector),
            )
            .first;
        final action = t.widget<GestureDetector>(target).onTap!;
        f.calls.clear();
        action();
        action();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Rewatch movie?'), findsOneWidget);
        expect(f.calls, isEmpty);
        await f.tap(t, 'Cancel');
      });
    },
  );
  testWidgets('R completed movie without restart stays Play and never resets', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.restart = false;
      await t.runAsync(() => MovieProgressStorage.markMovieAsFinished(f.imdb));
      await f.mount(t);
      expect(find.text('Play'), findsOneWidget);
      f.calls.clear();
      await f.tap(t, 'Play');
      expect(f.calls, ['play']);
      expect(find.text('Rewatch movie?'), findsNothing);
      await t.runAsync(() async {
        expect(await MovieProgressStorage.isMovieFinished(f.imdb), true);
      });
    });
  });
  testWidgets('R confirmed failed reset preserves Rewatch Found 2', (t) async {
    await catalogDetailCase(t, (f) async {
      final store = CatalogThrowingStore();
      SharedPreferencesStorePlatform.instance = store;
      await t.runAsync(() => MovieProgressStorage.markMovieAsFinished(f.imdb));
      await f.mount(t);
      store.reset = true;
      f.calls.clear();
      await f.tap(t, 'Rewatch');
      await t.pump(const Duration(milliseconds: 400));
      await f.tap(t, 'Clear progress and rewatch');
      await f.until(
        t,
        () =>
            find.textContaining('Could not fully clear:').evaluate().isNotEmpty,
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(f.calls, isEmpty);
      expect(find.text('Rewatch'), findsOneWidget);
      expect(find.textContaining('Could not fully clear:'), findsOneWidget);
    });
  });
  testWidgets('R watchlist toggles persist presented row and remove it', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.item = f
          .meta(rich: false)
          .withSourceAddon(
            StremioAddon(
              id: 'original-addon',
              name: 'Original',
              manifestUrl: '',
              baseUrl: '',
            ),
          );
      f.enricher = (id, type) async => f.meta(name: 'Presented Watchlist');
      await f.mount(t);
      await f.tap(t, 'My Watchlist');
      await f.until(
        t,
        () => find.text('Added to My Watchlist').evaluate().isNotEmpty,
      );
      await t.runAsync(() async {
        expect(await WatchlistStorage.isInMyWatchlist(f.item), true);
        final rows = await WatchlistStorage.getMyWatchlistItems();
        expect(rows.single.id, f.item.id);
        expect(rows.single.name, 'Presented Watchlist');
        expect(rows.single.sourceAddon?.id, 'original-addon');
      });
      await f.tap(t, 'In My Watchlist');
      await f.until(
        t,
        () => find.text('Removed from My Watchlist').evaluate().isNotEmpty,
      );
      await t.runAsync(() async {
        expect(await WatchlistStorage.getMyWatchlistItems(), isEmpty);
      });
    });
  });
  testWidgets('R throwing watchlist store rolls back with error snackbar', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      final store = CatalogThrowingStore()..watchlist = true;
      SharedPreferencesStorePlatform.instance = store;
      await f.mount(t);
      await f.tap(t, 'My Watchlist');
      await f.until(
        t,
        () => find.text("Couldn't update My Watchlist").evaluate().isNotEmpty,
      );
      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
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
  for (final kind in ['movie', 'series-off', 'disabled']) {
    testWidgets('R O primary hold $kind keeps exact host dispatch', (t) async {
      await catalogDetailCase(t, (f) async {
        if (kind == 'series-off') {
          f.item = f.meta(type: 'series');
          await QuickPlayStorage.setQuickPlayRules(
            QuickPlayRules.debrifyDefault(
              isMovie: false,
            ).copyWith(preferSeriesPacks: false),
            isMovie: false,
          );
        }
        f.hold = kind != 'disabled';
        await f.mount(t);
        f.calls.clear();
        await t.longPress(
          find.text(kind == 'series-off' ? 'Start Watching' : 'Play'),
        );
        await f.finish(t);
        expect(
          f.calls,
          kind == 'disabled'
              ? ['play']
              : [kind == 'series-off' ? 'episode' : 'browse'],
        );
      });
    });
  }
  for (final choice in ['Season pack sources', 'Episode sources']) {
    testWidgets('R O packs chooser $choice forwards exact action', (t) async {
      await catalogDetailCase(t, (f) async {
        f.item = f.meta(type: 'series');
        f.traktOptions = const [
          TraktMenuOption(
            action: TraktItemMenuAction.searchPacks,
            icon: Icons.inventory_2,
            color: Colors.amber,
            label: 'Packs',
            caption: 'Packs',
          ),
        ];
        await f.mount(t);
        f.calls.clear();
        await t.longPress(find.text('Start Watching'));
        await f.until(t, () => find.text(choice).evaluate().isNotEmpty);
        await t.pump(const Duration(milliseconds: 400));
        await f.tap(t, choice);
        await t.pump(const Duration(milliseconds: 400));
        expect(
          f.traktActions,
          choice == 'Season pack sources'
              ? [TraktItemMenuAction.searchPacks]
              : isEmpty,
        );
        expect(f.calls, choice == 'Episode sources' ? ['episode'] : isEmpty);
      });
    });
  }
  for (final tracker in ['trakt', 'simkl', 'mdblist']) {
    testWidgets('R O $tracker quick action hands exact host enum', (t) async {
      await catalogDetailCase(t, (f) async {
        if (tracker == 'trakt') {
          f.traktOptions = const [
            TraktMenuOption(
              action: TraktItemMenuAction.searchPacks,
              icon: Icons.inventory_2,
              color: Colors.amber,
              label: 'Exact Trakt',
              caption: 'Exact Trakt',
            ),
          ];
        }
        if (tracker == 'simkl') {
          f.simklOptions = buildSimklMenuOptions(
            inContinueWatching: false,
            isSimklAuthenticated: true,
            isSeries: false,
          );
        }
        if (tracker == 'mdblist') {
          f.mdblistOptions = buildMdblistMenuOptions(
            authenticated: true,
            isSeries: false,
          );
        }
        await f.mount(t);
        if (tracker == 'trakt') {
          await f.tap(t, 'Exact Trakt');
          expect(f.traktActions, [TraktItemMenuAction.searchPacks]);
        }
        if (tracker == 'simkl') {
          await f.tap(t, f.simklOptions.first.caption);
          expect(f.simklActions, [f.simklOptions.first.action]);
        }
        if (tracker == 'mdblist') {
          await f.tap(t, f.mdblistOptions.first.caption);
          expect(f.mdblistActions, [f.mdblistOptions.first.action]);
        }
      });
    });
  }
}
