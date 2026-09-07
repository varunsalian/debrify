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

// Unchanged public Home only; never invoke a stage binding/private State.
// Each style gets four cases. No claim of exclusive theme dependency or
// native behavior; Search.build itself also subscribes to AppThemeScope.
typedef _Appearance = ({AppTheme theme, double scale});

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
        {'id': 'label-$rail', 'type': 'movie', 'name': 'Item', 'poster': ''},
    ]}),
    200,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> call(http.Request request) async {
    final url = request.url.toString();
    requests.add(url);
    for (var rail = 0; rail < rows; rail++) {
      final root = rail == 8 ? 'https://label-b.invalid' : 'https://label-a.invalid';
      if (request.method == 'GET' && url == '$root/catalog/movie/rail$rail.json') {
        if (heldNinth && rail == 8) {
          heldEntries++;
          return release.future;
        }
        return page(rail);
      }
      // Mosaic's unchanged last-line prefetch may request the terminal page.
      if (request.method == 'GET' &&
          url == '$root/catalog/movie/rail$rail/skip=1.json') {
        return page(rail, empty: true);
      }
    }
    unexpected.add('${request.method} $url');
    throw StateError('Unseeded rail-label transport');
  }

  Future<void> install() async {
    StremioAddon addon(String suffix, Iterable<int> indices) => StremioAddon(
      id: 'label.$suffix', name: suffix == 'a' ? 'Source A' : 'Source B',
      manifestUrl: 'https://label-$suffix.invalid/manifest.json',
      baseUrl: 'https://label-$suffix.invalid', resources: ['catalog'],
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

Finder _labelRow() => find.byWidgetPredicate((widget) {
  if (widget is! Row || widget.children.isEmpty) return false;
  final first = widget.children.first;
  if (first is! Column || first.children.isEmpty) return false;
  final icon = first.children.first;
  return icon is Icon && icon.icon == Icons.keyboard_arrow_up_rounded;
});

Finder _railSurface(String style) => find.byWidgetPredicate((widget) {
  if (widget is! ListView && widget is! GridView) return false;
  final key = widget.key;
  final prefix = style == 'promenade' ? 'prom-rail-' : 'mosaic-rail-';
  return key is ValueKey<String> && key.value.startsWith(prefix);
});

List<Text> _texts(WidgetTester tester) {
  expect(_labelRow(), findsOneWidget);
  return tester.widgetList<Text>(find.descendant(
    of: _labelRow(), matching: find.byType(Text))).toList();
}

void _expectLabel(WidgetTester tester, String style, String title, String? count) {
  final row = tester.widget<Row>(_labelRow());
  expect(row.mainAxisAlignment,
      style == 'promenade' ? MainAxisAlignment.center : MainAxisAlignment.end);
  final texts = _texts(tester);
  expect(texts.map((text) => text.data), [title, if (count != null) count]);
  expect(texts.first.style!.fontWeight, FontWeight.w800);
  expect(texts.first.style!.letterSpacing, 2.4);
  if (count != null) {
    expect(texts.last.style!.fontWeight, FontWeight.w700);
    expect(texts.last.style!.letterSpacing, 0.6);
  }
  // Real Row children, not an algorithm copy: BOTH text branches are Flexible.
  final flexible = row.children.whereType<Flexible>().toList();
  expect(flexible, hasLength(count == null ? 1 : 2));
  for (final text in texts) {
    expect(text.style!.fontSize, 12);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await pumpFavourites(tester);
}

Future<void> _withHome(WidgetTester tester, String style, _Catalogs catalogs,
    Future<void> Function(ValueNotifier<_Appearance>) body) async {
  await prepareFavourites(tester);
  await StorageService.setTvHomeStyle(style);
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
  await catalogs.install();
  final appearance = ValueNotifier<_Appearance>((theme: AppThemes.legacy, scale: 0.8));
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
              child: stableChild!,
            ),
          ),
        ),
        home: const SearchScreen(isTelevision: true),
      ));
      await pumpFavourites(tester);
      expect(_labelRow(), findsOneWidget);
      await body(appearance);
      expect(catalogs.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      if (!catalogs.release.isCompleted) catalogs.release.complete(catalogs.page(8));
      try {
        // Existing helper: actual unmount, finite12x100ms +3ms async steps,
        // then inherited11s post-unmount fake-clock cleanup. No new drain.
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
  for (final style in ['promenade', 'mosaic']) {
    testWidgets('Home $style single rail keeps alignment and omits counter',
        (tester) async {
      await _withHome(tester, style, _Catalogs(rows: 1), (appearance) async {
        _expectLabel(tester, style, 'RAIL 0 MOVIES', null);
        final first = catalogNode(tester, 0, 0);
        first.requestFocus();
        await pumpFavourites(tester);
        expect(FocusManager.instance.primaryFocus, same(first));
        expect(_texts(tester), hasLength(1));
      });
    });

    testWidgets('Home $style narrow real header keeps counter and DPAD identity',
        (tester) async {
      final catalogs = _Catalogs(rows: 3, longTitle: true);
      await _withHome(tester, style, catalogs, (appearance) async {
        final first = catalogNode(tester, 0, 0);
        first.requestFocus();
        await pumpFavourites(tester);
        final wide = tester.renderObject<RenderBox>(_labelRow()).constraints.maxWidth;
        // ONE explicit physical viewport resize. Assert the actual header,
        // not viewport==label width or a copied Mosaic column calculation.
        tester.view.physicalSize = const Size(640, 1080);
        await pumpFavourites(tester);
        final narrow = tester.renderObject<RenderBox>(_labelRow());
        debugPrint('RAIL $style viewport=${tester.view.physicalSize} '
            'header=${narrow.constraints} size=${narrow.size} priorMax=$wide');
        expect(narrow.constraints.maxWidth, greaterThan(0));
        expect(narrow.constraints.maxWidth, lessThan(wide));
        _expectLabel(tester, style, catalogs.title(0).toUpperCase(), '1/3');
        final title = find.descendant(of: _labelRow(),
            matching: find.text(catalogs.title(0).toUpperCase()));
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(paragraph.didExceedMaxLines, isTrue);
        expect(paragraph.size.width, lessThanOrEqualTo(narrow.size.width));
        expect(catalogNode(tester, 0, 0), same(first));
        expect(FocusManager.instance.primaryFocus, same(first));
        await _key(tester, LogicalKeyboardKey.arrowDown);
        final second = catalogNode(tester, 1, 0);
        expect(FocusManager.instance.primaryFocus, same(second));
        _expectLabel(tester, style, catalogs.title(1).toUpperCase(), '2/3');
        await _key(tester, LogicalKeyboardKey.arrowUp);
        expect(catalogNode(tester, 0, 0), same(first));
        expect(FocusManager.instance.primaryFocus, same(first));
        _expectLabel(tester, style, catalogs.title(0).toUpperCase(), '1/3');
      });
    });

    testWidgets('Home $style held ninth rail refreshes live duplicate provenance',
        (tester) async {
      final catalogs = _Catalogs(rows: 9, heldNinth: true);
      await _withHome(tester, style, catalogs, (appearance) async {
        final first = catalogNode(tester, 0, 0);
        first.requestFocus();
        await pumpFavourites(tester);
        _expectLabel(tester, style, 'SHARED MOVIES', '1/8');
        for (var i = 0; i < 7; i++) {
          await _key(tester, LogicalKeyboardKey.arrowDown);
        }
        final tail = catalogNode(tester, 7, 0);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(catalogs.heldEntries, 1);
        expect(catalogs.release.isCompleted, isFalse);
        expect(FocusManager.instance.primaryFocus, same(tail));
        _expectLabel(tester, style, 'RAIL 7 MOVIES', '8/8');
        final tailScope = tail.enclosingScope;
        expect(tailScope, isNotNull);
        catalogs.release.complete(catalogs.page(8));
        await pumpFavourites(tester);
        final ninth = catalogNode(tester, 8, 0);
        // Existing quirk: the new rail renders, but deferred focus is lost.
        expect(FocusManager.instance.primaryFocus, same(tailScope));
        expect(tail.hasFocus, isFalse);
        expect(ninth.hasFocus, isFalse);
        expect(ninth.context, isNotNull);
        expect(ninth.context!.mounted, isTrue);
        _expectLabel(tester, style, 'SHARED MOVIES · SOURCE B', '9/9');
        // Explicit public-node RECOVERY, not automatic deferred-focus proof.
        ninth.requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        expect(FocusManager.instance.primaryFocus, same(ninth));
        for (var i = 0; i < 8; i++) {
          await _key(tester, LogicalKeyboardKey.arrowUp);
        }
        _expectLabel(tester, style, 'SHARED MOVIES · SOURCE A', '1/9');
        expect(catalogNode(tester, 0, 0), same(first));
        expect(FocusManager.instance.primaryFocus, same(first));
      });
    });

    testWidgets('Home $style inherited paint and scaler cross label height floor',
        (tester) async {
      await _withHome(tester, style, _Catalogs(rows: 2), (appearance) async {
        final first = catalogNode(tester, 0, 0);
        first.requestFocus();
        await pumpFavourites(tester);
        final search = tester.element(find.byType(SearchScreen));
        final oldColor = _texts(tester).first.style!.color;
        final next = AppTheme.fromDetail(DetailThemes.broadsheet);
        // Theme-only update first; do not use a simultaneous scaler change
        // as surrogate evidence for inherited theme notification.
        appearance.value = (theme: next, scale: 0.8);
        await pumpFavourites(tester);
        _expectLabel(tester, style, 'RAIL 0 MOVIES', '1/2');
        expect(_texts(tester).first.style!.color, next.fade(next.core.tx, 0.82));
        expect(_texts(tester).first.style!.color, isNot(oldColor));
        expect(_texts(tester).last.style!.color, next.fade(next.core.tx, 0.32));
        Finder title() => find.descendant(of: _labelRow(), matching: find.text('RAIL 0 MOVIES'));
        appearance.value = (theme: next, scale: 1.5);
        await pumpFavourites(tester);
        final before = tester.renderObject<RenderParagraph>(title());
        expect(before.textScaler.scale(10), closeTo(15, 0.000001));
        final beforeHeight = before.size.height;
        final beforeRowHeight = tester.getSize(_labelRow()).height;
        final surfaceKey = tester.widget(_railSurface(style)).key;
        appearance.value = (theme: next, scale: 1.8);
        await pumpFavourites(tester);
        final paragraph = tester.renderObject<RenderParagraph>(title());
        expect(paragraph.textScaler.scale(10), closeTo(18, 0.000001));
        expect(paragraph.size.height, greaterThan(beforeHeight));
        expect(tester.getSize(_labelRow()).height, greaterThan(beforeRowHeight));
        expect(paragraph.maxLines, 1);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        // Actual public rectangles only. No glyph-height ==1.35 heuristic
        // assertion, no frozen caption height, no private budget invocation.
        expect(tester.getBottomLeft(_labelRow()).dy,
            lessThanOrEqualTo(tester.getTopLeft(_railSurface(style)).dy));
        expect(tester.widget(_railSurface(style)).key, surfaceKey);
        expect(tester.element(find.byType(SearchScreen)), same(search));
        expect(catalogNode(tester, 0, 0), same(first));
        expect(FocusManager.instance.primaryFocus, same(first));
        _expectLabel(tester, style, 'RAIL 0 MOVIES', '1/2');
      });
    });
  }
}
