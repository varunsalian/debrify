import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/playback_startup_view.dart';

void main() {
  test('startup shield remains opaque and noninteractive in PiP', () {
    final source = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();
    final overlay = source.substring(
      source.indexOf('// Above the gesture layer: startup'),
      source.indexOf('// Controls overlay (shown only when ready)'),
    );
    expect(
      overlay,
      contains('if (_startupGateActive && !_startupGateOverlayHidden)'),
    );
    expect(overlay, isNot(contains('&& !inPip')));
    expect(overlay, contains('child: inPip'));
    expect(
      overlay,
      contains('? const AbsorbPointer(child: ColoredBox(color: Colors.black))'),
    );
    expect(overlay, contains(': PlaybackStartupView('));
  });

  test('non-startup transitions retain their overlay rendering site', () {
    final source = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();
    expect(source, contains('if (_rainbowActive) _buildTransitionOverlay(),'));
  });

  testWidgets('remote controls work below a consuming player focus', (
    tester,
  ) async {
    var left = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          onKeyEvent: (_, __) => KeyEventResult.handled,
          child: PlaybackStartupView(
            title: 'Arrival',
            details: 'Attempt 1',
            retrying: false,
            onBack: () => left = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(left, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Attempt 1'), findsOneWidget);
  });

  testWidgets('movie startup keeps attempts in details and Back available', (
    tester,
  ) async {
    var left = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackStartupView(
          title: 'Arrival',
          details: 'Checking stream 1 of 5',
          retrying: false,
          onBack: () => left = true,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Checking stream 1 of 5'), findsNothing);
    await tester.tap(find.text('Playback details'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Checking stream 1 of 5'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('startup-source-back')));
    expect(left, isTrue);
  });

  testWidgets('series retry fits a short landscape viewport', (tester) async {
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(740, 360), disableAnimations: true),
          child: PlaybackStartupView(
            title: 'Chernobyl',
            episode: 'Season 1 · Episode 3',
            details: 'Trying 2 of 5',
            retrying: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Season 1 · Episode 3'), findsOneWidget);
    expect(find.text('CONNECTING TO ANOTHER SOURCE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
