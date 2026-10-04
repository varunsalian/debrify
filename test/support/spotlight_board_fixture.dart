import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const spotlightCapture = ValueKey('spotlight-original-capture');
const spotlightTrailer = ValueKey('spotlight-host-trailer');

StremioMeta spotlightMeta(String id, {String? background}) => StremioMeta(
  id: id,
  type: 'movie',
  name: 'Title $id',
  description: 'A deterministic description for $id.',
  background: background,
  genres: const ['Drama'],
);

/// Host-owned nodes and callbacks, independent of the private board State.
class SpotlightBoardFixture {
  final key = GlobalKey<SpotlightBoardState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final heroNode = FocusNode(debugLabel: 'original hero');
  final ownedNodes = <FocusNode>[];
  final events = <String>[];
  final ambient = <(String?, Color?)>[];
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;
  late final MockClient client = MockClient((request) async {
    requests.add(request);
    if (respond != null) {
      return respond!(request);
    }
    return http.Response('{}', 404);
  });
  List<StremioMeta> hero = [spotlightMeta('hero-a'), spotlightMeta('hero-b')];
  List<SpotlightShelf> sections = [];
  bool dpad = true;
  bool trailers = false;
  bool animations = false;
  bool shelvesOnly = false;
  bool paintBackground = true;
  bool largeInteractions = false;
  bool expand = true;
  bool pendingShelves = false;
  String look = 'spotlight';
  Widget? trailer;
  Future<bool> Function()? loadShelves;
  int opened = 0;
  Duration now = Duration.zero;

  SpotlightShelf shelf(
    String id, {
    int count = 5,
    SpotlightCardShape shape = SpotlightCardShape.poster,
    bool metadata = false,
    bool images = false,
    bool preview = false,
  }) {
    final nodes = List.generate(count, (i) => FocusNode(debugLabel: '$id/$i'));
    ownedNodes.addAll(nodes);
    return SpotlightShelf(
      id: id,
      title: 'Shelf $id',
      nodes: nodes,
      items: [
        for (var i = 0; i < count; i++)
          SpotlightCard(
            title: 'Card $id/$i',
            coverEmoji: null,
            image: images ? 'https://artwork.test/$id-$i.png' : null,
            fallbackImage: images ? 'https://artwork.test/fallback.png' : null,
            metadata: metadata ? spotlightMeta('$id-$i') : null,
            shape: shape,
            onOpen: () => opened++,
            onOptions: () => events.add('options $id/$i'),
            previewBuilder: preview
                ? (_) {
                    events.add('preview $id/$i');
                    return SizedBox(key: ValueKey('preview $id/$i'));
                  }
                : null,
          ),
      ],
    );
  }

  Widget host() => MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('en', 'US'),
    theme: ThemeData(
      brightness: Brightness.dark,
      platform: TargetPlatform.macOS,
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: RepaintBoundary(
          key: spotlightCapture,
          child: AppThemeScope(
            theme: PremiumLooks.byId(look)!.build(),
            child: Scaffold(
              body: SpotlightBoard(
                key: key,
                hero: hero,
                sections: sections,
                heroNode: heroNode,
                heroAddon: StremioAddon(
                  id: 'fixture',
                  name: 'Fixture',
                  manifestUrl: 'https://metadata.test/manifest.json',
                  baseUrl: 'https://metadata.test',
                ),
                onHeroOpen: (_, _) => opened++,
                dpad: dpad,
                trailersEnabled: trailers,
                onDwell: trailers
                    ? (item) => events.add('dwell ${item.id}')
                    : null,
                onTrailerStop: () => events.add('stop'),
                onAmbient: (art, tint) => ambient.add((art, tint)),
                onLoadMoreRow: (row) => events.add('load row $row'),
                onLoadMoreShelves: loadShelves,
                pendingShelves: pendingShelves,
                onExitTop: () => events.add('exit top'),
                trailer: trailer,
                animationsEnabled: animations,
                shelvesOnly: shelvesOnly,
                paintBackground: paintBackground,
                largeScreenInteractions: largeInteractions,
                expandFocusedCard: expand,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1920, 1080),
    double dpr = 1,
  }) async {
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    WidgetsBinding.instance.scheduleFrame();
    await pump(tester);
  }

  Future<void> pump(WidgetTester tester, [int millis = 0]) async {
    now += Duration(milliseconds: millis);
    await tester.pump(Duration(milliseconds: millis));
  }

  Future<void> settleSetup(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await pump(tester, 100);
    }
  }

  Future<void> focus(WidgetTester tester, FocusNode node) async {
    node.requestFocus();
    await pump(tester);
    await pump(tester, 250);
  }

  Future<void> keyPress(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await pump(tester);
  }

  void close() {
    heroNode.dispose();
    for (final node in ownedNodes) {
      node.dispose();
    }
    client.close();
    ParallaxTravel.resetForTest();
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    ProfileRuntime.debugReset();
    StremioService.instance.invalidateCache();
  }
}

Future<void> spotlightCase(
  WidgetTester tester,
  Future<void> Function(SpotlightBoardFixture) body,
) async {
  SharedPreferences.setMockInitialValues({});
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  StremioService.instance.invalidateCache();
  PlatformUtil.debugSetAndroidTvCached(false);
  PlatformUtil.debugSetTvOS(false);
  final f = SpotlightBoardFixture();
  ParallaxTravel.resetForTest();
  ParallaxTravel.clock = () => f.now;
  try {
    await http.runWithClient(() => body(f), () => f.client);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    f.close();
  }
}
