import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _right = LogicalKeyboardKey.arrowRight;
const _left = LogicalKeyboardKey.arrowLeft;
const _start = Duration(seconds: 300);

/// Mounts a television session, lets the initial bar lapse and parks the
/// playhead at [at].
Future<P21Driver> _tv(WidgetTester t, {Duration at = _start}) async {
  final d = P21Driver(t, tv: true);
  await d.initialize();
  await d.mount(screen: P21Driver.screen());
  await d.wait(4000);
  await d.at(at);
  return d;
}

/// Three quick presses with the bar hidden: two ten-second nudges through
/// the desktop mapping, then the hold enters the scrub.
Future<void> _hold(P21Driver d, LogicalKeyboardKey key) async {
  for (var i = 0; i < 3; i++) {
    await d.key(key);
  }
}

/// A Debrify TV channel session whose next-channel request is held.
class _Switch {
  final requests = <Completer<Map<String, dynamic>?>>[];
  VideoPlayerScreen screen() => VideoPlayerScreen(
    videoUrl: 'https://p21-scrub.test/a.mp4',
    title: 'Film A',
    showChannelName: true,
    channelName: 'Alpha',
    channelNumber: 7,
    requestNextChannel: () {
      final request = Completer<Map<String, dynamic>?>();
      requests.add(request);
      return request.future;
    },
  );
  void release() => requests.last.complete({
    'url': 'https://p21-scrub.test/b.mp4',
    'title': 'Film B',
    'channelName': 'Beta',
    'channelNumber': 9,
  });
  void drop() {
    for (final r in requests) {
      if (!r.isCompleted) r.complete(null);
    }
  }
}

/// Raises the bar and puts focus on its progress row.
Future<void> _progressRow(P21Driver d) async {
  await d.key(LogicalKeyboardKey.arrowDown);
  d.bar.progressFocusNode.requestFocus();
  await d.wait(50);
}

/// Nine RIGHT presses on the progress row; returns each stride in seconds.
Future<List<int>> _strides(P21Driver d) async {
  final base = d.player.state.position;
  final previews = <Duration>[base];
  for (var i = 0; i < 9; i++) {
    await d.key(_right);
    previews.add(d.bar.scrubPreview!);
  }
  return [
    for (var i = 1; i < previews.length; i++)
      (previews[i] - previews[i - 1]).inSeconds,
  ];
}

