import 'package:debrify/widgets/home/snowy_mountain_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TV snow paints at 30 FPS without rebuilding the background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SnowyMountainBackground(lowPower: true)),
    );
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(SnowyMountainBackground),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    var repaints = 0;
    void onPaint() => repaints++;
    painter.addListener(onPaint);
    final imageElement = tester.element(find.byType(Image));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(repaints, inInclusiveRange(29, 31));
    expect(tester.element(find.byType(Image)), same(imageElement));
    painter.removeListener(onPaint);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'background decode preserves cover resolution without upscaling',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<int?> decodeAt(Size size) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          const MaterialApp(home: SnowyMountainBackground(lowPower: true)),
        );
        return (tester.widget<Image>(find.byType(Image)).image as ResizeImage)
            .width;
      }

      addTearDown(tester.view.resetPhysicalSize);
      expect(await decodeAt(const Size(960, 540)), 960);
      expect(await decodeAt(const Size(1920, 1080)), 1672);
      expect(await decodeAt(const Size(400, 800)), 1422);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'snow pauses for reduced motion, hidden routes and app suspension',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      Widget host({bool reduced = false, bool visible = true}) => MaterialApp(
        navigatorKey: navigator,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: visible,
            child: const SnowyMountainBackground(),
          ),
        ),
      );

      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(host(reduced: true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(host(visible: false));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(host());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Settings')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
