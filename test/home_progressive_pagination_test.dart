import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_ui_refresh.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:debrify/widgets/app_tab_switcher.dart';
import 'package:debrify/widgets/tv_ambient_art_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response page(String name, {int count = 1, int start = 0}) =>
    http.Response(
      jsonEncode({
        'metas': [
          for (var i = start; i < start + count; i++)
            {'id': 'fixture:$name:$i', 'type': 'movie', 'name': '$name $i'},
        ],
      }),
      200,
    );

class HomeFixture {
  HomeFixture(
    this.tester, {
    this.style = 'classic',
    this.fastFirst = true,
    this.tailCount = 0,
    this.horizontal = false,
    this.fastCount = 1,
  });

  final WidgetTester tester;
  final String style;
  final bool fastFirst;
  final int tailCount;
  final bool horizontal;
  final int fastCount;
  final navigator = GlobalKey<NavigatorState>();
  final slow = Completer<http.Response>();
  final secondPage = Completer<http.Response>();
  final requests = <String>[];
  late final client = MockClient((request) async {
    if (request.url.host != 'paging.invalid') return http.Response('', 404);
    final path = request.url.path;
    requests.add(path);
    if (path.contains('/slow')) return slow.future;
    if (path.contains('/tail')) return page('Tail');
    if (path.contains('skip=100')) return secondPage.future;
    if (path.contains('skip=200')) return page('End', count: 0);
    return page('Fast', count: horizontal ? 100 : fastCount);
  });

