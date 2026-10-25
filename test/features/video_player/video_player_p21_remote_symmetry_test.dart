import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _right = LogicalKeyboardKey.arrowRight;
const _left = LogicalKeyboardKey.arrowLeft;

Future<P21Driver> _tv(
  WidgetTester t, {
  Duration at = const Duration(seconds: 300),
  Duration? length,
}) async {
  final d = P21Driver(t, tv: true);
  await d.initialize();
  await d.mount(screen: P21Driver.screen());
  await d.wait(4000);
  if (length != null) await d.length(length);
  await d.at(at);
  return d;
}

Future<void> _hold(P21Driver d, LogicalKeyboardKey key) async {
  for (var i = 0; i < 3; i++) {
    await d.key(key);
  }
}

Future<void> _progressRow(P21Driver d) async {
  await d.key(LogicalKeyboardKey.arrowDown);
  d.bar.progressFocusNode.requestFocus();
  await d.wait(50);
}

/// Signed strides in seconds between consecutive previews after [presses]
/// of [key], starting from the current preview.
Future<List<int>> _strides(
  P21Driver d,
  LogicalKeyboardKey key,
  int presses,
) async {
  final previews = <Duration>[d.bar.scrubPreview!];
  for (var i = 0; i < presses; i++) {
    await d.key(key);
    previews.add(d.bar.scrubPreview!);
  }
  return [
    for (var i = 1; i < previews.length; i++)
      (previews[i] - previews[i - 1]).inSeconds,
  ];
}

/// Phase 21a Step 0c, class 2: the backward (LEFT) twin of every forward
/// remote behaviour: hold entry, stride acceleration, a reversal inside an
/// accelerated scrub, the clamp at zero through to the confirm's seek, and
/// the hold window.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 TV a LEFT hold accelerates backward from ten to thirty to sixty second strides',
    (t) async {
      final d = await _tv(
        t,
        length: const Duration(hours: 3),
        at: const Duration(hours: 2, minutes: 50),
      );
      try {
        await _hold(d, _left);
        expect(
          d.bar.scrubPreview,
          const Duration(hours: 2, minutes: 49, seconds: 30),
        );
        expect(await _strides(d, _left, 17), [
          ...List.filled(7, -10),
          ...List.filled(8, -30),
          -60,
          -60,
        ]);
        expect(d.seeks, hasLength(2), reason: 'a scrub step never seeks');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a progress-row LEFT scrub accelerates backward like a RIGHT one forward',
    (t) async {
      final d = await _tv(
        t,
        length: const Duration(hours: 2),
        at: const Duration(hours: 1),
      );
      try {
        await _progressRow(d);
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(minutes: 59, seconds: 50));
        expect(await _strides(d, _left, 9), [...List.filled(7, -10), -30, -30]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final first in [_right, _left]) {
    testWidgets(
      'P21 TV reversing an accelerated ${first == _right ? 'RIGHT' : 'LEFT'} scrub keeps the stride size and flips its sign',
      (t) async {
        final d = await _tv(
          t,
          length: const Duration(hours: 3),
          at: const Duration(hours: 1),
        );
        final back = first == _right ? _left : _right;
        final sign = first == _right ? -1 : 1;
        try {
          await _progressRow(d);
          await d.key(first);
          await _strides(d, first, 8);
          expect(await _strides(d, back, 1), [30 * sign]);
          await _strides(d, first, 7);
          expect(await _strides(d, back, 2), [60 * sign, 60 * sign]);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV LEFT and RIGHT inside a scrub step it back and forth by ten seconds',
    (t) async {
      final d = await _tv(t);
      try {
        await _hold(d, _right);
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 320));
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 310));
        await d.key(_right);
        expect(d.bar.scrubPreview, const Duration(seconds: 320));
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks.last, const Duration(seconds: 320));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a LEFT scrub clamped at the start confirms a seek to zero and resumes',
    (t) async {
      final d = await _tv(t, at: const Duration(seconds: 25));
      try {
        await _hold(d, _left);
        await d.key(_left);
        expect(d.bar.scrubPreview, Duration.zero);
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks.last, Duration.zero);
        expect(d.count('play'), 1);
        expect(d.player.state.playing, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a progress-row LEFT scrub from near the start clamps every stride at zero',
    (t) async {
      final d = await _tv(t, at: const Duration(seconds: 15));
      try {
        await _progressRow(d);
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 5));
        await d.key(_left);
        expect(d.bar.scrubPreview, Duration.zero);
        await d.key(_left);
        expect(d.bar.scrubPreview, Duration.zero);
        await d.key(_right);
        expect(d.bar.scrubPreview, const Duration(seconds: 10));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV LEFT presses about 300 ms apart are a hold, so the third enters a backward scrub',
    (t) async {
      final d = await _tv(t);
      try {
        await d.key(_left);
        await d.realWait(const Duration(milliseconds: 300));
        await d.key(_left);
        await d.realWait(const Duration(milliseconds: 300));
        await d.key(_left);
        expect(d.seeks, [
          const Duration(seconds: 290),
          const Duration(seconds: 280),
        ]);
        expect(d.bar.scrubPreview, const Duration(seconds: 270));
        expect(d.count('pause'), 1);
        expect(d.focused, 'tvProgress');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a direction change inside the hold window still counts toward the hold',
    (t) async {
      final d = await _tv(t);
      try {
        await d.key(_right);
        await d.key(_left);
        await d.key(_left);
        expect(d.seeks, [
          const Duration(seconds: 310),
          const Duration(seconds: 300),
        ]);
        expect(d.bar.scrubPreview, const Duration(seconds: 290));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
