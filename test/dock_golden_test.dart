import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:debrify/screens/video_player/widgets/styled_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders each arrangement so it can be LOOKED at.
///
/// The no-overflow tests pass a dock that has grown to fill the screen, and
/// passed one where every chip became its own row. Twice now the defect was
/// found by putting a screenshot beside the mock. These goldens make that a
/// step anyone can run instead of something someone has to notice.
///
/// Regenerate with:
///   flutter test --update-goldens test/dock_golden_test.dart
void main() {
  Widget host({
    required Size size,
    required PlayerDockStyle style,
    required PlayerDockPalette palette,
    PlayerDockSize dockSize = PlayerDockSize.auto,
    bool everything = true,
  }) {
    final natural = DockArrangement.forViewport(size);
    final arrangement = style.forcedArrangement ?? natural;
    final metrics = DockMetrics.compute(
      DockLayoutInput(
        viewport: size,
        safeArea: EdgeInsets.zero,
        arrangement: arrangement,
        infoPanelH: 0,
        textScale: 1.0,
        size: dockSize,
      ),
    )!;

    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF141018),
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: StyledDock(
                metrics: metrics,
                palette: DockPalettes.of(palette),
                arrangement: arrangement,
                title: 'Dune: Part Two',
                subtitle: '2024 · 2h 46m · 2160p HDR · Real-Debrid',
                infoPanel: null,
                clock: ValueNotifier(
                  const PlaybackUiClockValue(
                    position: Duration(minutes: 68, seconds: 24),
                    duration: Duration(hours: 2, minutes: 46, seconds: 9),
                    generation: 0,
                  ),
                ),
                isPlaying: true,
                onPlayPause: () {},
                onBack: () {},
                onAspect: () {},
                onSpeed: () {},
                onSleepTimer: () {},
                onShowTracks: () {},
                onShowPlaylist: () {},
                onRandom: () {},
                onRotate: () {},
                onSeekBarChangedStart: () {},
                onSeekBarChanged: (_) {},
                onSeekBarChangeEnd: () {},
                onNext: everything ? () {} : null,
                onPrevious: everything ? () {} : null,
                onNextChannel: everything ? () {} : null,
                onShowGuide: everything ? () {} : null,
                onShowIptvChannels: everything ? () {} : null,
                onShowStremioSources: () {},
                onRecord: everything ? () {} : null,
                onPip: () {},
                hasNext: everything,
                hasPrevious: everything,
                hasNextChannel: everything,
                hasGuide: everything,
                hasIptvChannels: everything,
                hasStremioSources: true,
                hasPlaylist: everything,
                hasRecord: everything,
                isRecording: false,
                showPipButton: true,
                hideSeekbar: false,
                hideOptions: false,
                hideBackButton: false,
                speed: 1.0,
                aspectMode: AspectMode.aspect16_9,
                isLandscape: true,
                showRotate: false,
                sleepTimerLabel: null,
                volume: 0.7,
                onVolumeChanged: (_) {},
                showFullscreen: true,
                onFullscreen: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Size size,
    required PlayerDockStyle style,
    PlayerDockPalette palette = PlayerDockPalette.ultraviolet,
    PlayerDockSize dockSize = PlayerDockSize.auto,
    bool everything = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        size: size,
        style: style,
        palette: palette,
        dockSize: dockSize,
        everything: everything,
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(StyledDock),
      matchesGoldenFile('goldens/dock_$name.png'),
    );
  }

  testWidgets('narrow — phone landscape', (t) async {
    await shoot(
      t,
      'narrow',
      size: const Size(844, 390),
      style: PlayerDockStyle.compact,
    );
  });

  testWidgets('regular — two tiers', (t) async {
    await shoot(
      t,
      'regular',
      size: const Size(900, 700),
      style: PlayerDockStyle.tiers,
    );
  });

  testWidgets('wide — cinema bar', (t) async {
    await shoot(
      t,
      'wide',
      size: const Size(1440, 810),
      style: PlayerDockStyle.cinema,
    );
  });

  testWidgets('wide — large density', (t) async {
    await shoot(
      t,
      'wide_large',
      size: const Size(2560, 1440),
      style: PlayerDockStyle.cinema,
      dockSize: PlayerDockSize.large,
    );
  });

  testWidgets('wide — aurum, the dark-ink palette', (t) async {
    await shoot(
      t,
      'wide_aurum',
      size: const Size(1440, 810),
      style: PlayerDockStyle.cinema,
      palette: PlayerDockPalette.aurum,
    );
  });

  testWidgets('regular — a plain single-file session', (t) async {
    await shoot(
      t,
      'regular_sparse',
      size: const Size(900, 700),
      style: PlayerDockStyle.tiers,
      everything: false,
    );
  });
}
