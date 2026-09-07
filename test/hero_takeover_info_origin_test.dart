import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;

// PREP ONLY, unrun. Original rendered notifier writes characterize passive
// presentation, not native playback, transport success or seven-stage credit.
typedef _Appearance = ({AppTheme theme, double scale, bool rtl});

const _seed = StremioMeta(
  id: 'passive-takeover', type: 'movie', name: 'Original movie', poster: '',
);

class _Transport {
  final unexpected = <String>[];
  final requests = <String>[];

  Future<http.Response> call(http.Request request) async {
    final url = request.url.toString();
    requests.add('${request.method} $url');
    const first = 'https://takeover-origin.invalid/catalog/movie/movies.json';
    const terminal =
        'https://takeover-origin.invalid/catalog/movie/movies/skip=1.json';
    if (request.method == 'GET' && (url == first || url == terminal)) {
      return http.Response(jsonEncode({'metas': [
        if (url == first)
          {'id': _seed.id, 'type': 'movie', 'name': _seed.name, 'poster': ''},
      ]}), 200, headers: {'content-type': 'application/json'});
    }
    unexpected.add('${request.method} $url');
    throw StateError('Unseeded passive takeover request');
  }

  Future<void> install() async {
    final addon = StremioAddon(
      id: 'takeover.origin', name: 'Takeover origin',
      manifestUrl: 'https://takeover-origin.invalid/manifest.json',
      baseUrl: 'https://takeover-origin.invalid', resources: ['catalog'],
      types: ['movie'], catalogs: [
        StremioAddonCatalog(id: 'movies', type: 'movie', name: 'Movies',
            extraSupported: ['skip']),
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stremio_addons_v1', jsonEncode([addon.toJson()]));
    StremioService.instance.invalidateCache();
    addTearDown(StremioService.instance.invalidateCache);
  }
}

class _OriginalSignals {
  _OriginalSignals(this.item, this.enriched, this.takeover, this.root);
  final ValueNotifier<StremioMeta?> item;
  final ValueNotifier<StremioMeta?> enriched;
  final ValueNotifier<double> takeover;
  final Finder root;
}

_OriginalSignals _findOriginalSignals(WidgetTester tester) {
  // Only the overlay's double VLB is nested under both item and enriched VLBs.
  // Do not call any builder or construct substitute notification sources.
  final candidates = <({Element element, List<Element> metadata})>[];
  for (final element in find.byWidgetPredicate(
      (w) => w is ValueListenableBuilder<double>).evaluate()) {
    final metadata = <Element>[];
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is ValueListenableBuilder<StremioMeta?>) {
        metadata.add(ancestor);
      }
      return ancestor.widget is! SearchScreen;
    });
    if (metadata.length == 2) candidates.add((element: element, metadata: metadata));
  }
  expect(candidates, hasLength(1));
  final found = candidates.single;
  final outer = found.metadata[1];
  final item = (outer.widget as ValueListenableBuilder<StremioMeta?>).valueListenable;
  final enriched = (found.metadata[0].widget
      as ValueListenableBuilder<StremioMeta?>).valueListenable;
  final takeover = (found.element.widget
      as ValueListenableBuilder<double>).valueListenable;
  expect(item, isA<ValueNotifier<StremioMeta?>>());
  expect(enriched, isA<ValueNotifier<StremioMeta?>>());
  expect(takeover, isA<ValueNotifier<double>>());
  expect(identical(item, enriched), isFalse);
  expect(item.value?.id, _seed.id);
  final recede = tester.widgetList<ValueListenableBuilder<double>>(
    find.byWidgetPredicate((w) => w is ValueListenableBuilder<double> &&
        w.child is Column),
  ).toList();
  expect(recede, hasLength(1));
  expect(recede.single.valueListenable, same(takeover));
  expect(takeover.value, 0);
  final root = find.byElementPredicate((element) => identical(element, outer));
  expect(root, findsOneWidget);
  return _OriginalSignals(item as ValueNotifier<StremioMeta?>,
      enriched as ValueNotifier<StremioMeta?>, takeover as ValueNotifier<double>, root);
}

Finder _text(_OriginalSignals signals, String value) => find.descendant(
  of: signals.root, matching: find.text(value),
);

