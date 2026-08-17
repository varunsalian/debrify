import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
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
      haptic: false,
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

  testWidgets('the menu opens under the key, not on release', (tester) async {
    hold.handle(okDown);
    await tester.pump(const Duration(milliseconds: 400));
    expect(holds, 0, reason: 'the dwell has not elapsed');
    await tester.pump(const Duration(milliseconds: 300));
    // Under the thumb: a long press that only pays out after you let go is
    // the thing users read as broken.
    expect(holds, 1);
    expect(taps, 0);

    // The release that ends the hold must not also count as a press.
    hold.handle(okUp);
    await tester.pump();
    expect(holds, 1);
    expect(taps, 0);
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

  testWidgets('the guard stops a held key from activating the menu it opened',
      (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TvHeldKeyGuard(
          child: Material(
            child: ListTile(
              autofocus: true, // exactly what the episode sheet does
              title: const Text('Play'),
              onTap: () => activations++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The tail of the press that opened this menu.
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 0,
        reason: 'a repeat belongs to the press that opened the menu');

    // A deliberate press afterwards must still work.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
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
