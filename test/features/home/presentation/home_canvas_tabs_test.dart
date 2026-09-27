import 'package:debrify/features/home/presentation/home_canvas_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (width, visible, more) in [
    (150.0, <String>[], '+5 more'),
    (313.0, ['C'], '+2 more'),
    (509.0, ['B', 'C'], '+2 more'),
    (901.0, ['B', 'C', 'D', 'E'], null),
  ]) {
    testWidgets('width $width preserves the active rail window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final read = <int>{};
      await tester.pumpWidget(
        _host(
          width: width,
          active: 2,
          titleAt: (i) {
            read.add(i);
            return ['A', 'B', 'C', 'D', 'E'][i];
          },
        ),
      );
      for (final title in ['A', 'B', 'C', 'D', 'E']) {
        expect(
          find.text(title),
          visible.contains(title) ? findsOneWidget : findsNothing,
        );
      }
      if (more != null) {
        expect(find.text(more), findsOneWidget);
      } else {
        expect(find.textContaining('more'), findsNothing);
      }
      expect(
        read,
        visible.map((title) => title.codeUnitAt(0) - 'A'.codeUnitAt(0)).toSet(),
      );
      if (visible.isNotEmpty) {
        expect(
          tester.widget<Text>(find.text('C')).style!.fontWeight,
          FontWeight.w800,
        );
      }
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'first and last rails stay in the window; empty titles keep their slots',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final titles = ['A', 'B', 'C', 'D', 'E'];
      await tester.pumpWidget(
        _host(width: 901, active: 0, titleAt: (i) => titles[i]),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('E'), findsNothing);
      expect(find.text('+1 more'), findsOneWidget);
      await tester.pumpWidget(
        _host(width: 901, active: 4, titleAt: (i) => titles[i]),
      );
      expect(find.text('A'), findsNothing);
      expect(
        tester.widget<Text>(find.text('E')).style!.fontWeight,
        FontWeight.w800,
      );
      titles[1] = '';
      await tester.pumpWidget(
        _host(width: 509, active: 2, titleAt: (i) => titles[i]),
      );
      expect(find.text('B'), findsNothing);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
      expect(find.text('D'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared tab clearance scales text above the chevron floor', (
    tester,
  ) async {
    final heights = <double>[];
    for (final scale in [.5, 1.0, 2.0]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) {
              heights.add(homeCanvasTabsHeight(context));
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(heights, [27, 27, 42.25]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tabs remain display-only and do not intercept rail navigation', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final keys = <LogicalKeyboardKey>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: node,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) keys.add(event.logicalKey);
            return KeyEventResult.handled;
          },
          child: SizedBox(
            width: 400,
            child: Builder(
              builder: (context) => buildHomeCanvasTabs(
                context: context,
                railCount: 1,
                active: 0,
                titleAt: (_) => 'Rail',
              ),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(keys, [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp]);
    expect(node.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required double width,
  required int active,
  required String Function(int) titleAt,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: Builder(
        builder: (context) => buildHomeCanvasTabs(
          context: context,
          railCount: 5,
          active: active,
          titleAt: titleAt,
        ),
      ),
    ),
  ),
);