Opacity _nearestOpacity(WidgetTester tester, Finder child) {
  expect(child, findsOneWidget);
  Opacity? result;
  tester.element(child).visitAncestorElements((element) {
    if (element.widget is Opacity) {
      result = element.widget as Opacity;
      return false;
    }
    return true;
  });
  expect(result, isNotNull);
  return result!;
}

Future<void> _withHome(WidgetTester tester,
    Future<void> Function(_OriginalSignals, ValueNotifier<_Appearance>) body) async {
  final previous = (dim: MainPageBridge.tvChromeDim.value,
    tint: MainPageBridge.tvHeroTint.value, art: MainPageBridge.tvAmbientArt.value,
    lights: MainPageBridge.tvStageLightsOff.value,
    ready: MainPageBridge.homeBoardReady.value);
  await prepareFavourites(tester);
  // Existing helper selects classic TV Home, 1920x1080/DPR1, scheduling OFF.
  await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
  final transport = _Transport();
  await transport.install();
  final client = MockClient(transport.call);
  final appearance = ValueNotifier<_Appearance>(
      (theme: AppThemes.legacy, scale: 0.8, rtl: false));
  await http.runWithClient(() async {
    try {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ValueListenableBuilder<_Appearance>(
          valueListenable: appearance, child: child,
          builder: (context, value, stableChild) => AppThemeScope(
            theme: value.theme,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(value.scale)),
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
      final signals = _findOriginalSignals(tester); // BEFORE any signal writes.
      expect(transport.requests, contains(
          'GET https://takeover-origin.invalid/catalog/movie/movies.json'));
      expect(transport.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
      await body(signals, appearance);
      expect(transport.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      try {
        // Existing unmount +12x100ms/3ms +11s post-unmount fakeclock cleanup.
        // No extra drain, error suppression or writes to disposed borrowed refs.
        await closeFavourites(tester);
        expect(MainPageBridge.tvChromeDim.value, 0);
        expect(MainPageBridge.tvStageLightsOff.value, isFalse);
      } finally {
        client.close();
        appearance.dispose();
        MainPageBridge.tvChromeDim.value = previous.dim;
        MainPageBridge.tvHeroTint.value = previous.tint;
        MainPageBridge.tvAmbientArt.value = previous.art;
        MainPageBridge.tvStageLightsOff.value = previous.lights;
        MainPageBridge.homeBoardReady.value = previous.ready;
      }
    }
    expect(transport.unexpected, isEmpty);
    expect(tester.takeException(), isNull);
  }, () => client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Home overlay shares original recede signal and null threshold',
      (tester) => _withHome(tester, (s, appearance) async {
    expect(_text(s, 'NOW PLAYING  ·  OFFICIAL TRAILER'), findsNothing);
    s.takeover.value = 0.001;
    await tester.pump();
    expect(_text(s, 'NOW PLAYING  ·  OFFICIAL TRAILER'), findsNothing);
    s.takeover.value = 0.0011;
    await tester.pump();
    expect(_text(s, 'NOW PLAYING  ·  OFFICIAL TRAILER'), findsOneWidget);
    expect(_nearestOpacity(tester, _text(s, 'ORIGINAL MOVIE')).opacity, 0);
    expect(MainPageBridge.tvChromeDim.value, 0.0011);
    final original = s.item.value;
    s.item.value = null;
    await tester.pump();
    expect(_text(s, 'ORIGINAL MOVIE'), findsNothing);
    s.item.value = original;
    await tester.pump();
    expect(_text(s, 'ORIGINAL MOVIE'), findsOneWidget);
  }));

  testWidgets('real Home metadata fallbacks keep original title and literal order',
      (tester) => _withHome(tester, (s, appearance) async {
    s.enriched.value = const StremioMeta(id: 'passive-enriched', type: 'movie',
      name: 'Enriched name', year: '1999', runtime: '101 min', imdbRating: 8.2,
      genres: ['Drama', 'Mystery', 'Comedy', 'Fourth']);
    s.takeover.value = 1;
    await tester.pump();
    final values = tester.widgetList<Text>(find.descendant(of: s.root,
        matching: find.byType(Text))).map((w) => w.data).toList();
    expect(values, ['NOW PLAYING  ·  OFFICIAL TRAILER', 'ORIGINAL MOVIE',
      '1h 41m', '8.2', 'DRAMA   •   MYSTERY   •   COMEDY']);
    s.item.value = const StremioMeta(id: 'passive-takeover', type: 'movie',
      name: 'Original movie', year: '2024', runtime: '80 min', imdbRating: 0,
      genres: ['Own']);
    await tester.pump();
    expect(tester.widgetList<Text>(find.descendant(of: s.root,
        matching: find.byType(Text))).map((w) => w.data).toList(),
      ['NOW PLAYING  ·  OFFICIAL TRAILER', 'ORIGINAL MOVIE',
       '2024', '1h 20m', '0.0', 'OWN']);
    s.enriched.value = null;
    s.item.value = _seed;
    await tester.pump();
    expect(tester.widgetList<Text>(find.descendant(of: s.root,
        matching: find.byType(Text))).map((w) => w.data).toList(),
      ['NOW PLAYING  ·  OFFICIAL TRAILER', 'ORIGINAL MOVIE']);
  }));

  testWidgets('takeover-only paint keeps captured title child across literal endpoints',
      (tester) => _withHome(tester, (s, appearance) async {
    s.takeover.value = 0.5;
    await tester.pump();
    final titleFinder = _text(s, 'ORIGINAL MOVIE');
    final title = tester.widget<Text>(titleFinder);
    expect(_nearestOpacity(tester, titleFinder).opacity, 0);
    s.takeover.value = 0.65;
    await tester.pump();
    expect(tester.widget<Text>(titleFinder), same(title));
    expect(_nearestOpacity(tester, titleFinder).opacity, closeTo(0.5, 0.000001));
    Transform? rise;
    tester.element(titleFinder).visitAncestorElements((element) {
      if (element.widget is Transform) {
        rise = element.widget as Transform;
        return false;
      }
      return true;
    });
    expect(rise, isNotNull);
    expect(rise!.transform.storage[13], closeTo(1.75, 0.000001));
    s.takeover.value = 0.8;
    await tester.pump();
    expect(tester.widget<Text>(titleFinder), same(title));
    expect(_nearestOpacity(tester, titleFinder).opacity, 1);
  }));

  testWidgets('same Home theme then metadata rebuild retain actual helper palette phases',
      (tester) => _withHome(tester, (s, appearance) async {
    s.item.value = const StremioMeta(id: 'passive-takeover', type: 'movie',
      name: 'Original movie', year: '2024', runtime: '80 min', imdbRating: 0);
    s.takeover.value = 0.8;
    await tester.pump();
    final screen = tester.element(find.byType(SearchScreen));
    expect(tester.widget<Text>(_text(s, 'ORIGINAL MOVIE')).style!.color,
        AppThemes.legacy.core.tx);
    final theme = AppTheme.fromDetail(DetailThemes.broadsheet);
    appearance.value = (theme: theme, scale: 0.8, rtl: false);
    await tester.pump();
    expect(tester.element(find.byType(SearchScreen)), same(screen));
    expect(tester.widget<Text>(_text(s, 'ORIGINAL MOVIE')).style!.color,
        theme.core.tx);
    expect(tester.widget<Text>(_text(s, '2024')).style!.color,
        theme.fade(theme.core.tx, 0.9));
    final title = tester.widget<Text>(_text(s, 'ORIGINAL MOVIE'));
    // Metadata rebuild AFTER theme-only paint exposes stale outer-app captures.
    s.enriched.value = const StremioMeta(id: 'passive-enriched', type: 'movie',
        name: 'Ignored enriched', genres: ['Drama']);
    await tester.pump();
    expect(tester.widget<Text>(_text(s, 'ORIGINAL MOVIE')), isNot(same(title)));
    expect(tester.widget<Text>(_text(s, 'ORIGINAL MOVIE')).style!.color,
        theme.core.tx);
    expect(tester.widget<Text>(_text(s, '2024')).style!.color,
        theme.fade(theme.core.tx, 0.9));
    expect(_nearestOpacity(tester, _text(s, 'ORIGINAL MOVIE')).opacity, 1);
    appearance.value = (theme: theme, scale: 1.1, rtl: true);
    await tester.pump();
    expect(tester.element(find.byType(SearchScreen)), same(screen));
    final rich = find.descendant(of: _text(s, 'ORIGINAL MOVIE'),
        matching: find.byType(RichText));
    expect(rich, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(rich);
    expect(paragraph.textDirection, TextDirection.rtl);
    expect(paragraph.textScaler.scale(46), closeTo(50.6, 0.000001));
    expect(tester.takeException(), isNull);
  }));
}
