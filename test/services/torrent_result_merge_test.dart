import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/torrent_result_merge.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(
  String hash, {
  String name = 'Fixture',
  String source = 'engine',
  int seeders = 0,
}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: name,
  source: source,
  seeders: seeders,
  sizeBytes: 0,
  createdUnix: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

void main() {
  for (final preserve in [false, true]) {
    test('empty batches retain empty output: preserve=$preserve', () {
      expect(mergeTorrentResults([], preserveSourceOrder: preserve), isEmpty);
      expect(
        mergeTorrentResults([[], []], preserveSourceOrder: preserve),
        isEmpty,
      );
    });
  }

  test(
    'Sources concatenation retains duplicates, identities and provider order',
    () {
      final first = row('shared', seeders: 1);
      final second = row('shared', seeders: 100);
      final batch = List<Torrent>.unmodifiable([first, second]);
      final batches = List<List<Torrent>>.unmodifiable(<List<Torrent>>[
        batch,
        [],
        [first],
      ]);
      final merged = mergeTorrentResults(batches, preserveSourceOrder: true);
      expect(merged, [same(first), same(second), same(first)]);
      merged.clear();
      expect(batch, [same(first), same(second)]);
      expect(batches, hasLength(3));
    },
  );

  test(
    'winner precedence is seeders then name then source with original identities',
    () {
      final high = row('seed', seeders: 20, name: 'Z');
      final low = row('seed', seeders: 10, name: 'A');
      final earlyName = row('name', name: 'A', source: 'z');
      final lateName = row('name', name: 'Z', source: 'a');
      final earlySource = row('source', source: 'a');
      final lateSource = row('source', source: 'z');
      final batches = [
        [low, lateName, lateSource],
        [high, earlyName, earlySource],
      ];
      for (final input in [batches, batches.reversed.toList()]) {
        expect(mergeTorrentResults(input), [
          same(high),
          same(earlyName),
          same(earlySource),
        ]);
      }
    },
  );

  test('exact tie retains first representative rather than copying models', () {
    final first = row('same');
    final second = row('same');
    expect(
      mergeTorrentResults([
        [first],
        [second],
      ]),
      [same(first)],
    );
    expect(
      mergeTorrentResults([
        [second],
        [first],
      ]),
      [same(second)],
    );
  });

  test(
    'dedupe retains exact hash semantics including empty and differently cased hashes',
    () {
      final upper = row('ABC');
      final lower = row('abc');
      final emptyLow = row('', seeders: 1);
      final emptyHigh = row('', seeders: 2);
      expect(
        mergeTorrentResults([
          [lower, emptyLow],
          [upper, emptyHigh],
        ]),
        [same(emptyHigh), same(upper), same(lower)],
      );
    },
  );

  test(
    'default merge sorts only its new list and leaves immutable inputs intact',
    () {
      final low = row('z', seeders: 1);
      final high = row('a', seeders: 2);
      final input = List<Torrent>.unmodifiable([low, high]);
      final merged = mergeTorrentResults([input]);
      expect(merged, [same(high), same(low)]);
      merged.removeLast();
      expect(input, [same(low), same(high)]);
    },
  );
}
