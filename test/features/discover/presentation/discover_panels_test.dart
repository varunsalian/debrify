import 'package:debrify/features/discover/presentation/discover_panels.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/see_all/simkl_see_all_screen.dart';
import 'package:debrify/screens/see_all/mdblist_see_all_screen.dart';
import 'package:debrify/screens/see_all/trakt_see_all_screen.dart';
import 'package:debrify/screens/see_all/continue_watching_see_all_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'embedded panels retain action identity, quick-play policy and lazy progress',
    () async {
      final calls = <String>[];
      final node = FocusNode();
      addTearDown(node.dispose);
      final item = StremioMeta(id: 'tt1', type: 'movie', name: 'Title');
      final addon = StremioAddon(
        id: 'one',
        name: 'One',
        baseUrl: 'https://example.invalid',
        manifestUrl: 'https://example.invalid/manifest.json',
      );
      var progressReads = 0;
      Widget panel(String source, {bool restricted = false}) =>
          buildDiscoverPanels(
            selected: source,
            isTelevision: true,
            sourceNode: node,
            preferences: null,
            mdblistEnabled: true,
            mdblistAuthenticated: true,
            addons: [addon],
            onSelectSource: (_) {},
            pikpakOnly: restricted,
            onItemFocused: (_) => calls.add('focus'),
            isBound: (_) => true,
            findAddon: (_) => addon,
            addonForContinue: (_) => addon,
            onOpenCatalog: (m, a, {bool isMdblistSource = false}) {
              expect(m, same(item));
              expect(a, same(addon));
              calls.add('open:$isMdblistSource');
            },
            onPlayCatalog: (m, a, {bool isMdblistSource = false}) =>
                calls.add('play:$isMdblistSource'),
            traktItems: [item],
            traktProgress: () {
              progressReads++;
              return {'tt1': .5};
            },
            onOpenTrakt: (_) => calls.add('trakt-open'),
            onPlayTrakt: (_) => calls.add('trakt-play'),
            simklItems: [item],
            simklProgress: {'tt1': .6},
            onOpenSimkl: (_) => calls.add('browse-open'),
            onPlaySimkl: (_) => calls.add('browse-play'),
            onOpenSimklContinuation: (_) => calls.add('resume-open'),
            onPlaySimklContinuation: (_) => calls.add('resume-play'),
            mdblistList: null,
            localItems: [item],
            localProgress: (_) => .7,
            onOpenLocal: (_) => calls.add('local-open'),
            onPlayLocal: (_) => calls.add('local-play'),
            reloadLocal: () async {
              calls.add('reload');
              return [item];
            },
          );
      final simkl = panel('simkl') as SimklSeeAllScreen;
      expect(simkl.leadingNode, same(node));
      expect(simkl.embedded, isTrue);
      expect(simkl.cwProgress['tt1'], .6);
      simkl.onOpen(item);
      simkl.onQuickPlay!(item);
      simkl.cwOnOpen!(item);
      simkl.cwOnQuickPlay!(item);
      expect(calls, [
        'browse-open',
        'browse-play',
        'resume-open',
        'resume-play',
      ]);
      calls.clear();
      final mdb = panel('mdblist') as MdblistSeeAllScreen;
      mdb.onOpen(item);
      mdb.onQuickPlay!(item);
      mdb.onItemFocused!(item);
      expect(calls, ['open:true', 'play:true', 'focus']);
      expect(mdb.isBound!(item), isTrue);
      expect(mdb.leadingNode, same(node));
      expect(mdb.embedded, isTrue);
      // Missing metadata policy keeps the local continuation fallback and reload.
      final local = panel('tmdb') as ContinueWatchingSeeAllScreen;
      expect(local.key, const ValueKey('disc_cw'));
      expect(local.progressOf(item), .7);
      expect(await local.onReload!(), [item]);
      expect(progressReads, 0);
      final trakt = panel('trakt') as TraktSeeAllScreen;
      expect(trakt.cwProgress['tt1'], .5);
      expect(progressReads, 1);
      expect(
        (panel('trakt', restricted: true) as TraktSeeAllScreen).onQuickPlay,
        isNull,
      );
      expect(
        (panel('mdblist', restricted: true) as MdblistSeeAllScreen).onQuickPlay,
        isNull,
      );
      expect(
        (panel('cw', restricted: true) as ContinueWatchingSeeAllScreen)
            .onQuickPlay,
        isNull,
      );
      final restricted = panel('simkl', restricted: true) as SimklSeeAllScreen;
      expect(restricted.onQuickPlay, isNull);
      expect(restricted.cwOnQuickPlay, isNull);
    },
  );
}
