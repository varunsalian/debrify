import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/theme/widgets/focus_expression.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:debrify/widgets/home/spotlight_card_trailer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../support/spotlight_board_fixture.dart';

class _PendingBoard extends SpotlightBoard {
  const _PendingBoard({required super.heroNode})
    : super(
        hero: const [
          StremioMeta(id: 'pending', type: 'movie', name: 'Pending'),
        ],
        sections: const [],
        heroAddon: null,
        onHeroOpen: _open,
        trailersEnabled: false,
      );
  static void _open(StremioMeta item, StremioAddon addon) {}
  @override
  SpotlightBoardState createState() => _PendingState();
}

class _PendingState extends SpotlightBoardState {
  bool pending = true;
  @override
  bool metadataArtworkPending(MetadataCategory category) => pending;
  void resolve() => setState(() => pending = false);
}

List<String> compositingAncestors(WidgetTester tester) {
  final result = <String>[];
  tester.element(find.byKey(spotlightTrailer)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Opacity ||
        widget is ShaderMask ||
        widget is ColorFiltered ||
        widget is BackdropFilter) {
      result.add(widget.runtimeType.toString());
    }
    return true;
  });
  return result;
}

List<(Widget, Element)> shelfRoots(WidgetTester tester) {
  final result = <(Widget, Element)>[];
  for (final element in find.byType(KeyedSubtree).evaluate()) {
    final key = element.widget.key.toString();
    if (!key.contains('shelf')) {
      continue;
    }
    element.visitChildElements((child) => result.add((child.widget, child)));
  }
  return result;
}

