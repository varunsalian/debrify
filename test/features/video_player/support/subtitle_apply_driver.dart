import 'dart:async';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'fake_player.dart';
import 'player_actions.dart';
import 'video_player_environment.dart';

const applyScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/apply-original.mp4',
  title: 'Subtitle apply original',
);
const applyTracks = [
  mk.SubtitleTrack('1', 'English captions', 'eng'),
  mk.SubtitleTrack('2', 'Spanish captions', 'spa'),
  mk.SubtitleTrack('3', 'French captions', 'fra'),
  mk.SubtitleTrack('4', 'PGS captions', 'eng', codec: 'hdmv_pgs_subtitle'),
  mk.SubtitleTrack('5', 'Image captions', 'eng', image: true),
];

/// Real menu/subscription/storage callers; no private State access or synthetic
/// apply-attempt injection. Held entry remains separate from completion (H).
class SubtitleApplyDriver {
  SubtitleApplyDriver(
    this.t, {
    bool native = true,
    void Function(FakePlayer)? configurePlayer,
  }) : f = VideoPlayerEnvironment(
         native: native,
         configurePlayer: configurePlayer,
       );
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  final logs = <String>[];
  final errors = <Object>[];
  final timers =
      <({String stack, DateTime at, Duration duration, Timer timer})>[];
  final periodic = <Duration>[];
  late DebugPrintCallback oldPrint;
  FakePlayer get player => f.player;
  FakeNativePlayer get native => player.platform as FakeNativePlayer;
  T observe<T>(T Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) =>
          errors.add(error),
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        periodic.add(duration);
        return parent.createPeriodicTimer(zone, duration, callback);
      },
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        timers.add((
          stack: StackTrace.current.toString(),
          at: t.binding.clock.now(),
          duration: duration,
          timer: timer,
        ));
        return timer;
      },
    ),
  );
  Future<void> initialize() async {
    await t.runAsync(f.initialize);
    oldPrint = debugPrint;
    debugPrint = (String? line, {int? wrapWidth}) {
      if (line != null) logs.add(line);
    };
  }

  Future<void> mount({
    VideoPlayerScreen screen = applyScreen,
    bool publishTracks = true,
    bool settleInitialization = true,
  }) async {
    await observe(() => f.mount(t, screen));
    if (publishTracks) publish();
    await f.advance(t);
    if (settleInitialization) {
      await f.until(t, () => periodic.contains(const Duration(seconds: 6)));
    }
  }

  void publish({
    String selected = '1',
    List<mk.SubtitleTrack> tracks = applyTracks,
  }) => player.publishTracks(
    mk.Tracks(
      audio: const [
        mk.AudioTrack('1', 'English audio', 'eng'),
        mk.AudioTrack('2', 'Spanish audio', 'spa'),
      ],
      subtitle: tracks,
    ),
    selected: mk.Track(
      audio: const mk.AudioTrack('1', 'English audio', 'eng'),
      subtitle: tracks.firstWhere(
        (v) => v.id == selected,
        orElse: () => mk.SubtitleTrack.no(),
      ),
    ),
  );
  Future<PlayerMenuPanel> menu() async {
    if (find.byType(TvControls).evaluate().isNotEmpty) {
      t.widget<TvControls>(find.byType(TvControls)).onShowTracks();
      await f.advance(t, const Duration(milliseconds: 300));
    } else {
      await openPlayerMenu(t, f);
    }
    await f.advance(t, const Duration(milliseconds: 300));
    return t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
  }

  Future<bool> select(
    String id, {
    PlayerMenuPanel? panel,
    String audio = '1',
  }) async {
    final current = panel ?? await menu();
    return f.finish(
      t,
      observe(
        () => id == 'no'
            ? current.onSubtitlesOff(audio)
            : current.onEmbeddedSubtitleSelected(id, audio),
      ),
    );
  }

  Future<Map<String, dynamic>?> saved({String? title}) => f.finish(
    t,
    TrackPreferencesStorage.getVideoTrackPreferences(
      videoTitle: title ?? applyScreen.title,
    ),
  );
  void fail({
    String prefix = 'sub',
    String level = 'error',
    String reason = 'subtitle decoder failed',
  }) => player.emit(
    'log',
    mk.PlayerLog(prefix: prefix, level: level, text: reason),
  );
  Future<void> rollback(String id) async {
    await f.until(t, () => player.state.track.subtitle.id == id);
    await f.until(t, () => logs.any((v) => v.contains('user notified')));
    await f.actions.settle(t);
    await f.advance(t);
  }

  Future<bool> addon(String id, {PlayerMenuPanel? panel}) async {
    final current = panel ?? await menu();
    return f.finish(t, startAddon(id, current));
  }

  Future<bool> startAddon(String id, PlayerMenuPanel current) {
    final sub = StremioSubtitle(
      id: id,
      url: 'https://player.test/$id.srt',
      lang: 'eng',
      source: 'Apply fixture',
    );
    f.network.replies[sub.url] = http.Response(
      '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
      200,
    );
    return observe(() => current.onAddonSubtitleSelected(sub, '1'));
  }

  Finder row(String label) => find
      .ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey(PlayerMenuSection.subtitles)),
          matching: find.text(label),
        ),
        matching: find.byType(GestureDetector),
      )
      .first;
  void expectSelected(PlayerMenuPanel panel, String id) {
    final label = id == 'no'
        ? 'Off'
        : panel.embeddedSubtitles.firstWhere((v) => v.id == id).label;
    expect(
      find.descendant(
        of: row(label),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
  }

  Future<void> close() async {
    try {
      await f.close(t);
    } finally {
      debugPrint = oldPrint;
    }
  }
}
