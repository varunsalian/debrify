import 'dart:async';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/episodes_screen.dart'
    show kCatalogDetailRouteName;
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_fixture.dart';

void main() {
  testWidgets('held primary action admits one host launch until completion', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      f.heldLaunch = Completer<void>();
      await f.mount(t);
      final first = f.model;
      first.onPrimary();
      first.onPrimary();
      await f.until(t, () => f.calls.contains('resumePlay'));
      expect(f.calls.where((c) => c == 'resumePlay').toList(), ['resumePlay']);
      expect(f.model.primaryBusy, false);
      f.heldLaunch!.complete();
      await t.pump();
      await t.pump();
      f.heldLaunch = null;
      f.model.onPrimary();
      await f.until(
        t,
        () => f.calls.where((c) => c == 'resumePlay').length == 2,
      );
      expect(f.promises, [null, null]);
    });
  });
  testWidgets(
    'Xtream injected seasons force Classic and keep exact panel wiring',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.xtream = true;
        await f.mount(t, style: 'console');
        expect(find.byType(DetailConsole), findsNothing);
        expect(find.byType(EpisodesPanel), findsOneWidget);
        final p = f.panel;
        expect(p.show, same(f.item));
        expect(p.showQuickPlay, true);
        expect(p.showChrome, false);
        expect(p.compact, true);
        final screen = t.widget<MergedDetailScreen>(find.byKey(f.key));
        expect(p.boundSourceCount, same(screen.boundSourceCount));
        expect(p.onSelectSource, same(screen.onSelectSource));
        expect(p.seasonsLoader, equals(f.seasonsLoader));
        expect(p.watchProgressLoader, equals(f.progressLoader));
        expect(p.onFocusLeftEdge, isNotNull);
        expect(f.calls.where((c) => c == 'seasons').toList(), ['seasons']);
        expect(f.calls.where((c) => c == 'progress').toList(), ['progress']);
        final routeCount = f.observer.events.length;
        p.onPlayEpisode!(f.episodes[1]);
        await f.until(t, () => f.calls.contains('directPlay'));
        await t.pump();
        expect(f.directEpisodes, [same(f.episodes[1])]);
        expect(f.observer.events.length, routeCount);
        f.next((season: 1, episode: 2, started: true), mutation: true);
        f.model.onPrimary();
        await f.until(t, () => f.calls.contains('resumePlay'));
        expect(f.promises, [(started: true, season: 1, episode: 2)]);
      });
    },
  );
  testWidgets('quick episode handoff carries the selection without popping', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      f.xtream = true;
      await f.mount(t, pushed: true);
      final selection = AdvancedSearchSelection(
        title: 'Second',
        imdbId: f.item.id,
        isSeries: true,
        season: 1,
        episode: 2,
      );
      final events = [...f.observer.events];
      f.panel.onQuickPlay!(selection);
      await f.until(t, () => f.calls.contains('quickPlay'));
      await t.pump();
      expect(f.quickSelections, [same(selection)]);
      expect(f.observer.events, events);
      expect(f.calls.where((c) => c == 'quickPlay').toList(), ['quickPlay']);
    });
  });
  testWidgets('movie browse invokes the host directly', (t) async {
    await mergedDetailCase(t, (f) async {
      f.item = const StremioMeta(
        id: 'merged-movie',
        type: 'movie',
        name: 'Original Movie',
      );
      await f.mount(t);
      f.calls.clear();
      f.model.onPrimaryLongPress!();
      expect(f.calls, ['movieBrowse']);
      expect(f.promises, isEmpty);
    });
  });
  testWidgets('packs disabled browses the exact merged episode promise', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      await QuickPlayStorage.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(
          isMovie: false,
        ).copyWith(preferSeriesPacks: false),
        isMovie: false,
      );
      await f.mount(t);
      f.next((season: 2, episode: 8, started: true), mutation: true);
      f.model.onPrimaryLongPress!();
      await f.until(t, () => f.calls.contains('episodeBrowse'));
      expect(f.promises, [(started: true, season: 2, episode: 8)]);
      expect(f.calls.where((c) => c.endsWith('Browse')).toList(), [
        'episodeBrowse',
      ]);
    });
  });
  testWidgets('selection pops two merged routes before invoking the host', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      f.xtream = true;
      await f.mount(t, pushed: true);
      final callbackEvents = <List<String>>[];
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kCatalogDetailRouteName),
          builder: (_) => MergedDetailScreen(
            item: f.item,
            addon: f.addon,
            isTelevision: false,
            onResume: (_) async {},
            seasonsLoader: f.seasonsLoader,
            onPlayEpisode: (_) async {},
            watchProgressLoader: f.progressLoader,
            onItemSelected: (s) {
              f.selections.add(s);
              callbackEvents.add([...f.observer.events]);
            },
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final panel = t
          .widgetList<EpisodesPanel>(find.byType(EpisodesPanel))
          .last;
      final selection = AdvancedSearchSelection(
        title: 'Second',
        imdbId: f.item.id,
        isSeries: true,
        season: 1,
        episode: 2,
      );
      panel.onItemSelected!(selection);
      await t.pump();
      expect(f.selections, [same(selection)]);
      expect(callbackEvents.single.sublist(callbackEvents.single.length - 2), [
        'pop:$kCatalogDetailRouteName',
        'pop:$kCatalogDetailRouteName',
      ]);
      for (var frame = 0; frame < 12; frame++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Host'), findsOneWidget);
      expect(find.byType(MergedDetailScreen), findsNothing);
    });
  });
}
