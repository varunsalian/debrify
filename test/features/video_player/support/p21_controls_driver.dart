import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_episode_driver.dart';

/// Bounds every case of a P21 file to one minute, so a hung mutant fails
/// fast instead of waiting out the ten-minute widget-test default.
void p21Timeouts() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 60));
  }
}

/// The Debrify channel guide row's name-and-status Column (created at
/// `channel_guide.dart:441:22`) overflows by one pixel under the test fonts
/// whenever its focus styling changes (a fixture artifact, not a
/// controls-runtime behaviour). Drops exactly that layout report, identified
/// by its message and the Column's creation site, for the rest of the case;
/// every other error, including any other overflow in that file, still fails
/// it.
void p21IgnoreGuideRowOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('A RenderFlex overflowed by 1.00 pixels on the bottom') &&
        RegExp(
          r'Column:file://\S*/channel_guide\.dart:441:22\b',
        ).hasMatch(text)) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Phase 21 controls-runtime driver: the real screen on the shared fixture
/// (TvEpisodeDriver), observed only through the widget tree, focus, the fake
/// player's calls and the timers the screen creates inside [observe].
///
/// `tv` sets the Android TV override BEFORE the screen mounts, so the
/// television bar, its PopScope and the remote router are the original ones.
class P21Driver extends TvEpisodeDriver {
  P21Driver(super.t, {this.tv = false, super.configurePlayer});
  final bool tv;

  @override
  Future<void> initialize() async {
    await super.initialize();
    PlatformUtil.debugSetAndroidTvCached(tv);
  }

  static final _wakeDrainMarker = Object();

  @override
  Future<void> close() async {
    try {
      await super.close();
      // Leave the shared wakelock queue's cursor in the isolate's real zone
      // (as EngineDriver does): a FakeAsync cursor from this case would stall
      // later PiP-lifecycle cases in the same isolate.
      late Future<void> pending;
      await t.runAsync(() async {
        pending = PlayerDisplayControls.instance.setWakelockOwner(
          _wakeDrainMarker,
          false,
        );
      });
      await f.finish<void>(t, pending);
    } finally {
      PlatformUtil.debugSetAndroidTvCached(false);
    }
  }

