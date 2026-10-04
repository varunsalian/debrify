import 'dart:async';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/playlist_poster_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/playlist_content_fixture.dart';
import '../../../../support/playlist_content_profile.dart';
import 'playlist_content_metadata_test.dart' show poster, selectedShow, stored;
import 'playlist_content_progress_test.dart' show seedSeries;

Future<void> seedProfiles(
  WidgetTester t,
  PlaylistContentFixture f,
  PlaylistContentProfiles p, {
  bool sharedId = false,
}) async {
  await t.runAsync(() async {
    p.switchTo(p.a);
    await PlaylistStorage.savePlaylistItemsRaw([
      {...f.item, 'title': 'A-read-boundary'},
    ], recordSyncDeletions: false);
    p.switchTo(p.b);
    await PlaylistStorage.savePlaylistItemsRaw([
      sharedId
          ? {...f.item, 'title': 'B'}
          : {
              'provider': 'realdebrid',
              'rdTorrentId': 'B-displaced',
              'title': 'B',
            },
    ], recordSyncDeletions: false);
    p.switchTo(p.a);
  });
}

void main() {
  for (final torbox in [false, true]) {
    testWidgets(
      'read A save B stale raw list tombstones displaced B torbox=$torbox',
      (t) => playlistContentCase(t, (f) async {
        seedSeries(f);
        await f.mount(t);
        if (torbox) {
          f.item['provider'] = 'torbox';
        }
        final p = PlaylistContentProfiles();
        await t.runAsync(p.open);
        try {
          await seedProfiles(t, f, p);
          f.series.showPosterUrl = poster;
          late PlaylistContentReadBarrier barrier;
          late Future<void> operation;
          await t.runAsync(() async {
            barrier = PlaylistContentReadBarrier();
            operation = barrier.run(
              () => torbox
                  ? f.member('updatePlaylistPoster')(selectedShow)
                        as Future<void>
                  : f.member('saveDetectedSeriesPosterToPlaylist')()
                        as Future<void>,
            );
            await barrier.reached.future.timeout(const Duration(seconds: 5));
            expect(ProfileRuntime.capture(), p.a);
            p.switchTo(p.b);
            barrier.release.complete();
            await operation;
          });
          expect(barrier.captured, isTrue);
          expect(
            (await stored(t)).single,
            containsPair('title', 'A-read-boundary'),
          );
          expect((await stored(t)).single['posterUrl'], poster);
          final key = WebDavSyncRecordKey.playlistItem('rd:B-displaced');
          // Use the production dedupe key rather than assuming its persisted form.
          final displaced = WebDavSyncRecordKey.playlistItem(
            PlaylistStorage.computePlaylistDedupeKey({
              'provider': 'realdebrid',
              'rdTorrentId': 'B-displaced',
              'title': 'B',
            }),
          );
          expect(displaced, isNotEmpty);
          expect(key, isNotEmpty);
          expect(await t.runAsync(() => p.tombstones(p.b.profileId)), {
            displaced,
          });
          p.switchTo(p.a);
          expect((await stored(t)).single['posterUrl'], isNull);
          expect(await t.runAsync(() => p.tombstones(p.a.profileId)), isEmpty);
          expect(
            await t.runAsync(
              () => PlaylistPosterStorage.getPlaylistPosterOverride(f.item),
            ),
            poster,
          );
          p.switchTo(p.b);
          expect(
            await t.runAsync(
              () => PlaylistPosterStorage.getPlaylistPosterOverride(f.item),
            ),
            isNull,
          );
        } finally {
          await t.runAsync(p.close);
        }
      }),
    );
  }
  testWidgets(
    'captured preference instance rejects read and held write after switch without tombstones',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      final p = PlaylistContentProfiles();
      await t.runAsync(p.open);
      try {
        await seedProfiles(t, f, p);
        final prefs = (await t.runAsync(ProfilePreferences.instance))!;
        late Completer<void> entered;
        late Completer<void> release;
        late Future<bool> write;
        await t.runAsync(() async {
          entered = Completer<void>();
          release = Completer<void>();
          final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          write = prefs.setString('user_playlist_v1', '[]');
          final rejected = expectLater(write, throwsStateError);
          p.switchTo(p.b);
          expect(() => prefs.getString('user_playlist_v1'), throwsStateError);
          release.complete();
          await barrier;
          await rejected;
        });
        expect((await stored(t)).single['title'], 'B');
        expect(await t.runAsync(() => p.tombstones(p.b.profileId)), isEmpty);
        p.switchTo(p.a);
        expect((await stored(t)).single['title'], 'A-read-boundary');
        expect(await t.runAsync(() => p.tombstones(p.a.profileId)), isEmpty);
      } finally {
        await t.runAsync(p.close);
      }
    }),
  );
  testWidgets(
    'metadata then after unmount and handoff saves imdb and poster into new profile',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      final model = f.series;
      final parse = f.member('parseSeriesPlaylist');
      final p = PlaylistContentProfiles();
      await t.runAsync(p.open);
      try {
        await seedProfiles(t, f, p, sharedId: true);
        final response = Completer<http.Response>();
        f.held['/shows/42'] = response;
        // Reuse the real metadata entry point with a saved mapping selecting 42.
        final prefs = (await t.runAsync(ProfilePreferences.instance))!;
        await t.runAsync(() => prefs.setString('tvmaze_series_mappings', '{}'));
        f.series.tvmazeShowId = null;
        final fix = f.member('showFixMetadataDialog')() as Future<void>;
        await t.pump();
        f.navigatorKey.currentState!.pop(selectedShow);
        await t.pump();
        await t.runAsync(() => fix);
        await f.until(
          t,
          () => f.requests.any((r) => r.url.path == '/shows/42'),
        );
        await t.pumpWidget(const SizedBox.shrink());
        p.switchTo(p.b);
        response.complete(
          f.json({
            'id': 42,
            'name': 'Fixture',
            'image': {'original': poster},
            'externals': {'imdb': 'tt42'},
            'genres': [],
          }),
        );
        for (
          var i = 0;
          i < 100 && (await stored(t)).single['imdbId'] != 'tt42';
          i++
        ) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump(const Duration(milliseconds: 10));
        }
        expect((await stored(t)).single['imdbId'], 'tt42');
        expect((await stored(t)).single['posterUrl'], poster);
        expect(model.imdbId, 'tt42');
        expect(parse, isNotNull);
        expect(await t.runAsync(() => p.tombstones(p.b.profileId)), isEmpty);
        p.switchTo(p.a);
        expect((await stored(t)).single['imdbId'], isNull);
        expect(await t.runAsync(() => p.tombstones(p.a.profileId)), isEmpty);
      } finally {
        await t.runAsync(p.close);
      }
    }),
  );
  testWidgets(
    'watched action starting after handoff targets new profile',
    (t) => playlistContentCase(t, (f) async {
      seedSeries(f);
      await f.mount(t);
      final p = PlaylistContentProfiles();
      await t.runAsync(p.open);
      try {
        await seedProfiles(t, f, p);
        p.switchTo(p.b);
        await f.invoke(
          t,
          () =>
              f.member('toggleWatchedState')(f.series.allEpisodes.first)
                  as Future<void>,
        );
        expect(
          await t.runAsync(
            () => EpisodeProgressStorage.isEpisodeFinished(
              seriesTitle: 'fixture',
              season: 1,
              episode: 1,
            ),
          ),
          isTrue,
        );
        expect(await t.runAsync(() => p.tombstones(p.b.profileId)), isEmpty);
        p.switchTo(p.a);
        expect(
          await t.runAsync(
            () => EpisodeProgressStorage.isEpisodeFinished(
              seriesTitle: 'fixture',
              season: 1,
              episode: 1,
            ),
          ),
          isFalse,
        );
        expect(await t.runAsync(() => p.tombstones(p.a.profileId)), isEmpty);
      } finally {
        await t.runAsync(p.close);
      }
    }),
  );
}
