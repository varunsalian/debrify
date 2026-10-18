import 'dart:async';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/tv_episode_driver.dart';

/// Phase 17 original behaviour that the independent Step-0b mutation sample
/// found unpinned: header ownership of a first-seen next-channel URL, the
/// overlay guard on the Debrify banner, the Stremio source-index default,
/// the existing-stage skip of the playing source, the candidate staleness
/// guards around the resolver, and the debounced save during a held switch.
Future<void> _expireSleep(WidgetTester t, TvEpisodeDriver d) async {
  await pickSleep(t, d.f, const SleepTimerSelection(SleepTimerMode.countdown));
  await waitSleepToast(t, d.f, 'Sleep timer ended — paused');
}

void main() {
  testWidgets(
    'P17 Debrify next opens a never-seen URL with the session headers',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      // A URL no other case opens: media_kit's static Media cache cannot
      // supply headers an earlier open registered for the same URI.
      const fresh = 'https://player.test/p17-review-gaps-headers-only.mp4';
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/p17-review-gaps-launch.mp4',
            title: 'Film A',
            httpHeaders: const {'Referer': 'p17-gaps'},
            requestNextChannel: () async => {
              'firstUrl': fresh,
              'firstTitle': 'Film B',
            },
          ),
        );
        await d.nextChannel();
        expect(d.opens.last.uri, fresh);
        expect(d.opens.last.httpHeaders, {'Referer': 'p17-gaps'});
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  Iterable<DebrifyTvBanner> floating(WidgetTester t) => t
      .widgetList<DebrifyTvBanner>(find.byType(DebrifyTvBanner))
      .where((v) => !v.flush);

  for (final overlay in [false, true]) {
    testWidgets(
      'P17 Debrify next landing with overlayOpen=$overlay ${overlay ? 'raises no' : 'raises the'} floating banner',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final held = Completer<Map<String, dynamic>?>();
        var requested = false;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Film A',
              showChannelName: true,
              channelName: 'Alpha',
              requestNextChannel: () {
                requested = true;
                return held.future;
              },
            ),
          );
          // Captured while the launch controls expose it: later the
          // switch transition hides them.
          final showMenu = playerControls(t).onShowTracks;
          final next = playerControls(t).onNextChannel!;
          await d.f.advance(t, const Duration(seconds: 8));
          expect(floating(t), isEmpty);
          final dynamic callback = next;
          final task = d.observe<dynamic>(() => callback()) as Future<dynamic>;
          await d.f.until(t, () => requested);
          if (overlay) {
            showMenu();
            await d.f.advance(t, const Duration(milliseconds: 300));
            expect(find.byType(PlayerMenuPanel), findsOneWidget);
          }
          held.complete({
            'url': 'https://player.test/b.mp4',
            'channelName': 'Beta',
          });
          await d.f.finish<dynamic>(t, task);
          await d.f.advance(t);
          expect(
            floating(t).map((v) => v.channelName),
            overlay ? isEmpty : ['Beta'],
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!held.isCompleted) held.complete(null);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P17 Stremio guide pick without an index resets a non-zero source index to zero',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final first = episodeSource('First.S01E02');
      final second = episodeSource('Second.S01E02');
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final g = await d.stremioGuide();
        await d.stremioPick(
          g,
          'b',
          sources: [first, second],
          sourceIndex: 1,
          resolver: (source) async => 'https://player.test/remembered.mp4',
        );
        var sheet = await d.sourceSheet();
        expect(sheet.currentSourceIndex, 1);
        sheet.onClose();
        await d.f.advance(t);
        await d.stremioPick(g, 'c', sources: [second, first]);
        sheet = await d.sourceSheet();
        expect(sheet.sources, [second, first]);
        expect(sheet.currentSourceIndex, 0);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P17 existing-source stage never re-tries the playing source', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    final allowed = <String>[];
    final current = episodeSource('Current.S01E02');
    final other = episodeSource('Other.S01E02');
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: current.directUrl!,
          title: 'Show.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          stremioSources: [current, other],
          stremioCurrentSourceIndex: 0,
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 1,
            episode: 1,
            searchEpisodes: (s, e) async => [],
            searchPacks: (s, e) async => [],
            validateCandidate: (source) async {
              allowed.add(source.displayTitle);
              return true;
            },
          ),
          resolveSourceToPlaylist: (s, {canContinue}) async => [
            PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
          ],
        ),
      );
      allowed.clear();
      final b = await d.browser();
      await d.f.finish<dynamic>(
        t,
        d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
      );
      expect(allowed, [other.displayTitle]);
      expect(d.opens.last.uri, other.directUrl);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P17 candidate that went stale during validation never reaches the resolver',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final first = episodeSource('First.S01E02');
      final gate = Completer<bool>();
      final trace = <String>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [episodeSource('Original.S01E01'), first],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 2),
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              validateCandidate: (source) {
                trace.add('allow:${source.name}');
                return gate.future;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async {
              trace.add('resolve:${s.name}');
              return [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];
            },
          ),
        );
        trace.clear();
        d.player.emit('completed', true);
        await d.f.until(t, () => trace.contains('allow:${first.name}'));
        await _expireSleep(t, d);
        gate.complete(true);
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(trace, ['allow:${first.name}']);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete(false);
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 resolver continuation reports an abandoned candidate request',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final first = episodeSource('First.S01E02');
      final resolving = Completer<void>();
      final release = Completer<void>();
      final continuation = <bool>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [episodeSource('Original.S01E01'), first],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 2),
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              validateCandidate: (source) async => true,
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async {
              continuation.add(canContinue!());
              if (!resolving.isCompleted) resolving.complete();
              await release.future;
              continuation.add(canContinue());
              return [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];
            },
          ),
        );
        continuation.clear();
        d.player.emit('completed', true);
        await d.f.until(t, () => resolving.isCompleted);
        await _expireSleep(t, d);
        release.complete();
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(continuation, [true, false]);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!release.isCompleted) release.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 debounced save cannot rewrite the outgoing episode while a guide pick holds its pause',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final incoming = episodeSource('Show.S01E03');
      final pause = Completer<void>();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentImdbId: 'tt1700024',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchPacks: (s, e) async => [],
              searchEpisodes: (s, e) async => e == 3 ? [incoming] : [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        d.player.state = d.player.state.copyWith(
          duration: const Duration(minutes: 40),
          position: const Duration(minutes: 5),
        );
        d.player.emit('duration', d.player.state.duration);
        d.player.emit('position', d.player.state.position);
        await d.f.advance(t, const Duration(seconds: 2));
        final b = await d.browser();
        var entered = false;
        d.player.beforeOperation = (name, value) async {
          if (name == 'pause' && !entered) {
            entered = true;
            await pause.future;
          }
        };
        final task = d.observe<dynamic>(() => b.onEpisodeSelected(1, 3));
        await d.f.until(t, () => entered);
        final atHold = _storedPositions(
          await d.f.finish(t, PlaybackStateStore.getPlaybackStateMap()),
        );
        expect(atHold, contains(300000));
        // The outgoing stream keeps reporting progress while the switch is
        // parked on its pause; the 6 s autosave tick fires inside the hold.
        d.player.state = d.player.state.copyWith(
          position: const Duration(minutes: 7),
        );
        d.player.emit('position', d.player.state.position);
        await d.f.advance(t, const Duration(seconds: 7));
        final afterTick = _storedPositions(
          await d.f.finish(t, PlaybackStateStore.getPlaybackStateMap()),
        );
        expect(afterTick, isNot(contains(420000)));
        expect(afterTick, contains(300000));
        pause.complete();
        await d.f.finish<dynamic>(t, task as Future<dynamic>);
        await d.f.actions.settle(t);
        expect(d.opens.last.uri, incoming.directUrl);
        expect(d.errors, isEmpty);
      } finally {
        if (!pause.isCompleted) pause.complete();
        await d.close();
      }
    },
  );
}

/// Every `positionMs` stored anywhere in the physical resume map.
List<Object?> _storedPositions(Object? node) => switch (node) {
  Map() => [
    if (node.containsKey('positionMs')) node['positionMs'],
    for (final v in node.values) ..._storedPositions(v),
  ],
  List() => [for (final v in node) ..._storedPositions(v)],
  _ => const [],
};
