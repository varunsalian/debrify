import 'dart:async';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/catalog_detail_fixture.dart';
import '../../../../support/catalog_detail_metadata_responses.dart';
import '../../../../support/catalog_detail_poster.dart';

// ChangeNotifier exposes this protected getter; tests inspect the borrowed
// singleton instances without changing production ownership or adding a seam.
bool _hasListeners(ChangeNotifier notifier) =>
    (notifier as dynamic).hasListeners as bool;

void main() {
  testWidgets('R initial saved watchlist title mounts In My Watchlist', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      await t.runAsync(() => WatchlistStorage.setMyWatchlistItem(f.item, true));
      await f.mount(t);
      expect(find.text('In My Watchlist'), findsOneWidget);
      expect(find.text('My Watchlist'), findsNothing);
    });
  });
  testWidgets('R O held uncached parents response renders parents guide row', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      final held = Completer<http.Response>();
      f.onRequest = (r) async =>
          catalogParentsRequest(r) ? held.future : http.Response('{}', 404);
      await f.mount(t, wait: false);
      await f.until(
        t,
        () => f.requests.where(catalogParentsRequest).isNotEmpty,
      );
      expect(f.requests.where(catalogParentsRequest), hasLength(1));
      expect(find.text('Sex & Nudity'), findsNothing);
      held.complete(catalogParentsResponse());
      await f.until(t, () => find.text('Sex & Nudity').evaluate().isNotEmpty);
      expect(find.text('Sex & Nudity'), findsOneWidget);
      expect(find.text('Moderate'), findsNWidgets(2));
    });
  });
  testWidgets('R O fixture served poster publishes a non-null artwork accent', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      final url = 'https://catalog-fixture.invalid/${f.imdb}-poster.png';
      await catalogFixturePoster(t, url);
      f.item = f.meta(poster: url);
      await f.mount(t);
      await f.until(
        t,
        () =>
            t
                .widget<ArtworkAccentScope>(find.byType(ArtworkAccentScope))
                .accent !=
            null,
      );
      expect(
        t.widget<ArtworkAccentScope>(find.byType(ArtworkAccentScope)).accent,
        isNotNull,
      );
      expect(f.requests.where((r) => r.url.toString() == url), isNotEmpty);
    });
  });
  testWidgets(
    'R O catalog back above Cover pops route without didPopNext read',
    (t) async {
      await catalogDetailCase(t, (f) async {
        await f.mount(t);
        await f.cover(t);
        var popped = false;
        unawaited(
          f.navigator.currentState!
              .push<void>(MaterialPageRoute<void>(builder: (_) => f.screen()))
              .then((_) {
                popped = true;
              }),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await f.finish(t);
        f.calls.clear();
        await t.tap(find.byIcon(Icons.arrow_back_rounded));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(popped, true);
        expect(find.text('Cover'), findsOneWidget);
        expect(find.text('Original Catalog'), findsOneWidget);
        expect(ModalRoute.of(t.element(find.text('Cover')))!.isCurrent, true);
        expect(f.calls, isEmpty);
      });
    },
  );
  testWidgets(
    'R three completion notifiers detach every listener after close',
    (t) async {
      await catalogDetailCase(t, (f) async {
        final notifiers = {
          'tracking': TrackingSourceStorage.trackingSourceRevision,
          'movie': MovieProgressStorage.movieFinishedRevision,
          'mdblist': MdblistService.instance.watchedRevision,
        };
        for (final e in notifiers.entries) {
          expect(
            _hasListeners(e.value),
            false,
            reason: 'before mount ${e.key}',
          );
        }
        await f.mount(t);
        for (final e in notifiers.entries) {
          expect(_hasListeners(e.value), true, reason: 'mounted ${e.key}');
        }
        await f.close(t);
        for (final e in notifiers.entries) {
          expect(_hasListeners(e.value), false, reason: 'after close ${e.key}');
        }
      });
    },
  );
}
