import 'dart:async';

import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';
import 'support/skip_segment_driver.dart';
import 'support/tv_episode_driver.dart' show tvDirectory;

const _at = Duration(seconds: 300);

Future<P21Driver> _tv(
  WidgetTester t, {
  bool over = false,
  Duration? at = _at,
  bool debrify = false,
  bool debrifyLookup = true,
  bool stremio = false,
  Future<Map<String, String>?> Function()? magicNext,
}) async {
  final d = P21Driver(t, tv: true);
  await d.initialize();
  final screen = P21Driver.screen(
    title: 'A',
    channelDirectory: debrify ? tvDirectory : null,
    requestChannelById: debrify && debrifyLookup ? (id) async => null : null,
    stremioTvChannels: stremio ? tvDirectory : null,
    stremioTvChannelSwitchProvider: stremio ? (id) async => null : null,
    requestMagicNext: magicNext,
  );
  over ? await d.mountOver(screen) : await d.mount(screen: screen);
  await d.wait(4000);
  if (at != null) await d.at(at);
  return d;
}

void main() {
  p21Timeouts();

  group('bar hidden', () {
    for (final key in [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
    ]) {
      testWidgets(
        'P21 TV ${key.keyLabel} on the hidden bar toggles playback and raises the bar on Play/Pause',
        (t) async {
          final d = await _tv(t);
          try {
            await d.key(key);
            expect(d.count('pause'), 1);
            expect(d.barUp, isTrue);
            expect(d.focused, 'tvPlayPause');
            await d.key(LogicalKeyboardKey.escape);
            expect(d.barUp, isFalse);
            await d.key(key);
            expect(d.count('play'), 1);
            expect(d.player.state.playing, isTrue);
            expect(d.barUp, isTrue);
            expect(d.seeks, isEmpty);
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }

    testWidgets(
      'P21 TV OK on the hidden bar takes the offered skip instead of pausing',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        final skip = SkipSegmentDriver(t, d.f);
        try {
          await skip.configure();
          await d.mount(screen: skipScreen());
          await skip.tick();
          await d.wait(8000);
          skip.expectButton(true);
          expect(d.barUp, isFalse);
          await d.key(LogicalKeyboardKey.select);
          expect(d.seeks, [const Duration(seconds: 30)]);
          expect(d.count('pause'), 0);
          expect(d.barUp, isFalse);
          skip.expectButton(false);
          // With nothing offered, OK pauses and raises again.
          await d.key(LogicalKeyboardKey.select);
          expect(d.count('pause'), 1);
          expect(d.barUp, isTrue);
          expect(d.errors, isEmpty);
        } finally {
          skip.releaseAll();
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV DOWN on the hidden bar raises it without touching playback',
      (t) async {
        final d = await _tv(t);
        try {
          final calls = d.player.calls.length;
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.barUp, isTrue);
          expect(d.focused, 'tvPlayPause');
          expect(d.player.calls.length, calls);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV UP on the hidden bar raises it when the session has no guide',
      (t) async {
        final d = await _tv(t);
        try {
          await d.key(LogicalKeyboardKey.arrowUp);
          expect(d.barUp, isTrue);
          expect(d.focused, 'tvPlayPause');
          expect(find.byType(ChannelGuide), findsNothing);
          expect(find.byType(StremioTvGuideSheet), findsNothing);
          expect(d.player.calls.where((c) => c.$1 == 'volume'), isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    for (final setup in [
      (debrify: true, lookup: true, stremio: true, expected: 'debrify'),
      (debrify: true, lookup: false, stremio: true, expected: 'stremio'),
      (debrify: false, lookup: false, stremio: true, expected: 'stremio'),
    ]) {
      testWidgets(
        'P21 TV UP on the hidden bar opens the ${setup.expected} guide (debrify=${setup.debrify} lookup=${setup.lookup})',
        (t) async {
          final d = await _tv(
            t,
            at: null,
            debrify: setup.debrify,
            debrifyLookup: setup.lookup,
            stremio: setup.stremio,
          );
          try {
            // Checked on the opening frames: the Debrify guide's focused row
            // overflows this fixture's viewport by a pixel once it settles.
            await d.key(LogicalKeyboardKey.arrowUp);
            expect(
              find.byType(ChannelGuide),
              setup.expected == 'debrify' ? findsOneWidget : findsNothing,
            );
            expect(
              find.byType(StremioTvGuideSheet),
              setup.expected == 'stremio' ? findsOneWidget : findsNothing,
            );
            expect(d.barUp, isFalse, reason: 'the guide opens instead');
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }

    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      testWidgets(
        'P21 TV a single ${key.keyLabel} on the hidden bar nudges ten seconds through the desktop mapping',
        (t) async {
          final d = await _tv(t);
          try {
            await d.key(key);
            expect(d.seeks, [
              key == LogicalKeyboardKey.arrowRight
                  ? const Duration(seconds: 310)
                  : const Duration(seconds: 290),
            ]);
            expect(d.barUp, isFalse);
            expect(d.bar.scrubPreview, isNull);
            expect(d.count('pause'), 0);
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  });

  testWidgets(
    'P21 TV quick non-arrow keys on the hidden bar never count as a hold',
    (t) async {
      final d = await _tv(t);
      try {
        for (var i = 0; i < 4; i++) {
          await d.key(LogicalKeyboardKey.keyA);
        }
        expect(d.bar.scrubPreview, isNull);
        expect(d.count('pause'), 0);
        expect(d.barUp, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  group('bar up', () {
    testWidgets(
      'P21 TV BACK on the raised bar lowers it and returns focus to the root',
      (t) async {
        final d = await _tv(t);
        try {
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.focused, 'tvPlayPause');
          await d.key(LogicalKeyboardKey.escape);
          expect(d.barUp, isFalse);
          expect(d.focused, 'tvPlayerRoot');
          expect(
            d.f.channels.where((c) => c.$2.method == 'SystemNavigator.pop'),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      testWidgets(
        'P21 TV ${key.keyLabel} inside the raised bar is left to traversal and restarts the countdown',
        (t) async {
          final d = await _tv(t);
          try {
            await d.key(LogicalKeyboardKey.arrowDown);
            await d.wait(2000);
            await d.key(key);
            expect(d.seeks, isEmpty);
            expect(d.bar.scrubPreview, isNull);
            expect(d.player.calls.where((c) => c.$1 == 'volume'), isEmpty);
            await d.wait(1500);
            expect(d.barUp, isTrue, reason: 'the key restarted the countdown');
            await d.wait(1600);
            expect(d.barUp, isFalse);
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  });

  group('transition', () {
    testWidgets(
      'P21 TV during a transition the remote drives nothing but BACK still leaves',
      (t) async {
        final next = Completer<Map<String, String>?>();
        final d = await _tv(t, over: true, magicNext: () => next.future);
        try {
          d.observe(d.bar.onNext!);
          await d.wait(100);
          expect(find.byType(TransitionOverlay), findsOneWidget);
          final calls = d.player.calls.length;
          for (final key in [
            LogicalKeyboardKey.select,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.arrowLeft,
          ]) {
            await d.key(key);
          }
          await d.key(LogicalKeyboardKey.arrowRight);
          await d.key(LogicalKeyboardKey.arrowRight);
          expect(d.player.calls.length, calls);
          expect(d.barUp, isFalse);
          expect(d.bar.scrubPreview, isNull);
          expect(d.playerRouteOpen, isTrue);
          await d.key(LogicalKeyboardKey.escape);
          await d.wait(500);
          expect(d.playerRouteOpen, isFalse, reason: 'BACK left the player');
          next.complete(null);
          await d.wait(100);
        } finally {
          if (!next.isCompleted) next.complete(null);
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV RIGHT during a live zap supersedes it with the next channel',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        final channels = [for (var i = 0; i < 5; i++) P21Driver.channel(i)];
        final open = Completer<void>();
        try {
          await d.mount(
            screen: P21Driver.iptv(channels),
            settleInitialization: false,
          );
          await d.wait(4000);
          d.player.delays['open'] = open;
          await d.key(LogicalKeyboardKey.arrowRight);
          await d.wait(100);
          expect(d.opens.last.uri, channels[1].url);
          // The outgoing tune is still in flight: RIGHT zaps again, OK and
          // DOWN drive nothing.
          final pauses = d.count('pause');
          await d.key(LogicalKeyboardKey.select);
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.count('pause'), pauses);
          expect(d.barUp, isFalse);
          await d.key(LogicalKeyboardKey.arrowRight);
          open.complete();
          await d.wait(500);
          expect(d.opens.last.uri, channels[2].url);
          // And LEFT supersedes a held tune backwards, one channel.
          final back = Completer<void>();
          d.player.delays['open'] = back;
          await d.key(LogicalKeyboardKey.arrowRight);
          await d.wait(100);
          await d.key(LogicalKeyboardKey.arrowLeft);
          back.complete();
          await d.wait(500);
          expect(d.opens.map((m) => m.uri).toList().sublist(3), [
            channels[3].url,
            channels[2].url,
          ]);
          expect(d.seeks, isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          if (!open.isCompleted) open.complete();
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV on a live channel LEFT and RIGHT zap with the bar hidden and never scrub',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        final channels = [for (var i = 0; i < 3; i++) P21Driver.channel(i)];
        try {
          await d.mount(
            screen: P21Driver.iptv(channels),
            settleInitialization: false,
          );
          await d.wait(4000);
          for (final expected in [1, 2, 0]) {
            await d.key(LogicalKeyboardKey.arrowRight);
            await d.wait(500);
            expect(d.opens.last.uri, channels[expected].url);
          }
          await d.key(LogicalKeyboardKey.arrowLeft);
          await d.wait(500);
          expect(d.opens.last.uri, channels[2].url);
          expect(d.bar.scrubPreview, isNull);
          expect(d.seeks, isEmpty);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV UP on a live channel with the bar hidden opens the IPTV sheet',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        final channels = [P21Driver.channel(0), P21Driver.channel(1)];
        try {
          await d.mount(
            screen: P21Driver.iptv(channels),
            settleInitialization: false,
          );
          await d.wait(4000);
          await d.key(LogicalKeyboardKey.arrowUp);
          await d.wait(400);
          expect(find.byType(IptvChannelSheet), findsOneWidget);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV BACK on the hidden bar is left to the desktop mapping, which leaves the player',
      (t) async {
        final d = await _tv(t, over: true);
        try {
          await d.key(LogicalKeyboardKey.escape);
          await d.wait(500);
          expect(d.playerRouteOpen, isFalse);
        } finally {
          await d.close();
        }
      },
    );
  });
}
