import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

void main() {
  testWidgets('primary focus dispatches the host focused callback', (t) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(f.host(f.identity()));
      await showcasePump(t);
      f.actions.first.requestFocus();
      await t.pump();
      f.calls.clear();
      f.primary.requestFocus();
      await t.pump();
      expect(f.primary.hasFocus, isTrue);
      expect(f.calls, ['focused']);
    });
  });

  testWidgets('OK activates once and a 600 ms hold calls only long press', (
    t,
  ) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(f.host(f.identity()));
      await showcasePump(t);
      f.calls.clear();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      expect(f.calls, ['primary']);
      f.calls.clear();
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 599));
      expect(f.calls, isEmpty);
      await t.pump(const Duration(milliseconds: 1));
      expect(f.calls, ['hold']);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      expect(f.calls, ['hold']);
    });
  });

  testWidgets('unmount and focus loss cancel an in-flight hold', (t) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(f.host(f.identity()));
      await showcasePump(t);
      f.calls.clear();
      await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 300));
      f.actions.first.requestFocus();
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(f.calls, isEmpty);
      f.primary.requestFocus();
      await t.pump();
      f.calls.clear();
      await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 700));
      await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(f.calls, isEmpty);
    });
  });

  testWidgets('without long press OK acts immediately on key down', (t) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(f.host(f.identity(value: f.model(longPress: false))));
      await showcasePump(t);
      f.calls.clear();
      await t.sendKeyDownEvent(LogicalKeyboardKey.gameButtonA);
      expect(f.calls, ['primary']);
      await t.sendKeyUpEvent(LogicalKeyboardKey.gameButtonA);
      expect(f.calls, ['primary']);
    });
  });

  testWidgets(
    'trailer mounts only when available and dispatches exactly once',
    (t) async {
      await showcaseCase(t, (f) async {
        await t.pumpWidget(f.host(f.identity()));
        await showcasePump(t);
        f.calls.clear();
        await t.tap(find.byIcon(Icons.theaters_rounded));
        expect(f.calls, ['trailer']);
        await t.pumpWidget(f.host(f.identity(value: f.model(trailer: false))));
        await showcasePump(t);
        expect(find.byIcon(Icons.theaters_rounded), findsNothing);
      });
    },
  );

  testWidgets(
    'pointer long press emits medium haptic and uses live callbacks',
    (t) async {
      final haptics = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await showcaseCase(t, (f) async {
        await t.pumpWidget(f.host(f.identity()));
        await showcasePump(t);
        await t.pumpWidget(
          f.host(
            f.identity(value: f.model(onHold: () => f.calls.add('new-hold'))),
          ),
        );
        await t.pump();
        f.calls.clear();
        await t.longPress(find.text('Resume'));
        expect(f.calls, ['new-hold']);
        expect(haptics, ['HapticFeedbackType.mediumImpact']);
        f.calls.clear();
        await t.sendKeyDownEvent(LogicalKeyboardKey.select);
        await t.pump(const Duration(milliseconds: 600));
        await t.sendKeyUpEvent(LogicalKeyboardKey.select);
        expect(f.calls, ['new-hold']);
      });
    },
  );
}
