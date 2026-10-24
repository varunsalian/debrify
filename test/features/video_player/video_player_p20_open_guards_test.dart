import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/resume_server_driver.dart';
import 'support/startup_driver.dart';
import 'support/stremio_tv_pick.dart';
import 'support/tv_episode_driver.dart';

final _wakeDrain = Object();
const _failed = 'No playable source could be started.';
const _rendererFailure = 'fixture MediaCodec video output failure';
const _serverOpen = 'SourceSelect: event=media_server_open ';

Future<void> _drainWake(WidgetTester t) => t.runAsync(
  () => PlayerDisplayControls.instance.setWakelockOwner(_wakeDrain, false),
);

Finder _failureSnack() =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(_failed));

Future<void> _directSurface(StartupDriver d) => d.f.finish(
  d.t,
  PlayerSettingsStorage.setAndroidVideoRendererMode(
    AndroidVideoRendererMode.directSurface,
  ),
);

/// The media-server launch from [ResumeServerDriver.screen] with extra fields.
VideoPlayerScreen _serverScreen(
  ResumeServerDriver server, {
  bool channels = false,
  Future<Map<String, dynamic>?> Function(String)? next,
}) {
  final seed = server.screen();
  return VideoPlayerScreen(
    videoUrl: seed.videoUrl,
    title: seed.title,
    httpHeaders: seed.httpHeaders,
    contentImdbId: seed.contentImdbId,
    contentType: seed.contentType,
    contentTitle: seed.contentTitle,
    contentSeason: seed.contentSeason,
    contentEpisode: seed.contentEpisode,
    resumePolicy: seed.resumePolicy,
    stremioSources: server.sources,
    stremioCurrentSourceIndex: 0,
    resolveStremioSource: (s) async => s.directUrl,
    stremioTvChannels: channels ? stremioTvPickDirectory : null,
    stremioTvCurrentChannelId: channels || next != null ? 'a' : null,
    stremioTvChannelSwitchProvider: channels ? stremioTvNoSwitch : null,
    stremioTvNextProvider: next,
  );
}

