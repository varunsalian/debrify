import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/torrent_service.dart';

// The streaming Sources list builds PROVISIONAL result sets by merging
// accumulated per-engine batches with TorrentService.mergeSearchResults and
// snaps to the awaited search's final merge on completion. These tests pin
// the property that makes that safe: merging incrementally-accumulated
// batches gives exactly the same set as the final one-shot merge.

Torrent t(String name, {String? hash, int seeders = 0}) => Torrent(
  rowid: 0,
  infohash: hash ?? name.hashCode.toRadixString(16).padLeft(40, '0'),
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: seeders,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

List<String> loadCorpus() {
  final raw =
      jsonDecode(File('test/fixtures/release_names.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final e in raw.entries)
      if (e.key != '_meta') ...(e.value as List).cast<String>(),
  ];
}

void main() {
  test('dedupe keeps the higher-seeded copy of a shared infohash', () {
    final low = t('Movie.2024.1080p.WEB', hash: 'a' * 40, seeders: 10);
    final high = t('Movie.2024.1080p.WEB-DL', hash: 'a' * 40, seeders: 99);
    final merged = TorrentService.mergeSearchResults([
      [low],
      [high],
    ]);
    expect(merged, hasLength(1));
    expect(merged.single.seeders, 99);
  });

  test('sorted by seeders descending', () {
    final merged = TorrentService.mergeSearchResults([
      [t('a', seeders: 5), t('b', seeders: 50)],
      [t('c', seeders: 20)],
    ]);
    expect(merged.map((x) => x.seeders).toList(), [50, 20, 5]);
  });

  // Batches with deliberate nastiness: duplicate infohashes across batches
  // with EQUAL seeders (tie-break territory), plus large equal-seeder runs
  // (addon direct streams all report 0 seeders).
  List<List<Torrent>> buildBatches() {
    final names = loadCorpus().take(300).toList();
    final batches = <List<Torrent>>[];
    for (var i = 0; i < names.length; i += 60) {
      batches.add([
        for (var j = i; j < names.length && j < i + 60; j++)
          // Every 5th row: seeders 0 → a big equal-seeder run per batch.
          t(names[j], seeders: j % 5 == 0 ? 0 : (j * 37) % 500),
        // Overlap: every batch re-reports the FIRST name with EQUAL seeders
        // but a different source-ish name suffix — two engines finding the
        // same torrent, tie-break must pick the same winner regardless of
        // which engine answered first.
        t(
          '${names.first} [mirror ${i ~/ 60}]',
          hash: names.first.hashCode.toRadixString(16).padLeft(40, '0'),
          seeders: 42,
        ),
      ]);
    }
    return batches;
  }

  void expectSameRows(List<Torrent> a, List<Torrent> b, String label) {
    expect(a.length, b.length, reason: '$label: lengths differ');
    for (var i = 0; i < a.length; i++) {
      expect(identical(a[i], b[i]), isTrue,
          reason: '$label: row $i diverged '
              '("${a[i].name}" vs "${b[i].name}")');
    }
  }

  test(
      'merge is ARRIVAL-ORDER independent — a streaming provisional merge '
      '(batches in completion order) equals the final merge (registration '
      'order), equal-seeder ties included', () {
    final batches = buildBatches();
    final registrationOrder = TorrentService.mergeSearchResults(batches);
    final arrivalOrder =
        TorrentService.mergeSearchResults(batches.reversed.toList());
    expectSameRows(arrivalOrder, registrationOrder, 'reversed-vs-forward');
  });

  test(
      'merge is associative — the NESTED final merge searchByImdbWithStremio '
      'performs (engines merged first, then merged with the addon batch) '
      'equals the flat provisional merge of the raw batches', () {
    final batches = buildBatches();
    final engineBatches = batches.sublist(0, batches.length - 1);
    final stremioBatch = batches.last;
    final nested = TorrentService.mergeSearchResults([
      TorrentService.mergeSearchResults(engineBatches),
      stremioBatch,
    ]);
    final flat = TorrentService.mergeSearchResults(batches);
    expectSameRows(nested, flat, 'nested-vs-flat');
  });

  test(
      'incremental batch merge == one-shot merge (the streaming provisional '
      'set can never drift from the final result)', () {
    final batches = buildBatches();
    final oneShot = TorrentService.mergeSearchResults(batches);

    // Streaming accumulation: merge after every batch, feed only the RAW
    // batches (as _streamBatches does), and compare the last provisional.
    final accumulated = <List<Torrent>>[];
    List<Torrent> provisional = const [];
    for (final b in batches) {
      accumulated.add(b);
      provisional = TorrentService.mergeSearchResults(accumulated);
    }
    expectSameRows(provisional, oneShot, 'incremental-vs-one-shot');
  });

  test('merging is pure — input batches are not mutated', () {
    final a = [t('x', seeders: 1), t('y', seeders: 2)];
    final snapshot = List.of(a);
    TorrentService.mergeSearchResults([a]);
    expect(a, snapshot);
  });
}
