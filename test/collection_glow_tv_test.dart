import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/collections/collection_focus_glow.dart';

void main() {
  testWidgets(
    'TV cached halo preserves settled pixels and skips disabled effects',
    (tester) async {
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() {
        debugDisableShadows = oldShadows;
        PlatformUtil.debugSetAndroidTvCached(null);
      });
      final key = GlobalKey();
      Widget view({
        bool active = true,
        bool enabled = true,
        bool reduced = false,
      }) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: CollectionFocusGlow(
                  active: active,
                  enabled: enabled,
                  child: const SizedBox(
                    width: 200,
                    height: 120,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<List<int>> pixels() async => (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final result = bytes!.buffer.asUint8List().toList();
        image.dispose();
        return result;
      }))!;
      PlatformUtil.debugSetAndroidTvCached(false);
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      final original = await pixels();
      PlatformUtil.debugSetAndroidTvCached(true);
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      expect(await pixels(), original);
      await tester.pumpWidget(view(active: false));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      await tester.pumpWidget(view(reduced: true));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
        Duration.zero,
      );
      await tester.pumpWidget(view(enabled: false));
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);
      debugDisableShadows = oldShadows;
    },
  );
}
