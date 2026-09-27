import 'dart:ui';

import 'package:debrify/features/home/presentation/home_art_poster.dart';
import 'package:debrify/widgets/home/card_focus_rise.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('activates once on release of ${key.keyLabel}', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var opened = 0;
      var focused = 0;
      await tester.pumpWidget(
        _host(_card(node, onOpen: () => opened++, onFocused: () => focused++)),
      );
      node.requestFocus();
      await tester.pump();
      expect(focused, 1);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      expect(opened, 0);
      await tester.sendKeyUpEvent(key);
      expect(opened, 1);
      await tester.pumpWidget(const SizedBox());
      // The card borrows this node; its caller may reuse it after removal.
      await tester.pumpWidget(
        _host(Focus(focusNode: node, child: const Text('Next'))),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('losing focus cancels an unfinished activation', (tester) async {
    final first = FocusNode();
    final other = FocusNode();
    addTearDown(first.dispose);
    addTearDown(other.dispose);
    var opened = 0;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            _card(first, onOpen: () => opened++),
            Focus(focusNode: other, child: const Text('Other')),
          ],
        ),
      ),
    );
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    other.requestFocus();
    await tester.pump();
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(opened, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hover and tap preserve optional title and live/progress content',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var opened = 0;
      await tester.pumpWidget(
        _host(
          _card(
            node,
            onOpen: () => opened++,
            showTitle: false,
            live: true,
            progress: .4,
          ),
        ),
      );
      expect(find.text('Favourite'), findsNothing);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.byIcon(Icons.live_tv_rounded), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        .4,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.byType(HomeArtPoster)));
      await tester.pump();
      expect(
        tester.widget<CardFocusRise>(find.byType(CardFocusRise)).active,
        isTrue,
      );
      await tester.tap(find.byType(HomeArtPoster));
      expect(opened, 1);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(
        tester.widget<CardFocusRise>(find.byType(CardFocusRise)).active,
        isFalse,
      );
      await mouse.removePointer();
      await tester.pumpWidget(_host(_card(node, onOpen: () => opened++)));
      expect(find.text('Favourite'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final tv in [false, true]) {
    testWidgets(
      'scrolls into view over the existing ${tv ? 140 : 260}ms interval',
      (tester) async {
        final node = FocusNode();
        final scroll = ScrollController();
        addTearDown(node.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 300,
              height: 400,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 600),
                    _card(node, onOpen: () {}, tv: tv),
                    const SizedBox(height: 600),
                  ],
                ),
              ),
            ),
          ),
        );
        node.requestFocus();
        await tester.pump();
        // Start the animation scheduled by the post-frame focus callback.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        final midway = scroll.offset;
        expect(midway, greaterThan(0));
        await tester.pump(Duration(milliseconds: (tv ? 140 : 260) - 70));
        expect(scroll.offset, greaterThan(midway));
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        expect(
          tester.getCenter(find.byType(HomeArtPoster)).dy,
          closeTo(viewport.center.dy, .01),
        );
        final settled = scroll.offset;
        await tester.pump(const Duration(milliseconds: 100));
        expect(scroll.offset, settled);
        await tester.pumpWidget(const SizedBox());
        expect(scroll.hasClients, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Widget _card(
  FocusNode node, {
  required VoidCallback onOpen,
  VoidCallback? onFocused,
  bool showTitle = true,
  bool live = false,
  double? progress,
  bool tv = true,
}) => SizedBox(
  width: 100,
  height: 200,
  child: HomeArtPoster(
    imageUrl: null,
    title: 'Favourite',
    badge: '7',
    focusNode: node,
    isTelevision: tv,
    onOpen: onOpen,
    onFocused: onFocused,
    showTitle: showTitle,
    live: live,
    progress: progress,
  ),
);
