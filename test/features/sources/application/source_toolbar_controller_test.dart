import 'package:debrify/features/sources/application/source_results_controller.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/models/source_results_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(String name, String source) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  source: source,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

void main() {
  late ProviderContainer container;
  late SourceResultsController controller;
  late ProviderSubscription<SourceResultsState> subscription;
  setUp(() {
    final session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt1',
        isSeries: false,
        title: 'One',
      ),
    );
    container = ProviderContainer.test();
    subscription = container.listen(sourceResultsProvider(session), (_, _) {});
    controller = container.read(sourceResultsProvider(session).notifier);
  });

  test(
    'search reset preserves toolbar choices but clears result interaction state',
    () {
      final filters = TorrentFilterState(qualities: {QualityTier.fullHd});
      controller.selectProvider('engine:one');
      controller.selectSort('name');
      controller.toggleSortDirection();
      controller.setFilters(filters);
      controller.display([row('early', 'one')]);
      controller.freeze();
      controller.bufferIfFrozen([row('pending', 'one')]);
      controller.beginSearch();
      final state = subscription.read();
      expect(state.displayed, isEmpty);
      expect(state.pending, isNull);
      expect(state.frozen, isFalse);
      expect(state.toolbar.sourceFilter, 'engine:one');
      expect(state.toolbar.sortBy, 'name');
      expect(state.toolbar.sortAsc, isTrue);
      expect(state.toolbar.filters, same(filters));
    },
  );

  test('changing toolbar preserves pending rows until explicit adoption', () {
    final early = row('early', 'one');
    final pending = row('pending', 'two');
    controller.display([early]);
    controller.freeze();
    controller.bufferIfFrozen([pending]);
    controller.selectProvider('engine:two');
    controller.selectSort('size');
    controller.setFilters(TorrentFilterState(sizes: {SizeBucket.over40gb}));
    expect(subscription.read().displayed, [same(early)]);
    expect(subscription.read().pending, [same(pending)]);
    expect(subscription.read().frozen, isTrue);
    controller.display(subscription.read().pending!);
    expect(subscription.read().toolbar.sourceFilter, 'engine:two');
    expect(subscription.read().toolbar.sortBy, 'size');
    expect(subscription.read().toolbar.filters.sizes, {SizeBucket.over40gb});
  });

  test(
    'reconciliation uses full provider presence even when quality filters hide it',
    () {
      controller.selectProvider('engine:configured');
      controller.setFilters(
        TorrentFilterState(qualities: {QualityTier.ultraHd}),
      );
      final candidate = row('Title 1080p', 'custom');
      final settings = SourcePrioritySettings(
        aliases: {'custom': 'engine:configured'},
      );
      controller.display([]);
      controller.freeze();
      controller.bufferIfFrozen([candidate]);
      expect(controller.project([candidate], settings), isEmpty);
      expect(
        controller.reconcileProvider(
          subscription.read().pending!,
          settings.aliases,
        ),
        isFalse,
      );
      expect(subscription.read().toolbar.sourceFilter, 'engine:configured');
      expect(controller.reconcileProvider([], settings.aliases), isTrue);
      expect(subscription.read().toolbar.sourceFilter, isNull);
      expect(subscription.read().pending, [same(candidate)]);
      expect(subscription.read().frozen, isTrue);
    },
  );

  test(
    'projection consumes current toolbar and clearing filters preserves sort/provider',
    () {
      final a = row('A 1080p', 'one');
      final b = row('B 1080p', 'one');
      final other = row('C 1080p', 'two');
      controller.selectProvider('engine:one');
      controller.selectSort('name');
      controller.setFilters(
        TorrentFilterState(qualities: {QualityTier.ultraHd}),
      );
      final settings = SourcePrioritySettings();
      expect(controller.project([a, b, other], settings), isEmpty);
      controller.setFilters(const TorrentFilterState.empty());
      expect(controller.project([a, b, other], settings), [same(b), same(a)]);
      controller.toggleSortDirection();
      expect(controller.project([b, a, other], settings), [same(a), same(b)]);
    },
  );

  test('retired profile rejects toolbar mutations and reconciliation', () {
    controller.selectProvider('engine:one');
    final before = subscription.read();
    ProfileSessionMemory.clearAll();
    controller.selectProvider(null);
    controller.selectSort('name');
    controller.toggleSortDirection();
    controller.setFilters(TorrentFilterState(qualities: {QualityTier.hd}));
    expect(controller.reconcileProvider([], {}), isFalse);
    expect(subscription.read(), same(before));
  });
}