void main() {
  p21Timeouts();
  testWidgets(
    'P21 TV the third quick RIGHT pauses into a scrub previewing ten seconds on from the playhead',
    (t) async {
      final d = await _tv(t);
      try {
        await _hold(d, _right);
        // The two taps before the hold were ordinary nudges.
        expect(d.seeks, [
          const Duration(seconds: 310),
          const Duration(seconds: 320),
        ]);
        expect(d.count('pause'), 1);
        expect(d.player.state.playing, isFalse);
        expect(d.barUp, isTrue);
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        expect(d.focused, 'tvProgress');
        expect(d.bar.isPlaying, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV the third quick LEFT scrubs ten seconds back from the playhead',
    (t) async {
      final d = await _tv(t);
      try {
        await _hold(d, _left);
        expect(d.seeks, [
          const Duration(seconds: 290),
          const Duration(seconds: 280),
        ]);
        expect(d.bar.scrubPreview, const Duration(seconds: 270));
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 260));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a scrub accelerates from ten to thirty to sixty second strides',
    (t) async {
      final d = await _tv(t, at: const Duration(seconds: 20));
      try {
        await d.length(const Duration(hours: 3));
        await _hold(d, _right);
        final previews = <Duration?>[d.bar.scrubPreview];
        for (var i = 0; i < 17; i++) {
          await d.key(_right);
          previews.add(d.bar.scrubPreview);
        }
        final strides = [
          for (var i = 1; i < previews.length; i++)
            (previews[i]! - previews[i - 1]!).inSeconds,
        ];
        // Begin took the first ten-second stride (repeat 0).
        expect(previews.first, const Duration(seconds: 50));
        expect(strides, [...List.filled(7, 10), ...List.filled(8, 30), 60, 60]);
        expect(d.seeks, hasLength(2), reason: 'a scrub step never seeks');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a scrub preview clamps to the start and to the end of the item',
    (t) async {
      final d = await _tv(t, at: const Duration(seconds: 25));
      try {
        await _hold(d, _left);
        // 25 - 10 - 10 = 5 s, then the preview stride clamps at zero.
        expect(d.bar.scrubPreview, Duration.zero);
        await d.key(_left);
        expect(d.bar.scrubPreview, Duration.zero);
        await d.key(LogicalKeyboardKey.escape);
        await d.at(const Duration(minutes: 19, seconds: 35));
        await d.wait(4000);
        await _hold(d, _right);
        expect(d.bar.scrubPreview, const Duration(minutes: 20));
        await d.key(_right);
        expect(d.bar.scrubPreview, const Duration(minutes: 20));
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks.last, const Duration(minutes: 20));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  ]) {
    testWidgets(
      'P21 TV ${key.keyLabel} confirms a scrub with one seek, resumes playback and refocuses Play/Pause',
      (t) async {
        final d = await _tv(t);
        try {
          await _hold(d, _right);
          await d.key(_right);
          final before = d.player.calls.length;
          await d.key(key);
          final after = [for (final c in d.player.calls.skip(before)) c.$1];
          expect(after.where((c) => c == 'seek' || c == 'play').toList(), [
            'seek',
            'play',
          ]);
          expect(d.seeks.last, const Duration(seconds: 340));
          expect(d.bar.scrubPreview, isNull);
          expect(d.player.state.playing, isTrue);
          expect(d.focused, 'tvPlayPause');
          // A fresh full interval from the confirm.
          await d.wait(2900);
          expect(d.barUp, isTrue);
          await d.wait(200);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV confirming a scrub begun while paused seeks without resuming',
    (t) async {
      final d = await _tv(t);
      try {
        await d.f.finish(t, d.player.pause());
        await d.wait(50);
        final pauses = d.count('pause');
        await _hold(d, _right);
        expect(d.count('pause'), pauses, reason: 'already paused');
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks.last, const Duration(seconds: 330));
        expect(d.count('play'), 0);
        expect(d.player.state.playing, isFalse);
        // Paused: the bar is meant to stay up.
        await d.wait(6500);
        expect(d.barUp, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final cancel in [
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.arrowDown,
  ]) {
    testWidgets(
      'P21 TV ${cancel.keyLabel} cancels a scrub without seeking and resumes playback',
      (t) async {
        final d = await _tv(t);
        try {
          await _hold(d, _right);
          final seeks = d.seeks.length;
          await d.key(cancel);
          expect(d.seeks, hasLength(seeks));
          expect(d.bar.scrubPreview, isNull);
          expect(d.count('play'), 1);
          expect(d.player.state.playing, isTrue);
          expect(d.focused, 'tvPlayPause');
          expect(d.barUp, isTrue);
          await d.wait(2900);
          expect(d.barUp, isTrue);
          await d.wait(200);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV system BACK during a scrub cancels it before anything else and keeps the player',
    (t) async {
      final d = await _tv(t);
      try {
        await _hold(d, _right);
        final seeks = d.seeks.length;
        await d.systemBack();
        expect(d.bar.scrubPreview, isNull);
        expect(d.seeks, hasLength(seeks));
        expect(d.count('play'), 1);
        expect(d.barUp, isTrue, reason: 'the cancel, not a bar hide');
        expect(d.focused, 'tvPlayPause');
        await d.systemBack();
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

  testWidgets('P21 TV a cancel of a scrub begun while paused does not resume', (
    t,
  ) async {
    final d = await _tv(t);
    try {
      await d.f.finish(t, d.player.pause());
      await d.wait(50);
      await _hold(d, _left);
      await d.key(LogicalKeyboardKey.escape);
      expect(d.count('play'), 0);
      expect(d.bar.scrubPreview, isNull);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P21 TV other keys during a scrub are swallowed without moving it',
    (t) async {
      final d = await _tv(t);
      try {
        await _hold(d, _right);
        final preview = d.bar.scrubPreview;
        final calls = d.player.calls.length;
        await d.key(LogicalKeyboardKey.arrowUp);
        await d.key(LogicalKeyboardKey.keyA);
        await d.key(LogicalKeyboardKey.space);
        expect(d.bar.scrubPreview, preview);
        expect(d.player.calls.length, calls);
        expect(d.player.state.playing, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a scrub holds the bar up even while the paused player still reports playing',
    (t) async {
      final d = await _tv(t);
      final pause = Completer<void>();
      try {
        d.player.delays['pause'] = pause;
        await _hold(d, _right);
        expect(d.player.state.playing, isTrue);
        await d.wait(7000);
        expect(d.barUp, isTrue);
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        pause.complete();
        await d.wait(50);
        await d.key(LogicalKeyboardKey.select);
        expect(d.player.state.playing, isTrue);
        // The confirm re-arms without clearing the block the scrub left
        // behind, so its first poll grants one more full interval.
        await d.wait(3100);
        expect(d.barUp, isTrue);
        await d.wait(2800);
        expect(d.barUp, isTrue);
        await d.wait(200);
        expect(d.barUp, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!pause.isCompleted) pause.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV slow LEFT taps stay ten-second nudges and never enter a scrub',
    (t) async {
      final d = await _tv(t);
      try {
        for (var i = 0; i < 4; i++) {
          await d.key(_left);
          await d.realWait(const Duration(milliseconds: 450));
        }
        expect(d.seeks, [
          for (var s = 290; s >= 260; s -= 10) Duration(seconds: s),
        ]);
        expect(d.count('pause'), 0);
        expect(d.barUp, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a slow tap after two quick ones restarts the hold count',
    (t) async {
      final d = await _tv(t);
      try {
        await d.key(_right);
        await d.key(_right);
        await d.realWait(const Duration(milliseconds: 450));
        await d.key(_right);
        await d.key(_right);
        expect(d.bar.scrubPreview, isNull);
        expect(d.seeks, hasLength(4));
        await d.key(_right);
        expect(d.bar.scrubPreview, isNotNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV LEFT or RIGHT on the raised progress row starts a scrub at once',
    (t) async {
      final d = await _tv(t);
      try {
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(d.focused, 'tvPlayPause');
        d.bar.progressFocusNode.requestFocus();
        await d.wait(50);
        expect(d.focused, 'tvProgress');
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 290));
        expect(d.count('pause'), 1);
        expect(d.seeks, isEmpty);
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 280));
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks, [const Duration(seconds: 280)]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a first progress-row scrub starts its strides from a zero hold count',
    (t) async {
      final d = await _tv(t, at: const Duration(seconds: 100));
      try {
        await d.length(const Duration(hours: 2));
        await d.key(LogicalKeyboardKey.arrowDown);
        d.bar.progressFocusNode.requestFocus();
        await d.wait(50);
        final previews = <Duration>[];
        for (var i = 0; i < 9; i++) {
          await d.key(_right);
          previews.add(d.bar.scrubPreview!);
        }
        expect(previews.first, const Duration(seconds: 110));
        expect(previews[7], const Duration(seconds: 180));
        expect(previews[8], const Duration(seconds: 210));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a progress-row scrub after two quick hidden taps inherits their hold count',
    (t) async {
      final d = await _tv(t, at: const Duration(seconds: 100));
      try {
        await d.length(const Duration(hours: 2));
        await d.key(_right);
        await d.key(_right);
        expect(d.seeks, hasLength(2));
        await d.key(LogicalKeyboardKey.arrowDown);
        d.bar.progressFocusNode.requestFocus();
        await d.wait(50);
        await d.key(_right);
        final base = d.bar.scrubPreview!;
        for (var i = 0; i < 6; i++) {
          await d.key(_right);
        }
        expect(d.bar.scrubPreview! - base, const Duration(seconds: 60));
        // The shared count reaches the thirty-second stride one press early.
        await d.key(_right);
        expect(d.bar.scrubPreview! - base, const Duration(seconds: 90));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P21 TV a confirm after a cancel restarts the stride count', (
    t,
  ) async {
    final d = await _tv(t, at: const Duration(seconds: 100));
    try {
      await d.length(const Duration(hours: 2));
      await _hold(d, _right);
      for (var i = 0; i < 9; i++) {
        await d.key(_right);
      }
      await d.key(LogicalKeyboardKey.escape);
      await d.wait(4000);
      await d.key(LogicalKeyboardKey.arrowDown);
      d.bar.progressFocusNode.requestFocus();
      await d.wait(50);
      final position = d.player.state.position;
      await d.key(_right);
      expect(d.bar.scrubPreview! - position, const Duration(seconds: 10));
      for (var i = 0; i < 9; i++) {
        await d.key(_right);
      }
      await d.key(LogicalKeyboardKey.select);
      await d.wait(4000);
      await d.key(LogicalKeyboardKey.arrowDown);
      d.bar.progressFocusNode.requestFocus();
      await d.wait(50);
      final again = d.player.state.position;
      await d.key(_right);
      expect(d.bar.scrubPreview! - again, const Duration(seconds: 10));
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P21 TV a session without a timeline swallows LEFT and RIGHT and never scrubs',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen(hideSeekbar: true));
        await d.wait(4000);
        for (var i = 0; i < 4; i++) {
          await d.key(_right);
          await d.key(_left);
        }
        expect(d.seeks, isEmpty);
        expect(d.count('pause'), 0);
        expect(d.bar.scrubPreview, isNull);
        expect(d.barUp, isFalse);
        expect(d.bar.progressFocusable, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV an unknown duration swallows LEFT and RIGHT like a live stream',
    (t) async {
      final d = await _tv(t);
      try {
        await d.length(Duration.zero);
        await _hold(d, _right);
        expect(d.seeks, isEmpty);
        expect(d.bar.scrubPreview, isNull);
        expect(d.count('pause'), 0);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a channel switch drops the scrub without seeking or resuming, and a later scrub seeks again',
    (t) async {
      final d = P21Driver(t, tv: true);
      final sw = _Switch();
      await d.initialize();
      try {
        await d.mount(screen: sw.screen());
        await d.wait(4000);
        await d.at(_start);
        await _hold(d, _right);
        expect(d.bar.scrubPreview, isNotNull);
        final seeks = d.seeks.length;
        final plays = d.count('play');
        final work = d.startNextChannel();
        await d.wait(0);
        expect(d.bar.scrubPreview, isNull);
        expect(d.seeks, hasLength(seeks));
        expect(d.count('play'), plays, reason: 'the transition drives play');
        sw.release();
        await d.f.finish(t, work);
        await d.wait(4000);
        await d.at(const Duration(seconds: 100));
        await d.wait(4000);
        await _progressRow(d);
        // The dropped scrub's count was reset: strides start from zero.
        expect(await _strides(d), [...List.filled(8, 10), 30]);
        await d.key(LogicalKeyboardKey.select);
        // Captured at this scrub's start, after the switch bumped it: the
        // confirm is current and seeks.
        expect(d.seeks.last, const Duration(seconds: 210));
        expect(d.seeks, hasLength(seeks + 1));
        expect(d.errors, isEmpty);
      } finally {
        sw.drop();
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a channel switch with no scrub keeps the hold count of earlier quick taps',
    (t) async {
      final d = P21Driver(t, tv: true);
      final sw = _Switch();
      await d.initialize();
      try {
        await d.mount(screen: sw.screen());
        await d.wait(4000);
        await d.at(_start);
        await d.key(_right);
        await d.key(_right);
        final work = d.startNextChannel();
        await d.wait(0);
        sw.release();
        await d.f.finish(t, work);
        await d.wait(4000);
        await d.at(const Duration(seconds: 100));
        await _progressRow(d);
        // One quick repeat is still counted: the 30 s stride comes a press
        // early.
        expect(await _strides(d), [...List.filled(7, 10), 30, 30]);
        expect(d.errors, isEmpty);
      } finally {
        sw.drop();
        await d.close();
      }
    },
  );

  for (final end in ['confirm', 'cancel']) {
    testWidgets(
      'P21 TV a scrub $end resets the stride count for the next scrub',
      (t) async {
        final d = await _tv(t, at: const Duration(seconds: 100));
        try {
          await d.length(const Duration(hours: 2));
          await _progressRow(d);
          await _strides(d);
          await d.key(
            end == 'confirm'
                ? LogicalKeyboardKey.select
                : LogicalKeyboardKey.escape,
          );
          await d.wait(4000);
          await _progressRow(d);
          expect(await _strides(d), [...List.filled(8, 10), 30]);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV a scrub cancelled within its first frame never takes focus to the progress row',
    (t) async {
      final d = await _tv(t);
      try {
        await d.key(_right);
        await d.key(_right);
        await d.observe(() async {
          await t.sendKeyEvent(_right);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
        });
        await d.wait(50);
        expect(d.bar.scrubPreview, isNull);
        expect(d.focused, 'tvPlayPause');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P21 TV each scrub stride restarts the bar countdown', (t) async {
    final d = await _tv(t);
    try {
      await _hold(d, _right);
      final armed = d.timers
          .where((v) => v.duration == const Duration(seconds: 3))
          .length;
      await d.key(_right);
      await d.key(_left);
      expect(
        d.timers.where((v) => v.duration == const Duration(seconds: 3)).length,
        armed + 2,
      );
      expect(d.activeTimers(const Duration(seconds: 3)), 1);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
}
