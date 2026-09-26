import 'package:debrify/features/sources/models/source_results_state.dart';
import 'package:debrify/features/sources/models/source_toolbar_state.dart';
import 'package:debrify/features/sources/presentation/source_picker_trace.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(String name) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

void main() {
  test(
    'delayed trace uses snapshots taken at separate subscription closes',
    () {
      final first = row('first');
      final selected = row('selected');
      var mounted = true;
      var resultsClosed = false;
      var searchClosed = false;
      var boundClosed = false;
      var searching = true;
      var boundCount = 2;
      final events = <(String, Map<String, Object?>)>[];
      final trace = SourcePickerTrace(
        pickerId: 123,
        emit: (event, fields) => events.add((event, fields)),
        isMounted: () => mounted,
        readResults: () {
          if (resultsClosed) throw StateError('Results subscription closed');
          return SourceResultsState(
            displayed: [first, selected],
            frozen: true,
            toolbar: const SourceToolbarState(sourceFilter: 'provider'),
          );
        },
        readSearching: () {
          if (searchClosed) throw StateError('Search subscription closed');
          return searching;
        },
        readBoundCount: () {
          if (boundClosed) throw StateError('Saved subscription closed');
          return boundCount;
        },
      );
      trace.retireResults(selected);
      resultsClosed = true;
      searching = false;
      trace.retireSearch();
      searchClosed = true;
      boundCount = 3;
      trace.retireBound();
      boundClosed = true;
      mounted = false;
      trace.log(
        'reveal_skipped',
        search: 4,
        season: 2,
        episode: 3,
        visible: [selected],
        selected: selected,
        railFocus: false,
        filterFocus: false,
        pillFocus: false,
        television: true,
        detail: {'reason': 'unmounted'},
      );
      expect(events.single.$1, 'reveal_skipped');
      expect(events.single.$2, {
        'picker': 123,
        'search': 4,
        'season': 2,
        'episode': 3,
        'bound_count': 3,
        'results': 2,
        'visible': 1,
        'match_index': 1,
        'visible_index': 0,
        'searching': false,
        'frozen': true,
        'rail_focus': false,
        'filter_focus': false,
        'pill_focus': false,
        'tv': true,
        'provider_filter': true,
        'reason': 'unmounted',
      });
    },
  );

  test('mounted events use current rows and retain detail overrides', () {
    final selected = row('selected');
    var results = SourceResultsState(displayed: [selected]);
    var searching = true;
    var boundCount = 1;
    final events = <Map<String, Object?>>[];
    final trace = SourcePickerTrace(
      pickerId: 1,
      emit: (_, fields) => events.add(fields),
      isMounted: () => true,
      readResults: () => results,
      readSearching: () => searching,
      readBoundCount: () => boundCount,
    );
    void log() => trace.log(
      'match',
      search: 1,
      season: null,
      episode: null,
      visible: [],
      selected: selected,
      railFocus: true,
      filterFocus: false,
      pillFocus: false,
      television: false,
      detail: {'search': 9},
    );
    log();
    results = SourceResultsState(displayed: [row('selected')], frozen: true);
    searching = false;
    boundCount = 2;
    log();
    expect(events.first['match_index'], 0);
    expect(events.last['match_index'], -1);
    expect(events.last['visible_index'], -1);
    expect(events.last['bound_count'], 2);
    expect(events.last['searching'], false);
    expect(events.last['frozen'], true);
    expect(events.last['search'], 9);
    expect(events.first['bound_count'], 1);
  });
}
