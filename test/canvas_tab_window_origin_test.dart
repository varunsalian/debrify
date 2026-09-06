import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage/home_prefs.dart';
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

// PREP ONLY. These mount unchanged public Home, never a tab-policy copy or
// private State. Theme assertions concern rendered output, not the identity
// of the inherited dependency element (Search.build also reads the theme).
typedef _Appearance = ({AppTheme theme, double scale});

class _Catalogs {
  _Catalogs({this.heldNinth = false});

  final bool heldNinth;
  final release = Completer<http.Response>();
  final requests = <String>[];
  final unexpected = <String>[];
  int heldEntries = 0;

  http.Response page(int rail, [int first = 0]) => http.Response(
    jsonEncode({
      'metas': [
        if (first == 0)
          for (var col = 0; col < 12; col++)
            {'id': 'tab-$rail-$col', 'type': 'movie', 'name': 'Item $col',
              'poster': ''},
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> call(http.Request request) async {
    final url = request.url.toString();
    requests.add(url);
    for (var rail = 0; rail < (heldNinth ? 9 : 6); rail++) {
      final root = rail == 8 ? 'https://tabs-b.invalid' : 'https://tabs-a.invalid';
      if (request.method == 'GET' &&
          url == '$root/catalog/movie/rail$rail.json') {
        if (heldNinth && rail == 8) {
          heldEntries++;
          return release.future;
        }
        return page(rail);
      }
      if (request.method == 'GET' &&
          url == '$root/catalog/movie/rail$rail/skip=12.json') {
        return page(rail, 12);
      }
    }
    unexpected.add('${request.method} $url');
    throw StateError('Unseeded Canvas transport');
  }

  Future<void> install() async {
    StremioAddon addon(String suffix, Iterable<int> rails) => StremioAddon(
      id: 'tabs.$suffix',
      name: suffix == 'a' ? 'Source A' : 'Source B',
      manifestUrl: 'https://tabs-$suffix.invalid/manifest.json',
      baseUrl: 'https://tabs-$suffix.invalid',
      resources: ['catalog'], types: ['movie'],
      catalogs: [
        for (final rail in rails)
          StremioAddonCatalog(
            id: 'rail$rail', type: 'movie',
            name: heldNinth && (rail == 0 || rail == 8)
                ? 'Shared Movies' : 'Rail $rail Movies',
            extraSupported: ['skip'],
          ),
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stremio_addons_v1', jsonEncode([
      addon('a', List.generate(heldNinth ? 8 : 6, (i) => i)).toJson(),
      if (heldNinth) addon('b', [8]).toJson(),
    ]));
    StremioService.instance.invalidateCache();
    addTearDown(StremioService.instance.invalidateCache);
  }
}

Finder _tabRow() => find.byWidgetPredicate((widget) {
  if (widget is! Row || widget.children.isEmpty) return false;
  final first = widget.children.first;
  if (first is! Padding) return false;
  final column = first.child;
  if (column is! Column || column.children.isEmpty) return false;
  final icon = column.children.first;
  return icon is Icon && icon.icon == Icons.keyboard_arrow_up_rounded;
});

Finder _shelf() => find.byWidgetPredicate((widget) => widget is ListView &&
    widget.key is ValueKey<String> &&
    (widget.key! as ValueKey<String>).value.startsWith('canvas-rail-'));

List<Text> _tabTexts(WidgetTester tester) {
  expect(_tabRow(), findsOneWidget);
  return tester.widgetList<Text>(find.descendant(
    of: _tabRow(), matching: find.byType(Text))).toList();
}

void _expectTabs(WidgetTester tester, List<String> labels, String? active,
    {String? tail}) {
  final texts = _tabTexts(tester);
  expect(texts.map((text) => text.data), [...labels, if (tail != null) tail]);
  for (final label in labels) {
    final text = texts.singleWhere((text) => text.data == label);
    expect(text.style!.fontWeight,
        label == active ? FontWeight.w800 : FontWeight.w600);
    expect(text.style!.fontSize, 12.5);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  }
  final underlines = tester.widgetList<Container>(find.descendant(
    of: _tabRow(), matching: find.byType(Container))).where((container) =>
      container.constraints?.maxWidth == 26 &&
      container.constraints?.maxHeight == 2.5).toList();
  expect(underlines, hasLength(labels.length));
  for (var i = 0; i < labels.length; i++) {
    expect((underlines[i].decoration! as BoxDecoration).color,
        labels[i] == active ? texts[i].style!.color : Colors.transparent);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _width(WidgetTester tester, double requested) async {
  expect(_tabRow(), findsOneWidget);
  final before = tester.renderObject<RenderBox>(_tabRow());
  final loss = tester.view.physicalSize.width - before.constraints.maxWidth;
  // Use measured public layout loss, not viewport==tab width or a copied
  // viewport/inset formula. There is one resize, no convergence/retry loop.
  tester.view.physicalSize = Size(requested + loss, 1080);
  await pumpFavourites(tester);
  final row = tester.renderObject<RenderBox>(_tabRow());
  debugPrint('CANVAS tabs requested=$requested constraints=${row.constraints} '
      'size=${row.size} measuredViewportLoss=$loss');
  expect(row.constraints.maxWidth, closeTo(requested, 0.000001));
  expect(row.size.width, closeTo(requested, 0.000001));
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await pumpFavourites(tester);
}

Future<void> _withHome(WidgetTester tester,
    Future<void> Function(_Catalogs, ValueNotifier<_Appearance>) body,
    {bool heldNinth = false}) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle('canvas');
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
  final catalogs = _Catalogs(heldNinth: heldNinth);
  await catalogs.install();
  final appearance = ValueNotifier<_Appearance>(
    (theme: AppThemes.legacy, scale: 0.8));
  final client = MockClient(catalogs.call);
  await http.runWithClient(() async {
    try {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ValueListenableBuilder<_Appearance>(
          valueListenable: appearance,
          child: child,
          builder: (context, value, stableChild) => AppThemeScope(
            theme: value.theme,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(value.scale)),
              child: stableChild!,
            ),
          ),
        ),
        home: const SearchScreen(isTelevision: true),
      ));
      await pumpFavourites(tester);
      expect(_tabRow(), findsOneWidget);
      await body(catalogs, appearance);
      expect(catalogs.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      if (!catalogs.release.isCompleted) catalogs.release.complete(catalogs.page(8));
      try {
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

  testWidgets('Home Canvas measured tab-width boundaries and four-slot cap',
      (tester) async {
    await _withHome(tester, (catalogs, appearance) async {
      final first = catalogNode(tester, 0, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      // Explicit visible outcomes; no copy of start/end/window calculations.
      final cases = [
        (width: 312.0, labels: <String>[], tail: '+6 more'),
        (width: 313.0, labels: ['Rail 0 Movies'], tail: '+5 more'),
        (width: 508.0, labels: ['Rail 0 Movies'], tail: '+5 more'),
        (width: 509.0, labels: ['Rail 0 Movies', 'Rail 1 Movies'], tail: '+4 more'),
        (width: 704.0, labels: ['Rail 0 Movies', 'Rail 1 Movies'], tail: '+4 more'),
        (width: 705.0, labels: ['Rail 0 Movies', 'Rail 1 Movies', 'Rail 2 Movies'],
          tail: '+3 more'),
        (width: 900.0, labels: ['Rail 0 Movies', 'Rail 1 Movies', 'Rail 2 Movies'],
          tail: '+3 more'),
        (width: 901.0, labels: ['Rail 0 Movies', 'Rail 1 Movies', 'Rail 2 Movies',
          'Rail 3 Movies'], tail: '+2 more'),
        (width: 1097.0, labels: ['Rail 0 Movies', 'Rail 1 Movies', 'Rail 2 Movies',
          'Rail 3 Movies'], tail: '+2 more'),
      ];
      for (final sample in cases) {
        await _width(tester, sample.width);
        _expectTabs(tester, sample.labels, 'Rail 0 Movies', tail: sample.tail);
        expect(catalogNode(tester, 0, 0), same(first));
        expect(FocusManager.instance.primaryFocus, same(first));
      }
    });
  });

  testWidgets('Home Canvas one-slot nonfirst active and tail DPAD preserve nodes',
      (tester) async {
    await _withHome(tester, (catalogs, appearance) async {
      await _width(tester, 313);
      catalogNode(tester, 0, 0).requestFocus();
      await pumpFavourites(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      final third = catalogNode(tester, 2, 0);
      expect(FocusManager.instance.primaryFocus, same(third));
      _expectTabs(tester, ['Rail 2 Movies'], 'Rail 2 Movies', tail: '+3 more');
      await _key(tester, LogicalKeyboardKey.arrowUp);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(catalogNode(tester, 2, 0), same(third));
      expect(FocusManager.instance.primaryFocus, same(third));
      for (var i = 0; i < 3; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
      }
      final last = catalogNode(tester, 5, 0);
      _expectTabs(tester, ['Rail 5 Movies'], 'Rail 5 Movies');
      await _width(tester, 901);
      _expectTabs(tester, ['Rail 2 Movies', 'Rail 3 Movies', 'Rail 4 Movies',
        'Rail 5 Movies'], 'Rail 5 Movies');
      expect(catalogNode(tester, 5, 0), same(last));
      expect(FocusManager.instance.primaryFocus, same(last));
    });
  });

  testWidgets('Home Canvas held ninth catalog adds live duplicate provenance',
      (tester) async {
    await _withHome(tester, (catalogs, appearance) async {
      await _width(tester, 901);
      final first = catalogNode(tester, 0, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      _expectTabs(tester, ['Shared Movies', 'Rail 1 Movies', 'Rail 2 Movies',
        'Rail 3 Movies'], 'Shared Movies', tail: '+4 more');
      for (var i = 0; i < 7; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
      }
      final lastBefore = catalogNode(tester, 7, 0);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(catalogs.heldEntries, 1);
      expect(catalogs.release.isCompleted, isFalse);
      expect(FocusManager.instance.primaryFocus, same(lastBefore));
      _expectTabs(tester, ['Rail 4 Movies', 'Rail 5 Movies', 'Rail 6 Movies',
        'Rail 7 Movies'], 'Rail 7 Movies');
      catalogs.release.complete(catalogs.page(8));
      await pumpFavourites(tester);
      expect(FocusManager.instance.primaryFocus, same(catalogNode(tester, 8, 0)));
      _expectTabs(tester, ['Rail 5 Movies', 'Rail 6 Movies', 'Rail 7 Movies',
        'Shared Movies · Source B'], 'Shared Movies · Source B');
      for (var i = 0; i < 8; i++) {
        await _key(tester, LogicalKeyboardKey.arrowUp);
      }
      _expectTabs(tester, ['Shared Movies · Source A', 'Rail 1 Movies',
        'Rail 2 Movies', 'Rail 3 Movies'], 'Shared Movies · Source A', tail: '+5 more');
      expect(catalogNode(tester, 0, 0), same(first));
      expect(FocusManager.instance.primaryFocus, same(first));
    }, heldNinth: true);
  });

  testWidgets('Home Canvas inherited theme changes actual active and idle paint',
      (tester) async {
    await _withHome(tester, (catalogs, appearance) async {
      await _width(tester, 509);
      final first = catalogNode(tester, 0, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      final searchElement = tester.element(find.byType(SearchScreen));
      final before = _tabTexts(tester).first.style!.color;
      final next = AppTheme.fromDetail(DetailThemes.broadsheet);
      expect(next.core.tx, isNot(AppThemes.legacy.core.tx));
      appearance.value = (theme: next, scale: 0.8);
      await pumpFavourites(tester);
      final texts = _tabTexts(tester);
      expect(texts[0].style!.color, next.core.tx);
      expect(texts[0].style!.color, isNot(before));
      expect(texts[1].style!.color, next.fade(next.core.tx, 0.5));
      expect(texts[2].style!.color, next.fade(next.core.tx, 0.24));
      _expectTabs(tester, ['Rail 0 Movies', 'Rail 1 Movies'], 'Rail 0 Movies',
          tail: '+4 more');
      expect(tester.element(find.byType(SearchScreen)), same(searchElement));
      expect(catalogNode(tester, 0, 0), same(first));
      expect(FocusManager.instance.primaryFocus, same(first));
    });
  });

  testWidgets('Home Canvas inner MediaQuery scales paragraphs with shelf clearance',
      (tester) async {
    await _withHome(tester, (catalogs, appearance) async {
      await _width(tester, 509);
      final first = catalogNode(tester, 0, 0);
      first.requestFocus();
      await pumpFavourites(tester);
      Finder label() => find.descendant(of: _tabRow(),
          matching: find.text('Rail 0 Movies'));
      final before = tester.getSize(label()).height;
      final shelfBefore = tester.getSize(_shelf());
      final shelfKey = tester.widget<ListView>(_shelf()).key;
      appearance.value = (theme: AppThemes.legacy, scale: 1.4);
      await pumpFavourites(tester);
      final paragraph = tester.renderObject<RenderParagraph>(label());
      expect(paragraph.textScaler.scale(10), closeTo(14, 0.000001));
      expect(paragraph.size.height, greaterThan(before));
      expect(paragraph.maxLines, 1);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(paragraph.constraints.maxWidth, lessThanOrEqualTo(170));
      expect(tester.getBottomLeft(_tabRow()).dy,
          lessThanOrEqualTo(tester.getTopLeft(_shelf()).dy));
      // Existing caption band also scales. Do not freeze its height or claim
      // that only the tab row is an inherited MediaQuery consumer.
      expect(tester.getSize(_shelf()).height, greaterThan(shelfBefore.height));
      expect(tester.getSize(_shelf()).width, shelfBefore.width);
      expect(tester.widget<ListView>(_shelf()).key, shelfKey);
      _expectTabs(tester, ['Rail 0 Movies', 'Rail 1 Movies'], 'Rail 0 Movies',
          tail: '+4 more');
      expect(catalogNode(tester, 0, 0), same(first));
      expect(FocusManager.instance.primaryFocus, same(first));
    });
  });
}
