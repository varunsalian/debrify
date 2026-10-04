import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

void main() {
  testWidgets(
    'identity orders all eight actions and dispatches each callback',
    (t) async {
      await showcaseCase(t, (f) async {
        await t.pumpWidget(
          f.host(f.identity(value: f.model(allActions: true))),
        );
        await showcasePump(t);
        const labels = [
          'Watchlist',
          'Trakt',
          'Simkl',
          'MDBList',
          'Trailer',
          'Sources',
          'Explore',
          'More',
        ];
        const callbacks = [
          'watchlist',
          'trackers',
          'secondary',
          'tertiary',
          'trailer',
          'browse',
          'explore',
          'more',
        ];
        final circles = [
          for (final node in f.actions)
            find.byWidgetPredicate((w) => w is Focus && w.focusNode == node),
        ];
        expect(circles, hasLength(8));
        for (var i = 0; i < circles.length; i++) {
          expect(circles[i], findsOneWidget);
          if (i > 0) {
            expect(
              t.getCenter(circles[i]).dx,
              greaterThan(t.getCenter(circles[i - 1]).dx),
            );
          }
        }
        for (var i = 0; i < circles.length; i++) {
          f.actions[i].requestFocus();
          await showcasePump(t);
          expect(
            find.descendant(of: circles[i], matching: find.text(labels[i])),
            findsOneWidget,
          );
          f.calls.clear();
          await t.tap(circles[i]);
          expect(f.calls, [callbacks[i]]);
          f.calls.clear();
          await t.sendKeyEvent(LogicalKeyboardKey.select);
          expect(f.calls, [callbacks[i]]);
        }
      }, television: true);
    },
  );

  testWidgets('page action count mounts all eight identity nodes', (t) async {
    const size = Size(1920, 1080);
    await showcaseCase(
      t,
      (f) async {
        await t.pumpWidget(
          f.host(f.page(value: f.model(allActions: true)), size: size),
        );
        await showcasePump(t);
        final nodes = t
            .widgetList<Focus>(find.byType(Focus))
            .where(
              (w) =>
                  w.focusNode?.debugLabel?.startsWith('showcase-act-') ?? false,
            );
        expect(nodes, hasLength(8));
        expect(nodes.map((w) => w.focusNode!.debugLabel), [
          for (var i = 0; i < 8; i++) 'showcase-act-$i',
        ]);
      },
      size: size,
      television: true,
    );
  });
}
