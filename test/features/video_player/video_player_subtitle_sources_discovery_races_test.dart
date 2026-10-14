import 'dart:async';
import 'dart:io';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart' show crossBoundary;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_subtitle_sources_priority_test.dart' show priorityScreen;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  testWidgets(
    'subtitle same-token discovery updates coalesce while download is held without duplicate native apply',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('higher');
      await d.register('lower');
      await d.order();
      final lower = Completer<http.Response>();
      final caption = Completer<http.Response>();
      d.f.network.handler = (r) {
        if (r.url.toString() == d.endpoint('lower')) {
          return lower.future;
        }
        if (r.url.toString() == d.caption('higher')) {
          return caption.future;
        }
        return d.f.network.replies[r.url.toString()] ??
            http.Response('{}', 404);
      };
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.until(t, () => d.requests(d.caption('higher')) == 1);
        final before = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        expect(d.player.state.track.subtitle.uri, isFalse);
        lower.complete(d.slots('lower'));
        await d.f.until(
          t,
          () => d.logs.any(
            (v) => v.contains('Fetched and cached 2 addon subtitles'),
          ),
        );
        expect(d.requests(d.caption('higher')), 1);
        expect(d.requests(d.caption('lower')), 0);
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(before),
        );
        caption.complete(d.f.network.replies[d.caption('higher')]!);
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        await d.f.actions.settle(t);
        expect(d.requests(d.caption('higher')), 1);
        expect(d.requests(d.caption('lower')), 0);
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(before + 1),
        );
        expect(
          await t.runAsync(
            () => File(d.player.state.track.subtitle.id).readAsString(),
          ),
          contains('higher'),
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!lower.isCompleted) {
          lower.complete(d.slots('lower'));
        }
        if (!caption.isCompleted) {
          caption.complete(http.Response('{}', 404));
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle newer content token proceeds while the outgoing generation download remains held',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('next');
      await d.order();
      final held = Completer<http.Response>();
      var deliveries = 0;
      d.f.network.handler = (r) {
        if (r.url.toString() == d.caption('next')) {
          deliveries++;
          if (deliveries == 1) {
            return held.future;
          }
        }
        return d.f.network.replies[r.url.toString()] ??
            http.Response('{}', 404);
      };
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/priority.mp4',
            title: 'Priority original',
            contentImdbId: 'tt1100001',
            contentType: 'movie',
            viewMode: PlaylistViewMode.raw,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/priority.mp4',
                title: 'First',
              ),
              PlaylistEntry(
                url: 'https://player.test/priority-next.mp4',
                title: 'Second',
              ),
            ],
          ),
          publishTracks: false,
        );
        await d.f.until(t, () => deliveries == 1);
        expect(d.player.state.track.subtitle.uri, isFalse);
        await crossBoundary(d, 'reset');
        await d.f.until(t, () => deliveries == 2);
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        expect(held.isCompleted, isFalse);
        final active = d.player.state.track.subtitle.id;
        final applies = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        held.complete(d.f.network.replies[d.caption('next')]!);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, active);
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(applies),
        );
        expect(d.requests(d.endpoint('next')), 2);
        expect(d.errors, isEmpty);
      } finally {
        if (!held.isCompleted) {
          held.complete(http.Response('{}', 404));
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stale discovery delivery cannot replace the incoming episode cache exposed by the menu',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('generation');
      await d.order();
      final old = Completer<http.Response>();
      d.f.network.replies[d.caption('fresh')] = http.Response(
        '1\n00:00:01,000 --> 00:00:02,000\nfresh\n',
        200,
      );
      d.f.network.handler = (r) =>
          r.url.path == '/subtitles/series/tt1100001:1:1.json'
          ? old.future
          : r.url.path == '/subtitles/series/tt1100001:1:2.json'
          ? d.slots('fresh')
          : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/trakt-one.mp4',
            title: 'Trakt.Show.S01E01.mkv',
            contentImdbId: 'tt1100001',
            contentType: 'series',
            playlist: traktPlaylist,
          ),
          publishTracks: false,
          settleInitialization: false,
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path == '/subtitles/series/tt1100001:1:1.json',
          ),
        );
        expect(old.isCompleted, isFalse);
        final browser = await traktBrowser(t, d.f);
        await d.f.finish<void>(
          t,
          d.observe(() => browser.onEpisodeSelected(1, 2)),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        final active = d.player.state.track.subtitle.id;
        old.complete(d.slots('retired'));
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, active);
        expect(d.requests(d.caption('retired')), 0);
        expect(
          d.logs.where(
            (s) =>
                s ==
                'VideoPlayer: Content changed during addon subtitle fetch, discarding results',
          ),
          isNotEmpty,
        );
        final panel = await d.menu();
        expect(panel.cachedAddonSlots, hasLength(1));
        expect(panel.cachedAddonSlots!.single.subtitles.map((s) => s.id), [
          'fresh',
        ]);
        expect(d.errors, isEmpty);
      } finally {
        if (!old.isCompleted) {
          old.complete(http.Response('{}', 404));
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle a new playback State owns an independent queue while a disposed State download is held',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('state-queue');
      await d.order();
      final old = Completer<http.Response>();
      var downloads = 0;
      d.f.network.handler = (r) {
        if (r.url.toString() == d.caption('state-queue') && ++downloads == 1) {
          return old.future;
        }
        return d.f.network.replies[r.url.toString()] ??
            http.Response('{}', 404);
      };
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.until(t, () => downloads == 1);
        expect(d.player.state.track.subtitle.uri, isFalse);
        final outgoing = d.player;
        await crossBoundary(d, 'dispose');
        expect(outgoing.disposed.isCompleted, isTrue);
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(old.isCompleted, isFalse);
        expect(d.f.players, hasLength(2));
        expect(downloads, 2);
        expect(d.player.state.track.subtitle.uri, isTrue);
        expect(outgoing.state.track.subtitle.uri, isFalse);
        final active = d.player.state.track.subtitle.id;
        old.complete(d.f.network.replies[d.caption('state-queue')]!);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, active);
        expect(outgoing.state.track.subtitle.uri, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!old.isCompleted) {
          old.complete(http.Response('{}', 404));
        }
        await removeFixture(d);
      }
    },
  );
}