  Future<void> drive(
    FutureOr<void> Function() action, {
    int waitMs = 60,
  }) async {
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }, () => client),
    );
  }

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await drive(() {});
      await pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(Duration duration) =>
      http.runWithClient(() => tester.pump(duration), () => client);

  Future<void> key(LogicalKeyboardKey key) => http.runWithClient(() async {
    await tester.sendKeyEvent(key);
  }, () => client);

  Future<void> mount({Widget Function(Widget)? wrap}) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      if (!slow.isCompleted) slow.complete(page('Cancelled', count: 0));
      if (!secondPage.isCompleted) {
        secondPage.complete(page('Cancelled', count: 0));
      }
      await tester.pump(const Duration(seconds: 2));
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    PlatformUtil.debugSetAndroidTvCached(true);
    AppThemeAdapter.debugUseTestTypography = true;
    addTearDown(() {
      PlatformUtil.debugSetAndroidTvCached(null);
      AppThemeAdapter.debugUseTestTypography = false;
      ProfileRuntime.debugReset();
    });
    const fast = StremioAddonCatalog(id: 'fast', type: 'movie', name: 'Fast');
    final addon = StremioAddon(
      id: 'paging',
      name: 'Paging',
      baseUrl: 'https://paging.invalid',
      manifestUrl: 'https://paging.invalid/manifest.json',
      resources: ['catalog'],
      catalogs: [
        if (fastFirst) fast,
        for (var i = 0; i < 7; i++)
          StremioAddonCatalog(id: 'slow$i', type: 'movie', name: 'Slow $i'),
        if (!fastFirst) fast,
        for (var i = 0; i < tailCount; i++)
          StremioAddonCatalog(id: 'tail$i', type: 'movie', name: 'Tail $i'),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
      'tv_home_style': style,
      'home_hero_source_v1': jsonEncode({
        'mode': 'custom',
        'ids': ['paging:movie:fast'],
      }),
    });
    StorageService.tvHomeStyleCached = style;
    StremioService.instance.invalidateCache();
    await drive(() async {
      await StremioService.instance.getCatalogAddons();
      final theme = AppTheme.fromDetail(DetailThemes.byId('signal'));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
          home: AppThemeScope(
            theme: theme,
            child:
                wrap?.call(const SearchScreen(isTelevision: true)) ??
                const SearchScreen(isTelevision: true),
          ),
        ),
      );
    }, waitMs: 300);
    await pump(const Duration(milliseconds: 100));
    expect(find.text('Fast 0'), findsWidgets);
  }

  Future<FocusNode> focusFast() async {
    final card = find.text('Fast 0').last;
    await tester.ensureVisible(card);
    await pump(const Duration(milliseconds: 500));
    final node = Focus.of(tester.element(card));
    node.requestFocus();
    await pump(const Duration(milliseconds: 500));
    expect(node.hasFocus, isTrue);
    return node;
  }

  Future<void> cover() async {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Focus(autofocus: true, child: Text('Cover')),
          ),
        ),
      ),
    );
    await pump(const Duration(milliseconds: 500));
    await pump(Duration.zero);
  }

  ScrollableState scroll(Axis axis) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere(
        (state) => axisDirectionToAxis(state.position.axisDirection) == axis,
      );

  Future<void> end(Axis axis) => drive(() {
    final position = scroll(axis).position;
    position.jumpTo(position.maxScrollExtent);
  });

  SpotlightShelf get fastShelf => tester
      .widget<SpotlightBoard>(find.byType(SpotlightBoard))
      .sections
      .firstWhere((shelf) => shelf.id?.endsWith('paging:movie:fast') == true);

  Future<void> nextFastPage() => drive(() {
    final board = tester.widget<SpotlightBoard>(find.byType(SpotlightBoard));
    board.onLoadMoreRow!(
      board.sections.indexWhere(
        (shelf) => shelf.id?.endsWith('paging:movie:fast') == true,
      ),
    );
  });

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets(
    'synced TV trailer volume refreshes live without reloading Home',
    (tester) async {
      final home = HomeFixture(tester, style: 'canvas');
      await home.mount();
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      final trailer = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_HeroTrailerLayer',
      );
      double volume() => (tester.widget(trailer) as dynamic).volume as double;
      expect(volume(), 70);
      final state = tester.state(find.byType(SearchScreen));
      final requests = List<String>.of(home.requests);
      await home.drive(() async {
        await StorageService.setAmbientTrailerVolume(
          AmbientTrailerSurface.homeHero,
          20,
        );
        WebDavSyncUiRefresh.dispatch({'home_hero_trailer_volume'});
      });
      await home.settle();
      expect(volume(), 20);
      expect(tester.state(find.byType(SearchScreen)), same(state));
      expect(home.requests, requests);
      await home.drive(() async {
        await StorageService.setAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
          false,
        );
        await StorageService.setAmbientTrailerVolume(
          AmbientTrailerSurface.homeHero,
          30,
        );
        WebDavSyncUiRefresh.dispatch({'home_hero_trailer_volume'});
      });
      await home.settle();
      expect(
        volume(),
        0,
        reason: 'A synced volume must not override local mute',
      );
      expect(home.requests, requests);
      await home.dispose();
    },
  );

  for (final style in ['classic', 'spotlight']) {
    testWidgets('$style Home can leave and reopen during progressive loading', (
      tester,
    ) async {
      final tab = ValueNotifier(15);
      addTearDown(tab.dispose);
      addTearDown(() {
        MainPageBridge.tvAmbientArt.value = null;
        MainPageBridge.tvHeroTint.value = null;
      });
      final home = HomeFixture(tester, style: style);
      await home.mount(
        wrap: (child) => ValueListenableBuilder<int>(
          valueListenable: tab,
          child: child,
          builder: (_, index, homePage) => Stack(
            fit: StackFit.expand,
            children: [
              TvAmbientArtStage(homeActive: index == 15),
              AppTabSwitcher(
                selectedIndex: index,
                isTelevision: true,
                entranceAnimation: const AlwaysStoppedAnimation(0),
                child: index == 15 ? homePage! : const SizedBox.expand(),
              ),
            ],
          ),
        ),
      );
      final original = tester.state(find.byType(SearchScreen));
      tab.value = 6;
      await home.pump(Duration.zero);
      expect(original.mounted, isFalse);
      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
      tab.value = 15;
      await home.pump(Duration.zero);
      expect(tester.state(find.byType(SearchScreen)), isNot(same(original)));
      // These responses were requested by the outgoing Home and may be
      // shared with the new one. Late loads must neither revive the old page
      // nor prevent the current page from accepting its catalog responses.
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.text('Fast 0'), findsWidgets);
      if (style == 'spotlight') {
        expect(
          tester
              .widget<SpotlightBoard>(find.byType(SpotlightBoard))
              .sections
              .expand((shelf) => shelf.items)
              .any((item) => item.title == 'Slow 0'),
          isTrue,
        );
      } else {
        expect(find.text('Slow 0'), findsWidgets);
      }
      for (final index in [17, 18, 6]) {
        tab.value = index;
        await home.pump(Duration.zero);
        MainPageBridge.tvAmbientArt.value =
            'https://example.invalid/late-$index.jpg';
        await home.pump(const Duration(milliseconds: 30));
        expect(find.byType(CachedNetworkImage), findsNothing);
      }
      await home.dispose();
    });
  }

  testWidgets('horizontal completion cannot cross a profile session', (
    tester,
  ) async {
    final home = HomeFixture(tester, style: 'spotlight', horizontal: true);
    await home.mount();
    await home.nextFastPage();
    expect(home.requests.any((path) => path.contains('skip=100')), isTrue);
    ProfileRuntime.promoteLegacyToCommitted(
      ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 1),
    );
    await home.drive(
      () => home.secondPage.complete(page('Fast', start: 100, count: 100)),
    );
    await home.settle();
    expect(home.fastShelf.items.length, 100);
    expect(home.fastShelf.nodes.length, 100);
    await home.dispose();
  });

  for (final style in ['canvas', 'spotlight']) {
    testWidgets('$style cancels deferred Down when focus moves sideways', (
      tester,
    ) async {
      final home = HomeFixture(tester, style: style, fastCount: 2);
      await home.mount();
      await home.focusFast();
      await home.key(LogicalKeyboardKey.arrowDown);
      await home.pump(Duration.zero);
      await home.key(LogicalKeyboardKey.arrowRight);
      await home.settle();
      final next = Focus.of(tester.element(find.text('Fast 1').last));
      expect(next.hasFocus, isTrue);
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      expect(next.hasFocus, isTrue);
      await home.dispose();
    });

    testWidgets('$style does not replay deferred Down after a covered route', (
      tester,
    ) async {
      final home = HomeFixture(tester, style: style);
      await home.mount();
      final origin = await home.focusFast();
      await home.key(LogicalKeyboardKey.arrowDown);
      await home.pump(Duration.zero);
      await home.cover();
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      home.navigator.currentState!.pop();
      await home.settle();
      expect(origin.hasFocus, isTrue);
      await home.dispose();
    });
  }
  for (final empty in [false, true]) {
    testWidgets(
      'covered Home does not fetch 40 more catalogs (empty batch=$empty)',
      (tester) async {
        final home = HomeFixture(tester, tailCount: 40);
        await home.mount();
        await home.focusFast();
        await home.cover();
        await home.drive(
          () => home.slow.complete(page('Slow', count: empty ? 0 : 1)),
        );
        await home.settle();
        expect(home.requests.where((path) => path.contains('/tail')), isEmpty);
        home.navigator.currentState!.pop();
        await home.settle();
        if (!empty) {
          // Applying the eight rows fills the viewport. Do not page based on
          // the old, short layout before that application has been laid out.
          expect(
            home.requests.where((path) => path.contains('/tail')),
            isEmpty,
          );
          await home.end(Axis.vertical);
          await home.settle();
        }
        expect(home.requests.any((path) => path.contains('/tail')), isTrue);
        expect(
          home.requests.where((path) => path.contains('/tail')).length,
          lessThan(40),
        );
        await home.dispose();
      },
    );
  }

  testWidgets(
    'horizontal page survives seven rows inserted above its catalog',
    (tester) async {
      final home = HomeFixture(
        tester,
        style: 'spotlight',
        fastFirst: false,
        horizontal: true,
      );
      await home.mount();
      await home.nextFastPage();
      await home.settle();
      expect(home.requests.any((path) => path.contains('skip=100')), isTrue);
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      expect(home.fastShelf.items.length, 100);
      await home.drive(
        () => home.secondPage.complete(page('Fast', start: 100, count: 100)),
      );
      await home.settle();
      expect(home.fastShelf.items.length, 200);
      expect(home.fastShelf.nodes.length, 200);
      await home.nextFastPage();
      await home.settle();
      expect(home.requests.any((path) => path.contains('skip=200')), isTrue);
      await home.dispose();
    },
  );

  for (final style in [
    'classic',
    'canvas',
    'atrium',
    'deck',
    'mosaic',
    'promenade',
    'tonight',
    'spotlight',
  ]) {
    testWidgets('$style defers Down within the reserved initial batch', (
      tester,
    ) async {
      final home = HomeFixture(tester, style: style);
      await home.mount();
      final origin = await home.focusFast();
      await home.key(LogicalKeyboardKey.arrowDown);
      await home.pump(Duration.zero);
      expect(origin.hasFocus, isTrue);
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      expect(origin.hasFocus, isFalse);
      expect(
        find
            .text('Slow 0')
            .evaluate()
            .any((element) => Focus.maybeOf(element)?.hasFocus ?? false),
        isTrue,
        reason:
            'primary=${FocusManager.instance.primaryFocus}; visible=${find.text('Slow 0').evaluate().map((e) => Focus.maybeOf(e)).toList()}',
      );
      await home.dispose();
    });
  }
}
