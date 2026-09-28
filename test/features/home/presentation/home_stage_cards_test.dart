import 'package:debrify/features/home/presentation/home_stage_cards.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final liveItem in [false, true]) {
    test(
      'stage actions preserve ${liveItem ? 'Atrium live' : 'captured'} item and current section',
      () {
        final first = StremioMeta(id: 'first', type: 'movie', name: 'First');
        final next = StremioMeta(id: 'next', type: 'movie', name: 'Next');
        final addon = StremioAddon(
          id: 'addon',
          name: 'Addon',
          baseUrl: 'https://example.invalid',
          manifestUrl: 'https://example.invalid/manifest.json',
        );
        CatalogSection section(String title) => CatalogSection(
          title: title,
          addon: addon,
          catalog: const StremioAddonCatalog(
            id: 'one',
            type: 'movie',
            name: 'One',
          ),
          items: [],
        );
        var currentSection = section('old');
        var currentItem = first;
        var restricted = false;
        final calls = <String>[];
        final node = FocusNode();
        addTearDown(node.dispose);
        final cards = HomeStageCards(
          sectionAt: (_) => currentSection,
          collectionFor: (_) => null,
          aspectOf: (_, {fallback}) => fallback ?? 2 / 3,
          artOf: (_, item, {bool wide = false}) => item.poster,
          isBound: (_) => false,
          pikpakOnly: () => restricted,
          openSection: (s, m) => calls.add('open:${s.title}:${m.id}'),
          playSection: (s, m) => calls.add('play:${s.title}:${m.id}'),
          openContinuationMenu: (_, _, _, _) => fail('not a continuation row'),
          onFocused: (_, m, _) => calls.add('focus:${m.id}'),
          focusSidebar: () {},
          switchRail: (_) {},
          loadMore: (i) => calls.add('page:$i'),
        );
        build({bool page = true}) => cards.build(
          rail: const HomeRail(sectionIndex: 0),
          railKey: 'stable',
          item: first,
          nodes: [node],
          column: 0,
          pageNearEnd: page,
          readActionItem: liveItem ? () => currentItem : null,
          onFocusedExtra: () => calls.add('extra'),
        );
        final cell = build();
        currentSection = section('new');
        currentItem = next;
        cell.onOpen();
        cell.onQuickPlay!();
        cell.onFocused();
        cell.onNearEnd!();
        final expected = liveItem ? 'next' : 'first';
        expect(calls, [
          'open:new:$expected',
          'play:new:$expected',
          'focus:$expected',
          'extra',
          'page:0',
        ]);
        expect(cell.item, same(first));
        expect(build(page: false).onNearEnd, isNull);
        restricted = true;
        expect(build().onQuickPlay, isNull);
      },
    );
  }
}
