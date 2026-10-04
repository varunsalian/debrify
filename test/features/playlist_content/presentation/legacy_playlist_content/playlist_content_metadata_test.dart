import 'dart:async';

import 'package:debrify/services/storage/playlist_poster_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/tvmaze_mapping_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/widgets/tvmaze_search_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/playlist_content_fixture.dart';
import 'playlist_content_progress_test.dart' show seedSeries;

const poster = 'https://artwork.test/original.png';
const selectedShow = <String, dynamic>{
  'id': 42,
  'name': 'Corrected Fixture',
  'image': {'original': poster, 'medium': 'https://artwork.test/medium.png'},
};

Future<List<Map<String, dynamic>>> stored(WidgetTester t) async =>
    (await t.runAsync(PlaylistStorage.getPlaylistItemsRaw))!;
Future<void> seed(WidgetTester t, PlaylistContentFixture f) async {
  await t.runAsync(
    () => PlaylistStorage.savePlaylistItemsRaw([
      {...f.item},
      {'provider': 'realdebrid', 'rdTorrentId': 'other', 'title': 'Other'},
    ]),
  );
}

void main() {
  for (final provider in [
    'realdebrid',
    'torbox',
    'pikpak',
    'premiumize',
    'alldebrid',
    'webdav',
    'rd',
    'torbox_webdl',
  ]) {
    testWidgets(
      'poster override and artwork provider=$provider',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t);
        f.item['provider'] = provider;
        await seed(t, f);
        await f.invoke(
          t,
          () => f.member('updatePlaylistPoster')(selectedShow) as Future<void>,
        );
        expect(
          await t.runAsync(
            () => PlaylistPosterStorage.getPlaylistPosterOverride(f.item),
          ),
          poster,
        );
        final rows = await stored(t);
        expect(
          rows.first['posterUrl'],
          ['webdav', 'rd', 'torbox_webdl'].contains(provider) ? null : poster,
        );
        expect(rows.last['posterUrl'], isNull);
        expect(
          f.item['posterUrl'],
          isNull,
          reason: 'The original item map is not refreshed',
        );
      }),
    );
  }
  testWidgets(
    'TorBox poster compares raw ids without string coercion',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      f.item['provider'] = 'torbox';
      await t.runAsync(
        () => PlaylistStorage.savePlaylistItemsRaw([
          {...f.item, 'torboxTorrentId': '91'},
        ]),
      );
      await f.invoke(
        t,
        () => f.member('updatePlaylistPoster')(selectedShow) as Future<void>,
      );
      expect((await stored(t)).single['posterUrl'], isNull);
      expect(
        await t.runAsync(
          () => PlaylistPosterStorage.getPlaylistPosterOverride(f.item),
        ),
        poster,
      );
    }),
  );
  testWidgets(
    'detected poster writes dedupe matching raw list without refreshing item',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      await seed(t, f);
      f.series.showPosterUrl = poster;
      await f.invoke(
        t,
        () => f.member('saveDetectedSeriesPosterToPlaylist')() as Future<void>,
      );
      expect((await stored(t)).first['posterUrl'], poster);
      expect((await stored(t)).last['posterUrl'], isNull);
      expect(f.item['posterUrl'], isNull);
    }),
  );
  for (final value in [null, '', 'tmdb:41', 'tt41']) {
    for (final existing in [false, true]) {
      testWidgets(
        'unforced imdb save value=$value existing=$existing',
        (t) => playlistContentCase(t, (f) async {
          seedSeries(f);
          await f.mount(t);
          if (existing) {
            f.item['imdbId'] = 'ttOld';
          }
          await seed(t, f);
          f.series.imdbId = value;
          await f.invoke(
            t,
            () => f.member('saveImdbIdToPlaylist')() as Future<void>,
          );
          expect(
            (await stored(t)).first['imdbId'],
            existing
                ? 'ttOld'
                : value == 'tt41'
                ? 'tt41'
                : null,
          );
        }),
      );
    }
  }
  testWidgets(
    'Fix Metadata cancellation changes no mapping poster or model',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      await seed(t, f);
      final model = f.series;
      final prior = await stored(t);
      final before = await t.runAsync(
        () => TvMazeMappingStorage.getTVMazeSeriesMapping(f.item),
      );
      final operation = f.member('showFixMetadataDialog')() as Future<void>;
      await t.pump();
      expect(find.byType(TVMazeSearchDialog), findsOneWidget);
      expect(
        t.widget<ModalBarrier>(find.byType(ModalBarrier).last).dismissible,
        isFalse,
      );
      f.navigatorKey.currentState!.pop();
      await t.pump();
      await t.runAsync(() => operation);
      await t.pump(const Duration(milliseconds: 600));
      expect(await stored(t), prior);
      expect(
        await t.runAsync(
          () => TvMazeMappingStorage.getTVMazeSeriesMapping(f.item),
        ),
        before,
      );
      expect(identical(f.series, model), isTrue);
    }),
  );
  for (final unmount in [false, true]) {
    testWidgets(
      'Fix Metadata cache misses mapping reset forced save unmount=$unmount',
      (t) => playlistContentCase(t, (f) async {
        seedSeries(f);
        await f.mount(t);
        await seed(t, f);
        final persisted = await stored(t);
        persisted.first['imdbId'] = 'ttOld';
        await t.runAsync(() => PlaylistStorage.savePlaylistItemsRaw(persisted));
        await t.runAsync(
          () => TvMazeMappingStorage.saveTVMazeSeriesMapping(
            playlistItem: f.item,
            tvmazeShowId: 41,
            showName: 'Old',
          ),
        );
        await t.runAsync(() => TVMazeService.getShowById(41));
        await t.runAsync(() => TVMazeService.getEpisodes(41));
        f.requests.clear();
        f.metadataImdb = 'tt42';
        f.metadataPoster = poster;
        final response = Completer<http.Response>();
        f.held['/shows/42'] = response;
        final model = f.series;
        final operation = f.member('showFixMetadataDialog')() as Future<void>;
        await t.pump();
        f.navigatorKey.currentState!.pop(selectedShow);
        await t.pump();
        await t.runAsync(() => operation);
        await t.pump(const Duration(milliseconds: 600));
        await f.until(
          t,
          () => f.requests.any((r) => r.url.path == '/shows/42'),
        );
        expect(identical(f.series, model), isTrue);
        expect(model.tvmazeShowId, isNull);
        expect(model.tvmazeShowName, isNull);
        expect(model.showPosterUrl, isNull);
        expect(f.member('isLoadingSeriesMetadata'), isTrue);
        expect(
          find.text('Metadata fixed! Using "Corrected Fixture" from TVMaze'),
          findsOneWidget,
        );
        expect(
          await t.runAsync(
            () => TvMazeMappingStorage.getTVMazeSeriesMapping(f.item),
          ),
          containsPair('tvmazeShowId', 42),
        );
        expect((await stored(t)).first['posterUrl'], poster);
        await t.runAsync(() => TVMazeService.getShowById(41));
        await t.runAsync(() => TVMazeService.getEpisodes(41));
        expect(
          f.requests.where((r) => r.url.path == '/shows/41'),
          hasLength(1),
        );
        expect(
          f.requests.where((r) => r.url.path == '/shows/41/episodes'),
          hasLength(1),
        );
        if (unmount) {
          await t.pumpWidget(const SizedBox.shrink());
        }
        response.complete(
          f.json({
            'id': 42,
            'name': 'Corrected Fixture',
            'image': {'original': poster},
            'externals': {'imdb': 'tt42'},
            'genres': ['Drama'],
          }),
        );
        await f.until(
          t,
          () => model.imdbId == 'tt42' && model.tvmazeShowId == 42,
        );
        for (
          var i = 0;
          i < 30 && (await stored(t)).first['imdbId'] != 'tt42';
          i++
        ) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump();
        }
        expect((await stored(t)).first['imdbId'], 'tt42');
        expect((await stored(t)).first['posterUrl'], poster);
        expect(f.item['imdbId'], isNull);
        expect(
          f.requests.where((r) => r.url.path == '/shows/42/episodes'),
          hasLength(1),
        );
        if (!unmount) {
          await f.until(t, () => f.member('isLoadingSeriesMetadata') == false);
        }
      }),
    );
  }
}
