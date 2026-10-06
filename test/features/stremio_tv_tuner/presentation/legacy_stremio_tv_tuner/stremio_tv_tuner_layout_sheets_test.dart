import 'package:debrify/theme/premium_looks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_tuner_fixture.dart';

Future<void> openActions(
  WidgetTester tester,
  StremioTvTunerFixture f, {
  int index = 1,
}) async {
  if (f.cards.evaluate().isNotEmpty) {
    final dynamic card = tester.widget(f.card(index));
    card.onLongPress();
  } else {
    final detector = tester.widget<GestureDetector>(
      find
          .ancestor(of: f.stages.first, matching: find.byType(GestureDetector))
          .first,
    );
    detector.onLongPress!();
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final (tv, width, wide) in [
    (false, 899.0, false),
    (false, 900.0, true),
    (true, 700.0, true),
  ]) {
    testWidgets('layout tv=$tv width=$width wide=$wide', (tester) async {
      await tunerCase(tester, (f) async {
        f.television = tv;
        f.platform = TargetPlatform.macOS;
        await f.mount(tester, size: Size(width, 844));
        expect(
          find.byType(PageView),
          wide ? findsNothing : findsOneWidget,
          reason: 'wide threshold and TV override stay exact',
        );
        expect(f.cards, wide ? findsWidgets : findsNothing);
        if (!wide) {
          final pager = tester.widget<PageView>(find.byType(PageView));
          expect(pager.scrollDirection, Axis.vertical);
          f.events.clear();
          pager.onPageChanged!(1);
          expect(f.events.take(2), [
            'load channel-1',
            'load channel-2',
          ], reason: 'pager preloads current then next');
          expect(f.focused.last, 1);
          expect(find.text('Channels'), findsOneWidget);
          expect(find.text('Details'), findsOneWidget);
        }
      });
    });
  }
  testWidgets(
    'touch dial centre ring updates before Stage and snaps only once at depth zero',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.television = false;
        f.platform = TargetPlatform.android;
        f.autoRefresh = true;
        await f.mount(tester, size: const Size(1280, 800));
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(
          list.padding,
          const EdgeInsets.symmetric(horizontal: (1280 - 154) / 2),
        );
        final dynamic first = tester.widget(f.card(0));
        expect(first.touchSelect, isTrue);
        expect(first.centredId.value, 'channel-0');
        list.controller!.jumpTo(154 * 2 + 30);
        await tester.pump();
        final dynamic third = tester.widget(f.card(2));
        expect(
          third.centredId.value,
          'channel-2',
          reason: 'centre ring follows scroll immediately',
        );
        expect(
          find.descendant(
            of: f.stages,
            matching: find.text('Broadcast channel-0'),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 180));
        expect(
          find.descendant(
            of: f.stages,
            matching: find.text('Broadcast channel-2'),
          ),
          findsOneWidget,
          reason: 'Stage follows settled centre',
        );
        final notification = tester
            .widget<NotificationListener<ScrollNotification>>(
              find
                  .ancestor(
                    of: find.byType(ListView),
                    matching: find.byWidgetPredicate(
                      (w) => w is NotificationListener<ScrollNotification>,
                    ),
                  )
                  .first,
            );
        final context = tester.element(find.byType(ListView));
        notification.onNotification!(
          ScrollEndNotification(
            metrics: list.controller!.position,
            context: context,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump();
        expect(
          list.controller!.offset,
          308,
          reason: 'touch snap lands on 154 extent at 220ms',
        );
        await tester.pump(const Duration(milliseconds: 440));
        expect(
          list.controller!.offset,
          308,
          reason: 'snap completion does not loop',
        );
      });
    },
  );
  testWidgets(
    'touch tap plays without focus, hover does not light a second card; desktop hover shows hint',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.television = false;
        f.platform = TargetPlatform.android;
        await f.mount(tester, size: const Size(1280, 800));
        await tester.tap(f.card(1));
        await tester.pump();
        expect(f.events, contains('play channel-1'));
        expect(
          f.nodes[1].hasFocus,
          isFalse,
          reason: 'touch tap does not request focus',
        );
        final mouse = tester.widget<MouseRegion>(
          find
              .descendant(of: f.card(1), matching: find.byType(MouseRegion))
              .first,
        );
        mouse.onEnter!(const PointerEnterEvent());
        await tester.pump();
        expect(
          find.text('RIGHT-CLICK'),
          findsNothing,
          reason: 'touch hover never shows desktop hint',
        );
        final scale = tester.widget<AnimatedScale>(
          find
              .descendant(of: f.card(1), matching: find.byType(AnimatedScale))
              .first,
        );
        expect(
          scale.scale,
          1,
          reason: 'touch hover never lights inactive card',
        );
        f.platform = TargetPlatform.macOS;
        await f.mount(tester, size: const Size(1280, 800));
        final desktop = tester.widget<MouseRegion>(
          find
              .descendant(of: f.card(1), matching: find.byType(MouseRegion))
              .first,
        );
        desktop.onEnter!(const PointerEnterEvent());
        await tester.pump();
        expect(find.text('RIGHT-CLICK'), findsOneWidget);
        desktop.onExit!(const PointerExitEvent());
        await tester.pump();
        expect(find.text('RIGHT-CLICK'), findsNothing);
      });
    },
  );
  testWidgets(
    'Down opens quick actions with haptic, captured theme and conditional local tiles',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        await f.focus(tester, 1);
        final focus = f.focusWidget(1, tester);
        focus.onKeyEvent!(
          f.nodes[1],
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.arrowDown,
            logicalKey: LogicalKeyboardKey.arrowDown,
            timeStamp: Duration.zero,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Play this channel now'),
          findsOneWidget,
          reason: 'Down opens actions',
        );
        expect(f.haptics, ['HapticFeedbackType.mediumImpact']);
        expect(find.text('View details'), findsOneWidget);
        expect(find.text('Channel guide'), findsOneWidget);
        expect(find.text('Edit local catalog'), findsOneWidget);
        expect(find.text('Copy catalog JSON'), findsOneWidget);
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(
          sheet.backgroundColor,
          PremiumLooks.byId(f.look)!.build().stremioTv.sheetBg,
          reason: 'sheet captures tuner surface theme',
        );
        await tester.tap(find.text('Edit local catalog'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(f.events, contains('edit channel-1'));
        expect(
          find.byType(BottomSheet),
          findsNothing,
          reason: 'tile pops sheet before host action completes',
        );
        f.hideNowPlaying = true;
        f.localCallbacks = false;
        await f.refresh(tester);
        await openActions(tester, f);
        expect(
          find.text('View details'),
          findsNothing,
          reason: 'hidden mode omits Details tile',
        );
        expect(find.text('Channel guide'), findsNothing);
        expect(find.text('Edit local catalog'), findsNothing);
        expect(find.text('Copy catalog JSON'), findsNothing);
        f.navigatorKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      });
    },
  );
  for (final (label, action) in [
    ('Play this channel now', 'play'),
    ('View details', 'detail'),
    ('Channel guide', 'guide'),
    ('Add to favorites', 'favorite'),
    ('Copy catalog JSON', 'export'),
  ]) {
    testWidgets('quick action $action pops and dispatches channel', (
      tester,
    ) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        await openActions(tester, f);
        await tester.tap(find.text(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(f.events, contains('$action channel-1'));
        expect(find.byType(BottomSheet), findsNothing);
      });
    });
  }
  testWidgets(
    'channel list ticks at 5s, jumps pager, and cancels timer on close',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.television = false;
        f.platform = TargetPlatform.android;
        await f.mount(tester, size: const Size(390, 844));
        await tester.tap(find.text('Channels'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet),
        );
        expect(
          (sheet.initialChildSize, sheet.minChildSize, sheet.maxChildSize),
          (0.78, 0.45, 0.96),
        );
        expect(
          f.periodicTimers.where((p) => p.$2.isActive).map((p) => p.$1),
          [const Duration(seconds: 5)],
          reason: 'one sheet-owned 5s timer',
        );
        f.service.calls.clear();
        await tester.pump(const Duration(seconds: 4));
        expect(f.service.calls, isEmpty);
        await tester.pump(const Duration(seconds: 1));
        expect(
          f.service.calls,
          isNotEmpty,
          reason: 'sheet tick refreshes rows at 5s',
        );
        await tester.tap(find.text('Local Cinema'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          f.focused.last,
          1,
          reason: 'row tap jumps pager and selects channel',
        );
        expect(
          f.periodicTimers.where((p) => p.$2.isActive),
          isEmpty,
          reason: 'no active periodic Timer after channel-list close',
        );
      });
    },
  );
  testWidgets(
    'null broadcast distinguishes loading from no broadcast and hidden state',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.service.now['channel-0'] = null;
        f.loading.add('channel-0');
        await f.mount(tester);
        expect(
          find.descendant(of: f.stages, matching: find.text('Tuning in…')),
          findsOneWidget,
        );
        f.loading.clear();
        await f.refresh(tester);
        expect(find.text('No broadcast on this channel'), findsOneWidget);
        f.service.now['channel-0'] = tunerPlaying('channel-0');
        f.hideNowPlaying = true;
        await f.refresh(tester);
        expect(
          find.text('Now playing hidden — tune in to reveal'),
          findsOneWidget,
        );
        expect(find.text('Broadcast channel-0'), findsNothing);
      });
    },
  );
  testWidgets(
    'phone Stage tap plays and description sheet captures calling theme',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.television = false;
        f.platform = TargetPlatform.android;
        f.look = 'console';
        await f.mount(tester, size: const Size(390, 844));
        final detector = tester.widget<GestureDetector>(
          find
              .ancestor(
                of: f.stages.first,
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        detector.onTap!();
        expect(
          f.events.last,
          'play channel-0',
          reason: 'phone Stage tap plays its channel',
        );
        expect(
          find.text('Read more'),
          findsOneWidget,
          reason: 'long synopsis exposes description sheet',
        );
        await tester.tap(find.text('Read more'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(
          sheet.backgroundColor,
          PremiumLooks.byId(f.look)!.build().stremioTv.sheetBg,
          reason: 'description sheet captures calling element theme',
        );
        expect(
          find.text(f.service.now['channel-0']!.item.description!.trim()),
          findsWidgets,
        );
        f.navigatorKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      });
    },
  );
}
