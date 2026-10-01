import 'package:debrify/features/home/presentation/home_stage_cards.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/features/home/presentation/home_catalog_item_actions.dart';

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
          items: _Items(
            pikpakOnly: () => restricted,
            open: (s, m) => calls.add('open:${s.title}:${m.id}'),
            play: (s, m) => calls.add('play:${s.title}:${m.id}'),
          ),
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

/// Records the catalog item actions the stage cards dispatch.
class _Items implements HomeCatalogItemActions {
  _Items({
    required bool Function() pikpakOnly,
    required void Function(CatalogSection, StremioMeta) open,
    required void Function(CatalogSection, StremioMeta) play,
  }) : _pikpakOnly = pikpakOnly,
       _open = open,
       _play = play;
  final bool Function() _pikpakOnly;
  final void Function(CatalogSection, StremioMeta) _open;
  final void Function(CatalogSection, StremioMeta) _play;

  @override
  bool isBound(StremioMeta item) => false;
  @override
  bool get pikpakOnly => _pikpakOnly();
  @override
  void open(CatalogSection section, StremioMeta item, {String? heroTag}) =>
      _open(section, item);
  @override
  void quickPlay(CatalogSection section, StremioMeta item) =>
      _play(section, item);
  @override
  void openSeeAll(CatalogSection section) => fail('not used by stage cards');
  @override
  String? sourceTag(CatalogSection section) => null;
}
