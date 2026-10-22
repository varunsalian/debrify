import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/startup_driver.dart' show startupSource;
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

final _wakeDrain = Object();

Future<void> _background(PipLifecycleDriver d) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    await d.lifecycle(state);
  }
}

void main() {
  // Before any tracker singleton binds a client in this isolate.
  TraktTestTransport.install();
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(false));

  testWidgets(
    'P20 a play edge inside a manual source validation restarts no Trakt or Simkl heartbeat',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize(
        targets: {
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        },
      );
      final a = startupSource('p20-gate-a', url: 'https://gate.test/a.mp4');
      final b = startupSource('p20-gate-b', url: 'https://gate.test/b.mp4');
      final opened = Completer<void>();
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P20 gate',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            traktScrobble: true,
            simklScrobble: true,
            mdblistScrobble: true,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        await d.drain();
        expect(d.trackerActions('trakt'), ['start']);
        final beats = d.heartbeats.length;
        expect(d.heartbeats.where((h) => h.isActive), isNotEmpty);
        f.player.delays['open'] = opened;
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        d.observe(() => sheet.onSourceSelected(1, b.directUrl!));
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        expect(d.heartbeats.length, beats);
        f.player.state = f.player.state.copyWith(
          playing: true,
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', const Duration(minutes: 20));
        f.player.emit('playing', true);
        await d.drain();
        expect(
          d.heartbeats.length,
          beats,
          reason: 'an unvalidated candidate re-arms no tracker heartbeat',
        );
        expect(d.trackerActions('trakt'), ['start']);
        opened.complete();
        await d.drain();
      } finally {
        if (!opened.isCompleted) opened.complete();
        await f.close(t);
        await t.runAsync(
          () => PlayerDisplayControls.instance.setWakelockOwner(
            _wakeDrain,
            false,
          ),
        );
      }
    },
  );

  testWidgets(
    'P20 a play edge while PiP is up is not paused by the background latch',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        await d.settle();
        await _background(d);
        await d.settle();
        final pauses = d.operations('pause').length;
        expect(pauses, greaterThan(0), reason: 'backgrounding paused it');
        await d.deliver('onPipModeChanged', true);
        f.player.state = f.player.state.copyWith(playing: true);
        f.player.emit('playing', true);
        await d.settle();
        expect(d.operations('pause').length, pauses);
        await d.deliver('onPipModeChanged', false);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 on TV a live IPTV launch keeps focus off the bar it hides at the ready edge',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      final live = IptvChannel(
        name: 'P20 TV live',
        url: 'https://gate.test/live.ts',
        contentType: 'live',
        group: 'News',
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: live.url,
            title: live.name,
            iptvChannels: [live],
            iptvStartIndex: 0,
          ),
        );
        final node = t
            .widget<TvControls>(find.byType(TvControls))
            .playPauseFocusNode;
        expect(FocusManager.instance.primaryFocus, isNot(node));
      } finally {
        await d.close();
      }
    },
  );
}
