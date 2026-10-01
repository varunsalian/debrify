import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/presentation/home_catalog_card.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/card_metadata_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('card opens once on release of ${key.keyLabel}', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var opens = 0;
      await tester.pumpWidget(_host(_card(node, onOpen: () => opens++)));
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      expect(opens, 0);
      await tester.sendKeyUpEvent(key);
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: node, child: const Text('Reuse')),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV hold fills for 500ms and release does not also open', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var opens = 0;
    var holds = 0;
    await tester.pumpWidget(
      _host(_card(node, onOpen: () => opens++, onLongPress: () => holds++)),
    );
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(holds, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      1,
    );
    // AnimationController completes on the first frame after its duration.
    await tester.pump(const Duration(milliseconds: 1));
    expect(holds, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(opens, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opens, 1);
    expect(holds, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus loss and disposal cancel an unfinished hold', (
    tester,
  ) async {
    final node = FocusNode();
    final other = FocusNode();
    addTearDown(node.dispose);
    addTearDown(other.dispose);
    var actions = 0;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            _card(node, onOpen: () => actions++, onLongPress: () => actions++),
            Focus(focusNode: other, child: const Text('Other')),
          ],
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    other.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(actions, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(actions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touch long press prefers menu over quick play and keeps progress badges',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var menu = 0;
      var quick = 0;
      var opens = 0;
      await tester.pumpWidget(
        _host(
          _card(
            node,
            tv: false,
            onOpen: () => opens++,
            onLongPress: () => menu++,
            onQuickPlay: () => quick++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('S2 · E5'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        .4,
      );
      await tester.longPress(find.byType(HomeCatalogCard));
      expect(menu, 1);
      expect(quick, 0);
      expect(opens, 0);
      await tester.tap(find.byType(HomeCatalogCard));
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hero shuttle chooses the poster on push and pop', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            _card(node, onOpen: () {}, heroTag: 'poster'),
            const Hero(tag: 'backdrop', child: Text('Detail backdrop')),
          ],
        ),
      ),
    );
    final posterFinder = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'poster',
    );
    final backdropContext = tester.element(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'backdrop',
      ),
    );
    final poster = tester.widget<Hero>(posterFinder);
    final posterContext = tester.element(posterFinder);
    final animation = const AlwaysStoppedAnimation<double>(.5);
    for (final direction in HeroFlightDirection.values) {
      final shuttle =
          poster.flightShuttleBuilder!(
                posterContext,
                animation,
                direction,
                direction == HeroFlightDirection.push
                    ? posterContext
                    : backdropContext,
                direction == HeroFlightDirection.push
                    ? backdropContext
                    : posterContext,
              )
              as Material;
      expect(shuttle.type, MaterialType.transparency);
      expect(shuttle.child, same(poster.child));
    }
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _host(Widget child) {
  final data = CardMetadataFake()
    ..respond = (item) async => MetadataPresentation(item);
  return ProviderScope(
    overrides: [
      homeCardMetadataRepositoryProvider.overrideWith(
        (ref, epoch) => data.repository(epoch),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Widget _card(
  FocusNode node, {
  required VoidCallback onOpen,
  VoidCallback? onLongPress,
  VoidCallback? onQuickPlay,
  bool tv = true,
  String? heroTag,
}) => SizedBox(
  width: 120,
  height: 180,
  child: HomeCatalogCard(
    item: const StremioMeta(id: 'card', type: 'movie', name: 'Catalog'),
    isTelevision: tv,
    focusNode: node,
    hasBoundSource: true,
    showWatchedBadge: false,
    progress: .4,
    episodeLabel: 'S2 · E5',
    onOpen: onOpen,
    onLongPress: onLongPress,
    onQuickPlay: onQuickPlay,
    heroTag: heroTag,
  ),
);
