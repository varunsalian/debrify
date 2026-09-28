import 'package:debrify/features/home/presentation/home_see_all_navigation.dart';
import 'package:debrify/models/mdblist_list_choice.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/see_all/catalog_see_all_screen.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:debrify/screens/see_all/trakt_see_all_screen.dart';
import 'package:debrify/screens/see_all/simkl_see_all_screen.dart';
import 'package:debrify/screens/see_all/mdblist_see_all_screen.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';
import 'package:debrify/services/simkl/simkl_list_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const first = StremioMeta(id: 'one', type: 'movie', name: 'First');
const second = StremioMeta(id: 'two', type: 'series', name: 'Second');

class Harness {
  final navigator = GlobalKey<NavigatorState>();
  late BuildContext context;
  late Widget screen;
  bool pikpak = false;
  final items = <StremioMeta>[first];
  final progress = <String, double>{'one': .2};
  final calls = <String>[];
  late final routes = HomeSeeAllNavigation(
    isTelevision: () => true,
    pikpakOnly: () => pikpak,
    // Capture the real destination without starting its unrelated network reads.
    wrap: (child) {
      screen = child;
      return const SizedBox();
    },
    isBound: (item) => item.id == 'one',
    afterReturn: () async {
      calls.add('return');
    },
    afterTrackerReturn: () async {
      calls.add('tracker return');
    },
    traktItems: () => items,
    traktProgress: () => progress,
    simklItems: () => items,
    simklProgress: () => progress,
    openTraktItem: (_) => calls.add('trakt open'),
    playTraktItem: (_) => calls.add('trakt play'),
    openSimklItem: (_) => calls.add('simkl open'),
    playSimklItem: (_) => calls.add('simkl play'),
    openSimklCwItem: (_) => calls.add('simkl cw open'),
    playSimklCwItem: (_) => calls.add('simkl cw play'),
    openMdblist: (_) => calls.add('mdb open'),
    playMdblist: (_) => calls.add('mdb play'),
    openItem: (_, addon) => calls.add('open ${addon.id}'),
    playItem: (_, addon) => calls.add('play ${addon.id}'),
  );
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    ),
  );
  Future<void> pop(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('catalog snapshots on build and returns to ordinary refresh', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    final addon = StremioAddon(
      id: 'origin',
      name: 'Origin',
      baseUrl: '',
      manifestUrl: '',
    );
    final section = CatalogSection(
      title: 'Search',
      addon: addon,
      catalog: StremioAddonCatalog(id: 'movies', type: 'movie', name: 'Movies'),
      items: h.items,
      query: 'query',
      nextSkip: 25,
    );
    h.routes.openCatalog(h.context, section);
    h.items.add(second);
    section.nextSkip = 50;
    await tester.pumpAndSettle();
    final screen = h.screen as CatalogSeeAllScreen;
    expect(screen.seedItems, [first, second]);
    expect(screen.seedNextSkip, 50);
    expect(screen.query, 'query');
    h.items.clear();
    expect(screen.seedItems, hasLength(2));
    screen.onOpenItem(first);
    screen.onQuickPlay!(first);
    await h.pop(tester);
    expect(h.calls, ['open origin', 'play origin', 'return']);
  });

  testWidgets('continuation preserves reload and optional return ownership', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    h.routes.pushContinuation(
      h.context,
      title: 'Continue Watching',
      initialCategory: 'series',
      items: h.items,
      progressOf: (_) => .3,
      onOpen: (_) => h.calls.add('open'),
      onQuickPlay: null,
      onReload: () async => [second],
      onReturn: () => h.calls.add('cw return'),
    );
    h.items.add(second);
    await tester.pumpAndSettle();
    final screen = h.screen as ContinueWatchingSeeAllScreen;
    expect(screen.items, [first, second]);
    expect(screen.initialCategory, 'series');
    expect(screen.onQuickPlay, isNull);
    expect(await screen.onReload!(), [second]);
    screen.onOpen(first);
    await h.pop(tester);
    expect(h.calls, ['open', 'cw return']);
  });

  testWidgets('Trakt grid and list preserve different snapshot timing', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    h.routes.openTrakt(h.context, 'series');
    h.items.add(second);
    await tester.pumpAndSettle();
    var screen = h.screen as TraktSeeAllScreen;
    expect(screen.cwItems, [first, second]);
    expect(screen.initialCategory, 'series');
    h.progress['one'] = .8;
    expect(screen.cwProgress['one'], .8);
    screen.onQuickPlay!(first);
    await h.pop(tester);
    h.items
      ..clear()
      ..add(first);
    h.pikpak = true;
    h.routes.openList(
      h.context,
      HomeListSection(
        rowId: 'traktlist:watchlist',
        title: 'Watchlist',
        items: [],
        traktChoice: const TraktListChoice.builtin(TraktSeeAllList.watchlist),
      ),
    );
    h.items.add(second);
    await tester.pumpAndSettle();
    screen = h.screen as TraktSeeAllScreen;
    expect(screen.cwItems, [first]);
    expect(screen.initialList!.builtin, TraktSeeAllList.watchlist);
    expect(screen.onQuickPlay, isNull);
    await h.pop(tester);
    expect(h.calls, ['trakt play', 'tracker return', 'tracker return']);
  });

  testWidgets(
    'Simkl keeps separate CW actions and MDBList keeps public-list origin',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      h.routes.openList(
        h.context,
        HomeListSection(
          rowId: 'simkllist:planToWatch',
          title: 'Simkl',
          items: [],
          simklList: SimklSeeAllList.planToWatch,
        ),
      );
      h.items.add(second);
      await tester.pumpAndSettle();
      final simkl = h.screen as SimklSeeAllScreen;
      expect(simkl.cwItems, [first]);
      simkl.onOpen(first);
      simkl.cwOnOpen!(first);
      simkl.onQuickPlay!(first);
      simkl.cwOnQuickPlay!(first);
      await h.pop(tester);
      h.routes.openList(
        h.context,
        HomeListSection(
          rowId: 'mdblistlist:top:1',
          title: 'MDBList',
          items: [],
          mdblistList: const MdblistListChoice(id: 1, name: 'Top'),
        ),
      );
      await tester.pumpAndSettle();
      final mdb = h.screen as MdblistSeeAllScreen;
      expect(mdb.initialListIsPublic, isTrue);
      mdb.onOpen(first);
      mdb.onQuickPlay!(first);
      await h.pop(tester);
      expect(h.calls, [
        'simkl open',
        'simkl cw open',
        'simkl play',
        'simkl cw play',
        'tracker return',
        'mdb open',
        'mdb play',
        'tracker return',
      ]);
    },
  );
}
