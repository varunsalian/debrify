import 'dart:async';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

void expectSelection(
  AdvancedSearchSelection s,
  EpisodesPanelFixture f, {
  bool whole = false,
  bool custom = false,
}) {
  expect(
    s.imdbId,
    custom ? CustomSeriesIdentity(f.addon.sourceBindingKey, f.id).id : f.id,
  );
  expect(s.isSeries, isTrue);
  expect(s.title, f.show.name);
  expect(s.year, '2026');
  expect(s.season, whole ? null : 1);
  expect(s.episode, whole ? null : 1);
  expect(s.contentType, 'series');
  expect(s.posterUrl, isNull);
  expect(s.traktSource, !whole && !custom);
  expect(s.mdblistSource, !whole && !custom);
  expect(s.traktProgressPercent, whole || custom ? null : 25);
  expect(s.mdblistProgressPercent, whole || custom ? null : 25);
  expect(s.simklSource, isFalse);
  expect(s.simklProgressPercent, isNull);
  expect(s.fromCatalogEpisodeDrillDown, !whole);
  expect(s.fromCatalogItemDetail, isFalse);
  expect(s.initialContinuousShuffle, isFalse);
  expect(s.stremioAddonId, custom ? f.addon.id : null);
  expect(s.stremioAddonKey, custom ? f.addon.sourceBindingKey : null);
  expect(s.stremioCatalogId, custom ? f.id : null);
  expect(s.stremioVideoId, custom ? 'provider-owned-pilot' : null);
}

void main() {
  testWidgets(
    'original addon fixture loads grouped episodes and TVMaze probe',
    (t) async {
      await episodesPanelCase(t, 'harness', 1, (f) async {
        await f.mount(t);
        expect(f.view.seasons.map((s) => s.number), [1, 2]);
        expect(f.view.episodes.map((e) => e.title), ['Pilot', 'Episode 1.2']);
        expect(
          f.requests.where((r) => r.url.host == 'episodes-original.invalid'),
          hasLength(1),
        );
        expect(
          f.requests
              .where((r) => r.url.host == 'api.tvmaze.com')
              .map((r) => r.url.path),
          ['/shows/1', '/lookup/shows'],
        );
        expect(
          f.requests
              .singleWhere((r) => r.url.path == '/lookup/shows')
              .url
              .queryParameters,
          {'imdb': f.id},
        );
        expect(f.view.showImageUrl, isNull);
      });
    },
  );
  for (final sources in [false, true]) {
    for (final customId in [false, true]) {
      testWidgets(
        'terminal ${sources ? 'Sources' : 'Quick Play'} exact order and selection custom=$customId',
        (t) async {
          await episodesPanelCase(
            t,
            'handoff-$sources-$customId',
            10 + (sources ? 2 : 0) + (customId ? 1 : 0),
            (f) async {
              f.traktSource = true;
              f.mdblistSource = true;
              f.progressLoader = () async => {'1-1': 25};
              if (customId) {
                f.videosOverride = [
                  {
                    'id': 'provider-owned-pilot',
                    'season': 1,
                    'episode': 1,
                    'title': 'Pilot',
                    'imdbRating': 7.5,
                  },
                ];
              }
              await f.mount(t);
              f.calls.clear();
              if (sources) {
                await f.sheet(t);
                await t.tap(find.text('Sources'));
              } else {
                f.view.play(f.view.episodes.first);
              }
              await t.pump();
              expect(f.calls, ['before', sources ? 'item' : 'quick']);
              expectSelection(
                sources ? f.selections.single : f.quickSelections.single,
                f,
                custom: customId,
              );
              expect(sources ? f.quickSelections : f.selections, isEmpty);
            },
          );
        },
      );
    }
  }
  testWidgets('Quick Play falls back to item with before dispatch', (t) async {
    await episodesPanelCase(t, 'quick-fallback', 20, (f) async {
      f.hasQuick = false;
      f.traktSource = true;
      f.mdblistSource = true;
      f.progressLoader = () async => {'1-1': 25};
      await f.mount(t);
      f.calls.clear();
      f.view.play(f.view.episodes.first);
      expect(f.calls, ['before', 'item']);
      expectSelection(f.selections.single, f);
      expect(f.quickSelections, isEmpty);
    });
  });
  for (final classic in [false, true]) {
    testWidgets(
      'direct host play short circuits ${classic ? 'Sources and Quick Play tiles' : 'view and sheet Play'}',
      (t) async {
        await episodesPanelCase(
          t,
          'direct-play-$classic',
          22 + (classic ? 1 : 0),
          (f) async {
            f.hasPlay = true;
            f.custom = !classic;
            await f.mount(t);
            f.calls.clear();
            if (classic) {
              final tile = t
                  .widgetList<EpisodeTile>(find.byType(EpisodeTile))
                  .first;
              tile.onSources();
              tile.onPlay();
              expect(f.played, [same(tile.episode), same(tile.episode)]);
            } else {
              final episode = f.view.episodes.first;
              f.view.play(episode);
              await f.sheet(t);
              await t.tap(find.text('Play'));
              expect(f.played, [same(episode), same(episode)]);
            }
            expect(f.calls, ['directPlay', 'directPlay']);
            expect(f.selections, isEmpty);
            expect(f.quickSelections, isEmpty);
          },
        );
      },
    );
  }
  testWidgets(
    'unavailable search dispatches whole show; direct-source offers Retry only',
    (t) async {
      await episodesPanelCase(t, 'unavailable-search', 30, (f) async {
        f.failMeta = true;
        await f.mount(t);
        expect(f.view.unavailable, isTrue);
        expect(
          f.requests.any(
            (r) =>
                r.url.host == 'api.trakt.tv' && r.url.path.endsWith('/seasons'),
          ),
          isTrue,
        );
        expect(
          f.requests.where((r) => r.url.host == 'api.tvmaze.com'),
          isEmpty,
        );
        f.calls.clear();
        f.view.onSearchForSources!();
        expect(f.calls, ['before', 'item']);
        expectSelection(f.selections.single, f, whole: true);
        f.direct = true;
        f.hasItem = false;
        await t.pumpWidget(f.shell(f.panel()));
        expect(f.view.onSearchForSources, isNull);
      });
    },
  );
  testWidgets(
    'source picker is awaited before count refresh and current host callback is used',
    (t) async {
      await episodesPanelCase(t, 'source-picker', 31, (f) async {
        f.custom = false;
        f.chrome = true;
        f.hasSourcePicker = true;
        final held = Completer<void>();
        f.sourcePicker = (_) => held.future;
        await f.mount(t);
        expect(find.text('Select Source'), findsOneWidget);
        await t.tap(find.text('Select Source'));
        await t.pump();
        f.sourceCount = 2;
        expect(find.text('Sources (2)'), findsNothing);
        held.complete();
        await t.pump();
        await t.pump();
        expect(find.text('Sources (2)'), findsOneWidget);
        expect(f.calls.where((c) => c == 'selectSource'), ['selectSource']);
        expect(f.sourceItems.last.id, f.id);
      });
    },
  );
}
