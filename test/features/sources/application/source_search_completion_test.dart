import 'package:debrify/features/sources/application/source_results_controller.dart';
import 'package:debrify/features/sources/application/source_search_completion.dart';
import 'package:debrify/features/sources/application/source_seasons_controller.dart';
import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/source_seasons_repository.dart';
import 'package:debrify/features/sources/models/source_results_state.dart';
import 'package:debrify/features/sources/models/source_toolbar_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Repository implements SourceSeasonsRepository {
  @override
  bool get isCurrent => true;
  @override
  Future<SourceSeasonGuide?> load() =>
      throw StateError('Unexpected metadata IO');
}

class ScopedResults extends SourceResultsController {
  ScopedResults(super.session, this.initial);
  final SourceResultsState initial;
  @override
  SourceResultsState build() => initial;
}

const selection = AdvancedSearchSelection(
  imdbId: 'tt-completion',
  title: 'Fixture',
  isSeries: true,
);
Torrent row(int season, {String source = 'alpha'}) => Torrent(
  rowid: season,
  infohash: '$source-$season',
  name: 'Season $season',
  source: source,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  seasonNumber: season,
  coverageType: 'seasonPack',
);

void main() {
  late ProviderContainer container;
  late SourcesSession session;
  late SourceResultsController results;
  late SourceSeasonsController seasons;
  late SourceSearchCompletion completion;
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
        sourceSeasonsRepositoryProvider.overrideWith(
          (ref, key) => Repository(),
        ),
      ],
    );
    container.listen(sourceResultsProvider(session), (_, _) {});
    container.listen(sourceSeasonsProvider(session), (_, _) {});
    results = container.read(sourceResultsProvider(session).notifier);
    seasons = container.read(sourceSeasonsProvider(session).notifier);
    completion = container.read(sourceSearchCompletionProvider);
  });

  test(
    'completion uses parked full set without adopting it or rebuilding rows',
    () {
      final displayed = row(1);
      final pending = [row(2, source: 'beta'), row(4, source: 'beta')];
      results.display([displayed]);
      results.selectProvider('engine:alpha');
      results.freeze();
      results.bufferIfFrozen(pending);
      expect(
        container.read(sourceResultsProvider(session)).toolbar.sourceFilter,
        'engine:alpha',
      );
      final outcome = completion.complete(
        session,
        selection: selection,
        hasSeasonScope: true,
        aliases: {},
      );
      expect(outcome, SourceCompletionResult.keepProjection);
      expect(container.read(sourceSeasonsProvider(session)).derived, [2, 4]);
      final state = container.read(sourceResultsProvider(session));
      expect(state.displayed, [same(displayed)]);
      expect(state.pending, pending);
      expect(state.frozen, isTrue);
      expect(state.toolbar.sourceFilter, isNull);
    },
  );

  for (final scoped in [false, true]) {
    test('ineligible season snapshot retains menu: scoped=$scoped', () {
      seasons.acceptResults([row(1), row(2)], unscoped: true);
      results.display([row(2)]);
      completion.complete(
        session,
        selection: scoped ? selection.scopedToSeason(2) : selection,
        hasSeasonScope: scoped,
        aliases: {},
      );
      expect(container.read(sourceSeasonsProvider(session)).derived, [1, 2]);
    });
  }

  test('missing final provider requests projection rebuild only once', () {
    results.display([row(2)]);
    results.selectProvider('engine:gone');
    results.selectSort('size');
    expect(
      completion.complete(
        session,
        selection: selection,
        hasSeasonScope: true,
        aliases: {},
      ),
      SourceCompletionResult.rebuildProjection,
    );
    final state = container.read(sourceResultsProvider(session));
    expect(state.toolbar.sourceFilter, isNull);
    expect(state.toolbar.sortBy, 'size');
    expect(
      completion.complete(
        session,
        selection: selection,
        hasSeasonScope: true,
        aliases: {},
      ),
      SourceCompletionResult.keepProjection,
    );
  });

  test('completion retains provider selection resolved through aliases', () {
    results.display([row(1, source: 'renamed')]);
    results.selectProvider('engine:alpha');
    expect(
      completion.complete(
        session,
        selection: selection,
        hasSeasonScope: true,
        aliases: {'renamed': 'engine:alpha'},
      ),
      SourceCompletionResult.keepProjection,
    );
    expect(
      container.read(sourceResultsProvider(session)).toolbar.sourceFilter,
      'engine:alpha',
    );
  });

  test(
    'nested results override is reconciled without changing parent state',
    () {
      results.display([row(1)]);
      results.selectProvider('engine:alpha');
      final child = ProviderContainer.test(
        parent: container,
        overrides: [
          sourceResultsProvider(session).overrideWith(
            () => ScopedResults(
              session,
              SourceResultsState(
                displayed: [row(2)],
                toolbar: const SourceToolbarState(sourceFilter: 'engine:gone'),
              ),
            ),
          ),
        ],
      );
      child.listen(sourceResultsProvider(session), (_, _) {});
      expect(
        child
            .read(sourceSearchCompletionProvider)
            .complete(
              session,
              selection: selection,
              hasSeasonScope: false,
              aliases: {},
            ),
        SourceCompletionResult.rebuildProjection,
      );
      expect(
        child.read(sourceResultsProvider(session)).toolbar.sourceFilter,
        isNull,
      );
      expect(
        container.read(sourceResultsProvider(session)).toolbar.sourceFilter,
        'engine:alpha',
      );
    },
  );

  for (final retirement in ['profile', 'scope']) {
    test('$retirement retirement rejects completion', () {
      if (retirement == 'profile') {
        ProfileSessionMemory.clearAll();
      } else {
        container.dispose();
      }
      expect(
        completion.complete(
          session,
          selection: selection,
          hasSeasonScope: true,
          aliases: {},
        ),
        SourceCompletionResult.retired,
      );
    });
  }
}