void main() {
  testWidgets(
    'Android TV leading insertion retains the original node and visual anchor',
    (tester) async {
      await spotlightCase(tester, (f) async {
        PlatformUtil.debugSetAndroidTvCached(true);
        f.sections = [f.shelf('a'), f.shelf('b'), f.shelf('c')];
        await f.mount(tester);
        f.key.currentState!.focusShelf(1);
        await f.pump(tester);
        await f.pump(tester, 250);
        final origin = f.sections[1].nodes.first;
        expect(origin.hasFocus, isTrue);
        final point = tester.getTopLeft(find.text('Card b/0'));
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final pixels = scroll.position.pixels;
        f.sections = [f.shelf('inserted'), ...f.sections];
        await tester.pumpWidget(f.host());
        await f.pump(tester);
        expect(origin.hasFocus, isTrue);
        expect(scroll.position.pixels, greaterThan(pixels));
        expect(
          tester.getTopLeft(find.text('Card b/0')).dy,
          closeTo(point.dy, 1),
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
  for (final handoff in ['profile', 'unmount']) {
    testWidgets('held description publishes nothing after $handoff', (
      tester,
    ) async {
      await spotlightCase(tester, (f) async {
        final prefs = await SharedPreferences.getInstance();
        final addon = StremioAddon(
          id: 'held',
          name: 'Held metadata',
          manifestUrl: 'https://metadata.test/manifest.json',
          baseUrl: 'https://metadata.test',
          resources: const ['meta'],
          types: const ['movie'],
        );
        await prefs.setString(
          'stremio_addons_v1',
          jsonEncode([addon.toJson()]),
        );
        StremioService.instance.invalidateCache();
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        f.respond = (request) {
          if (!entered.isCompleted) {
            entered.complete();
          }
          return response.future;
        };
        final shelf = f.shelf('a');
        f.sections = [
          SpotlightShelf(
            id: shelf.id,
            title: shelf.title,
            nodes: shelf.nodes,
            items: [
              for (var i = 0; i < shelf.items.length; i++)
                SpotlightCard(
                  title: 'Sparse $i',
                  onOpen: () {},
                  metadata: StremioMeta(
                    id: 'tt999990$i',
                    imdbId: 'tt999990$i',
                    type: 'movie',
                    name: 'Sparse $i',
                  ),
                ),
            ],
          ),
        ];
        await f.mount(tester);
        await f.focus(tester, f.sections.first.nodes.first);
        await f.pump(tester, 50);
        for (var i = 0; i < 20 && !entered.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await f.pump(tester);
        }
        expect(
          entered.isCompleted,
          isTrue,
          reason: 'Exercise the actual held HTTP request',
        );
        if (handoff == 'profile') {
          ProfileRuntime.initializeCommitted(
            ProfileScope(
              profileId: 'incoming',
              dataGeneration: 1,
              sessionEpoch: 2,
            ),
          );
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        response.complete(
          http.Response(
            jsonEncode({
              'meta': {
                'id': 'tt9999900',
                'type': 'movie',
                'name': 'Sparse 0',
                'description': 'Late held description',
              },
            }),
            200,
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await f.pump(tester);
        }
        expect(find.textContaining('Late held description'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }
  for (final pointer in [false, true]) {
    testWidgets(
      'interaction selects exactly the owning mounted card State pointer=$pointer',
      (tester) async {
        await spotlightCase(tester, (f) async {
          f.dpad = false;
          f.shelvesOnly = true;
          f.largeInteractions = true;
          f.sections = [f.shelf('a')];
          await f.mount(tester, size: const Size(1440, 900));
          final cards = find.byWidgetPredicate(
            (w) =>
                w.runtimeType.toString() == '_Card' ||
                w.runtimeType.toString() == 'SpotlightBoardCard',
          );
          final states = tester.stateList<State>(cards).toList();
          final target = cards.at(1);
          if (pointer) {
            final region = tester.widget<MouseRegion>(
              find
                  .descendant(
                    of: target,
                    matching: find.byWidgetPredicate(
                      (w) => w is MouseRegion && w.onEnter != null,
                    ),
                  )
                  .first,
            );
            region.onEnter!(const PointerEnterEvent());
            await f.pump(tester);
          } else {
            await f.focus(tester, f.sections.first.nodes[1]);
          }
          final active = find.byWidgetPredicate(
            (w) => w is ParallaxFocus && w.focused,
          );
          expect(active, findsOneWidget);
          expect(find.descendant(of: target, matching: active), findsOneWidget);
          expect(tester.state(target), same(states[1]));
          expect(tester.takeException(), isNull);
        });
      },
    );
  }
  testWidgets(
    'card trailer dwell, stop ordering, growth and text timer stay on the original card',
    (tester) async {
      await spotlightCase(tester, (f) async {
        f.trailers = true;
        f.sections = [f.shelf('a', metadata: true)];
        await f.mount(tester);
        await f.focus(tester, f.sections.first.nodes.first);
        await f.pump(tester, 1749);
        expect(find.byType(SpotlightCardTrailer), findsNothing);
        expect(f.events.where((e) => e == 'stop'), isEmpty);
        await f.pump(tester, 1);
        expect(find.byType(SpotlightCardTrailer), findsOneWidget);
        expect(f.events.where((e) => e == 'stop'), hasLength(1));
        final trailer = tester.widget<SpotlightCardTrailer>(
          find.byType(SpotlightCardTrailer),
        );
        expect(trailer.key, const ValueKey('a-0'));
        trailer.onPlayingChanged(true);
        await f.pump(tester, 700);
        final text = find.byKey(const ValueKey('spotlight-trailer-text-a-0'));
        expect(tester.widget<AnimatedOpacity>(text).opacity, 1);
        await f.pump(tester, 1299);
        expect(tester.widget<AnimatedOpacity>(text).opacity, 1);
        await f.pump(tester, 1);
        expect(tester.widget<AnimatedOpacity>(text).opacity, 0);
        final tween = tester.widget<TweenAnimationBuilder<double>>(
          find
              .ancestor(
                of: text,
                matching: find.byWidgetPredicate(
                  (w) => w is TweenAnimationBuilder<double>,
                ),
              )
              .first,
        );
        expect(tween.tween.end, closeTo((470 / 260) * 1.38, 0.00001));
        await f.focus(tester, f.sections.first.nodes[1]);
        expect(find.byType(SpotlightCardTrailer), findsNothing);
      });
    },
  );

  for (final expires in [false, true]) {
    testWidgets(
      'held progressive DOWN preserves originating focus and real three-second window expires=$expires',
      (tester) async {
        await spotlightCase(tester, (f) async {
          final result = Completer<bool>();
          var loads = 0;
          f.loadShelves = () {
            loads++;
            return result.future;
          };
          f.pendingShelves = true;
          f.sections = [f.shelf('a')];
          await f.mount(tester);
          final origin = f.sections.first.nodes[1];
          await f.focus(tester, origin);
          await f.keyPress(tester, LogicalKeyboardKey.arrowDown);
          await f.keyPress(tester, LogicalKeyboardKey.arrowDown);
          expect(loads, 1);
          expect(origin.hasFocus, isTrue);
          expect(find.text('Loading more'), findsOneWidget);
          result.complete(false);
          await f.pump(tester);
          await f.pump(tester);
          if (expires) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 3100)),
            );
          }
          final added = f.shelf('b');
          f.sections = [...f.sections, added];
          await tester.pumpWidget(f.host());
          await f.pump(tester);
          await f.pump(tester);
          await f.pump(tester, 250);
          expect(added.nodes.first.hasFocus, !expires);
          expect(origin.hasFocus, expires);
        });
      },
    );
  }
  testWidgets('original fixture mounts without a production seam', (
    tester,
  ) async {
    await spotlightCase(tester, (f) async {
      f.sections = [f.shelf('a')];
      await f.mount(tester);
      expect(f.key.currentState!.currentHeroId, 'hero-a');
      expect(find.text('Shelf a'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'live subclass pending override changes flip memo at its original site',
    (tester) async {
      await spotlightCase(tester, (f) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: PremiumLooks.byId('spotlight')!.build(),
              child: Scaffold(body: _PendingBoard(heroNode: f.heroNode)),
            ),
          ),
        );
        await tester.pump();
        final state = tester.state<_PendingState>(find.byType(_PendingBoard));
        expect(state.heroAlignmentItemId, isNull);
        state.resolve();
        await tester.pump();
        expect(state.heroAlignmentItemId, 'pending');
      });
    },
  );

  testWidgets('hero cadence waits exactly two seconds and never advances', (
    tester,
  ) async {
    await spotlightCase(tester, (f) async {
      f.trailers = true;
      await f.mount(tester);
      await f.focus(tester, f.heroNode);
      await f.pump(tester, 1749);
      expect(f.events.where((e) => e.startsWith('dwell')), isEmpty);
      await f.pump(tester, 1);
      expect(f.events.where((e) => e.startsWith('dwell')), ['dwell hero-a']);
      await f.pump(tester, 5000);
      expect(f.events.where((e) => e.startsWith('dwell')), ['dwell hero-a']);
      expect(f.key.currentState!.currentHeroId, 'hero-a');
    });
  });

  for (final trailers in [false, true]) {
    testWidgets('no cadence without hero focus trailers=$trailers', (
      tester,
    ) async {
      await spotlightCase(tester, (f) async {
        f.trailers = trailers;
        f.sections = [f.shelf('a')];
        await f.mount(tester);
        await f.focus(tester, f.sections.first.nodes.first);
        await f.pump(tester, 4000);
        expect(f.events.where((e) => e.startsWith('dwell')), isEmpty);
      });
    });
  }

  for (final exit in ['page', 'down', 'focus loss', 'scroll away', 'unmount']) {
    testWidgets('rolling hero stops once on $exit', (tester) async {
      await spotlightCase(tester, (f) async {
        f.trailers = true;
        f.sections = [for (var i = 0; i < 5; i++) f.shelf('$i')];
        await f.mount(tester);
        await f.focus(tester, f.heroNode);
        await f.pump(tester, 1750);
        expect(f.events, contains('dwell hero-a'));
        f.events.clear();
        switch (exit) {
          case 'page':
            await f.keyPress(tester, LogicalKeyboardKey.arrowRight);
          case 'down':
            await f.keyPress(tester, LogicalKeyboardKey.arrowDown);
          case 'focus loss':
            await f.focus(tester, f.sections.first.nodes.first);
          case 'scroll away':
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(600);
            await f.pump(tester);
          case 'unmount':
            await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(f.events.where((e) => e == 'stop'), hasLength(1));
      });
    });
  }

  testWidgets(
    'hidden touch route retries after one second without dwelling behind it',
    (tester) async {
      await spotlightCase(tester, (f) async {
        f.dpad = false;
        f.trailers = true;
        await f.mount(tester, size: const Size(1440, 900));
        unawaited(
          f.navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover route')),
            ),
          ),
        );
        await f.pump(tester, 2000);
        expect(f.events.where((e) => e.startsWith('dwell')), isEmpty);
        f.navigatorKey.currentState!.pop();
        await f.pump(tester, 999);
        expect(f.events.where((e) => e.startsWith('dwell')), isEmpty);
        await f.pump(tester, 1);
        expect(f.events.where((e) => e.startsWith('dwell')), ['dwell hero-a']);
      });
    },
  );

  for (final dpad in [false, true]) {
    for (final animations in [false, true]) {
      testWidgets(
        'host trailer stays mounted with original ordered ancestors dpad=$dpad animations=$animations',
        (tester) async {
          await spotlightCase(tester, (f) async {
            f.dpad = dpad;
            f.animations = animations;
            f.trailer = const SizedBox.expand(key: spotlightTrailer);
            f.sections = [f.shelf('a')];
            await f.mount(tester, size: const Size(1440, 900));
            expect(find.byKey(spotlightTrailer), findsOneWidget);
            expect(
              compositingAncestors(tester),
              !animations
                  ? <String>[]
                  : dpad
                  ? ['Opacity']
                  : ['ShaderMask', 'Opacity'],
            );
            if (animations && dpad) {
              final opacity = find.ancestor(
                of: find.byKey(spotlightTrailer),
                matching: find.byType(Opacity),
              );
              expect(tester.widget<Opacity>(opacity).opacity, 1.0);
              await f.focus(tester, f.heroNode);
              await f.keyPress(tester, LogicalKeyboardKey.arrowDown);
              expect(tester.widget<Opacity>(opacity).opacity, 0.0);
            }
          });
        },
      );
    }
  }

  testWidgets(
    'desktop owner stops the hero before preview and leaving re-arms it',
    (tester) async {
      await spotlightCase(tester, (f) async {
        f.dpad = false;
        f.trailers = true;
        f.largeInteractions = true;
        f.sections = [f.shelf('a', preview: true)];
        await f.mount(tester, size: const Size(1440, 900));
        await f.pump(tester, 1000);
        expect(f.events.where((e) => e.startsWith('dwell')), isEmpty);
        f.events.clear();
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        addTearDown(pointer.removePointer);
        final region = tester.widget<MouseRegion>(
          find.ancestor(
            of: find.text('Card a/0'),
            matching: find.byWidgetPredicate(
              (w) => w is MouseRegion && w.onEnter != null,
            ),
          ),
        );
        region.onEnter!(const PointerEnterEvent());
        await f.pump(tester);
        expect(
          f.events.indexOf('stop'),
          lessThan(f.events.indexOf('preview a/0')),
        );
        f.events.clear();
        await f.pump(tester, 3000);
        expect(f.events.where((e) => e.startsWith('dwell')), isEmpty);
        region.onExit!(const PointerExitEvent());
        await f.pump(tester);
        await f.pump(tester, 2000);
        expect(f.events.where((e) => e.startsWith('dwell')), ['dwell hero-a']);
      });
    },
  );

  testWidgets('dpad card hover is absent and fallback cursor is conditional', (
    tester,
  ) async {
    await spotlightCase(tester, (f) async {
      f.sections = [f.shelf('a')];
      await f.mount(tester);
      final card = find.text('Card a/0');
      expect(
        find.ancestor(
          of: card,
          matching: find.byWidgetPredicate(
            (w) => w is MouseRegion && w.onEnter != null,
          ),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(of: card, matching: find.byType(FocusExpressionBox)),
        findsNothing,
      );
      expect(
        find.ancestor(of: card, matching: find.byType(ParallaxFocus)),
        findsOneWidget,
      );
    });
  });

  testWidgets('dpad ignores a reported desktop preview lease', (tester) async {
    await spotlightCase(tester, (f) async {
      f.trailers = true;
      f.sections = [f.shelf('a')];
      await f.mount(tester);
      await f.focus(tester, f.heroNode);
      final dynamic card = tester.widget(
        find
            .byWidgetPredicate(
              (w) =>
                  w.runtimeType.toString() == '_Card' ||
                  w.runtimeType.toString() == 'SpotlightBoardCard',
            )
            .first,
      );
      final Function report = card.onDesktopPreviewActivityChanged;
      report(Object(), true);
      expect(f.events.where((e) => e == 'stop'), isEmpty);
      await f.pump(tester, 1750);
      expect(f.events.where((e) => e.startsWith('dwell')), ['dwell hero-a']);
    });
  });

  testWidgets('TV ground veil snaps to row and ignores scroll glide', (
    tester,
  ) async {
    await spotlightCase(tester, (f) async {
      f.sections = [f.shelf('a'), f.shelf('b')];
      await f.mount(tester);
      await f.focus(tester, f.heroNode);
      await f.keyPress(tester, LogicalKeyboardKey.arrowDown);
      double alpha() => tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .singleWhere((box) => box.color.a > 0 && box.color.a < 1)
          .color
          .a;
      expect(alpha(), closeTo(0.72, 0.001));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent * 0.65);
      await f.pump(tester);
      expect(alpha(), closeTo(0.72, 0.001));
    });
  });

  testWidgets(
    'horizontal movement preserves shelf roots and board identity with a vertical positive control',
    (tester) async {
      await spotlightCase(tester, (f) async {
        f.sections = [f.shelf('a'), f.shelf('b')];
        await f.mount(tester);
        await f.focus(tester, f.sections.first.nodes.first);
        await f.settleSetup(tester);
        final board = f.key.currentState;
        final scrollStates = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .toList();
        final roots = shelfRoots(tester);
        final cardFinder = find.byWidgetPredicate(
          (w) =>
              w.runtimeType.toString() == '_Card' ||
              w.runtimeType.toString() == 'SpotlightBoardCard',
        );
        final cardStates = tester.stateList<State>(cardFinder).toList();
        final parallaxFinder = find.byWidgetPredicate(
          (w) =>
              w is StatefulWidget &&
              w.runtimeType.toString().contains('ParallaxBody'),
        );
        final parallaxStates = tester.stateList<State>(parallaxFinder).toList();
        expect(parallaxStates, isNotEmpty);
        expect(roots, isNotEmpty);
        var builds = 0;
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          if (element.widget is SpotlightBoard) {
            builds++;
          }
          previous?.call(element, builtOnce);
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        await f.keyPress(tester, LogicalKeyboardKey.arrowRight);
        await f.pump(tester, 250);
        expect(builds, 0);
        final after = shelfRoots(tester);
        expect(after, hasLength(roots.length));
        for (var i = 0; i < roots.length; i++) {
          expect(after[i].$1, same(roots[i].$1));
          expect(after[i].$2, same(roots[i].$2));
        }
        expect(f.key.currentState, same(board));
        expect(
          tester.stateList<State>(cardFinder).toList(),
          orderedEquals(cardStates),
        );
        expect(
          tester.stateList<State>(parallaxFinder).toList(),
          orderedEquals(parallaxStates),
        );
        expect(
          tester.stateList<ScrollableState>(find.byType(Scrollable)).toList(),
          orderedEquals(scrollStates),
        );
        await f.keyPress(tester, LogicalKeyboardKey.arrowDown);
        await f.pump(tester, 250);
        expect(builds, 1);
        expect(shelfRoots(tester).first.$1, isNot(same(roots.first.$1)));
        expect(f.key.currentState, same(board));
        await f.keyPress(tester, LogicalKeyboardKey.arrowUp);
        await f.pump(tester, 250);
        expect(builds, 2);
        expect(
          tester.stateList<State>(cardFinder).toList(),
          orderedEquals(cardStates),
        );
        expect(
          tester.stateList<State>(parallaxFinder).toList(),
          orderedEquals(parallaxStates),
        );
        f.sections = [...f.sections];
        await tester.pumpWidget(f.host());
        await f.pump(tester);
        expect(builds, 3);
        expect(
          tester.stateList<State>(cardFinder).toList(),
          orderedEquals(cardStates),
        );
        expect(
          tester.stateList<State>(parallaxFinder).toList(),
          orderedEquals(parallaxStates),
        );
      });
    },
  );

  for (final tv in [false, true]) {
    for (final shape in [SpotlightCardShape.poster, SpotlightCardShape.wide]) {
      for (final dpr in [1.0, 2.0]) {
        testWidgets(
          'card decode width stays stable across focus shape=$shape TV=$tv DPR=$dpr',
          (tester) async {
            await spotlightCase(tester, (f) async {
              PlatformUtil.debugSetAndroidTvCached(tv);
              f.sections = [
                f.shelf('a', shape: shape, images: true, metadata: true),
              ];
              await f.mount(tester, dpr: dpr);
              int decode() => tester
                  .widgetList<CachedNetworkImage>(
                    find.byType(CachedNetworkImage),
                  )
                  .firstWhere(
                    (w) => w.imageUrl == 'https://artwork.test/a-0.png',
                  )
                  .memCacheWidth!;
              final before = decode();
              final factor = tv ? 1.0 : 1.18;
              final restingWidth = shape == SpotlightCardShape.poster
                  ? 260.0
                  : 470.0;
              expect(
                before,
                (restingWidth * factor * dpr * 1.1).round().clamp(100, 1000),
              );
              await f.focus(tester, f.sections.first.nodes.first);
              await f.pump(tester, 250);
              final after = decode();
              expect(
                after,
                (470.0 * factor * dpr * 1.1).round().clamp(100, 1000),
              );
              await f.pump(tester, 250);
              expect(decode(), after);
            });
          },
        );
      }
    }
  }
}
