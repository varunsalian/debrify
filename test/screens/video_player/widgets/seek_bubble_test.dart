// The seek bubble names the time under the pointer while hovering and under
// the thumb while the bar is held, and is otherwise absent.

import 'package:debrify/screens/video_player/widgets/seek_bubble.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const length = Duration(minutes: 100);
  String fmt(Duration d) => '${d.inMinutes}m';

  Widget host({
    double progress = 0.25,
    double inset = 0,
    Widget child = const ColoredBox(color: Colors.grey),
    TextDirection direction = TextDirection.ltr,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1000,
              height: 40,
              child: SeekBubble(
                duration: length,
                progress: progress,
                inset: inset,
                format: fmt,
                fill: Colors.black,
                ink: Colors.white,
                fontSize: 12,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('hover shows the time under the pointer and leaves with it', (
    t,
  ) async {
    await t.pumpWidget(host());
    expect(find.textContaining('m'), findsNothing);

    final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    final box = t.getRect(find.byType(SeekBubble));
    await gesture.moveTo(Offset(box.left + box.width * 0.5, box.center.dy));
    await t.pump();
    expect(find.text('50m'), findsOneWidget);

    await gesture.moveTo(Offset(box.left + box.width * 0.9, box.center.dy));
    await t.pump();
    expect(find.text('90m'), findsOneWidget);

    await gesture.moveTo(Offset(box.center.dx, box.bottom + 200));
    await t.pump();
    expect(find.textContaining('m'), findsNothing);
  });

  testWidgets('a held bar shows the time under the thumb until release', (
    t,
  ) async {
    await t.pumpWidget(host(progress: 0.25));
    final box = t.getRect(find.byType(SeekBubble));
    final touch = await t.startGesture(
      Offset(box.left + box.width * 0.8, box.center.dy),
    );
    await t.pump();
    expect(
      find.text('25m'),
      findsOneWidget,
      reason: 'the thumb, not the touch',
    );
    await touch.up();
    await t.pump();
    expect(find.text('25m'), findsNothing);
  });

  testWidgets('a mouse drag follows the thumb and lands where it let go', (
    t,
  ) async {
    await t.pumpWidget(host(progress: 0.25));
    final box = t.getRect(find.byType(SeekBubble));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(box.left + box.width * 0.1, box.center.dy));
    await t.pump();
    expect(find.text('10m'), findsOneWidget);
    await mouse.down(Offset(box.left + box.width * 0.1, box.center.dy));
    await mouse.moveTo(Offset(box.left + box.width * 0.6, box.center.dy));
    await t.pump();
    expect(find.text('25m'), findsOneWidget, reason: 'the thumb while held');
    await mouse.up();
    await t.pump();
    expect(find.text('60m'), findsOneWidget, reason: 'where it let go');
    expect(find.text('10m'), findsNothing);
  });

  testWidgets('an RTL bar names the time from its right end', (t) async {
    await t.pumpWidget(host(direction: TextDirection.rtl));
    final box = t.getRect(find.byType(SeekBubble));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(box.left + box.width * 0.2, box.center.dy));
    await t.pump();
    expect(find.text('80m'), findsOneWidget);
  });

  testWidgets('the pill sits over a real slider thumb and stays on the bar', (
    t,
  ) async {
    for (final value in [0.5, 1.0]) {
      await t.pumpWidget(
        host(
          progress: value,
          inset: 12,
          child: SliderTheme(
            data: const SliderThemeData(
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(min: 0, max: 1, value: value, onChanged: (_) {}),
          ),
        ),
      );
      final bar = t.getRect(find.byType(Slider));
      final thumbX = bar.left + 12 + value * (bar.width - 24);
      await t.startGesture(bar.center);
      await t.pump();
      final pill = t.getRect(find.text('${(100 * value).round()}m'));
      if (value < 1) {
        expect((pill.center.dx - thumbX).abs(), lessThan(1.0));
      } else {
        expect(pill.right, lessThanOrEqualTo(bar.right + 0.01));
      }
    }
  });
}