bool _stopped(ResumeServerDriver server) =>
    server.reports.any((r) => r.url.path.endsWith('/Playing/Stopped'));

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P20 a Stremio TV channel switch releases the outgoing resume guard: the new channel saves its own position',
    (t) async {
      final d = EngineDriver(
        t,
        configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
      );
      await d.initialize();
      try {
        await d.f.finish<void>(
          t,
          VideoProgressStorage.saveVideoPlaybackState(
            videoTitle: 'P20 guarded slot',
            videoUrl: 'https://guard.test/a.mp4',
            positionMs: const Duration(minutes: 4).inMilliseconds,
            durationMs: const Duration(minutes: 20).inMilliseconds,
          ),
        );
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://guard.test/a.mp4',
            title: 'P20 guarded slot',
            stremioTvChannels: stremioTvPickDirectory,
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: stremioTvNoSwitch,
          ),
        );
        List<Object?> seeks() => [
          for (final c in d.player.calls)
            if (c.$1 == 'seek') c.$2,
        ];
        expect(
          seeks(),
          contains(const Duration(minutes: 4)),
          reason: 'the launch armed a guarded resume that did not land',
        );
        final switched = await beginStremioTvPick(
          t,
          d.f,
          'b',
          observe: d.observe,
        );
        await d.f.finish<dynamic>(t, switched);
        final before = seeks().length;
        await d.f.advance(t, const Duration(seconds: 7));
        await d.f.actions.settle(t);
        expect(seeks().skip(before), isEmpty, reason: 'no stale re-seek');
        final saved = await d.f.finish(
          t,
          VideoProgressStorage.getVideoPlaybackState(videoTitle: 'Channel b'),
        );
        expect(saved, isNotNull);
        expect(
          saved!['positionMs'] as int,
          lessThan(const Duration(seconds: 10).inMilliseconds),
          reason: 'the old target must not be substituted for the new channel',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a superseded Stremio TV startup open that throws after a renderer rebuild fails neither the new watch nor the launch',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      await _directSurface(d);
      const url = 'https://guard.test/rebuilt-slot.mp4';
      final gate = d.openGates[url] = Completer<void>();
      try {
        await d.begin(
          const VideoPlayerScreen(
            videoUrl: url,
            title: 'P20 rebuilt slot',
            stremioTvChannels: stremioTvPickDirectory,
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: stremioTvNoSwitch,
          ),
        );
        await d.openEntered();
        final old = d.player;
        old.emit('error', _rendererFailure);
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.openEntered(2);
        expect(
          d.subscriptions.where(
            (s) => s.owner == 'tv' && identical(s.player, d.player),
          ),
          isNotEmpty,
          reason: 'the rebuilt instance installed its own startup watch',
        );
        old.failures['open'] = StateError('superseded open failed late');
        gate.complete();
        await d.tick(const Duration(seconds: 1));
        expect(
          d.logs.where(
            (l) => l.startsWith('VideoPlayer: initial open failed:'),
          ),
          hasLength(1),
        );
        expect(_failureSnack(), findsNothing);
        d.frame();
        await d.tick(const Duration(seconds: 2));
        await d.settle();
        expect(_failureSnack(), findsNothing);
        expect(d.routeReturned, isFalse);
      } finally {
        gate.completeIfPending();
        await d.close();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a Stremio TV startup rejection is abandoned when a channel switch lands during its report',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      d.prearm = Completer<void>();
      final resource = (await d.f.finish(
        t,
        MediaServerService.connections(),
      )).single;
      try {
        await d.begin(_serverScreen(server, channels: true));
        await d.f.until(t, () => d.prearmEntered);
        await d.f.finish(
          t,
          MediaServerService.remove(resource, revokeBorrowers: true),
        );
        d.prearm!.complete();
        await d.f.until(t, () => _failureSnack().evaluate().isNotEmpty);
        expect(d.opens, isEmpty);
        final switched = await beginStremioTvPick(t, d.f, 'b');
        await d.f.finish<dynamic>(t, switched);
        expect(d.opens, ['https://stremio-pick.test/b.mp4']);
        d.frame();
        await d.tick(const Duration(seconds: 2));
        await d.settle();
        expect(d.routeReturned, isFalse);
      } finally {
        d.prearm!.completeIfPending();
        await d.close();
        server.restoreFactories();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a Stremio TV startup open superseded during server watch preparation never arms its startup watch',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      final hold = Completer<void>();
      var held = false;
      server.heldRequest = (r) => !hold.isCompleted;
      server.beforeRequest = (r) async {
        held = true;
        await hold.future;
      };
      try {
        await d.begin(_serverScreen(server, channels: true));
        await d.f.until(t, () => held);
        expect(d.opens, isEmpty);
        final switched = await beginStremioTvPick(t, d.f, 'b');
        await d.f.finish<dynamic>(t, switched);
        hold.complete();
        await d.tick(const Duration(seconds: 1));
        await d.settle();
        expect(d.opens, ['https://stremio-pick.test/b.mp4']);
        expect(
          d.subscriptions.where((s) => s.owner == 'tv'),
          isEmpty,
          reason: 'beforeOpen must not run for the superseded launch',
        );
        expect(d.logs.where((l) => l.startsWith(_serverOpen)), isEmpty);
        d.frame();
        await d.initialized();
        await d.settle();
      } finally {
        hold.completeIfPending();
        await d.close();
        server.restoreFactories();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a startup candidate is re-authorized at its open: an IPTV source without a ticket never opens',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('p20-unticketed', addon: 'iptv:p20');
      try {
        await d.begin(
          d.screen(sources: [a], resolve: (s) async => s.directUrl),
        );
        await d.f.until(t, () => d.event('exhausted').isNotEmpty);
        expect(d.opens, isEmpty);
        await d.f.until(t, () => d.routeReturned);
      } finally {
        await d.close();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a plain Stremio source matching the launch URL is not treated as a media-server watch source',
    (t) async {
      final a = startupSource('p20-plain-row');
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P20 plain row',
            stremioSources: [a],
            stremioCurrentSourceIndex: 0,
          ),
        );
        d.player.emit('error', 'HTTP error 403 Forbidden');
        await d.f.advance(t);
        expect(
          d.logs.where(
            (l) => l.startsWith('SourceSelect: event=media_server_'),
          ),
          isEmpty,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a next slot on another URL closes the outgoing server watch session and opens no server watch',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      try {
        await d.begin(
          _serverScreen(
            server,
            next: (id) async => {
              'channelId': 'b',
              'url': 'https://plain.test/next-slot.mp4',
              'title': 'Channel b',
            },
          ),
        );
        await d.initialized();
        d.player.emit('position', const Duration(seconds: 1));
        await d.f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
        );
        expect(d.logs.where((l) => l.startsWith(_serverOpen)), hasLength(1));
        expect(_stopped(server), isFalse);
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
        await d.settle();
        expect(d.opens.last, 'https://plain.test/next-slot.mp4');
        await d.f.until(
          t,
          () => _stopped(server),
          reason: 'the outgoing session closes at the new open',
        );
        expect(d.logs.where((l) => l.startsWith(_serverOpen)), hasLength(1));
      } finally {
        await d.close();
        server.restoreFactories();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a renderer rebuild reopening the same server source keeps its watch session reporting',
    (t) async {
      final d = StartupDriver(t, native: true, autoFrame: true);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      await _directSurface(d);
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      try {
        await d.begin(_serverScreen(server));
        await d.initialized();
        d.player.emit('position', const Duration(seconds: 1));
        await d.f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
        );
        final old = d.player;
        old.emit('error', _rendererFailure);
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.openEntered(2);
        await d.settle();
        expect(_stopped(server), isFalse);
        d.player.emit('position', const Duration(seconds: 61));
        await d.f.until(
          t,
          () => server.reports.any(
            (r) =>
                r.url.path.endsWith('/Progress') &&
                server.body(r)['PositionTicks'] == 610000000,
          ),
          reason: 'the rebuilt player still reports through the same session',
        );
        expect(_stopped(server), isFalse);
      } finally {
        await d.close();
        server.restoreFactories();
        await _drainWake(t);
      }
    },
  );
  testWidgets(
    'P20 a renderer rebuild of a pending Stremio TV launch cancels the outgoing startup watch on the old player',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      await _directSurface(d);
      try {
        await d.begin(
          const VideoPlayerScreen(
            videoUrl: 'https://guard.test/rebuilt-watch.mp4',
            title: 'P20 rebuilt watch',
            stremioTvChannels: stremioTvPickDirectory,
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: stremioTvNoSwitch,
          ),
        );
        await d.openEntered();
        final old = d.player;
        Iterable<StartupSubscription> watch(FakePlayer p) => d.subscriptions
            .where((s) => s.owner == 'tv' && identical(s.player, p));
        expect(watch(old), isNotEmpty);
        expect(watch(old).where((s) => s.cancelled), isEmpty);
        old.emit('error', _rendererFailure);
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.openEntered(2);
        expect(watch(d.player), isNotEmpty);
        expect(
          watch(old).where((s) => !s.cancelled),
          isEmpty,
          reason: 'the rebuild disposes the outgoing startup watch',
        );
        d.frame();
        await d.tick(const Duration(seconds: 2));
        await d.settle();
      } finally {
        await d.close();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a shuffle candidate whose native open fails keeps its new identity, so shuffle moves on to the other episode',
    (t) async {
      String url(String name) =>
          'https://guard.test/${Uri.encodeComponent(name)}.mp4';
      PlaylistEntry entry(String name) =>
          PlaylistEntry(url: url(name), title: name);
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: url('Mix.S01E01.mkv'),
            title: 'Mix.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            disableAutoResume: true,
            initialContinuousShuffle: true,
            playlist: [entry('Mix.S01E01.mkv'), entry('Mix.S01E02.mkv')],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              loadCustomEpisodeInventory: () async => [
                for (final n in [1, 2])
                  {'season': 1, 'number': n, 'airdate': '2020-01-0$n'},
              ],
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        d.player.failures['open'] = StateError('shuffle open failed');
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next()) as Future<dynamic>,
        );
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.actions.settle(t);
        // The failed E02 open had started, so its identity was not rolled
        // back: shuffle then treats E02 as current and picks E01.
        expect(d.opens.map((m) => m.uri), [
          url('Mix.S01E01.mkv'),
          url('Mix.S01E02.mkv'),
          url('Mix.S01E01.mkv'),
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 turning continuous shuffle off while a server-source episode is held in watch preparation publishes nothing for it',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      final hold = Completer<void>();
      var held = false;
      final launch = server.sources.first;
      final shuffled = server.sources.last;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: launch.directUrl!,
            title: 'Mix.S01E01.mkv',
            httpHeaders: launch.httpHeaders,
            contentType: 'series',
            contentTitle: 'Mix',
            contentSeason: 1,
            contentEpisode: 1,
            disableAutoResume: true,
            initialContinuousShuffle: true,
            stremioSources: [launch],
            stremioCurrentSourceIndex: 0,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              loadCustomEpisodeInventory: () async => [
                for (final n in [1, 2])
                  {'season': 1, 'number': n, 'airdate': '2020-01-0$n'},
              ],
              searchEpisodes: (s, e) async => [shuffled],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: 'Mix.S01E02.mkv'),
            ],
          ),
        );
        List<String> serverLogs(String event) => [
          for (final l in d.logs)
            if (l.startsWith('SourceSelect: event=media_server_$event ')) l,
        ];
        String sourceId(String line) =>
            RegExp(r'sourceId=(\S+)').firstMatch(line)!.group(1)!;
        expect(serverLogs('open'), hasLength(1));
        final launchId = sourceId(serverLogs('open').single);
        d.player.emit('position', const Duration(seconds: 1));
        await d.f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
          reason: 'the launch item reports through its server session',
        );
        server.heldRequest = (r) => !hold.isCompleted;
        server.beforeRequest = (r) async {
          held = true;
          await hold.future;
        };
        final dynamic next = playerControls(t).onNext!;
        d.observe<dynamic>(() => next());
        await d.f.until(
          t,
          () => held,
          reason: 'the shuffle pick of the server episode prepares its watch',
        );
        playerControls(t).onRandom();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        expect(menu.continuousShuffle, isTrue);
        d.observe(menu.onShuffleContinuousToggle);
        await d.f.advance(t, const Duration(milliseconds: 300));
        d.f.navigator.currentState!.maybePop();
        await d.f.advance(t, const Duration(milliseconds: 400));
        hold.complete();
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.actions.settle(t);
        expect(
          d.opens.map((m) => m.uri),
          [launch.directUrl],
          reason: 'the cancelled shuffle request never opens its episode',
        );
        expect(
          serverLogs('open'),
          hasLength(1),
          reason: 'no media_server_open for a request that lost ownership',
        );
        // The playing item stays the opened watch source: its error is not
        // attributed to the abandoned shuffle candidate.
        d.player.emit('error', 'HTTP error 403 Forbidden');
        await d.f.advance(t);
        expect(serverLogs('player_error'), hasLength(1));
        expect(sourceId(serverLogs('player_error').single), launchId);
        // Pinned current behaviour (P20 Follow-up): the outgoing session was
        // already closed at the cancelled open's entry, so the still-playing
        // item stops reporting; no session reports for the candidate either.
        expect(_stopped(server), isTrue);
        final reported = server.reports.length;
        d.player.emit('position', const Duration(seconds: 61));
        await d.f.advance(t, const Duration(seconds: 12));
        await d.f.actions.settle(t);
        expect(server.reports.skip(reported), isEmpty);
      } finally {
        hold.completeIfPending();
        await d.close();
        server.restoreFactories();
      }
    },
  );
}
