import 'package:debrify/services/local_bound_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(720, 320)]) {
    testWidgets('movie source picker fits $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold(body: Text('Detail'));
            },
          ),
        ),
      );
      final selection = LocalBoundSourceService.pickMovieSource(
        page,
        title: 'Movie',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        Focus.of(tester.element(find.text('Pick Video File'))).hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('Pick Folder'))).hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(await selection, isNull);
    });
  }
}
