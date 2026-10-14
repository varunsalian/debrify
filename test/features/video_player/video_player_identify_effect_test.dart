import 'dart:convert';
import 'dart:async';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/identify_title_driver.dart';
import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/skip_segment_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'identify manual subtitle B preserves tracker and skip launch identity A',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      final cipher = (await t.runAsync(() => seedTrakt(target: false)))!;
      await t.runAsync(() async {
        await SimklStorage.setSimklAccessToken('vplayer-synthetic-simkl');
        await MdblistStorage.saveMdblistApiKey('vplayer-synthetic-mdblist');
        await TrackingSourceStorage.setTrackingScrobbleTargets({
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        });
      });
      final skip = SkipSegmentDriver(t, d.f);
      final identifyReply = d.f.network.handler!;
      await skip.configure();
      d.f.network.handler = (r) {
        if (r.url.host == 'api.skipdb.tv') return skipReply();
        if ([
          'api.trakt.tv',
          'api.simkl.com',
          'api.mdblist.com',
        ].contains(r.url.host)) {
          return secondaryReply(r);
        }
        return identifyReply(r);
      };
      d.metas = [IdentifyTitleDriver.identityMeta('Manual B', type: 'series')];
      try {
        cipher.hold = true;
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/identity-a.mp4',
            title: 'Launch A',
            contentImdbId: 'tt1200001',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            traktScrobble: true,
            simklScrobble: true,
            mdblistScrobble: true,
          ),
        );
        cipher.releaseAll();
        await d.f.until(
          t,
          () =>
              d.periodic.where((v) => v == const Duration(minutes: 2)).length >=
              2,
        );
        await d.f.actions.settle(t);
        final pending = d.start(await d.menu());
        await d.found('Manual B');
        await t.tap(find.text('Manual B'));
        final result = await d.f.finish(t, pending);
        expect(result?.imdbId, 'tt1200002');
        expect(result?.identityLabel, 'Subtitles for Manual B S2E3');
        expect(
          d.subtitlePaths,
          contains('/subtitles/series/tt1200002:2:3.json'),
        );
        expect(
          d.subtitlePaths,
          contains('/subtitles/series/tt1200001:2:3.json'),
        );
        d.panel.onClose();
        await d.f.advance(t);
        final menu = await d.menu();
        expect(menu.contentImdbId, 'tt1200002');
        expect(menu.subtitleIdentityLabel, 'Subtitles for Manual B S2E3');
        d.f.network.requests.clear();
        await skip.duration(const Duration(seconds: 1000));
        await skip.tick(40);
        playerControls(t).onPlayPause();
        await d.f.until(
          t,
          () =>
              d.f.network.requests
                  .where((r) => r.url.path == '/scrobble/pause')
                  .length ==
              3,
        );
        final trackerRequests = d.f.network.requests
            .where((r) => r.url.path == '/scrobble/pause')
            .toList();
        expect(
          trackerRequests.map((r) => r.url.host),
          unorderedEquals(['api.trakt.tv', 'api.simkl.com', 'api.mdblist.com']),
        );
        for (final r in trackerRequests) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          expect(jsonEncode(body), contains('tt1200001'));
          expect(jsonEncode(body), isNot(contains('tt1200002')));
        }
        expect(skip.requests, hasLength(1));
        skip.expectQuery(id: 'tt1200001', season: 2, episode: 3, seconds: 1000);
        expect(d.errors, isEmpty);
      } finally {
        cipher.releaseAll();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'identify manual season episode feeds direct prefetch when earlier coordinates are absent',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [
        IdentifyTitleDriver.identityMeta('Manual series', type: 'series'),
      ];
      final prepared = <(int, int, String?)>[];
      final direct = source(
        'Unparseable source',
        'https://player.test/direct.mp4',
      );
      final fetcher = SeriesSourceFetcher(
        searchPacks: (_, __) async => [],
        searchEpisodes: (_, __) async => [],
        season: 0,
        episode: 0,
        prepareNextDirectEpisode: (s, e, v) async {
          prepared.add((s, e, v.directUrl));
        },
      );
      try {
        await d.mountIdentity(
          screen: VideoPlayerScreen(
            videoUrl: direct.directUrl!,
            title: 'Unparseable source',
            stremioSources: [direct],
            stremioCurrentSourceIndex: 0,
            seriesSourceFetcher: fetcher,
          ),
        );
        final skip = SkipSegmentDriver(t, d.f);
        await skip.duration(const Duration(seconds: 100));
        await skip.tick(40);
        expect(prepared, isEmpty);
        final pending = d.start(await d.menu());
        await d.found('Manual series');
        await t.tap(find.text('Manual series'));
        await d.episode('4', '9');
        expect((await d.f.finish(t, pending))?.episode, 9);
        await skip.tick(45);
        expect(prepared, [(4, 9, direct.directUrl)]);
        await skip.tick(46);
        expect(prepared, hasLength(1));
        expect(d.subtitlePaths, ['/subtitles/series/tt1200002:4:9.json']);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );

  testWidgets(
    'identify movie after manual series clears coordinates before direct prefetch and adopts the new cache',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [
        IdentifyTitleDriver.identityMeta('Manual series', type: 'series'),
      ];
      final prepared = <(int, int)>[];
      final direct = source(
        'Unparseable',
        'https://player.test/manual-clear.mp4',
      );
      final fetcher = SeriesSourceFetcher(
        searchPacks: (_, __) async => [],
        searchEpisodes: (_, __) async => [],
        season: 0,
        episode: 0,
        prepareNextDirectEpisode: (s, e, _) async {
          prepared.add((s, e));
        },
      );
      try {
        await d.mountIdentity(
          screen: VideoPlayerScreen(
            videoUrl: direct.directUrl!,
            title: 'Unparseable',
            stremioSources: [direct],
            stremioCurrentSourceIndex: 0,
            seriesSourceFetcher: fetcher,
          ),
        );
        final series = d.start(await d.menu());
        await d.found('Manual series');
        await t.tap(find.text('Manual series'));
        await d.episode('4', '9');
        expect((await d.f.finish(t, series))?.season, 4);
        d.panel.onClose();
        await d.f.advance(t);
        d.metas = [
          IdentifyTitleDriver.identityMeta('Manual movie', id: 'tt1200003'),
        ];
        final movie = d.start(await d.menu());
        await d.found('Manual movie');
        await t.tap(find.text('Manual movie'));
        final result = await d.f.finish(t, movie);
        expect(result?.imdbId, 'tt1200003');
        expect(result?.contentType, 'movie');
        expect(result?.season, isNull);
        expect(result?.episode, isNull);
        expect(result?.identityLabel, 'Subtitles for Manual movie');
        final skip = SkipSegmentDriver(t, d.f);
        await skip.duration(const Duration(seconds: 100));
        await skip.tick(45);
        expect(prepared, isEmpty);
        expect(d.subtitlePaths, [
          '/subtitles/series/tt1200002:4:9.json',
          '/subtitles/movie/tt1200003.json',
        ]);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );

  testWidgets(
    'identify provider-owned playlist shrinking to the current index uses dynamic fallback through the quick caller',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      final a = source('Original', 'https://player.test/source-a.mp4');
      final b = source('Incoming', 'https://player.test/source-b.mp4');
      final returned = [
        PlaylistEntry(url: b.directUrl!, title: 'Incoming entry'),
      ];
      final commits = <String>[];
      try {
        await d.mountIdentity(
          screen: VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Original dynamic title',
            stremioSources: [a, b],
            stremioCurrentSourceIndex: 0,
            resolveSourceToPlaylist: (_, {canContinue}) async => returned,
            onStremioSourceCommitted: (v) async {
              commits.add(v.name);
            },
          ),
        );
        playerControls(t).onShowStremioSources!();
        await d.f.advance(t);
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = await d.f.finish(t, sheet.resolveSource(b));
        expect(url, b.directUrl);
        sheet.onSourceSelected(1, url!);
        await d.f.until(t, () => commits.isNotEmpty);
        await d.f.actions.settle(t);
        expect(commits, ['Incoming']);
        returned.clear();
        expect(playerControls(t).onSpeed, returnsNormally);
        await d.f.advance(t);
        expect(
          d.panel.subtitleIdentityLabel,
          'Detected: Original dynamic title',
        );
        expect(d.panel.hasPlaylist, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'identify manual title clears prior addon and embedded policy latches before selecting the new subtitle',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      await d.order(language: 'eng', embeddedFirst: true);
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('deu'),
      );
      final discovery = Completer<http.Response>();
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/latches.mp4',
            title: 'Old identity',
            contentImdbId: 'tt1200001',
            contentType: 'movie',
          ),
        );
        await d.f.until(
          t,
          () => d.player.calls.any(
            (call) =>
                call.$1 == 'subtitle' &&
                (call.$2 as mk.SubtitleTrack).id == '1',
          ),
        );
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.uri, isFalse);
        final old = const StremioSubtitle(
          id: 'old-choice',
          url: 'https://identify.subtitle.test/old.srt',
          lang: 'eng',
          source: 'Identity fixture',
        );
        var panel = await d.menu();
        expect(
          await d.f.finish(
            t,
            d.observe(() => panel.onAddonSubtitleSelected(old, '1')),
          ),
          isTrue,
        );
        expect(d.player.state.track.subtitle.uri, isTrue);
        await d.order(language: 'eng');
        panel.onClose();
        await d.f.advance(t);
        panel = await d.menu();
        expect(panel.selectedSubtitleId, 'stremio:old-choice');
        d.discovery = (_) => discovery.future;
        final pending = d.start(panel);
        await d.found('Chosen title');
        await t.tap(find.text('Chosen title'));
        await d.f.until(
          t,
          () => d.subtitlePaths.contains('/subtitles/movie/tt1200002.json'),
        );
        panel.onClose();
        await d.f.advance(t);
        final whileHeld = await d.menu();
        expect(discovery.isCompleted, isFalse);
        expect(whileHeld.selectedSubtitleId, d.player.state.track.subtitle.id);
        discovery.complete(d.slots('identify'));
        final chosen = await d.f.finish(t, pending);
        expect(chosen?.selectedSubtitleId, 'identify');
        expect(d.requests(d.caption('identify')), 1);
        expect(d.player.state.track.subtitle.uri, isTrue);
        expect(d.player.state.track.subtitle.id, isNot(contains('old-choice')));
        expect(d.errors, isEmpty);
      } finally {
        if (!discovery.isCompleted) discovery.complete(d.slots('identify'));
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'identify clears old addon slots before audio policy refresh during held new discovery',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('deu'),
      );
      final held = Completer<http.Response>();
      d.discovery = (r) =>
          r.url.path.contains('tt1200001') ? d.slots('launch') : held.future;
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/cache-policy.mp4',
            title: 'Launch A',
            contentImdbId: 'tt1200001',
            contentType: 'movie',
          ),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        await d.f.actions.settle(t);
        expect(d.requests(d.caption('launch')), 1);
        expect(d.requests(d.caption('identify')), 0);
        final panel = await d.menu();
        expect(panel.cachedAddonSlots, isNotNull);
        final pending = d.start(panel);
        await d.found('Chosen title');
        await t.tap(find.text('Chosen title'));
        await d.f.until(
          t,
          () => d.subtitlePaths.contains('/subtitles/movie/tt1200002.json'),
        );
        final heldPath = d.player.state.track.subtitle.id;
        final subtitleCalls = d.player.calls
            .where((call) => call.$1 == 'subtitle')
            .length;
        d.native.properties['current-tracks/audio/lang'] = 'spa';
        await d.f.finish(
          t,
          d.observe(
            () => panel.onAudioSelected('2', d.player.state.track.subtitle.id),
          ),
        );
        expect(held.isCompleted, isFalse);
        expect(d.requests(d.caption('launch')), 1);
        expect(d.requests(d.caption('identify')), 0);
        expect(d.player.state.track.subtitle.id, heldPath);
        expect(
          d.player.calls.where((call) => call.$1 == 'subtitle'),
          hasLength(subtitleCalls),
        );
        held.complete(d.slots('identify'));
        expect((await d.f.finish(t, pending))?.selectedSubtitleId, 'identify');
        expect(d.requests(d.caption('identify')), 1);
        expect(d.player.state.track.subtitle.uri, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        if (!held.isCompleted) held.complete(d.slots('identify'));
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'identify uses the series snapshot coordinates when the resolver playlist title changes in place',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [
        IdentifyTitleDriver.identityMeta('Chosen series', type: 'series'),
      ];
      final a = source('Original', 'https://player.test/snapshot-a.mp4');
      final b = source('Incoming', 'https://player.test/snapshot-b.mp4');
      final returned = [
        PlaylistEntry(url: b.directUrl!, title: 'Snapshot.Show.S02E03.mkv'),
      ];
      final commits = <String>[];
      try {
        await d.mountIdentity(
          screen: VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Original',
            stremioSources: [a, b],
            stremioCurrentSourceIndex: 0,
            resolveSourceToPlaylist: (_, {canContinue}) async => returned,
            onStremioSourceCommitted: (v) async {
              commits.add(v.name);
            },
          ),
        );
        playerControls(t).onShowStremioSources!();
        await d.f.advance(t);
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = await d.f.finish(t, sheet.resolveSource(b));
        sheet.onSourceSelected(1, url!);
        await d.f.until(t, () => commits.isNotEmpty);
        await d.f.actions.settle(t);
        final originalMenu = await d.menu();
        expect(originalMenu.contentSeason, 2);
        expect(originalMenu.contentEpisode, 3);
        originalMenu.onClose();
        await d.f.advance(t);
        returned[0] = PlaylistEntry(
          url: b.directUrl!,
          title: 'Changed.Show.S07E11.mkv',
        );
        final panel = await d.menu();
        expect(panel.subtitleIdentityLabel, 'Detected: Changed Show');
        final pending = d.start(panel);
        await d.found('Chosen series');
        await t.tap(find.text('Chosen series'));
        final selected = await d.f.finish(t, pending);
        expect(find.text('Which episode?'), findsNothing);
        expect(selected?.season, 2);
        expect(selected?.episode, 3);
        expect(
          d.subtitlePaths,
          contains('/subtitles/series/tt1200002:2:3.json'),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
