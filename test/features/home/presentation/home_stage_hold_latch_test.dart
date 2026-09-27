import 'package:debrify/features/home/presentation/home_stage_hold_latch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _down = LogicalKeyboardKey.arrowDown;
const _up = LogicalKeyboardKey.arrowUp;

void main() {
  test(
    'only a successful jump latches, and repeats do not invoke it again',
    () {
      final latch = HomeStageHoldLatch();
      var calls = 0;
      latch.jump(_down, () {
        calls++;
        return false;
      });
      expect(latch.swallows(_down), isFalse);
      latch.jump(_down, () {
        calls++;
        return true;
      });
      expect(latch.swallows(_down), isTrue);
      expect(latch.swallows(_up), isFalse);
      latch.jump(_down, () {
        calls++;
        return true;
      });
      expect(calls, 2);
      // The legacy latch tracks one specific key; a different successful jump
      // replaces it rather than blocking every direction.
      latch.jump(_up, () => true);
      expect(latch.swallows(_up), isTrue);
      expect(latch.swallows(_down), isFalse);
    },
  );

  test(
    'an unsuccessful or throwing different-key jump preserves the current latch',
    () {
      final latch = HomeStageHoldLatch();
      latch.jump(_down, () => true);
      latch.jump(_up, () => false);
      expect(latch.swallows(_down), isTrue);
      expect(
        () => latch.jump(_up, () => throw StateError('jump failed')),
        throwsStateError,
      );
      expect(latch.swallows(_down), isTrue);
      expect(latch.swallows(_up), isFalse);
    },
  );

  for (final freshDown in [false, true]) {
    test(
      'matching ${freshDown ? 'fresh down recovers a missed release' : 'key up releases the latch'} without consuming the event',
      () {
        final latch = HomeStageHoldLatch();
        latch.jump(_down, () => true);
        final KeyEvent event = freshDown
            ? const KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.arrowDown,
                logicalKey: _down,
                timeStamp: Duration.zero,
              )
            : const KeyUpEvent(
                physicalKey: PhysicalKeyboardKey.arrowDown,
                logicalKey: _down,
                timeStamp: Duration.zero,
              );
        expect(latch.handleKeyEvent(event), isFalse);
        expect(latch.swallows(_down), isFalse);
        var calls = 0;
        latch.jump(_down, () {
          calls++;
          return true;
        });
        expect(calls, 1);
      },
    );
  }

  test('repeats and other keys neither release nor consume the held key', () {
    final latch = HomeStageHoldLatch();
    latch.jump(_down, () => true);
    for (final event in [
      const KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: _down,
        timeStamp: Duration.zero,
      ),
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: _up,
        timeStamp: Duration.zero,
      ),
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: _up,
        timeStamp: Duration.zero,
      ),
    ]) {
      expect(latch.handleKeyEvent(event), isFalse);
      expect(latch.swallows(_down), isTrue);
      expect(latch.swallows(_up), isFalse);
    }
  });

  test('layout reset clears only its view-owned latch', () {
    final first = HomeStageHoldLatch();
    final second = HomeStageHoldLatch();
    first.jump(_down, () => true);
    expect(second.swallows(_down), isFalse);
    second.jump(_up, () => true);
    first.reset();
    expect(first.swallows(_down), isFalse);
    expect(second.swallows(_up), isTrue);
    first.reset();
    first.jump(_down, () => true);
    expect(first.swallows(_down), isTrue);
  });

  testWidgets(
    'borrowed global registration observes handled keys and can be removed by tear-off',
    (tester) async {
      final latch = HomeStageHoldLatch();
      final node = FocusNode();
      addTearDown(node.dispose);
      final events = <Type>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: node,
            onKeyEvent: (_, event) {
              events.add(event.runtimeType);
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      HardwareKeyboard.instance.addHandler(latch.handleKeyEvent);
      var registered = true;
      addTearDown(() {
        if (registered) {
          HardwareKeyboard.instance.removeHandler(latch.handleKeyEvent);
        }
      });
      await tester.sendKeyDownEvent(_down);
      latch.jump(_down, () => true);
      await tester.sendKeyRepeatEvent(_down);
      expect(latch.swallows(_down), isTrue);
      await tester.sendKeyUpEvent(_down);
      expect(latch.swallows(_down), isFalse);
      expect(events, [KeyDownEvent, KeyRepeatEvent, KeyUpEvent]);
      HardwareKeyboard.instance.removeHandler(latch.handleKeyEvent);
      registered = false;
      latch.jump(_down, () => true);
      await tester.sendKeyDownEvent(_down);
      expect(latch.swallows(_down), isTrue);
      await tester.sendKeyUpEvent(_down);
      expect(latch.swallows(_down), isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
