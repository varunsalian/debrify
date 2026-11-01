import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:debrify/screens/video_player/widgets/dock_widgets.dart';
import 'package:debrify/screens/video_player/widgets/styled_dock.dart';
import 'package:debrify/services/player_controls_display_settings.dart';
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
    Duration position = const Duration(minutes: 68),
    Duration duration = const Duration(minutes: 166),
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
                  PlaybackUiClockValue(
                    position: position,
                    duration: duration,
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
    // With every capability enabled, narrow and regular both need a More
    // affordance — narrow because it shows three tools, regular because the
    // tools tier is capped at two lines. Wide is icon-only and scrolls, so it
    // never needs one.
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
        entry.value != DockArrangement.wide,
        reason:
            'More is the overflow escape for narrow and regular, and wide '
            'has none because it scrolls icon-only — ${entry.key}',
      );
    }
  });

  testWidgets('tool chips hug their content instead of filling the row', (
    tester,
  ) async {
    // A Container with an `alignment` expands to fill bounded constraints, so
    // every chip in the two-tier Wrap became a full-width row: six lines of
    // tools, and a dock that ate the screen. It never overflowed, so the
    // no-overflow tests passed it happily.
    const size = Size(900, 700);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    expect(DockArrangement.forViewport(size), DockArrangement.regular);

    await tester.pumpWidget(
      host(
        size: size,
        safeArea: EdgeInsets.zero,
        textScale: 1.0,
        dockSize: PlayerDockSize.auto,
        withPanel: false,
      ),
    );
    await tester.pump();

    final chips = find.byType(DockChip);
    expect(chips, findsWidgets);
    for (final element in chips.evaluate()) {
      final width = (element.renderObject! as RenderBox).size.width;
      expect(
        width,
        lessThan(size.width / 2),
        reason:
            'a chip ${width.toStringAsFixed(1)}lp wide in a ${size.width}lp '
            'dock means it is filling the row, not hugging its label',
      );
    }
  });

  testWidgets('the two-tier dock does not eat the screen', (tester) async {
    const size = Size(900, 700);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        size: size,
        safeArea: EdgeInsets.zero,
        textScale: 1.0,
        dockSize: PlayerDockSize.auto,
        withPanel: false,
      ),
    );
    await tester.pump();

    // The tools tier is budgeted as at most one extra row; a dock taller than
    // half the viewport means it wrapped far more than that.
    final dock = tester.getSize(find.byType(StyledDock));
    expect(dock.height, lessThanOrEqualTo(size.height));
    final toolsRow = tester.getSize(find.byType(Wrap).first);
    expect(
      toolsRow.height,
      lessThan(size.height * 0.35),
      reason: 'tools tier ${toolsRow.height}lp tall — it is stacking',
    );
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

  group('readouts and labels', () {
    const size = Size(800, 700); // regular: readouts flank the bar
    tearDown(() {
      PlayerControlsDisplaySettings.showRemaining.value = false;
      PlayerControlsDisplaySettings.iconOnly.value = false;
    });

    Future<void> pump(
      WidgetTester tester, {
      Duration position = const Duration(minutes: 68),
      Duration duration = const Duration(minutes: 166),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          size: size,
          safeArea: EdgeInsets.zero,
          textScale: 1.0,
          dockSize: PlayerDockSize.auto,
          withPanel: false,
          position: position,
          duration: duration,
        ),
      );
      await tester.pump();
    }

    testWidgets('the seek row readouts sit flush with both edges', (
      tester,
    ) async {
      // A user saw far more space after the duration than before the
      // position: loose Flexibles left their unused share at the row's end.
      // The user's own numbers: short readouts leave the most room unused.
      await pump(
        tester,
        position: const Duration(minutes: 3, seconds: 25),
        duration: const Duration(minutes: 46, seconds: 20),
      );
      final left = tester.getRect(find.text('03:25')).left;
      final right = size.width - tester.getRect(find.text('46:20')).right;
      expect(right, closeTo(left, 1));
    });

    testWidgets('tapping the duration switches to the time left', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('2:46:00'));
      await tester.pump();

      expect(find.text('-1:38:00'), findsOneWidget);
      expect(PlayerControlsDisplaySettings.showRemaining.value, isTrue);

      await tester.tap(find.text('-1:38:00'));
      await tester.pump();
      expect(find.text('2:46:00'), findsOneWidget);
    });

    testWidgets('the duration is a full-height tap target', (tester) async {
      await pump(tester);
      final readout = find.ancestor(
        of: find.text('2:46:00'),
        matching: find.byType(GestureDetector),
      );
      expect(
        tester.getSize(readout.first).height,
        greaterThanOrEqualTo(DockLayoutInput.minTarget),
      );
    });

    test('the time left never reads below zero or before a duration', () {
      PlaybackUiClockValue at(int position, int duration) =>
          PlaybackUiClockValue(
            position: Duration(seconds: position),
            duration: Duration(seconds: duration),
            generation: 0,
          );
      expect(DockDurationReadout.text(at(205, 2780), true), '-42:55');
      expect(DockDurationReadout.text(at(205, 2780), false), '46:20');
      expect(DockDurationReadout.text(at(2790, 2780), true), '-00:00');
      expect(DockDurationReadout.text(at(0, 0), true), '00:00');
    });

    testWidgets('both choices fit every approved viewport and text scale', (
      tester,
    ) async {
      PlayerControlsDisplaySettings.showRemaining.value = true;
      PlayerControlsDisplaySettings.iconOnly.value = true;
      for (final size in viewports) {
        for (final scale in scales) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            host(
              size: size,
              safeArea: EdgeInsets.zero,
              textScale: scale,
              dockSize: PlayerDockSize.auto,
              withPanel: false,
            ),
          );
          await tester.pump();
          final err = tester.takeException();
          if (err != null) fail('$size / scale $scale: $err');
        }
      }
    });

    testWidgets('icons only also applies to the narrow row', (tester) async {
      const phone = Size(599, 360);
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      PlayerControlsDisplaySettings.iconOnly.value = true;
      await tester.pumpWidget(
        host(
          size: phone,
          safeArea: EdgeInsets.zero,
          textScale: 1.0,
          dockSize: PlayerDockSize.auto,
          withPanel: false,
        ),
      );
      await tester.pump();
      expect(find.text('More'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('icons only drops the tool labels and keeps the tools', (
      tester,
    ) async {
      await pump(tester);
      final chips = find.byType(DockChip).evaluate().length;
      expect(find.text('More'), findsOneWidget);

      PlayerControlsDisplaySettings.iconOnly.value = true;
      await tester.pump();

      expect(find.text('More'), findsNothing);
      expect(
        find.byType(DockChip).evaluate().length,
        greaterThanOrEqualTo(chips),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
