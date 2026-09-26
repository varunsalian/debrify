import 'package:debrify/features/search/application/keyword_providers.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

import '../keyword_torrent_fixture.dart';

KeywordProviders reconcile(
  List<Torrent> items, {
  Set<String> direct = const {},
  Set<String> torrent = const {},
  Set<String> seen = const {},
}) => reconcileKeywordProviders(
  items,
  selectedDirect: direct,
  selectedTorrent: torrent,
  seen: seen,
);

void main() {
  final direct = keywordTorrent(
    'Direct',
    source: 'shared',
    type: StreamType.directUrl,
  );
  final external = keywordTorrent(
    'External',
    source: 'shared',
    type: StreamType.externalUrl,
  );
  final torrent = keywordTorrent('Torrent', source: 'shared');

  test('direct and external share a bucket distinct from torrents', () {
    final result = reconcile([
      direct,
      external,
      torrent,
      keywordTorrent('Unknown'),
    ]);
    expect(result.directCounts, {'shared': 2});
    expect(result.torrentCounts, {'shared': 1, 'unknown': 1});
    expect(result.selectedDirect, {'shared'});
    expect(result.selectedTorrent, {'shared', 'unknown'});
    expect(result.seen, {'d:shared', 't:shared', 't:unknown'});
  });

  test('a user-unticked source stays unticked in a later streaming batch', () {
    final first = reconcile([direct, torrent]);
    final next = reconcile(
      [direct, external, torrent, keywordTorrent('New', source: 'new')],
      direct: const {},
      torrent: first.selectedTorrent,
      seen: first.seen,
    );
    expect(next.selectedDirect, isEmpty);
    expect(next.selectedTorrent, {'shared', 'new'});
    expect(next.directCounts['shared'], 2);
    expect(first.selectedDirect, {'shared'});
    expect(first.seen, {'d:shared', 't:shared'});
  });

  test('seen identity distinguishes the same source in two stream groups', () {
    final first = reconcile([torrent]);
    final next = reconcile([torrent, direct], seen: first.seen);
    expect(next.selectedTorrent, isEmpty);
    expect(next.selectedDirect, {'shared'});
  });

  test(
    'dedupe removes vanished selections and lets reappearing sources tick',
    () {
      final first = reconcile([torrent, direct]);
      final vanished = reconcile(
        [torrent],
        direct: first.selectedDirect,
        torrent: first.selectedTorrent,
        seen: first.seen,
      );
      expect(vanished.directCounts, isEmpty);
      expect(vanished.selectedDirect, isEmpty);
      expect(vanished.seen, {'t:shared'});
      final restored = reconcile(
        [torrent, direct],
        direct: vanished.selectedDirect,
        torrent: vanished.selectedTorrent,
        seen: vanished.seen,
      );
      expect(restored.selectedDirect, {'shared'});
    },
  );

  test('empty result set drops counts, selections and seen keys', () {
    final empty = reconcile(
      [],
      direct: {'a'},
      torrent: {'b'},
      seen: {'d:a', 't:b'},
    );
    expect(empty.directCounts, isEmpty);
    expect(empty.torrentCounts, isEmpty);
    expect(empty.selectedDirect, isEmpty);
    expect(empty.selectedTorrent, isEmpty);
    expect(empty.seen, isEmpty);
  });

  test(
    'reconciliation never mutates inputs and publishes immutable collections',
    () {
      final selected = {'shared'};
      final seen = {'t:shared'};
      final result = reconcile([torrent], torrent: selected, seen: seen);
      selected.clear();
      seen.clear();
      expect(result.selectedTorrent, {'shared'});
      expect(result.seen, {'t:shared'});
      expect(() => result.torrentCounts.clear(), throwsUnsupportedError);
      expect(() => result.selectedTorrent.clear(), throwsUnsupportedError);
      expect(() => result.seen.clear(), throwsUnsupportedError);
    },
  );
}