  /// Like [mount], but the player is pushed over a home route, so a BACK
  /// that leaves the player is observable as the route going away.
  Future<void> mountOver(VideoPlayerScreen screen) async {
    await observe(() async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: f.navigator,
          theme: ThemeData.dark(),
          home: const SizedBox(key: ValueKey('p21-home')),
        ),
      );
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
      await f.until(t, () => f.controllers.isNotEmpty);
      player.deliverReady();
      await f.until(t, () => player.calls.any((c) => c.$1 == 'open'));
      for (var i = 0; i < 20; i++) {
        await f.advance(t, const Duration(milliseconds: 100));
      }
    });
    publish();
    await f.advance(t);
    await f.until(t, () => periodic.contains(const Duration(seconds: 6)));
  }

  /// Mounts the screen up to its player instance but withholds the ready
  /// callback, so nothing is ready yet. [ready] completes the startup. With
  /// [over] the player is pushed over a home route (see [mountOver]).
  Future<void> mountUnready(
    VideoPlayerScreen screen, {
    bool over = false,
  }) async {
    await observe(() async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: f.navigator,
          theme: ThemeData.dark(),
          home: over ? const SizedBox(key: ValueKey('p21-home')) : screen,
        ),
      );
      if (over) {
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );
      }
      await f.until(t, () => f.controllers.isNotEmpty);
      await f.advance(t, const Duration(milliseconds: 100));
    });
  }

  Future<void> ready() async {
    await observe(() async {
      player.deliverReady();
      await f.until(t, () => player.calls.any((c) => c.$1 == 'open'));
      for (var i = 0; i < 20; i++) {
        await f.advance(t, const Duration(milliseconds: 100));
      }
    });
  }

  /// Whether the pushed player route is still on the navigator.
  bool get playerRouteOpen =>
      find.byType(VideoPlayerScreen, skipOffstage: false).evaluate().isNotEmpty;

  /// A live IPTV session over [channels].
  static VideoPlayerScreen iptv(List<IptvChannel> channels, {int index = 0}) =>
      VideoPlayerScreen(
        videoUrl: channels[index].url,
        title: channels[index].name,
        iptvChannels: channels,
        iptvStartIndex: index,
        iptvSourceId: 'p21-source',
      );

  static IptvChannel channel(int id, {bool live = true}) => IptvChannel(
    name: 'P21 channel $id',
    url: 'https://p21-iptv.test/$id.ts',
    contentType: live ? 'live' : 'vod',
    group: 'News',
    channelNumber: id,
  );

  /// Periodic timers the screen creates inside [observe], with their period.
  final periodicTimers = <(Duration, Timer)>[];

  @override
  T observe<T>(T Function() body) => runZoned(
    () => super.observe(body),
    zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createPeriodicTimer(zone, duration, callback);
        periodicTimers.add((duration, timer));
        return timer;
      },
    ),
  );

  /// Active periodic timers of [period].
  int activePeriodic(Duration period) =>
      periodicTimers.where((v) => v.$1 == period && v.$2.isActive).length;

  /// Starts the next Debrify TV channel from whichever bar is mounted.
  Future<dynamic> startNextChannel() {
    final dynamic callback = tv ? bar.onNextChannel! : controls.onNextChannel!;
    return observe<dynamic>(() => callback()) as Future<dynamic>;
  }

  /// The player root's focus node (the State's `_tvRootFocus`).
  FocusNode get root => t
      .widget<Focus>(
        find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'tvPlayerRoot',
        ),
      )
      .focusNode!;

  String? get focused => FocusManager.instance.primaryFocus?.debugLabel;

  TvControls get bar => t.widget<TvControls>(find.byType(TvControls));
  Controls get controls => t.widget<Controls>(find.byType(Controls));

  /// Whether the controls layer is raised: on a television the bar's
  /// ExcludeFocus, elsewhere the touch dock's opacity.
  bool get barUp {
    if (tv) {
      return !t
          .widget<ExcludeFocus>(
            find
                .ancestor(
                  of: find.byType(TvControls, skipOffstage: false),
                  matching: find.byType(ExcludeFocus, skipOffstage: false),
                )
                .first,
          )
          .excluding;
    }
    return t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(Controls, skipOffstage: false),
                    matching: find.byType(AnimatedOpacity, skipOffstage: false),
                  )
                  .first,
            )
            .opacity ==
        1;
  }

  /// Sends one key (down and up) inside the observed zone, then lets 50 ms
  /// of fake time pass.
  Future<void> key(LogicalKeyboardKey key) async {
    await observe(() => t.sendKeyEvent(key));
    await f.advance(t, const Duration(milliseconds: 50));
  }

  /// A key-repeat (held key) event, as a remote's auto-repeat delivers it.
  Future<void> repeat(LogicalKeyboardKey key) async {
    await observe(() => t.sendKeyRepeatEvent(key));
    await f.advance(t, const Duration(milliseconds: 20));
  }

  /// Lets real (wall-clock) time pass, for the remote's DateTime-based hold
  /// detection window.
  Future<void> realWait(Duration time) =>
      t.runAsync(() => Future<void>.delayed(time));

  Future<void> wait(int milliseconds) =>
      f.advance(t, Duration(milliseconds: milliseconds));

  /// BACK as the system delivers it (tvOS Menu, Android back): through the
  /// route's PopScope, never as a key.
  Future<void> systemBack() async {
    await observe(() => t.binding.handlePopRoute());
    await f.advance(t, const Duration(milliseconds: 50));
  }

  /// A desktop pointer moving over the player.
  Future<void> hover() async {
    observe(() => pointerRegion.onHover!(const PointerHoverEvent()));
    await f.advance(t);
  }

  /// The player's own pointer region: the hover-handling ancestor of the
  /// full-screen gesture layer.
  MouseRegion get pointerRegion => t
      .widgetList<MouseRegion>(
        find.ancestor(
          of: find.byWidget(gestures),
          matching: find.byType(MouseRegion),
        ),
      )
      .firstWhere((w) => w.onHover != null);

  /// The full-screen gesture layer below the controls.
  GestureDetector get gestures => t
      .widgetList<GestureDetector>(find.byType(GestureDetector))
      .firstWhere((w) => w.onPanStart != null && w.onDoubleTapDown != null);

  /// Moves the fake player's position (state and stream).
  Future<void> at(Duration position) async {
    player.state = player.state.copyWith(position: position);
    player.emit('position', position);
    await f.advance(t);
  }

  /// Changes the fake player's duration (state and stream).
  Future<void> length(Duration duration) async {
    player.state = player.state.copyWith(duration: duration);
    player.emit('duration', duration);
    await f.advance(t);
  }

  /// Moves only the native player's reported state and delivers no stream
  /// event, so the screen's own copies of the playhead, the playing flag and
  /// the length (written only by delivered events of the current player
  /// instance) keep their values. Production reaches the same split whenever
  /// a skip writes the playhead before its seek lands, a replaced instance's
  /// events are filtered out, or the renderer fallback resets the copies
  /// while the old state still reports.
  void playerReports({Duration? position, bool? playing, Duration? duration}) {
    player.state = player.state.copyWith(
      position: position,
      playing: playing,
      duration: duration,
    );
  }

  /// Active one-shot timers of [duration] created by the screen.
  int activeTimers(Duration duration) =>
      timers.where((v) => v.timer.isActive && v.duration == duration).length;

  List<String> get playerCalls => [for (final c in player.calls) c.$1];

  int count(String call) => player.calls.where((c) => c.$1 == call).length;

  /// Scrobble seeks reported to the three trackers (Trakt, Simkl, MDBList)
  /// are only visible as their log lines when no account is linked, so the
  /// player-side seek list is the boundary these cases observe.
  List<Duration> get seekTargets => seeks;

  static VideoPlayerScreen screen({
    String url = 'https://p21.test/a.mp4',
    String title = 'P21 controls',
    bool hideOptions = false,
    bool hideSeekbar = false,
    bool hideBackButton = false,
    List<Map<String, dynamic>>? channelDirectory,
    Future<Map<String, dynamic>?> Function(String)? requestChannelById,
    List<Map<String, dynamic>>? stremioTvChannels,
    Future<Map<String, dynamic>?> Function(String)?
    stremioTvChannelSwitchProvider,
    Future<Map<String, String>?> Function()? requestMagicNext,
  }) => VideoPlayerScreen(
    videoUrl: url,
    title: title,
    hideOptions: hideOptions,
    hideSeekbar: hideSeekbar,
    hideBackButton: hideBackButton,
    channelDirectory: channelDirectory,
    requestChannelById: requestChannelById,
    stremioTvChannels: stremioTvChannels,
    stremioTvChannelSwitchProvider: stremioTvChannelSwitchProvider,
    requestMagicNext: requestMagicNext,
  );
}
