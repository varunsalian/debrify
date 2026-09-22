import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    MainPageBridge.notifyContentPlaybackStopped();
  });

  tearDown(() {
    MainPageBridge.hideAutoLaunchOverlay = null;
    MainPageBridge.notifyContentPlaybackStopped();
    ProfileRuntime.debugReset();
  });

  testWidgets('settings rejection stops playback before releasing the loader', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    var playbackActive = false;
    var stops = 0;
    var handoffs = 0;
    void started() => playbackActive = true;
    void stopped() {
      playbackActive = false;
      stops++;
    }

    // Inject the native rejection after the real launch notification, without
    // requiring Android or opening an actual player. Exercise public push's
    // catch/finally and the same stop-listener contract used by WebDAV sync.
    void reject() => throw NativePlayerSettingsUnavailable();
    MainPageBridge.addPlayerLaunchListener(started);
    MainPageBridge.addPlayerLaunchListener(reject);
    MainPageBridge.addContentPlaybackStopListener(stopped);
    addTearDown(() {
      MainPageBridge.removePlayerLaunchListener(started);
      MainPageBridge.removePlayerLaunchListener(reject);
      MainPageBridge.removeContentPlaybackStopListener(stopped);
    });

    await VideoPlayerLauncher.push(
      context,
      const VideoPlayerLaunchArgs(
        videoUrl: 'file:///probe.mp4',
        title: 'Probe',
      ),
      onPlayerHandoff: () {
        handoffs++;
        expect(playbackActive, isFalse);
      },
    );
    await tester.pump();
    expect(playbackActive, isFalse);
    expect(stops, 1);
    expect(handoffs, 1);
    expect(
      find.text('Player settings could not be loaded. Please try again.'),
      findsOneWidget,
    );
    // A later return/cleanup must not dispatch a second stop notification.
    MainPageBridge.notifyContentPlaybackStopped();
    expect(stops, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rejected trailer does not stop an existing content session', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    var stops = 0;
    void stopped() => stops++;
    MainPageBridge.addContentPlaybackStopListener(stopped);
    addTearDown(
      () => MainPageBridge.removeContentPlaybackStopListener(stopped),
    );
    MainPageBridge.notifyPlayerLaunching();
    MainPageBridge.hideAutoLaunchOverlay = () =>
        throw NativePlayerSettingsUnavailable();

    await VideoPlayerLauncher.push(
      context,
      const VideoPlayerLaunchArgs(
        videoUrl: 'file:///trailer.mp4',
        title: 'Trailer',
      ),
      isTrailer: true,
    );
    expect(stops, 0);
    MainPageBridge.hideAutoLaunchOverlay = null;
    MainPageBridge.notifyContentPlaybackStopped();
    expect(stops, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
