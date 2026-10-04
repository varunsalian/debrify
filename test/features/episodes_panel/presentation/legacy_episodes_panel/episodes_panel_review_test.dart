import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/episodes_panel_fixture.dart';
import 'episodes_panel_watched_test.dart'
    show actWatched, episodeBody, expectRequest;

void main() {
  testWidgets(
    'season change resets a scrolled Classic list and publishes season-control intent',
    (t) async {
      await episodesPanelCase(t, 'review-season-scroll', 600, (f) async {
        f.custom = false;
        f.chrome = true;
        f.videosOverride = [
          for (final season in [1, 2])
            for (var number = 1; number <= 20; number++)
              {
                'season': season,
                'episode': number,
                'title': number == 1 ? 'Pilot' : 'Episode $number',
                'imdbRating': 7.5,
              },
        ];
        await f.mount(t);
        final controller = t
            .widget<ListView>(find.byType(ListView))
            .controller!;
        controller.jumpTo(240);
        await t.pump();
        expect(controller.offset, 240);
        t
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged!(2);
        await t.pump();
        expect(controller.offset, 0);
        f.custom = true;
        await t.pumpWidget(f.shell(f.panel()));
        expect(f.view.selectedSeasonNumber, 2);
        expect(f.view.focusIntent, EpisodeFocusIntent.seasonControl);
      });
    },
  );

  testWidgets(
    'fully watched direct-source inventory still emits incomplete series',
    (t) async {
      await episodesPanelCase(t, 'review-direct-completion', 601, (f) async {
        f.direct = true;
        f.progress = {'1-1': 100, '1-2': 100, '2-1': 100, '2-2': 100};
        await f.mount(t);
        expect(f.completionEmissions, [false]);
      });
    },
  );

  for (final expired in [false, true]) {
    testWidgets(
      'direct-source Trakt gate hides rating and makes no auth request expired=$expired',
      (t) async {
        await episodesPanelCase(
          t,
          'review-direct-auth-$expired',
          expired ? 603 : 602,
          (f) async {
            await t.runAsync(() async {
              await f.authenticate({TrackingSource.trakt});
              if (expired) {
                await TraktStorage.setTraktRefreshToken(
                  'episodes-test-refresh',
                );
                await TraktStorage.setTraktTokenExpiry(0);
              }
            });
            f.direct = true;
            f.onRequest = (r) async => r.url.path == '/oauth/token'
                ? http.Response(
                    jsonEncode({
                      'access_token': 'episodes-refreshed',
                      'refresh_token': 'episodes-test-refresh',
                      'created_at':
                          DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      'expires_in': 86400,
                    }),
                    200,
                  )
                : null;
            await f.mount(t);
            await f.sheet(t);
            expect(find.text('Rate on Trakt'), findsNothing);
            expect(
              f.requests.where((r) => r.url.host == 'api.trakt.tv'),
              isEmpty,
            );
          },
        );
      },
    );
  }

  testWidgets(
    'Trakt episode rating submits canonical progress identity and complete body',
    (t) async {
      await episodesPanelCase(t, 'review-trakt-rating', 604, (f) async {
        f.show = StremioMeta(
          id: 'provider-review-604',
          imdbId: f.id,
          type: 'series',
          name: f.show.name,
        );
        expect(f.show.progressId, isNot(f.show.id));
        await t.runAsync(() => f.authenticate({TrackingSource.trakt}));
        await f.mount(t);
        await f.sheet(t);
        f.requests.clear();
        await t.tap(find.text('Rate on Trakt'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(Dialog), findsOneWidget);
        await t.tap(
          find.descendant(of: find.byType(Dialog), matching: find.text('7')),
        );
        await t.pump();
        await f.until(t, () => find.text('Rated 7/10').evaluate().isNotEmpty);
        expect(f.requests, hasLength(1));
        expectRequest(
          f.requests.single,
          method: 'POST',
          host: 'api.trakt.tv',
          path: '/sync/ratings',
          query: {},
          body: episodeBody({'imdb': f.id}, attributes: {'rating': 7}),
        );
      });
    },
  );

  for (final revision in [false, true]) {
    testWidgets(
      'primed MDBList continue-watching cache refetches after ${revision ? 'revision bump' : 'watched action'}',
      (t) async {
        await episodesPanelCase(
          t,
          'review-cw-$revision',
          revision ? 606 : 605,
          (f) async {
            await t.runAsync(() => f.authenticate({TrackingSource.mdblist}));
            f.progressLoader = () async => {};
            f.onRequest = (r) async => r.url.path == '/upnext'
                ? http.Response('{"items":[],"has_more":false}', 200)
                : null;
            final cw = MdblistContinueWatchingService.instance;
            cw.resetProfileScope();
            try {
              await f.mount(t);
              await t.runAsync(() async {
                expect((await cw.fetch()).isSuccess, isTrue);
              });
              final before = f.requests
                  .where((r) => r.url.path == '/upnext')
                  .length;
              expect(before, 1);
              await t.runAsync(() async {
                expect((await cw.fetch()).isSuccess, isTrue);
              });
              expect(
                f.requests.where((r) => r.url.path == '/upnext'),
                hasLength(before),
              );
              if (revision) {
                MdblistService.instance.playbackRevision.value++;
                await t.pump();
              } else {
                await actWatched(t, f, true);
              }
              await t.runAsync(() async {
                expect((await cw.fetch()).isSuccess, isTrue);
              });
              expect(
                f.requests.where((r) => r.url.path == '/upnext'),
                hasLength(before + 1),
              );
            } finally {
              cw.resetProfileScope();
            }
          },
        );
      },
    );
  }

  testWidgets(
    'TVMaze stills fill missing thumbnails and preserve addon stills without fetching artwork',
    (t) async {
      await episodesPanelCase(t, 'review-thumbnails', 607, (f) async {
        f.videosOverride = [
          {
            'season': 1,
            'episode': 1,
            'title': 'Pilot',
            'imdbRating': 7.5,
            'thumbnail': 'https://addon-art.invalid/kept.jpg',
          },
          {'season': 1, 'episode': 2, 'title': 'Second', 'imdbRating': 7.5},
        ];
        f.onRequest = (r) async {
          if (r.url.host != 'api.tvmaze.com') return null;
          if (r.url.path == '/lookup/shows') {
            return http.Response('{"id":607}', 200);
          }
          if (r.url.path == '/shows/607/episodes') {
            return http.Response(
              jsonEncode([
                for (final number in [1, 2])
                  {
                    'season': 1,
                    'number': number,
                    'image': {
                      'medium': 'https://tvmaze-art.invalid/$number.jpg',
                    },
                  },
              ]),
              200,
            );
          }
          return null;
        };
        await f.mount(t);
        expect(f.view.episodes.map((e) => e.thumbnailUrl), [
          'https://addon-art.invalid/kept.jpg',
          'https://tvmaze-art.invalid/2.jpg',
        ]);
        expect(
          f.requests.where((r) => r.url.host.endsWith('-art.invalid')),
          isEmpty,
        );
        expect(find.byType(EpisodeTile), findsNothing);
      });
    },
  );

  testWidgets('source button disposes its owned focus node on unmount', (
    t,
  ) async {
    await episodesPanelCase(t, 'review-source-dispose', 608, (f) async {
      f.custom = false;
      f.chrome = true;
      f.hasSourcePicker = true;
      await f.mount(t);
      final nodes = FocusManager.instance.rootScope.descendants
          .where((n) => n.debugLabel == 'catalog-select-source-btn')
          .toList();
      expect(nodes, hasLength(1));
      final node = nodes.single;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      expect(() => node.addListener(() {}), throwsFlutterError);
    });
  });
}
