import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_tuner_fixture.dart';

KeyEvent event(
  LogicalKeyboardKey key, {
  bool repeat = false,
  bool up = false,
}) => up
    ? KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: key,
        timeStamp: Duration.zero,
      )
    : repeat
    ? KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: key,
        timeStamp: Duration.zero,
      )
    : KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: key,
        timeStamp: Duration.zero,
      );

void main() {
  testWidgets('D-pad focus centres a mid-list TV dial card', (tester) async {
    await tunerCase(tester, (f) async {
      await f.mount(tester);
      await f.focus(tester, 0);
      for (var index = 0; index < 10; index++) {
        final focus = f.focusWidget(index, tester);
        focus.onKeyEvent!(f.nodes[index], event(LogicalKeyboardKey.arrowRight));
        await tester.pump();
        await tester.pump();
      }
      expect(f.nodes[10].hasPrimaryFocus, isTrue);
      final viewport = tester.getRect(find.byType(ListView));
      expect(
        tester.getCenter(f.card(10)).dx,
        closeTo(viewport.center.dx, 0.01),
        reason: 'D-pad focus centres the card instead of left-aligning it',
      );
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        greaterThan(0),
        reason: 'mid-list centering moves the dial',
      );
    }, count: 40);
  });

  testWidgets(
    'Left and Right repeat, first Left hands off, last Right stops, Up borrows host callback',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        await f.focus(tester, 0);
        final first = f.focusWidget(0, tester);
        expect(
          first.onKeyEvent!(f.nodes[0], event(LogicalKeyboardKey.arrowLeft)),
          KeyEventResult.handled,
        );
        expect(
          f.events.last,
          'sidebar',
          reason: 'first Left hands focus to sidebar',
        );
        first.onKeyEvent!(
          f.nodes[0],
          event(LogicalKeyboardKey.arrowRight, repeat: true),
        );
        await tester.pump();
        await tester.pump();
        expect(
          f.nodes[1].hasPrimaryFocus,
          isTrue,
          reason: 'Right repeat surfs to neighbor',
        );
        final second = f.focusWidget(1, tester);
        second.onKeyEvent!(
          f.nodes[1],
          event(LogicalKeyboardKey.arrowLeft, repeat: true),
        );
        await tester.pump();
        await tester.pump();
        expect(
          f.nodes[0].hasPrimaryFocus,
          isTrue,
          reason: 'Left repeat surfs to neighbor',
        );
        second.onKeyEvent!(f.nodes[1], event(LogicalKeyboardKey.arrowUp));
        expect(f.events.last, 'header', reason: 'Up dispatches host focus');
        final dynamic card = tester.widget(f.card(1));
        expect(
          identical(card.onUp, f.focusHeader),
          isTrue,
          reason: 'Up preserves host function identity',
        );
        await f.focus(tester, f.nodes.length - 1);
        final last = f.focusWidget(f.channels.length - 1, tester);
        last.onKeyEvent!(f.nodes.last, event(LogicalKeyboardKey.arrowRight));
        await tester.pump();
        expect(
          f.nodes.last.hasPrimaryFocus,
          isTrue,
          reason: 'end Right stays on last channel',
        );
        expect(
          last.onKeyEvent!(
            f.nodes.last,
            event(LogicalKeyboardKey.arrowRight, up: true),
          ),
          KeyEventResult.ignored,
        );
        expect(
          last.onKeyEvent!(f.nodes.last, event(LogicalKeyboardKey.keyA)),
          KeyEventResult.ignored,
        );
        expect(
          last.onKeyEvent!(
            f.nodes.last,
            event(LogicalKeyboardKey.enter, repeat: true),
          ),
          KeyEventResult.ignored,
        );
        last.onKeyEvent!(f.nodes.last, event(LogicalKeyboardKey.enter));
        expect(
          f.events.last,
          'play channel-5',
          reason: 'activate key plays once on KeyDown',
        );
      });
    },
  );

  testWidgets(
    'vanished card drops captured press and changed dial index resolves live neighbor',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        await f.focus(tester, 1);
        final old = f.focusWidget(1, tester);
        f.channels.removeAt(1);
        f.events.clear();
        old.onKeyEvent!(f.nodes[1], event(LogicalKeyboardKey.arrowLeft));
        expect(
          f.events,
          isEmpty,
          reason: 'vanished channel press does not hand off',
        );
        await tester.pump();
        expect(
          f.nodes[1].hasPrimaryFocus,
          isTrue,
          reason: 'vanished channel press does not surf',
        );
        final shifted = f.focusWidget(
          2,
          tester,
        ); // original third card has a captured index of 1
        shifted.onKeyEvent!(f.nodes[3], event(LogicalKeyboardKey.arrowRight));
        await tester.pump();
        await tester.pump();
        expect(
          f.nodes[4].hasPrimaryFocus,
          isTrue,
          reason: 'captured index is validated against live list',
        );
      });
    },
  );

  testWidgets(
    'first duplicate wins and didUpdateWidget rebuilds an in-place valid-but-wrong cache',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        final dynamic second = tester.widget(f.card(1));
        second.onFocused();
        expect(
          f.focused.last,
          0,
          reason: 'earlier duplicate wins over displayed copy',
        );
        // Reuse the non-winning duplicate slot. Every cached index stays
        // valid, so lookup self-repair cannot conceal a skipped update.
        f.allChannels[2] = f.channels[2];
        await f.refresh(tester);
        final dynamic third = tester.widget(f.card(2));
        third.onFocused();
        expect(
          f.focused.last,
          2,
          reason:
              'in-place update rebuilds cache even when old index is still valid',
        );
      }, duplicate: true);
    },
  );

  testWidgets('lookup repairs stale cache before host rebuild', (tester) async {
    await tunerCase(tester, (f) async {
      await f.mount(tester);
      f.allChannels.removeAt(0);
      final dynamic second = tester.widget(f.card(1));
      second.onFocused();
      expect(f.focused.last, 0, reason: 'stale lookup reindexes the live list');
    });
  });

  testWidgets(
    '200-channel controller jumps and retries a card delayed beyond first callback',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        await f.focus(tester, 0);
        expect(
          f.nodes[150].context,
          isNull,
          reason: 'target starts recycled off-screen',
        );
        final list = tester.widget<ListView>(find.byType(ListView));
        final scroll = list.controller!;
        late double desired;
        var delayed = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          delayed = f.nodes[150].context == null;
          scroll.jumpTo(desired);
        });
        expect(f.controller!.focusRealIndex(150), isTrue);
        desired = scroll.offset;
        scroll.jumpTo(0);
        await tester.pump();
        expect(
          delayed,
          isTrue,
          reason: 'target remains unattached for first retry callback',
        );
        expect(
          f.nodes[150].hasPrimaryFocus,
          isFalse,
          reason: 'focus waits for attachment',
        );
        await tester.pump();
        await tester.pump();
        expect(
          f.nodes[150].hasPrimaryFocus,
          isTrue,
          reason: 'later retry focuses delayed target',
        );
        expect(f.controller!.focusRealIndex(-1), isFalse);
        expect(f.controller!.focusRealIndex(200), isFalse);
        f.channels.removeAt(149);
        expect(
          f.controller!.focusRealIndex(149),
          isFalse,
          reason: 'channel outside dial rejects controller focus',
        );
      }, count: 200);
    },
  );

  testWidgets('focus retry rejects a node removed from the live host list', (
    tester,
  ) async {
    await tunerCase(tester, (f) async {
      await f.mount(tester);
      await f.focus(tester, 0);
      final target = f.nodes[150];
      var attachedBeforeRemoval = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        attachedBeforeRemoval = target.context != null;
        f.nodes.remove(target);
      });
      expect(f.controller!.focusRealIndex(150), isTrue);
      await tester.pump();
      await tester.pump();
      expect(
        attachedBeforeRemoval,
        isTrue,
        reason: 'target attaches before host removal and deferred focus',
      );
      expect(
        target.hasPrimaryFocus,
        isFalse,
        reason: 'removed host node never receives deferred focus',
      );
    }, count: 200);
  });

  testWidgets('phone controller requests direct focus without dial clients', (
    tester,
  ) async {
    await tunerCase(tester, (f) async {
      f.television = false;
      f.platform = TargetPlatform.android;
      await f.mount(tester, size: const Size(390, 844));
      expect(
        f.controller!.focusRealIndex(0),
        isTrue,
        reason: 'narrow controller accepts a live channel',
      );
      expect(
        f.nodes[0].hasFocus,
        isFalse,
        reason: 'unattached host node has no Focus widget in pager',
      );
    });
  });

  testWidgets(
    'desktop dial has 154 extent, 32 pad, clamped vertical wheel and drag devices',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.television = false;
        f.platform = TargetPlatform.macOS;
        await f.mount(tester, size: const Size(900, 800));
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(
          tester.getTopLeft(f.card(1)).dx - tester.getTopLeft(f.card(0)).dx,
          154,
          reason: 'dial item extent stays 138 plus margins',
        );
        expect(list.padding, const EdgeInsets.symmetric(horizontal: 32));
        final listener = tester
            .widgetList<Listener>(
              find.ancestor(
                of: find.byType(ListView),
                matching: find.byType(Listener),
              ),
            )
            .firstWhere((w) => w.onPointerSignal != null);
        listener.onPointerSignal!(
          const PointerScrollEvent(scrollDelta: Offset(0, 100)),
        );
        expect(
          list.controller!.offset,
          100,
          reason: 'vertical wheel maps to horizontal offset',
        );
        listener.onPointerSignal!(
          const PointerScrollEvent(scrollDelta: Offset(50, 0)),
        );
        expect(
          list.controller!.offset,
          100,
          reason: 'horizontal wheel is left to Scrollable',
        );
        listener.onPointerSignal!(
          const PointerScrollEvent(scrollDelta: Offset(0, 10000)),
        );
        expect(
          list.controller!.offset,
          list.controller!.position.maxScrollExtent,
          reason: 'wheel clamps at end',
        );
        final config = tester.widget<ScrollConfiguration>(
          find
              .ancestor(
                of: find.byType(ListView),
                matching: find.byType(ScrollConfiguration),
              )
              .first,
        );
        expect(
          config.behavior.dragDevices,
          containsAll([
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          ]),
        );
      }, count: 20);
    },
  );
}
