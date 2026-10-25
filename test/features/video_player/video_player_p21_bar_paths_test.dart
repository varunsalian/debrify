import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _hide = Duration(seconds: 3);

/// A tap on the empty left of the player, which toggles the controls layer
/// whether it is raised or not (the centre is kept for raised buttons).
Future<void> _tap(P21Driver d) async {
  await d.observe(() => d.t.tapAt(const Offset(150, 400)));
  await d.wait(320);
}

/// Phase 21 Step 0b: the auto-hide and bar paths that do not go through the
/// usual raise/lower pair: a lowering by BACK or tap while a countdown is
/// pending, a tap raise or lower on a television, a desktop expiry under a
/// route, and a scrub abandoned within its first frame.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 desktop an auto-hide under a route leaves keyboard focus in that route',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final sheet = FocusNode(debugLabel: 'p21-route-sheet');
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.hover();
        expect(d.barUp, isTrue);
        d.f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Focus(
              focusNode: sheet,
              autofocus: true,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await d.wait(500);
        expect(d.focused, 'p21-route-sheet');
        // The desktop countdown is not held by a route: it expires and only
        // lowers the dock.
        await d.wait(2600);
        expect(d.barUp, isFalse);
        expect(d.focused, 'p21-route-sheet');
        d.f.navigator.currentState!.pop();
        await d.wait(500);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        sheet.dispose();
      }
    },
  );

  for (final lower in ['BACK', 'tap']) {
    testWidgets(
      'P21 TV a bar lowered by $lower with a countdown pending lets it lapse instead of polling',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.barUp, isTrue);
          expect(d.activeTimers(_hide), 1);
          await d.wait(1000);
          lower == 'BACK'
              ? await d.key(LogicalKeyboardKey.escape)
              : await _tap(d);
          expect(d.barUp, isFalse);
          // Lowering leaves the raise's countdown running...
          expect(d.activeTimers(_hide), 1);
          final armed = d.timers.where((v) => v.duration == _hide).length;
          // ...and its tick finds nothing to dismiss and arms nothing.
          await d.wait(9000);
          expect(d.activeTimers(_hide), 0);
          expect(d.timers.where((v) => v.duration == _hide).length, armed);
          expect(d.barUp, isFalse);
          expect(d.focused, 'tvPlayerRoot');
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV a raise after a tap lowered a blocked bar forgets the block and hides on the first poll',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        await d.f.finish(t, d.player.pause());
        // The 3 s poll finds it paused: the block is remembered.
        await d.wait(3500);
        expect(d.barUp, isTrue);
        // A tap lowers it without going through the bar's own lower.
        await _tap(d);
        expect(d.barUp, isFalse);
        await d.f.finish(t, d.player.play());
        await d.wait(500);
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(d.barUp, isTrue);
        await d.wait(2900);
        expect(d.barUp, isTrue);
        await d.wait(150);
        expect(d.barUp, isFalse, reason: 'no extra interval from the block');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a tap raise shows the bar but leaves focus on the player root',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        await _tap(d);
        expect(d.barUp, isTrue);
        expect(d.focused, 'tvPlayerRoot');
        // The tap is accepted at the 300 ms double-tap timeout, which starts
        // the countdown.
        await d.wait(2900);
        expect(d.barUp, isTrue);
        await d.wait(150);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a progress-row scrub abandoned by a transition in its first frame leaves focus on the progress row',
    (t) async {
      final next = Completer<Map<String, String>?>();
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(
          screen: P21Driver.screen(requestMagicNext: () => next.future),
        );
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        await d.key(LogicalKeyboardKey.arrowDown);
        d.bar.progressFocusNode.requestFocus();
        await d.wait(50);
        expect(d.focused, 'tvProgress');
        final seeks = d.seeks.length;
        // RIGHT starts the scrub; the next item starts before any frame.
        await d.observe(() => t.sendKeyEvent(LogicalKeyboardKey.arrowRight));
        d.observe(d.bar.onNext!);
        await d.wait(50);
        expect(d.bar.scrubPreview, isNull);
        expect(d.seeks, hasLength(seeks));
        expect(d.focused, 'tvProgress');
        next.complete(null);
        await d.wait(100);
        expect(d.errors, isEmpty);
      } finally {
        if (!next.isCompleted) next.complete(null);
        await d.close();
      }
    },
  );
}
