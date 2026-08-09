import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:debrify/screens/video_player/widgets/styled_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// §7.5 — the styled dock must never overflow, at any viewport the budget
/// approves, at any supported text scale.
///
/// `DockMetrics.compute` returning non-null is a *promise* that the rendered
/// widget fits. An earlier build satisfied the arithmetic while the widget
/// still overflowed, so this asserts the rendering, not the formula.
void main() {
  const viewports = <Size>[
    Size(320, 320), // the smallest thing the budget might approve
    Size(360, 640), // phone portrait
    Size(599, 360), // the plan's worked worst case
    Size(599, 479), // narrow side of both gates
    Size(600, 480), // regular side of both gates
    Size(800, 480),
    Size(1280, 800),
    Size(2560, 1440), // wide
  ];
  const insets = <EdgeInsets>[
    EdgeInsets.zero,
    EdgeInsets.only(top: 48, bottom: 34),
  ];
  const scales = <double>[1.0, 1.15, 1.3];

  Widget host({
    required Size size,
    required EdgeInsets safeArea,
    required double textScale,
    required PlayerDockSize dockSize,
    required bool withPanel,
    double infoPanelHeight = 0,
  }) {
    final arrangement = DockArrangement.forViewport(size);
    final metrics = DockMetrics.compute(
      DockLayoutInput(
        viewport: size,
        safeArea: safeArea,
        arrangement: arrangement,
        infoPanelH: withPanel ? infoPanelHeight : 0,
        textScale: textScale,
        size: dockSize,
      ),
    );
    if (metrics == null) return const SizedBox.shrink();

    return MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: safeArea,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: StyledDock(
                metrics: metrics,
                palette: DockPalettes.ultraviolet,
                arrangement: arrangement,
                title: 'Dune: Part Two',
                subtitle: '2024 · 2h 46m',
                infoPanel: withPanel
                    ? SizedBox(height: infoPanelHeight, width: size.width)
                    : null,
                clock: ValueNotifier(
                  const PlaybackUiClockValue(
                    position: Duration(minutes: 68),
                    duration: Duration(minutes: 166),
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
                // Everything available: the densest row the dock can produce.
                onNext: () {},
                onPrevious: () {},
                onNextChannel: () {},
                onShowGuide: () {},
                onShowIptvChannels: () {},
                onShowStremioSources: () {},
                onRecord: () {},
                onPip: () {},
                hasNext: true,
                hasPrevious: true,
                hasNextChannel: true,
                hasGuide: true,
                hasIptvChannels: true,
                hasStremioSources: true,
                hasPlaylist: true,
                hasRecord: true,
                isRecording: true,
                showPipButton: true,
                hideSeekbar: false,
                hideOptions: false,
                hideBackButton: false,
                speed: 1.0,
                aspectMode: AspectMode.contain,
                isLandscape: true,
                showRotate: true,
                sleepTimerLabel: '30 min',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('never overflows at any approved viewport, inset or text scale', (
    tester,
  ) async {
    for (final size in viewports) {
      for (final safeArea in insets) {
        for (final scale in scales) {
          for (final dockSize in PlayerDockSize.values) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              host(
                size: size,
                safeArea: safeArea,
                textScale: scale,
                dockSize: dockSize,
                withPanel: false,
              ),
            );
            await tester.pump();

            final err = tester.takeException();
            if (err != null) {
              fail('$size / $safeArea / scale $scale / ${dockSize.name}: $err');
            }
          }
        }
      }
    }
  });

  testWidgets('never overflows with a full-EPG info panel mounted', (
    tester,
  ) async {
    // 100lp is the measured full-EPG panel; the budget must absorb it.
    for (final size in viewports) {
      for (final dockSize in [PlayerDockSize.auto, PlayerDockSize.large]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(
            size: size,
            safeArea: EdgeInsets.zero,
            textScale: 1.3,
            dockSize: dockSize,
            withPanel: true,
            infoPanelHeight: 100,
          ),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '$size / panel 100 / ${dockSize.name}',
        );
      }
    }
  });

  testWidgets('each arrangement renders its own shape', (tester) async {
    // narrow keeps a single More affordance; wide drops chip labels entirely.
    for (final entry in {
      const Size(599, 360): DockArrangement.narrow,
      const Size(800, 700): DockArrangement.regular,
      const Size(1280, 800): DockArrangement.wide,
    }.entries) {
      tester.view.physicalSize = entry.key;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      expect(
        DockArrangement.forViewport(entry.key),
        entry.value,
        reason: '${entry.key}',
      );

      await tester.pumpWidget(
        host(
          size: entry.key,
          safeArea: EdgeInsets.zero,
          textScale: 1.0,
          dockSize: PlayerDockSize.auto,
          withPanel: false,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final hasMore = find.text('More').evaluate().isNotEmpty;
      expect(
        hasMore,
        entry.value == DockArrangement.narrow,
        reason: 'More belongs to narrow only — ${entry.key}',
      );
    }
  });

  testWidgets('PiP stays reachable when options are hidden', (tester) async {
    // Legacy keeps PiP in the top bar, independent of hideOptions. Burying it
    // in the tools row lost it entirely whenever options were hidden.
    const size = Size(1280, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final metrics = DockMetrics.compute(
      const DockLayoutInput(
        viewport: size,
        safeArea: EdgeInsets.zero,
        arrangement: DockArrangement.wide,
        infoPanelH: 0,
        textScale: 1.0,
        size: PlayerDockSize.auto,
      ),
    )!;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: size),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              body: StyledDock(
                metrics: metrics,
                palette: DockPalettes.ultraviolet,
                arrangement: DockArrangement.wide,
                title: '',
                subtitle: null,
                infoPanel: null,
                clock: ValueNotifier(
                  const PlaybackUiClockValue(
                    position: Duration.zero,
                    duration: Duration(minutes: 10),
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
                onPip: () {},
                showPipButton: true,
                hideSeekbar: true,
                hideOptions: true,
                hideBackButton: false,
                speed: 1.0,
                aspectMode: AspectMode.contain,
                isLandscape: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byIcon(Icons.picture_in_picture_alt_rounded),
      findsOneWidget,
      reason: 'PiP must survive hideOptions',
    );
  });
}
