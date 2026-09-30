import 'dart:async';

import 'package:debrify/features/home/presentation/home_sources_navigation.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/screens/search_screen/home_sources_entry.dart';

const selection = AdvancedSearchSelection(
  imdbId: 'tt123',
  title: 'Episode',
  isSeries: true,
  season: 4,
  episode: 2,
);
const initialMeta = PlaybackMeta.catalog(addonId: 'origin');
const laterMeta = PlaybackMeta.catalog(addonId: 'later');

class Harness {
  final originVisible = ValueNotifier(true);
  final refresh = Completer<void>();
  final navigator = GlobalKey<NavigatorState>();
  final events = <String>[];
  late BuildContext context;
  late HomeSourcesNavigation navigation;
  bool current = true;
  PlaybackMeta metadata = initialMeta;
  PlaybackMeta? receivedMeta;
  AdvancedSearchSelection? receivedSelection;
  bool? tv;
  bool? television;
  bool? bindMode;
  bool? forcePlay;
  String? keyword;
  int activations = 0;

  Future<void> mount(WidgetTester tester) async {
    final bridge = HomeSourcesNavigation(
      buildScreen:
          ({
            required selection,
            required meta,
            required isTelevision,
            bindMode = false,
            keywordSeed,
            forcePlayOnTap = false,
          }) {
            events.add('build');
            receivedMeta = meta;
            receivedSelection = selection;
            tv = isTelevision;
            this.bindMode = bindMode;
            keyword = keywordSeed;
            forcePlay = forcePlayOnTap;
            return Scaffold(
              body: TextButton(
                autofocus: true,
                onPressed: () => activations++,
                child: const Text('Destination'),
              ),
            );
          },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeSourcesNavigationProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: originVisible,
              builder: (_, visible, _) => visible
                  ? Builder(
                      builder: (context) {
                        this.context = context;
                        navigation = ProviderScope.containerOf(
                          context,
                        ).read(homeSourcesNavigationProvider);
                        return const Text('Origin');
                      },
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    addTearDown(originVisible.dispose);
  }

  PlaybackMeta buildMeta() {
    events.add('metadata');
    return metadata;
  }

  Future<void> returned() {
    events.add('refresh');
    return refresh.future;
  }

  Future<void> open(String mode, {AdvancedSearchSelection value = selection}) =>
      mode == 'browse' || mode == 'play'
      ? navigation.browse(
          context,
          selection: value,
          buildMeta: buildMeta,
          isTelevision: () => television ?? true,
          forcePlayOnTap: mode == 'play',
          isCurrent: () => current,
          onReturned: returned,
        )
      : navigation.bind(
          context,
          selection: value,
          buildMeta: buildMeta,
          isTelevision: () => television ?? false,
          keywordSeed: mode == 'keyword' ? 'Episode complete' : null,
          isCurrent: () => current,
          onReturned: returned,
        );
}

void main() {
  for (final scenario in [
    (type: 'movie', year: '2024', keyword: false, custom: false, seed: null),
    (
      type: 'movie',
      year: '2024',
      keyword: true,
      custom: false,
      seed: 'Title 2024',
    ),
    (type: 'movie', year: '', keyword: true, custom: false, seed: 'Title'),
    (
      type: 'series',
      year: '2024',
      keyword: true,
      custom: true,
      seed: 'Title complete',
    ),
    (type: 'series', year: '', keyword: false, custom: true, seed: null),
  ]) {
    testWidgets(
      'catalog binding preserves payload and lazy metadata: $scenario',
      (tester) async {
        final h = Harness();
        await h.mount(tester);
        final addon = StremioAddon(
          id: 'addon',
          name: 'Addon',
          manifestUrl: 'https://fixture.invalid/manifest.json',
          baseUrl: 'https://fixture.invalid',
        );
        final item = StremioMeta(
          id: 'catalog-id',
          name: 'Title',
          type: scenario.type,
          year: scenario.year,
          poster: 'poster',
          sourceAddon: addon,
        );
        final id = scenario.custom
            ? CustomSeriesIdentity(addon.sourceBindingKey, item.id).id
            : 'tt123';
        AdvancedSearchSelection? metadataSelection;
        final action = h.navigation.bindCatalog(
          h.context,
          item: item,
          progressId: id,
          keyword: scenario.keyword,
          buildMeta: (selection) {
            metadataSelection = selection;
            return h.buildMeta();
          },
          isTelevision: () => true,
          isCurrent: () => h.current,
          onReturned: h.returned,
        );
        expect(h.events, isEmpty);
        h.metadata = laterMeta;
        await tester.pumpAndSettle();
        final selected = h.receivedSelection!;
        expect(metadataSelection, same(selected));
        expect(selected.imdbId, id);
        expect(selected.isSeries, scenario.type == 'series');
        expect(selected.title, 'Title');
        expect(selected.year, scenario.year);
        expect(selected.posterUrl, 'poster');
        expect(selected.contentType, scenario.type);
        expect(selected.season, isNull);
        expect(selected.episode, isNull);
        expect(selected.stremioAddonId, addon.id);
        expect(
          selected.stremioAddonKey,
          scenario.custom ? addon.sourceBindingKey : null,
        );
        expect(selected.stremioCatalogId, scenario.custom ? item.id : null);
        expect(h.receivedMeta, same(laterMeta));
        expect(h.keyword, scenario.seed);
        expect(h.bindMode, isTrue);
        expect(h.forcePlay, isFalse);
        h.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(h.events.last, 'refresh');
        h.refresh.complete();
        await action;
      },
    );
  }
  testWidgets(
    'catalog binding rejects retired and missing identities without metadata reads',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      Future<void> open() => h.navigation.bindCatalog(
        h.context,
        item: const StremioMeta(id: '', name: 'Title', type: 'movie'),
        progressId: null,
        keyword: false,
        buildMeta: (_) => h.buildMeta(),
        isTelevision: () => true,
        isCurrent: () => h.current,
        onReturned: h.returned,
      );
      h.current = false;
      await open();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      h.current = true;
      await open();
      await tester.pump();
      expect(
        find.text('No IMDb match to pin a source for "Title".'),
        findsOneWidget,
      );
      expect(h.events, isEmpty);
      expect(h.navigator.currentState!.canPop(), isFalse);
    },
  );

  for (final mode in ['browse', 'play', 'bind', 'keyword']) {
    testWidgets(
      '$mode preserves arguments, metadata timing and awaited return',
      (tester) async {
        final h = Harness();
        await h.mount(tester);
        var completed = false;
        final action = h.open(mode).then((_) => completed = true);
        final browsing = mode == 'browse' || mode == 'play';
        expect(h.events, browsing ? ['metadata'] : isEmpty);
        h.metadata = laterMeta;
        h.television = !browsing;
        await tester.pumpAndSettle();
        expect(h.receivedSelection, same(selection));
        expect(h.receivedMeta, same(browsing ? initialMeta : laterMeta));
        expect(h.tv, !browsing);
        expect(h.bindMode, !browsing);
        expect(h.forcePlay, mode == 'play');
        expect(h.keyword, mode == 'keyword' ? 'Episode complete' : null);
        expect(
          find.byType(TvHeldKeyGuard),
          browsing ? findsOneWidget : findsNothing,
        );
        expect(h.events, ['metadata', 'build']);
        expect(completed, false);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(h.events.last, 'refresh');
        expect(completed, false);
        h.refresh.complete();
        await action;
        expect(completed, true);
        expect(h.events.where((e) => e == 'refresh'), hasLength(1));
        expect(find.text('Origin'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'empty browse identity shows old message without metadata or route',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await h.open(
        'browse',
        value: const AdvancedSearchSelection(
          imdbId: '',
          title: 'Unknown',
          isSeries: false,
        ),
      );
      await tester.pump();
      expect(
        find.text('No IMDb match to find sources for "Unknown".'),
        findsOneWidget,
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 3),
      );
      expect(h.events, isEmpty);
      expect(h.navigator.currentState!.canPop(), false);
    },
  );

  testWidgets(
    'browse swallows held activation repeats but accepts a fresh press',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      final action = h.open('browse');
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      expect(h.activations, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(h.activations, 1);
      h.refresh.complete();
      h.navigator.currentState!.pop();
      await action;
      await tester.pumpAndSettle();
    },
  );

  for (final mode in ['browse', 'bind']) {
    for (final retirement in ['profile', 'dispose']) {
      testWidgets('$mode rejects $retirement retirement before navigation', (
        tester,
      ) async {
        final h = Harness();
        await h.mount(tester);
        if (retirement == 'profile') {
          h.current = false;
        } else {
          h.originVisible.value = false;
          await tester.pump();
        }
        await h.open(mode);
        expect(h.events, isEmpty);
        expect(h.navigator.currentState!.canPop(), false);
      });

      testWidgets(
        '$mode skips feedback after $retirement retirement on route',
        (tester) async {
          final h = Harness();
          await h.mount(tester);
          final action = h.open(mode);
          await tester.pumpAndSettle();
          if (retirement == 'profile') {
            h.current = false;
          } else {
            h.originVisible.value = false;
            await tester.pump();
          }
          h.navigator.currentState!.pop();
          await action;
          await tester.pumpAndSettle();
          expect(h.events, isNot(contains('refresh')));
        },
      );
    }
  }

  testWidgets(
    'bind retirement before first frame prevents lazy metadata access',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      final action = h.open('bind');
      h.current = false;
      await tester.pumpAndSettle();
      expect(h.events, isEmpty);
      h.navigator.currentState!.pop();
      await action;
      await tester.pumpAndSettle();
    },
  );
}
