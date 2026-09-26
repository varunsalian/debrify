import 'package:debrify/features/sources/application/source_batch_preparation.dart';
import 'package:debrify/features/sources/application/saved_sources_controller.dart';
import 'package:debrify/features/sources/application/source_binding_match_dependencies.dart';
import 'package:debrify/features/sources/application/source_results_controller.dart';
import 'package:debrify/features/sources/application/source_search_controller.dart';
import 'package:debrify/features/sources/data/source_binding_matcher.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/source_search_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Search extends SourceSearchController {
  Search(super.session);
  @override
  SourceSearchState build() => SourceSearchState(searching: true);
  void complete() => state = SourceSearchState();
}

class Saved extends SavedSourcesController {
  Saved(super.session, [this.initial]);
  final SavedSourcesState? initial;
  @override
  SavedSourcesState build() => initial ?? SavedSourcesState();
  void replace(SavedSourcesState value) => state = value;
}

const selection = AdvancedSearchSelection(
  imdbId: 'tt-owner',
  title: 'Fixture',
  isSeries: true,
);
const pin = SeriesSource(
  torrentHash: '',
  torrentName: '',
  debridService: SeriesSource.addonDirectService,
  debridTorrentId: '',
  boundAt: 0,
  addonId: 'addon',
  addonKey: 'config',
  streamKey: 'profile',
);
Torrent row(String name) => Torrent(
  rowid: 0,
  infohash: '',
  name: name,
  source: 'fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: StreamType.directUrl,
);
SourceBindingMatcher classifier(bool iptv) => SourceBindingMatcher(
  mediaServerKeyFor: (_) => throw StateError('Unexpected media lookup'),
  isIptv: (_) => iptv,
);

void main() {
  late ProviderContainer container;
  late SourcesSession session;
  late SourceResultsController controller;
  late SourceBatchPreparation preparation;
  late Search search;
  late Saved saved;
  setUp(() {
    ProfileSessionMemory.debugReset();
    addTearDown(ProfileSessionMemory.debugReset);
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: selection,
    );
    container = ProviderContainer.test(
      overrides: [
        sourceSearchProvider(session).overrideWith(() => Search(session)),
        savedSourcesProvider(session).overrideWith(() => Saved(session)),
        sourceBindingMatcherProvider.overrideWithValue(classifier(false)),
      ],
    );
    container.listen(sourceSearchProvider(session), (_, _) {});
    container.listen(savedSourcesProvider(session), (_, _) {});
    container.listen(sourceResultsProvider(session), (_, _) {});
    controller = container.read(sourceResultsProvider(session).notifier);
    preparation = container.read(sourceBatchPreparationProvider);
    search = container.read(sourceSearchProvider(session).notifier) as Search;
    saved = container.read(savedSourcesProvider(session).notifier) as Saved;
  });

  test(
    'cached fallback reads completion state without adopting or buffering',
    () {
      final cached = row('Cached');
      saved.replace(SavedSourcesState(sources: [pin], cachedEpisode: cached));
      controller.freeze();
      final provisional = preparation.prepare(
        session,
        [],
        selection: selection,
        bindMode: false,
      )!;
      expect(provisional.cachedEpisodeInserted, isFalse);
      expect(provisional.torrents, isEmpty);
      search.complete();
      final finalRows = preparation.prepare(
        session,
        [],
        selection: selection,
        bindMode: false,
      )!;
      expect(finalRows.cachedEpisodeInserted, isTrue);
      expect(finalRows.torrents, [same(cached)]);
      expect(() => finalRows.torrents.clear(), throwsUnsupportedError);
      final state = container.read(sourceResultsProvider(session));
      expect(state.displayed, isEmpty);
      expect(state.pending, isNull);
      expect(state.frozen, isTrue);
    },
  );

  test('each batch uses the latest saved pin snapshot', () {
    search.complete();
    final cached = row('Cached');
    saved.replace(SavedSourcesState(sources: [pin], cachedEpisode: cached));
    expect(
      preparation
          .prepare(session, [], selection: selection, bindMode: false)!
          .torrents,
      [same(cached)],
    );
    saved.replace(SavedSourcesState());
    expect(
      preparation
          .prepare(session, [], selection: selection, bindMode: false)!
          .torrents,
      isEmpty,
    );
  });

  test(
    'nested classifier override reaches preparation without leaking to parent',
    () {
      final torrent = row('IPTV series');
      final child = ProviderContainer.test(
        parent: container,
        overrides: [
          sourceBindingMatcherProvider.overrideWithValue(classifier(true)),
        ],
      );
      child.listen(sourceResultsProvider(session), (_, _) {});
      final childPreparation = child.read(sourceBatchPreparationProvider);
      expect(child.read(sourceBindingMatcherProvider).isIptv(torrent), isTrue);
      expect(identical(childPreparation, preparation), isFalse);
      expect(
        childPreparation
            .prepare(session, [torrent], selection: selection, bindMode: true)!
            .torrents,
        [same(torrent)],
      );
      expect(
        preparation
            .prepare(session, [torrent], selection: selection, bindMode: true)!
            .torrents,
        isEmpty,
      );
      expect(
        childPreparation
            .prepare(session, [torrent], selection: selection, bindMode: false)!
            .torrents,
        isEmpty,
      );
    },
  );

  test('nested saved-state override supplies its own fallback', () {
    search.complete();
    final parentRow = row('Parent');
    final childRow = row('Child');
    saved.replace(SavedSourcesState(sources: [pin], cachedEpisode: parentRow));
    final child = ProviderContainer.test(
      parent: container,
      overrides: [
        savedSourcesProvider(session).overrideWith(
          () => Saved(
            session,
            SavedSourcesState(sources: [pin], cachedEpisode: childRow),
          ),
        ),
      ],
    );
    final operation = child.read(sourceBatchPreparationProvider);
    expect(
      operation
          .prepare(session, [], selection: selection, bindMode: false)!
          .torrents,
      [same(childRow)],
    );
    expect(
      preparation
          .prepare(session, [], selection: selection, bindMode: false)!
          .torrents,
      [same(parentRow)],
    );
  });

  test('retired profile and disposed scope reject preparation', () {
    ProfileSessionMemory.clearAll();
    expect(
      preparation.prepare(session, [], selection: selection, bindMode: false),
      isNull,
    );
    container.dispose();
    expect(
      preparation.prepare(session, [], selection: selection, bindMode: false),
      isNull,
    );
  });
}
