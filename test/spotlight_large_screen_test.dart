import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:debrify/widgets/home/spotlight_card_trailer.dart';
import 'package:debrify/utils/spotlight_interaction_policy.dart';

void main() {
  test(
    'tablets and desktop windows qualify without enabling landscape phones',
    () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(
          spotlightUsesRichCards(
            viewport: const Size(1024, 768),
            platform: platform,
          ),
          isTrue,
        );
        expect(
          spotlightUsesRichCards(
            viewport: const Size(844, 390),
            platform: platform,
          ),
          isFalse,
        );
        expect(
          spotlightUsesRichCards(
            viewport: const Size(500, 768),
            platform: platform,
          ),
          isFalse,
        );
      }
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          spotlightUsesRichCards(
            viewport: const Size(1000, 500),
            platform: platform,
          ),
          isTrue,
        );
        expect(
          spotlightUsesRichCards(
            viewport: const Size(500, 800),
            platform: platform,
          ),
          isFalse,
        );
      }
    },
  );

  late FocusNode hero;
  late List<FocusNode> nodes;
  var opened = 0;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    hero = FocusNode();
    nodes = List.generate(10, (_) => FocusNode());
    opened = 0;
  });
  tearDown(() {
    hero.dispose();
    for (final node in nodes) {
      node.dispose();
    }
  });
  Widget host({
    SpotlightCardShape shape = SpotlightCardShape.poster,
    bool trailers = false,
    bool reduced = false,
    bool expand = true,
    int shelfCount = 1,
    int itemCount = 10,
    TargetPlatform platform = TargetPlatform.iOS,
  }) => MaterialApp(
    theme: ThemeData(platform: platform),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: SpotlightBoard(
              hero: const [],
              heroNode: hero,
              heroAddon: null,
              onHeroOpen: (_, __) {},
              dpad: false,
              shelvesOnly: true,
              largeScreenInteractions: true,
              expandFocusedCard: expand,
              trailersEnabled: trailers,
              sections: [
                for (var shelf = 0; shelf < shelfCount; shelf++)
                  SpotlightShelf(
                    id: 'movies$shelf',
                    title: 'Movies $shelf',
                    nodes: nodes.sublist(shelf * 10, shelf * 10 + 10),
                    items: List.generate(
                      itemCount,
                      (index) => SpotlightCard(
                        shape: shape,
                        metadata: StremioMeta(
                          id: 'title${shelf * 10 + index}',
                          type: 'movie',
                          name: 'Title ${shelf * 10 + index}',
                          description: 'Description ${shelf * 10 + index}',
                        ),
                        title: 'Title ${shelf * 10 + index}',
                        onOpen: () => opened++,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Finder active() => find.byWidgetPredicate(
    (widget) => widget is ParallaxFocus && widget.focused,
  );
  Finder horizontal() => find.byWidgetPredicate(
    (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
  );
  void surface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'tablet scrolling moves one visual focus and a single tap still opens',
    (tester) async {
      surface(tester, const Size(1024, 768));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(active(), findsOneWidget);
      final first = tester.element(active());
      expect(nodes.any((node) => node.hasFocus), isFalse);
      await tester.drag(horizontal(), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(active(), findsOneWidget);
      expect(tester.element(active()), isNot(same(first)));
      final visibleCard = tester.getRect(active()).intersect(
        Offset.zero & const Size(1024, 768),
      );
      await tester.tapAt(visibleCard.center);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('short tablet row keeps its scroll extent during a swipe', (
    tester,
  ) async {
    surface(tester, const Size(1024, 768));
    await tester.pumpWidget(host(itemCount: 4));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(of: horizontal(), matching: find.byType(Scrollable))
          .first,
    );
    final extent = scrollable.position.maxScrollExtent;
    expect(extent, greaterThan(0));
    final drag = await tester.startGesture(tester.getCenter(horizontal()));
    await drag.moveBy(const Offset(-30, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      scrollable.position.maxScrollExtent,
      greaterThanOrEqualTo(extent - 1),
    );
    expect(scrollable.position.pixels, greaterThan(0));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('overlapping horizontal rows stay moving until both end', (
    tester,
  ) async {
    surface(tester, const Size(1200, 1000));
    nodes.addAll(List.generate(10, (_) => FocusNode()));
    await tester.pumpWidget(host(shelfCount: 2, trailers: true));
    await tester.pumpAndSettle();
    final rows = tester
        .stateList<ScrollableState>(
          find.descendant(of: horizontal(), matching: find.byType(Scrollable)),
        )
        .toList();
    expect(rows, hasLength(2));
    for (final row in rows) {
      ScrollStartNotification(
        metrics: row.position,
        context: row.context,
        dragDetails: DragStartDetails(),
      ).dispatch(row.context);
    }
    await tester.pump();
    ScrollEndNotification(
      metrics: rows[0].position,
      context: rows[0].context,
    ).dispatch(rows[0].context);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SpotlightCardTrailer), findsNothing);
    ScrollEndNotification(
      metrics: rows[1].position,
      context: rows[1].context,
    ).dispatch(rows[1].context);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SpotlightCardTrailer), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'desktop height resize does not select a card without pointer or focus',
    (tester) async {
      surface(tester, const Size(1200, 1000));
      nodes.addAll(List.generate(20, (_) => FocusNode()));
      await tester.pumpWidget(
        host(shelfCount: 3, trailers: true, platform: TargetPlatform.windows),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(active(), findsNothing);
      tester.view.physicalSize = const Size(1200, 400);
      await tester.pumpAndSettle();
      expect(active(), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tablet fling advances and settles without losing selection', (
    tester,
  ) async {
    surface(tester, const Size(1024, 768));
    await tester.pumpWidget(host(trailers: true));
    await tester.pumpAndSettle();
    final row = tester.state<ScrollableState>(
      find
          .descendant(of: horizontal(), matching: find.byType(Scrollable))
          .first,
    );
    await tester.fling(horizontal(), const Offset(-500, 0), 1500);
    await tester.pump();
    expect(find.byType(SpotlightCardTrailer), findsNothing);
    await tester.pumpAndSettle();
    expect(row.position.pixels, greaterThan(200));
    expect(active(), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SpotlightCardTrailer), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'removing a scrolling row releases previews on the remaining row',
    (tester) async {
      surface(tester, const Size(1200, 1000));
      nodes.addAll(List.generate(10, (_) => FocusNode()));
      await tester.pumpWidget(host(shelfCount: 2, trailers: true));
      await tester.pumpAndSettle();
      final row = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: horizontal(),
              matching: find.byType(Scrollable),
            ),
          )
          .last;
      ScrollStartNotification(
        metrics: row.position,
        context: row.context,
        dragDetails: DragStartDetails(),
      ).dispatch(row.context);
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(shelfCount: 1, trailers: true));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(SpotlightCardTrailer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelled tablet drag allows scrolling and preview to resume', (
    tester,
  ) async {
    surface(tester, const Size(1024, 768));
    await tester.pumpWidget(host(trailers: true));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(tester.getCenter(horizontal()));
    await drag.moveBy(const Offset(-30, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-150, 0));
    await tester.pump();
    await drag.cancel();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SpotlightCardTrailer), findsOneWidget);
    final row = tester.state<ScrollableState>(
      find
          .descendant(of: horizontal(), matching: find.byType(Scrollable))
          .first,
    );
    final before = row.position.pixels;
    await tester.drag(horizontal(), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(row.position.pixels, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all four cards can reach the reading cursor by touch', (
    tester,
  ) async {
    surface(tester, const Size(1024, 768));
    await tester.pumpWidget(host(itemCount: 4));
    await tester.pumpAndSettle();
    for (var index = 1; index < 4; index++) {
      for (var attempt = 0; attempt < 15; attempt++) {
        final target = find.ancestor(
          of: active(),
          matching: find.byWidgetPredicate(
            (widget) => widget is Focus && widget.focusNode == nodes[index],
          ),
        );
        if (target.evaluate().isNotEmpty) break;
        await tester.drag(horizontal(), const Offset(-120, 0));
        await tester.pumpAndSettle();
      }
      expect(
        find.ancestor(
          of: active(),
          matching: find.byWidgetPredicate(
            (widget) => widget is Focus && widget.focusNode == nodes[index],
          ),
        ),
        findsOneWidget,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('horizontal swipe owns its row before vertical transfer', (
    tester,
  ) async {
    surface(tester, const Size(1024, 768));
    nodes.addAll(List.generate(40, (_) => FocusNode()));
    await tester.pumpWidget(host(itemCount: 4, shelfCount: 5));
    await tester.pumpAndSettle();
    await tester.drag(horizontal().first, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: active(),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Focus && nodes.take(4).contains(widget.focusNode),
        ),
      ),
      findsOneWidget,
    );
    final vertical = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(vertical, const Offset(0, -400));
    await tester.pumpAndSettle();
    final selected = tester.element(active());
    expect(
      find.ancestor(
        of: active(),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Focus && nodes.take(4).contains(widget.focusNode),
        ),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(tester.element(active()), same(selected));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hover exit preserves keyboard focus and its running preview', (
    tester,
  ) async {
    surface(tester, const Size(1200, 800));
    await tester.pumpWidget(
      host(platform: TargetPlatform.windows, trailers: true),
    );
    await tester.pump();
    nodes[1].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SpotlightCardTrailer), findsOneWidget);
    final preview = tester.element(find.byType(SpotlightCardTrailer));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1190, 790));
    final card = nodes[1].context!.findRenderObject() as RenderBox;
    await mouse.moveTo(card.localToGlobal(card.size.center(Offset.zero)));
    await tester.pump();
    await mouse.moveTo(const Offset(1190, 790));
    await tester.pump();
    expect(nodes[1].hasFocus, isTrue);
    expect(active(), findsOneWidget);
    expect(
      (nodes[1].context!.findRenderObject() as RenderBox).size.aspectRatio,
      greaterThan(1.0),
    );
    expect(tester.element(find.byType(SpotlightCardTrailer)), same(preview));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keyboard focus changes preserve a hovered card and its running preview',
    (tester) async {
      surface(tester, const Size(1200, 800));
      await tester.pumpWidget(
        host(platform: TargetPlatform.windows, trailers: true),
      );
      await tester.pumpAndSettle();
      nodes[1].requestFocus();
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1190, 790));
      final card = nodes[1].context!.findRenderObject() as RenderBox;
      await mouse.moveTo(card.localToGlobal(card.size.center(Offset.zero)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpotlightCardTrailer), findsOneWidget);
      final preview = tester.element(find.byType(SpotlightCardTrailer));
      nodes[1].unfocus();
      await tester.pumpAndSettle();
      expect(nodes[1].hasFocus, isFalse);
      expect(active(), findsOneWidget);
      expect(
        (nodes[1].context!.findRenderObject() as RenderBox).size.aspectRatio,
        greaterThan(1.0),
      );
      expect(tester.element(find.byType(SpotlightCardTrailer)), same(preview));
      nodes[1].requestFocus();
      await tester.pumpAndSettle();
      expect(nodes[1].hasFocus, isTrue);
      expect(tester.element(find.byType(SpotlightCardTrailer)), same(preview));
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving another hovered card restores keyboard selection', (
    tester,
  ) async {
    surface(tester, const Size(1200, 800));
    await tester.pumpWidget(host(platform: TargetPlatform.windows));
    await tester.pumpAndSettle();
    nodes[1].requestFocus();
    await tester.pumpAndSettle();
    final selected = tester.element(active());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1190, 790));
    final other = nodes[2].context!.findRenderObject() as RenderBox;
    await mouse.moveTo(other.localToGlobal(other.size.center(Offset.zero)));
    await tester.pumpAndSettle();
    expect(tester.element(active()), isNot(same(selected)));
    await mouse.moveTo(const Offset(1190, 790));
    await tester.pumpAndSettle();
    expect(nodes[1].hasFocus, isTrue);
    expect(tester.element(active()), same(selected));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hover during a held scroll does not restart trailer dwell', (
    tester,
  ) async {
    surface(tester, const Size(1200, 800));
    await tester.pumpWidget(
      host(platform: TargetPlatform.windows, trailers: true),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1190, 790));
    final drag = await tester.startGesture(tester.getCenter(horizontal()));
    await drag.moveBy(const Offset(-100, 0));
    await tester.pump();
    final card = nodes[1].context!.findRenderObject() as RenderBox;
    await mouse.moveTo(card.localToGlobal(card.size.center(Offset.zero)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SpotlightCardTrailer), findsNothing);
    await drag.moveBy(const Offset(-400, 0));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SpotlightCardTrailer), findsNothing);
    await mouse.moveTo(const Offset(1190, 790));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SpotlightCardTrailer), findsNothing);
    expect(active(), findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('macOS scroll keeps selection under the stationary mouse', (
    tester,
  ) async {
    surface(tester, const Size(1200, 800));
    await tester.pumpWidget(host(platform: TargetPlatform.macOS, expand: false));
    await tester.pumpAndSettle();
    expect(active(), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final target = nodes[2].context!.findRenderObject() as RenderBox;
    final position = target.localToGlobal(target.size.center(Offset.zero));
    await mouse.addPointer(location: position);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(PointerScrollEvent(
      position: position,
      scrollDelta: const Offset(250, 0),
    ));
    await tester.pumpAndSettle();
    expect(active(), findsOneWidget);
    expect(tester.getRect(active()).contains(position), isTrue);
    await mouse.moveTo(const Offset(1190, 790));
    await tester.pumpAndSettle();
    expect(active(), findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expanded posters retain row height with landscape-sized width', (tester) async {
    surface(tester, const Size(1200, 800));
    await tester.pumpWidget(host(platform: TargetPlatform.macOS));
    await tester.pumpAndSettle();
    final restingSize = (nodes[1].context!.findRenderObject() as RenderBox).size;
    nodes[1].requestFocus();
    await tester.pumpAndSettle();
    final posterSize = (nodes[1].context!.findRenderObject() as RenderBox).size;
    await tester.pumpWidget(host(platform: TargetPlatform.macOS, shape: SpotlightCardShape.wide));
    await tester.pumpAndSettle();
    final landscapeSize = (nodes[1].context!.findRenderObject() as RenderBox).size;
    expect(posterSize.width, closeTo(landscapeSize.width, 0.01));
    expect(posterSize.height, closeTo(restingSize.height, 0.01));
    expect(posterSize.width, greaterThan(restingSize.width));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop hover and keyboard each own one expanded card', (
    tester,
  ) async {
    surface(tester, const Size(1200, 800));
    await tester.pumpWidget(host(platform: TargetPlatform.windows));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1190, 790));
    final target = nodes[2].context!.findRenderObject() as RenderBox;
    await mouse.moveTo(target.localToGlobal(target.size.center(Offset.zero)));
    await tester.pumpAndSettle();
    expect(active(), findsOneWidget);
    expect(
      (nodes[2].context!.findRenderObject() as RenderBox).size.aspectRatio,
      greaterThan(1.0),
    );
    await mouse.removePointer();
    nodes[1].requestFocus();
    await tester.pumpAndSettle();
    expect(active(), findsOneWidget);
    expect(
      (nodes[1].context!.findRenderObject() as RenderBox).size.aspectRatio,
      greaterThan(1.0),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'card trailer waits for scrolling to stop and resize removes the preview',
    (tester) async {
      surface(tester, const Size(1024, 768));
      await tester.pumpWidget(host(trailers: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpotlightCardTrailer), findsOneWidget);
      await tester.drag(horizontal(), const Offset(-400, 0));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpotlightCardTrailer), findsOneWidget);
      tester.view.physicalSize = const Size(500, 768);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      expect(active(), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'landscape phones stay compact in behavior and reduced motion blocks previews',
    (tester) async {
      surface(tester, const Size(844, 390));
      await tester.pumpWidget(host(trailers: true));
      await tester.pump(const Duration(seconds: 3));
      expect(active(), findsNothing);
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpWidget(host(trailers: true, reduced: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('vertical scroll transfers the preview to a visible shelf', (
    tester,
  ) async {
    surface(tester, const Size(1024, 768));
    nodes.addAll(List.generate(40, (_) => FocusNode()));
    await tester.pumpWidget(host(shelfCount: 5));
    await tester.pumpAndSettle();
    final before = tester.element(active());
    final vertical = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(vertical, const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(active(), findsOneWidget);
    expect(tester.element(active()), isNot(same(before)));
    final rect = tester.getRect(active());
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(768));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'disabling expansion or reduced motion tears down a running card preview',
    (tester) async {
      surface(tester, const Size(1024, 768));
      await tester.pumpWidget(host(trailers: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(SpotlightCardTrailer), findsOneWidget);
      await tester.pumpWidget(host(trailers: true, reduced: true));
      await tester.pump();
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      await tester.pumpWidget(host(trailers: true, expand: false));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(SpotlightCardTrailer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
