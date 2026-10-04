import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_fixture.dart';

KeyEvent press(LogicalKeyboardKey key, {bool repeat = false}) => repeat
    ? KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: key,
        timeStamp: Duration.zero,
      )
    : KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: key,
        timeStamp: Duration.zero,
      );

void main() {
  testWidgets(
    'two-pane keys cross RIGHT LEFT repeat UP to back and DOWN stays in pane',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.xtream = true;
        f.television = true;
        f.severalSeasons = true;
        await f.mount(t, style: 'classic');
        final info = f.access['infoPane'] as FocusScopeNode;
        final episodes = f.access['episodesPane'] as FocusScopeNode;
        final entry = f.access['leftEntry'] as FocusNode;
        final back = f.access['backButton'] as FocusNode;
        final infoWidget = t
            .widgetList<FocusScope>(find.byType(FocusScope))
            .singleWhere((w) => w.focusNode == info);
        final episodesWidget = t
            .widgetList<FocusScope>(find.byType(FocusScope))
            .singleWhere((w) => w.focusNode == episodes);
        entry.requestFocus();
        await t.pump();
        await t.pump();

        expect(info.hasFocus, true);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pump();
        expect(FocusManager.instance.primaryFocus, same(back));
        entry.requestFocus();
        await t.pump();
        for (var key = 0; key < 8 && !episodes.hasFocus; key++) {
          expect(
            infoWidget.onKeyEvent!(
              info,
              press(LogicalKeyboardKey.arrowRight, repeat: true),
            ),
            KeyEventResult.handled,
          );
          await t.pump();
          await t.pump();
        }
        expect(episodes.hasFocus, true);
        // Season-header controls let the event reach the pane handler.
        final header = episodes.traversalDescendants.firstWhere(
          (n) => n.debugLabel == 'catalog-ep-season',
        );
        header.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pump();
        expect(info.hasFocus, true);
        header.requestFocus();
        await t.pump();
        for (var key = 0; key < 8 && !info.hasFocus; key++) {
          expect(
            episodesWidget.onKeyEvent!(
              episodes,
              press(LogicalKeyboardKey.arrowLeft, repeat: true),
            ),
            KeyEventResult.handled,
          );
          await t.pump();
        }
        expect(FocusManager.instance.primaryFocus, same(entry));
        expect(
          infoWidget.onKeyEvent!(info, press(LogicalKeyboardKey.arrowUp)),
          KeyEventResult.handled,
        );
        await t.pump();
        expect(FocusManager.instance.primaryFocus, same(back));
        info.traversalDescendants.last.requestFocus();
        await t.pump();
        expect(
          infoWidget.onKeyEvent!(
            info,
            press(LogicalKeyboardKey.arrowDown, repeat: true),
          ),
          KeyEventResult.handled,
        );
        await t.pump();
        expect(info.hasFocus, true);
        expect(episodes.hasFocus, false);
        expect(
          infoWidget.onKeyEvent!(
            info,
            const KeyUpEvent(
              physicalKey: PhysicalKeyboardKey.arrowDown,
              logicalKey: LogicalKeyboardKey.arrowDown,
              timeStamp: Duration.zero,
            ),
          ),
          KeyEventResult.ignored,
        );
      });
    },
  );
  for (final movie in [false, true]) {
    testWidgets(
      'action row LEFT stops and last RIGHT ${movie ? 'stops for movie' : 'crosses for wide series'}',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.television = true;
          f.xtream = !movie;
          if (movie) {
            f.item = const StremioMeta(
              id: 'original-focus-movie',
              type: 'movie',
              name: 'Original Focus Movie',
            );
          }
          await f.mount(t, style: 'classic');
          final row = find.byWidgetPredicate(
            (w) => w is Focus && w.child is Wrap && w.onKeyEvent != null,
          );
          final widget = t.widget<Focus>(row);
          final wrap = find
              .descendant(of: row, matching: find.byType(Wrap))
              .first;
          final node = Focus.of(t.element(wrap));
          final buttons = node.traversalDescendants.toList()
            ..sort((a, b) {
              final y = (a.rect.center.dy / 24).round().compareTo(
                (b.rect.center.dy / 24).round(),
              );
              return y != 0 ? y : a.rect.center.dx.compareTo(b.rect.center.dx);
            });
          if (movie) {
            expect(
              FocusManager.instance.primaryFocus,
              same(f.access['leftEntry']),
            );
          }
          buttons.first.requestFocus();
          await t.pump();
          expect(
            widget.onKeyEvent!(node, press(LogicalKeyboardKey.arrowLeft)),
            KeyEventResult.handled,
          );
          await t.pump();
          expect(FocusManager.instance.primaryFocus, same(buttons.first));
          for (var i = 1; i < buttons.length; i++) {
            expect(
              widget.onKeyEvent!(
                node,
                press(LogicalKeyboardKey.arrowRight, repeat: true),
              ),
              KeyEventResult.handled,
            );
            await t.pump();
            expect(FocusManager.instance.primaryFocus, same(buttons[i]));
          }
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await t.pump();
          if (movie) {
            expect(FocusManager.instance.primaryFocus, same(buttons.last));
          } else {
            expect((f.access['episodesPane'] as FocusScopeNode).hasFocus, true);
          }
        });
      },
    );
  }
  testWidgets(
    'recommendation rail caps ten and edge traps handle down and repeat dispatch',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.television = true;
        f.xtream = true;
        f.recommendations = List.generate(
          12,
          (i) => StremioMeta(
            id: 'original-rec-$i',
            type: 'series',
            name: 'Original Rec $i',
          ),
        );
        await f.mount(t, style: 'classic');
        final cards = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_RecCard',
        );
        expect(cards, findsNWidgets(10));
        final traps = t
            .widgetList(
              find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_RailEdgeTrap',
              ),
            )
            .toList();
        dynamic first = traps.first;
        dynamic last = traps.last;
        expect(first.trapLeft, true);
        expect(last.trapRight, true);
        final firstCard = cards.evaluate().first.widget;
        final cardContext = t.element(
          find
              .descendant(
                of: find.byWidget(firstCard),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        final railNode = Focus.of(cardContext);
        railNode.requestFocus();
        await t.pump();
        expect(FocusManager.instance.primaryFocus, same(railNode));
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pump();
        expect(FocusManager.instance.primaryFocus, same(railNode));
        for (final pair in [
          (first, LogicalKeyboardKey.arrowLeft),
          (last, LogicalKeyboardKey.arrowRight),
        ]) {
          final focus = t.widget<Focus>(
            find
                .descendant(
                  of: find.byWidget(pair.$1),
                  matching: find.byType(Focus),
                )
                .first,
          );
          expect(
            focus.onKeyEvent!(
              f.access['infoPane'] as FocusNode,
              press(pair.$2, repeat: true),
            ),
            KeyEventResult.handled,
          );
          expect(
            focus.onKeyEvent!(
              f.access['infoPane'] as FocusNode,
              press(LogicalKeyboardKey.arrowDown),
            ),
            KeyEventResult.ignored,
          );
        }
        await t.pump();
        expect((f.access['episodesPane'] as FocusScopeNode).hasFocus, true);
      });
    },
  );
  testWidgets(
    'panel left-edge callback follows primary and source action availability',
    (t) async {
      for (final source in [false, true]) {
        await mergedDetailCase(t, (f) async {
          f.xtream = true;
          f.showPrimary = false;
          f.canSelectSource = source;
          await f.mount(t, style: 'classic');
          expect(f.panel.onFocusLeftEdge, source ? isNotNull : isNull);
          if (source) {
            f.panel.onFocusLeftEdge!();
            await t.pump();
            expect(
              FocusManager.instance.primaryFocus,
              same(f.access['leftEntry']),
            );
          }
        });
      }
    },
  );
}
