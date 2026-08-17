import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A held DPAD centre never becomes a pointer long-press, so every episode
/// card recognises the hold from the keys instead. This pins that machine:
/// press opens playback, hold opens the options menu, and the two can never
/// both fire for one press.
void main() {
  const okDown = KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.enter,
    logicalKey: LogicalKeyboardKey.enter,
    timeStamp: Duration.zero,
  );
  const okRepeat = KeyRepeatEvent(
    physicalKey: PhysicalKeyboardKey.enter,
    logicalKey: LogicalKeyboardKey.enter,
    timeStamp: Duration.zero,
  );
  const okUp = KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.enter,
    logicalKey: LogicalKeyboardKey.enter,
    timeStamp: Duration.zero,
  );

  late int taps;
  late int holds;
  late TvHoldOk hold;

  setUp(() {
    taps = 0;
    holds = 0;
    hold = TvHoldOk(
      onTap: () => taps++,
      onHold: () => holds++,
      dwell: const Duration(milliseconds: 600),
      // The test binding has no haptics channel wired.
      hapticOnArm: false,
    );
  });

  testWidgets('a quick press plays and never opens the menu', (tester) async {
    hold.handle(okDown);
    await tester.pump(const Duration(milliseconds: 120));
    hold.handle(okUp);
    await tester.pump(const Duration(milliseconds: 800));
    expect(taps, 1);
    expect(holds, 0);
  });

  testWidgets('the menu waits for the key to come up', (tester) async {
    hold.handle(okDown);
    await tester.pump(const Duration(milliseconds: 900));
    // NOT while the key is down. A menu opened here autofocuses its first
    // entry into a keyboard that is still auto-repeating this very press, and
    // the next repeat activates it — which is how a held OK used to read as a
    // plain press that just played the episode.
    expect(holds, 0, reason: 'the key has not been released yet');
    expect(hold.armed, isTrue, reason: 'but the press has become a hold');

    hold.handle(okUp);
    await tester.pump();
    expect(holds, 1);
    expect(taps, 0, reason: 'a hold is not also a press');
  });

  testWidgets('repeats under a held key are swallowed, never passed on', (
    tester,
  ) async {
    hold.handle(okDown);
    // Anything but `handled` and these reach the shortcut layer, where the
    // default activator includes repeats.
    expect(hold.handle(okRepeat), KeyEventResult.handled);
    expect(hold.handle(okRepeat), KeyEventResult.handled);
    hold.reset(); // the press never ends in this test
  });

  testWidgets('repeats do not restart the dwell', (tester) async {
    hold.handle(okDown);
    for (var i = 0; i < 5; i++) {
      hold.handle(okRepeat);
      await tester.pump(const Duration(milliseconds: 150));
    }
    hold.handle(okUp);
    await tester.pump();
    expect(holds, 1);
    expect(taps, 0);
  });

  testWidgets('a key-up with no key-down of ours is not a tap', (tester) async {
    // The press began on another card; only the release landed here.
    hold.handle(okUp);
    await tester.pump();
    expect(taps, 0);
    expect(holds, 0);
  });

  testWidgets('losing focus abandons an in-flight hold', (tester) async {
    hold.handle(okDown);
    await tester.pump(const Duration(milliseconds: 200));
    hold.reset();
    await tester.pump(const Duration(milliseconds: 900));
    // The key-up lands after the cursor moved on: neither gesture may fire.
    hold.handle(okUp);
    await tester.pump();
    expect(holds, 0);
    expect(taps, 0);
  });
}
