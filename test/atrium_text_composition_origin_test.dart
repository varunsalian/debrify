import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/search/stage_visuals.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart' show catalogNode;
import 'atrium_layout_attribution_test.dart' show checkActualWall;

// Real Home constructs all text, identities and focus handlers. The transport
// fixture is adapted from the shared-rail pin, never a copy of label policy.
typedef _Appearance = ({AppTheme theme, double scale, bool rtl});

class _Catalogs {
  _Catalogs({required this.rows, this.longTitle = false, this.heldNinth = false});
  final int rows;
  final bool longTitle;
  final bool heldNinth;
  final release = Completer<http.Response>();
  final unexpected = <String>[];
  final requests = <String>[];
  int heldEntries = 0;

  String title(int rail) {
    if (heldNinth && (rail == 0 || rail == 8)) return 'Shared Movies';
    if (longTitle) return 'Rail $rail Movies ${List.filled(12, 'Long label').join(' ')}';
    return 'Rail $rail Movies';
  }

  http.Response page(int rail, {bool empty = false}) => http.Response(
    jsonEncode({'metas': [
      if (!empty)
        {'id': 'atrium-text-$rail', 'type': 'movie', 'name': 'Catalog Item $rail', 'poster': ''},
    ]}),
    200,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> call(http.Request request) async {
    final url = request.url.toString();
    requests.add(url);
    for (var rail = 0; rail < rows; rail++) {
      final root = rail == 8 ? 'https://atrium-text-b.invalid' : 'https://atrium-text-a.invalid';
      if (request.method == 'GET' && url == '$root/catalog/movie/rail$rail.json') {
        if (heldNinth && rail == 8) {
          heldEntries++;
          return release.future;
        }
        return page(rail);
      }
      // Existing catalog-cell near-end prefetch may request the terminal page.
      if (request.method == 'GET' &&
          url == '$root/catalog/movie/rail$rail/skip=1.json') {
        return page(rail, empty: true);
      }
    }
    unexpected.add('${request.method} $url');
    throw StateError('Unseeded Atrium text transport');
  }

  Future<void> install() async {
    StremioAddon addon(String suffix, Iterable<int> indices) => StremioAddon(
      id: 'atrium.text.$suffix', name: suffix == 'a' ? 'Source A' : 'Source B',
      manifestUrl: 'https://atrium-text-$suffix.invalid/manifest.json',
      baseUrl: 'https://atrium-text-$suffix.invalid', resources: ['catalog'],
      types: ['movie'], catalogs: [
        for (final rail in indices)
          StremioAddonCatalog(id: 'rail$rail', type: 'movie', name: title(rail),
            extraSupported: ['skip']),
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stremio_addons_v1', jsonEncode([
      addon('a', List.generate(heldNinth ? 8 : rows, (i) => i)).toJson(),
      if (heldNinth) addon('b', [8]).toJson(),
    ]));
    StremioService.instance.invalidateCache();
    addTearDown(StremioService.instance.invalidateCache);
  }
}

Finder _eyebrow() => find.byWidgetPredicate((widget) => widget is Text &&
    widget.style?.fontSize == 11 && widget.style?.letterSpacing == 2.6);
Finder _wallLabels() => find.byWidgetPredicate((widget) => widget is Text &&
    widget.style?.fontSize == 12 && widget.style?.letterSpacing == 1.6);

void _expectText(WidgetTester tester, String eyebrow, List<String> wall) {
  expect(_eyebrow(), findsOneWidget);
  final text = tester.widget<Text>(_eyebrow());
  expect(text.data, eyebrow);
  expect(text.maxLines, 1);
  expect(text.overflow, TextOverflow.ellipsis);
  expect(text.style!.fontWeight, FontWeight.w800);
  expect(tester.widgetList<Text>(_wallLabels()).map((text) => text.data), wall);
  expect(tester.takeException(), isNull);
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await pumpFavourites(tester);
}

