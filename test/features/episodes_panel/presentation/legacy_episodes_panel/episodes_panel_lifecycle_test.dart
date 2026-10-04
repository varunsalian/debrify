import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:http/http.dart' as http;
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

void main() {
  testWidgets(
    'same-key replacements preserve State and init-time handler/auth but use live chrome, progress loader and builder',
    (t) async {
      await episodesPanelCase(t, 'replacement', 40, (f) async {
        await t.runAsync(() => f.authenticate({TrackingSource.simkl}));
        f.custom = false;
        f.chrome = false;
        var oldReads = 0, newReads = 0;
        f.progressLoader = () async {
          oldReads++;
          return {};
        };
        await f.mount(t);
        final state = f.key.currentState!;
        expect(oldReads, 1);
        expect(
          t
              .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
              .focusNode!
              .onKeyEvent,
          isNull,
        );
        expect(
          t
              .widgetList<EpisodeTile>(find.byType(EpisodeTile))
              .first
              .onTrackerOptions,
          isNotNull,
        );
        await t.runAsync(SimklStorage.clearSimklAuth);
        f.show = const StremioMeta(
          id: 'tt9800041',
          imdbId: 'tt9800041',
          type: 'series',
          name: 'Replacement Show',
        );
        f.progressLoader = () async {
          newReads++;
          return {'1-1': 47};
        };
        f.chrome = true;
        final metaBefore = f.requests
            .where((r) => r.url.host == 'episodes-original.invalid')
            .length;
        await t.pumpWidget(f.shell(f.panel()));
        expect(f.key.currentState, same(state));
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(
          t
              .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
              .focusNode!
              .onKeyEvent,
          isNull,
        );
        expect(
          t
              .widgetList<EpisodeTile>(find.byType(EpisodeTile))
              .first
              .onTrackerOptions,
          isNotNull,
          reason: 'Cached init-time auth is not re-resolved by replacement',
        );
        expect(
          f.requests.where((r) => r.url.host == 'episodes-original.invalid'),
          hasLength(metaBefore),
        );
        expect(newReads, 0);
        expect(oldReads, 1);
        await t.runAsync(state.refreshWatchProgress);
        await t.pump();
        expect(newReads, 1);
        expect(oldReads, 1);
        expect(
          t
              .widgetList<EpisodeTile>(find.byType(EpisodeTile))
              .first
              .watchProgress,
          47,
        );
        f.custom = true;
        await t.pumpWidget(f.shell(f.panel()));
        expect(f.key.currentState, same(state));
        expect(f.view.episodes.first.title, 'Pilot');
        expect(f.view.progressOf(f.view.episodes.first), 47);
        expect(find.byType(EpisodeTile), findsNothing);
      });
    },
  );
  testWidgets(
    'GlobalKey refresh reads the current progress map without a re-entry',
    (t) async {
      await episodesPanelCase(t, 'public-refresh', 42, (f) async {
        var reads = 0;
        f.progressLoader = () async {
          reads++;
          return f.progress;
        };
        f.progress = {'1-1': 18};
        await f.mount(t);
        final state = f.key.currentState;
        expect(f.view.progressOf(f.view.episodes.first), 18);
        f.progress = {'1-1': 63};
        await t.runAsync(f.key.currentState!.refreshWatchProgress);
        await t.pump();
        expect(f.key.currentState, same(state));
        expect(reads, 2);
        expect(f.view.progressOf(f.view.episodes.first), 63);
        expect(
          f.requests.where((r) => r.url.host == 'episodes-original.invalid'),
          hasLength(1),
        );
      });
    },
  );
  testWidgets(
    'MDBList revision waits for current route then 750 ms and refreshes once',
    (t) async {
      await episodesPanelCase(t, 'revision-route', 43, (f) async {
        var reads = 0;
        f.progressLoader = () async {
          reads++;
          return {};
        };
        await f.mount(t);
        expect(reads, 1);
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        MdblistService.instance.playbackRevision.value++;
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(reads, 1);
        f.navigator.currentState!.pop();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 749));
        expect(reads, 1);
        await t.pump(const Duration(milliseconds: 1));
        await f.until(t, () => reads == 2);
        await t.pump(const Duration(seconds: 2));
        expect(reads, 2);
      });
    },
  );
  testWidgets(
    'newer MDBList bump supersedes older timer and unmount prevents publication',
    (t) async {
      await episodesPanelCase(t, 'revision-supersede', 44, (f) async {
        var reads = 0;
        f.progressLoader = () async {
          reads++;
          return {};
        };
        await f.mount(t);
        MdblistService.instance.playbackRevision.value++;
        await t.pump(const Duration(milliseconds: 300));
        MdblistService.instance.playbackRevision.value++;
        await t.pump(const Duration(milliseconds: 749));
        expect(reads, 1);
        await t.pump(const Duration(milliseconds: 1));
        await f.until(t, () => reads == 2);
        MdblistService.instance.playbackRevision.value++;
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 2));
        expect(reads, 2);
        MdblistService.instance.playbackRevision.value++;
        await t.pump(const Duration(seconds: 2));
        expect(reads, 2);
      });
    },
  );
  testWidgets(
    'mid-present scope change rejects old metadata before publishing the fresh request',
    (t) async {
      await episodesPanelCase(t, 'metadata-mid-scope', 47, (f) async {
        await f.mount(t);
        final initial = f.view.episodes;
        final pending = [
          Completer<http.Response>(),
          Completer<http.Response>(),
        ];
        var lookups = 0;
        f.onRequest = (request) async {
          if (request.url.host != 'api.tvmaze.com') return null;
          if (request.url.path == '/lookup/shows') {
            return pending[lookups++].future;
          }
          if (request.url.path.endsWith('/episodes')) {
            return http.Response(
              jsonEncode([
                {
                  'season': 1,
                  'number': 1,
                  'name': 'Scope metadata',
                  'image': {'medium': 'scope-thumb'},
                },
              ]),
              200,
            );
          }
          return null;
        };
        await t.runAsync(TVMazeService.clearCache);
        await t.runAsync(
          () => MetadataPreferencesService.save(
            MetadataPreferences(
              providers: {MetadataCategory.episodeArtwork: 'tvmaze'},
            ),
          ),
        );
        await f.until(t, () => lookups == 1);
        ProfileRuntime.scope.value = ProfileScope(
          profileId: 'episodes-metadata-scope',
          dataGeneration: 1,
          sessionEpoch: 0,
        );
        await f.until(t, () => lookups == 2);
        pending.first.complete(http.Response('{"id":77}', 200));
        await f.until(
          t,
          () => f.requests.any((r) => r.url.path == '/shows/77/episodes'),
        );
        for (var frame = 0; frame < 5; frame++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await t.pump();
        }
        expect(f.view.episodes, same(initial));
        expect(f.view.episodes.first.thumbnailUrl, isNull);
        pending.last.complete(http.Response('{"id":78}', 200));
        await f.until(
          t,
          () => f.view.episodes.first.thumbnailUrl == 'scope-thumb',
        );
        expect(f.view.episodes, isNot(same(initial)));
        expect(
          f.view.episodes.first.stremioVideoId,
          initial.first.stremioVideoId,
        );
      });
    },
  );
  for (final profile in [false, true]) {
    testWidgets(
      '${profile ? 'scope' : 'metadata policy'} notification rebuilds retained panel; after unmount publishes nothing',
      (t) async {
        await episodesPanelCase(t, 'policy-$profile', 45 + (profile ? 1 : 0), (
          f,
        ) async {
          await f.mount(t);
          final view = f.view;
          final requests = f.requests.length;
          if (profile) {
            ProfileRuntime.scope.value = ProfileScope(
              profileId: 'episodes-notification',
              dataGeneration: 1,
              sessionEpoch: 0,
            );
          } else {
            MetadataPreferencesService.revision.value++;
          }
          await t.pump();
          await t.pump();
          expect(f.view, isNot(same(view)));
          expect(f.view.generation, view.generation);
          expect(f.view.selectedSeasonNumber, view.selectedSeasonNumber);
          expect(f.requests, hasLength(requests));
          final latest = f.view;
          await t.pumpWidget(const SizedBox.shrink());
          if (profile) {
            ProfileRuntime.scope.value = ProfileScope(
              profileId: 'episodes-notification',
              dataGeneration: 2,
              sessionEpoch: 0,
            );
          } else {
            MetadataPreferencesService.revision.value++;
          }
          await t.pump();
          await t.pump();
          expect(f.view, same(latest));
        });
      },
    );
  }
}
