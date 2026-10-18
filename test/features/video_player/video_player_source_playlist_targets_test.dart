import 'dart:async';
import 'package:flutter/material.dart';
import 'package:debrify/models/torrent.dart';
import 'support/local_completion_driver.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'support/player_actions.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/features/video_player/application/vp_filename_hash.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';

import 'support/startup_driver.dart';

void main() {
  for (final target in [
    'matching',
    'opaque singleton',
    'missing pack',
    'specials only',
  ]) {
    testWidgets(
      'P16 explicit playlist target $target preserves the exact episode contract and outgoing checkpoint',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('Show.S01E02.mkv'),
            b = startupSource('Incoming.Show');
        final entries = target == 'matching'
            ? [
                const PlaylistEntry(
                  url: 'https://startup.test/special',
                  title: 'Show.S00E01.mkv',
                ),
                const PlaylistEntry(
                  url: 'https://startup.test/e2',
                  title: 'Show.S01E02.mkv',
                ),
                const PlaylistEntry(
                  url: 'https://startup.test/e1',
                  title: 'Show.S01E01.mkv',
                ),
              ]
            : target == 'opaque singleton'
            ? [
                const PlaylistEntry(
                  url: 'https://startup.test/opaque',
                  title: 'Torrentio quality',
                ),
              ]
            : [
                const PlaylistEntry(
                  url: 'https://startup.test/special',
                  title: 'Show.S00E01.mkv',
                ),
                PlaylistEntry(
                  url: 'https://startup.test/missing',
                  title: target == 'specials only'
                      ? 'Show.S00E02.mkv'
                      : 'Show.S01E01.mkv',
                ),
              ];
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              id: 'tt9200016',
              type: 'series',
              season: 1,
              episode: 2,
              entries: [PlaylistEntry(url: a.directUrl!, title: a.name)],
              playlist: (s, {canContinue}) async => entries,
            ),
          );
          await d.initialized();
          await d.player.seek(const Duration(seconds: 73));
          await d.tick();
          final sheet = await d.sheet();
          final url = await d.f.finish(t, sheet.resolveSource(b));
          expect(url, entries.first.url);
          final action = d.select(sheet, 1, url!);
          await d.f.finish(t, action.future);
          final success = target == 'matching' || target == 'opaque singleton';
          expect(d.commits, success ? [a, b] : [a]);
          expect(
            d.opens,
            success
                ? [a.directUrl, entries[target == 'matching' ? 1 : 0].url]
                : [a.directUrl, a.directUrl],
          );
          expect(
            d.player.state.position,
            target == 'opaque singleton'
                ? const Duration(milliseconds: 80)
                : const Duration(seconds: 73),
            reason:
                'The unparseable manual singleton has no episode identity for automatic restore; the original still accepts it',
          );
          expect(
            d.player.state.playlist.medias.single.uri,
            success ? entries[target == 'matching' ? 1 : 0].url : a.directUrl,
          );
          expect(
            find.text('This source is unavailable. Choose another source.'),
            success ? findsNothing : findsOneWidget,
          );
          expect(
            d.event('candidate_open').where((s) => s.contains('sourceIndex=1')),
            hasLength(success ? 1 : 0),
            reason:
                'A validated pack missing the current episode must never open any of its rows',
          );
          final saved = await d.f.finish(
            t,
            SeriesProgressStorage.getSeriesPlaybackState(
              seriesTitle: 'show',
              season: 1,
              episode: 2,
              imdbId: 'tt9200016',
            ),
          );
          expect(saved?['positionMs'], 73000);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final outgoingPack in [false, true]) {
    testWidgets(
      'P16 an accepted manual pack whose resume seek throws restores its ${outgoingPack ? 'playlist' : 'direct'} identity, headers and physical checkpoint',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource(
              'Show.S01E02.mkv',
              url: 'https://startup.test/resume-restore-a',
              headers: {'X-Outgoing': 'a'},
            ),
            b = startupSource(
              'Show.S01E02.mkv',
              url: 'https://startup.test/resume-restore-b',
            );
        try {
          await d.begin(
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: a.name,
              httpHeaders: a.httpHeaders,
              contentType: 'series',
              contentImdbId: 'tt9200016',
              contentSeason: 1,
              contentEpisode: 2,
              stremioSources: [a, b],
              playlist: outgoingPack
                  ? [
                      PlaylistEntry(
                        url: a.directUrl!,
                        title: a.name,
                        httpHeaders: a.httpHeaders,
                      ),
                    ]
                  : null,
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                const PlaylistEntry(
                  url: 'https://startup.test/bonus',
                  title: 'Show.S00E01.mkv',
                ),
                PlaylistEntry(
                  url: b.directUrl!,
                  title: b.name,
                  httpHeaders: {'X-Incoming': 'b'},
                ),
                const PlaylistEntry(
                  url: 'https://startup.test/third',
                  title: 'Show.S01E03.mkv',
                ),
              ],
              onStremioSourceCommitted: (s) async => d.commits.add(s),
            ),
          );
          await d.initialized();
          await d.player.seek(const Duration(seconds: 73));
          await d.tick();
          // The direct launch has a URL legacy key; its later pack entry has
          // a filename key. Seed that real incoming bookmark to exercise the
          // accepted-open -> resume-seek failure boundary in both layouts.
          await d.f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(vpFilenameHash(b.name), {
              'positionMs': 73000,
              'durationMs': 1200000,
              'speed': 1.0,
              'aspect': 'contain',
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          d.player.failures['seek'] = StateError(
            'fixture manual pack landing failed',
          );
          final action = d.select(sheet, 1, url);
          Object? error;
          try {
            await d.f.finish(t, action.future);
          } catch (e) {
            error = e;
          }
          expect(error, isNull);
          expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
          expect(d.commits, [a]);
          expect(
            d.logs,
            contains('Player: manual playlist source rejected (StateError)'),
          );
          expect(d.player.state.position, const Duration(seconds: 73));
          expect(
            find.text('This source is unavailable. Choose another source.'),
            findsOneWidget,
          );
          final restored =
              d.player.calls.where((c) => c.$1 == 'open').last.$2
                  as (mk.Playable, bool);
          expect((restored.$1 as mk.Media).httpHeaders, {'X-Outgoing': 'a'});
          playerControls(t).onPlayPause();
          await d.settle();
          final saved = await d.f.finish(
            t,
            SeriesProgressStorage.getSeriesPlaybackState(
              seriesTitle: outgoingPack ? 'show' : a.name,
              season: 1,
              episode: 2,
              imdbId: 'tt9200016',
            ),
          );
          expect(saved?['positionMs'], 73000);
          final bookmark = await d.f.finish(
            t,
            VideoResumeStorage.getVideoResume(
              outgoingPack ? vpFilenameHash(a.name) : a.directUrl!,
            ),
          );
          expect(bookmark?['positionMs'], 73000);
          if (outgoingPack) {
            playerControls(t).onShowPlaylist();
            await d.f.until(
              t,
              () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
            );
            final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
            expect(browser.currentEpisodeIndex, 0);
            expect(browser.seriesPlaylist.allEpisodes.map((e) => e.url), [
              a.directUrl,
            ]);
            expect(
              browser.seriesPlaylist.allEpisodes.single.seriesInfo.episode,
              2,
            );
          } else {
            expect(playerControls(t).hasPlaylist, isFalse);
            final c = startupSource('failed-after-restore');
            await d.update(
              d.screen(
                type: 'series',
                id: 'tt9200016',
                season: 1,
                episode: 2,
                sources: [a, b, c],
                resolve: (s) async => s.directUrl,
              ),
            );
            final next = await d.sheet();
            d.openFailures[c.directUrl!] = StateError(
              'fixture follow-up candidate failed',
            );
            await d.f.finish(t, d.select(next, 2, c.directUrl!).future);
            expect(d.opens, [
              a.directUrl,
              b.directUrl,
              a.directUrl,
              c.directUrl,
              a.directUrl,
            ]);
            expect(d.player.state.playlist.medias.single.uri, a.directUrl);
          }
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 an invalid manual pack swallows an outgoing direct reopen failure and still clears its replacement playlist',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('direct-restore-a'),
          b = startupSource('wrong-pack');
      try {
        await d.begin(
          d.screen(
            type: 'series',
            season: 1,
            episode: 2,
            sources: [a, b],
            playlist: (s, {canContinue}) async => const [
              PlaylistEntry(
                url: 'https://startup.test/wrong-e1',
                title: 'Show.S01E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://startup.test/wrong-e3',
                title: 'Show.S01E03.mkv',
              ),
            ],
          ),
        );
        await d.initialized();
        await d.player.seek(const Duration(seconds: 73));
        await d.tick();
        final sheet = await d.sheet();
        final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
        d.openFailures[a.directUrl!] = StateError(
          'fixture outgoing direct reopen failed',
        );
        final action = d.select(sheet, 1, url);
        Object? error;
        try {
          await d.f.finish(t, action.future);
        } catch (e) {
          error = e;
        }
        expect(error, isNull);
        expect(d.opens, [a.directUrl, a.directUrl]);
        expect(d.commits, [a]);
        expect(
          d.logs,
          contains(
            'Player: outgoing direct source restore failed (StateError)',
          ),
        );
        expect(d.player.state.playing, isFalse);
        expect(d.player.state.position, const Duration(seconds: 73));
        expect(playerControls(t).hasPlaylist, isFalse);
        final restoredSheet = await d.sheet();
        expect(restoredSheet.currentSourceIndex, 0);
        restoredSheet.onClose();
        await d.tick();
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsOneWidget,
        );
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P16 a rejected pack restores an unlanded remote target when the startup gate prevented its checkpoint',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource(
            'Remote.Show.S01E02.mkv',
            type: StreamType.torrent,
          ),
          b = startupSource(
            'Remote.Show.S01E02.mkv',
            url: 'https://startup.test/remote-failed-pack',
          );
      final first = d.openGates[a.directUrl!] = Completer<void>();
      final landing = Completer<void>();
      final tracks = CompletionDelivery(
        'restoreTrackPreferences',
        (v) => v == null,
      );
      try {
        await tracks.run(
          () => d.begin(
            d.screen(
              type: 'series',
              season: 1,
              episode: 2,
              id: 'tt9200016',
              startAtPercent: .25,
              entries: [PlaylistEntry(url: a.directUrl!, title: a.name)],
              sources: [a, b],
              playlist: (s, {canContinue}) async => [
                PlaylistEntry(url: b.directUrl!, title: b.name),
              ],
            ),
          ),
        );
        await d.openEntered();
        d.player.seekAcknowledgementPosition = Duration.zero;
        d.openGates.remove(a.directUrl!);
        first.complete();
        await d.f.until(t, () => tracks.pending.isNotEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
        ]);
        final key = vpFilenameHash(a.name);
        expect(
          await d.f.finish(t, VideoResumeStorage.getVideoResume(key)),
          isNull,
        );
        final sheet = await d.sheet();
        final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
        d.openFailures[b.directUrl!] = StateError(
          'fixture rejected remote pack',
        );
        d.player.delays['seek'] = landing;
        final action = d.select(sheet, 1, url);
        await d.f.until(
          t,
          () => d.player.calls.where((c) => c.$1 == 'seek').length == 2,
        );
        expect(action.isCompleted, isFalse);
        expect(landing.isCompleted, isFalse);
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsNothing,
        );
        landing.complete();
        await d.f.finish(t, action.future);
        expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
        expect(d.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
          const Duration(minutes: 5),
        ]);
        expect(d.player.state.position, Duration.zero);
        expect(tracks.pending, isNotEmpty);
        expect(
          await d.f.finish(t, VideoResumeStorage.getVideoResume(key)),
          isNull,
        );
        tracks.release();
        await d.initialized();
        playerControls(t).onPlayPause();
        await d.settle();
        final saved = await d.f.finish(
          t,
          VideoResumeStorage.getVideoResume(key),
        );
        expect(saved?['positionMs'], 300000);
        expect(d.commits, [a]);
      } finally {
        first.completeIfPending();
        landing.completeIfPending();
        tracks.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'P16 a same-content pack source switch clears a recent manual episode restriction and restores its physical local checkpoint',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('Show.S01E01.mkv'),
          b = startupSource('Incoming.Show');
      const second = 'https://startup.test/manual-e2';
      const incoming = 'https://startup.test/manual-incoming-e2';
      try {
        await d.begin(
          d.screen(
            type: 'series',
            id: 'tt9200016',
            season: 1,
            episode: 1,
            sources: [a, b],
            entries: [
              PlaylistEntry(url: a.directUrl!, title: a.name),
              const PlaylistEntry(url: second, title: 'Show.S01E02.mkv'),
            ],
            playlist: (s, {canContinue}) async => const [
              PlaylistEntry(
                url: 'https://startup.test/manual-incoming-e1',
                title: 'Show.S01E01.mkv',
              ),
              PlaylistEntry(url: incoming, title: 'Show.S01E02.mkv'),
            ],
          ),
        );
        await d.initialized();
        playerControls(t).onShowPlaylist();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        final selected = d.observe(
          () => d.f.actions.start('real manual episode selection', () async {
            await browser.onEpisodeSelected(1, 2);
          }),
        );
        await d.f.finish(t, selected.future);
        await d.f.until(t, () => find.byType(SeriesBrowser).evaluate().isEmpty);
        expect(d.player.state.playlist.medias.single.uri, second);
        await d.player.seek(const Duration(seconds: 73));
        await d.tick();
        final sheet = await d.sheet();
        final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
        await d.f.finish(t, d.select(sheet, 1, url).future);
        expect(d.player.state.playlist.medias.single.uri, incoming);
        expect(d.player.state.position, const Duration(seconds: 73));
        final saved = await d.f.finish(
          t,
          SeriesProgressStorage.getSeriesPlaybackState(
            seriesTitle: 'show',
            season: 1,
            episode: 2,
            imdbId: 'tt9200016',
          ),
        );
        expect(saved?['positionMs'], 73000);
        expect(d.commits.last, b);
      } finally {
        await d.close();
      }
    },
  );
}