Future<void> _withHome(WidgetTester tester, _Catalogs catalogs,
    Future<void> Function(ValueNotifier<_Appearance>) body,
    {bool savedFavourite = false}) async {
  await prepareFavourites(tester);
  // Original Atrium viewport; later one explicitly declared geometry transition.
  tester.view.physicalSize = const Size(1920, 1080);
  await StorageService.setTvHomeStyle('atrium');
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
  if (savedFavourite) {
    await MyWatchlistStore.setMyWatchlistItem(const StremioMeta(
      id: 'atrium-saved', type: 'movie', name: 'Saved Atrium Movie', poster: '',
    ), true);
  }
  await catalogs.install();
  final appearance = ValueNotifier<_Appearance>(
      (theme: AppThemes.legacy, scale: 0.8, rtl: false));
  final client = MockClient(catalogs.call);
  await http.runWithClient(() async {
    try {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ValueListenableBuilder<_Appearance>(
          valueListenable: appearance, child: child,
          builder: (context, value, stableChild) => AppThemeScope(
            theme: value.theme,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(value.scale)),
              child: Directionality(
                textDirection: value.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: stableChild!,
              ),
            ),
          ),
        ),
        home: const SearchScreen(isTelevision: true),
      ));
      await pumpFavourites(tester);
      expect(_eyebrow(), findsOneWidget);
      await body(appearance);
      expect(catalogs.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      if (!catalogs.release.isCompleted) catalogs.release.complete(catalogs.page(8));
      try {
        // Existing helper: unmount, finite12x100ms/3ms async steps, then11s
        // post-unmount fake-clock cleanup. No new drain or suppressed errors.
        await closeFavourites(tester);
      } finally {
        client.close();
        appearance.dispose();
      }
    }
    expect(catalogs.unexpected, isEmpty);
    expect(tester.takeException(), isNull);
  }, () => client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Atrium dossier follows focused row while wall keeps its window',
      (tester) async {
    await _withHome(tester, _Catalogs(rows: 3), (appearance) async {
      final first = catalogNode(tester, 0, 0);
      final second = catalogNode(tester, 1, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      _expectText(tester, 'RAIL 0 MOVIES', ['RAIL 0 MOVIES', 'RAIL 1 MOVIES']);
      final initial = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
      expect(initial.item.value!.id, 'atrium-text-0');
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, same(second));
      _expectText(tester, 'RAIL 1 MOVIES', ['RAIL 0 MOVIES', 'RAIL 1 MOVIES']);
      final changed = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
      expect(changed.item, same(initial.item));
      expect(changed.enriched, same(initial.enriched));
      expect(changed.trailerShowing, same(initial.trailerShowing));
      expect(changed.item.value!.id, 'atrium-text-1');
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, same(catalogNode(tester, 2, 0)));
      _expectText(tester, 'RAIL 2 MOVIES', ['RAIL 1 MOVIES', 'RAIL 2 MOVIES']);
      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(second));
      _expectText(tester, 'RAIL 1 MOVIES', ['RAIL 1 MOVIES', 'RAIL 2 MOVIES']);
    });
  });

  testWidgets('Atrium held append refreshes dossier and wall addon provenance',
      (tester) async {
    final catalogs = _Catalogs(rows: 9, heldNinth: true);
    await _withHome(tester, catalogs, (appearance) async {
      catalogNode(tester, 0, 0).requestFocus();
      await pumpFavourites(tester);
      _expectText(tester, 'SHARED MOVIES', ['SHARED MOVIES', 'RAIL 1 MOVIES']);
      for (var i = 0; i < 7; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
      }
      final tail = catalogNode(tester, 7, 0);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(catalogs.heldEntries, 1);
      expect(catalogs.release.isCompleted, isFalse);
      expect(FocusManager.instance.primaryFocus, same(tail));
      _expectText(tester, 'RAIL 7 MOVIES', ['RAIL 6 MOVIES', 'RAIL 7 MOVIES']);
      catalogs.release.complete(catalogs.page(8));
      await pumpFavourites(tester);
      // Existing actual Atrium pin proves retained-bottom deferred advancement;
      // do not import the distinct Promenade/Mosaic focus-loss expectation.
      expect(FocusManager.instance.primaryFocus, same(catalogNode(tester, 8, 0)));
      _expectText(tester, 'SHARED MOVIES · SOURCE B',
          ['RAIL 7 MOVIES', 'SHARED MOVIES · SOURCE B']);
      for (var i = 0; i < 8; i++) {
        await _key(tester, LogicalKeyboardKey.arrowUp);
      }
      _expectText(tester, 'SHARED MOVIES · SOURCE A',
          ['SHARED MOVIES · SOURCE A', 'RAIL 1 MOVIES']);
      expect(FocusManager.instance.primaryFocus, same(catalogNode(tester, 0, 0)));
    });
  });

  testWidgets('Atrium public favourite focus swaps the actual identity branch',
      (tester) async {
    await _withHome(tester, _Catalogs(rows: 1), (appearance) async {
      final poster = tester.widget<ArtPoster>(find.byWidgetPredicate(
          (widget) => widget is ArtPoster && widget.title == 'Saved Atrium Movie'));
      final node = poster.focusNode;
      node.requestFocus();
      await pumpFavourites(tester);
      expect(find.byType(StageFavIdentity), findsOneWidget);
      expect(find.byType(CanvasIdentity), findsNothing);
      final fav = tester.widget<StageFavIdentity>(find.byType(StageFavIdentity));
      expect(fav.fav.title, 'Saved Atrium Movie');
      expect(fav.fav.subtitle, 'MY WATCHLIST · MOVIE');
      _expectText(tester, 'WATCHLIST MOVIES', ['WATCHLIST MOVIES', 'RAIL 0 MOVIES']);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, same(catalogNode(tester, 0, 0)));
      expect(find.byType(StageFavIdentity), findsNothing);
      expect(find.byType(CanvasIdentity), findsOneWidget);
      _expectText(tester, 'RAIL 0 MOVIES', ['WATCHLIST MOVIES', 'RAIL 0 MOVIES']);
      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(node));
      expect(find.byType(StageFavIdentity), findsOneWidget);
    }, savedFavourite: true);
  });

  testWidgets('Atrium inherited theme RTL and long text preserve actual labels',
      (tester) async {
    final catalogs = _Catalogs(rows: 2, longTitle: true);
    await _withHome(tester, catalogs, (appearance) async {
      final first = catalogNode(tester, 0, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      final before = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
      final theme = AppTheme.fromDetail(DetailThemes.broadsheet);
      final searchElement = tester.element(find.byType(SearchScreen));
      final originalWallColor = tester.widgetList<Text>(_wallLabels()).first.style!.color;
      final originalEyebrowColor = tester.widget<Text>(_eyebrow()).style!.color;
      appearance.value = (theme: theme, scale: 0.8, rtl: false);
      await pumpFavourites(tester);
      expect(tester.element(find.byType(SearchScreen)), same(searchElement));
      for (final text in tester.widgetList<Text>(_wallLabels())) {
        expect(text.style!.color, theme.fade(theme.core.tx, 0.86));
        expect(text.style!.color, isNot(originalWallColor));
      }
      expect(tester.widget<Text>(_eyebrow()).style!.color, originalEyebrowColor);
      appearance.value = (theme: theme, scale: 1.1, rtl: true);
      await pumpFavourites(tester);
      _expectText(tester, catalogs.title(0).toUpperCase(),
          [catalogs.title(0).toUpperCase(), catalogs.title(1).toUpperCase()]);
      final labels = checkActualWall(tester, 2);
      for (final paragraph in labels) {
        expect(paragraph.textDirection, TextDirection.rtl);
        expect(paragraph.textScaler.scale(12), closeTo(13.2, 0.000001));
        expect(paragraph.didExceedMaxLines, isTrue);
      }
      for (final text in tester.widgetList<Text>(_wallLabels())) {
        expect(text.style!.color, theme.fade(theme.core.tx, 0.86));
      }
      final eyebrow = tester.renderObject<RenderParagraph>(_eyebrow());
      expect(eyebrow.textDirection, TextDirection.rtl);
      expect(eyebrow.maxLines, 1);
      expect(eyebrow.overflow, TextOverflow.ellipsis);
      final after = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
      expect(after.item, same(before.item));
      expect(after.enriched, same(before.enriched));
      expect(after.trailerShowing, same(before.trailerShowing));
      expect(FocusManager.instance.primaryFocus, same(first));
    });
  });

  testWidgets('Atrium dossier uses narrow then headline in constrained geometry',
      (tester) async {
    await _withHome(tester, _Catalogs(rows: 2), (appearance) async {
      final first = catalogNode(tester, 0, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      final before = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
      expect(before.variant, StageIdentityVariant.narrow);
      expect(before.maxWidth, 520);
      checkActualWall(tester, 2);
      tester.view.physicalSize = const Size(640, 436);
      appearance.value = (theme: AppThemes.legacy, scale: 2.2, rtl: false);
      await pumpFavourites(tester);
      final after = tester.widget<CanvasIdentity>(find.byType(CanvasIdentity));
      expect(after.variant, StageIdentityVariant.headline);
      expect(after.maxWidth, closeTo(147.2, 0.000001));
      expect(after.item, same(before.item));
      expect(after.enriched, same(before.enriched));
      expect(after.trailerShowing, same(before.trailerShowing));
      final paragraphs = checkActualWall(tester, 1);
      expect(paragraphs.single.textScaler.scale(12), closeTo(26.4, 0.000001));
      _expectText(tester, 'RAIL 0 MOVIES', ['RAIL 0 MOVIES']);
      expect(FocusManager.instance.primaryFocus, same(first));
    });
  });
}
