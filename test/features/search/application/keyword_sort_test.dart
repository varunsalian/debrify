import 'package:debrify/features/search/application/keyword_sort.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent torrent(String name, {int seeders = 0, int size = 0, int date = 0}) =>
    Torrent(
      rowid: 0,
      infohash: name,
      name: name,
      sizeBytes: size,
      createdUnix: date,
      seeders: seeders,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
    );

void main() {
  final first = torrent('Zulu', seeders: 5, size: 900, date: 100);
  final second = torrent('alpha', seeders: 50, size: 100, date: 300);
  final third = torrent('Bravo', seeders: 0, size: 500, date: 200);
  final input = List<Torrent>.unmodifiable([first, second, third]);

  final ascending = <String, List<Torrent>>{
    'seeders': [third, first, second],
    'size': [second, third, first],
    'date': [first, third, second],
    'name': [second, third, first],
  };
  for (final field in ascending.keys) {
    for (final asc in [true, false]) {
      test('$field sorts ${asc ? 'ascending' : 'descending'} on a copy', () {
        final result = sortKeywordResults(input, field: field, ascending: asc);
        expect(result, asc ? ascending[field] : ascending[field]!.reversed);
        expect(input, [first, second, third]);
        expect(identical(result, input), isFalse);
      });
    }
  }

  for (final field in ['relevance', 'unknown']) {
    for (final asc in [true, false]) {
      test('$field retains engine order with ascending=$asc', () {
        final result = sortKeywordResults(input, field: field, ascending: asc);
        expect(result, input);
        result.clear();
        expect(input, [first, second, third]);
      });
    }
  }

  test('name uses the displayed title instead of the raw release name', () {
    final a = torrent('Zulu\nAlpha.release.1080p');
    final z = torrent('Alpha\nZulu.release.1080p');
    expect(sortKeywordResults([z, a], field: 'name', ascending: true), [a, z]);
  });

  test('equal numeric values do not introduce a name or hash tie-breaker', () {
    final z = torrent('Zulu', seeders: 10);
    final a = torrent('Alpha', seeders: 10);
    expect(sortKeywordResults([z, a], field: 'seeders', ascending: false), [
      z,
      a,
    ]);
  });

  test('case-only name differences remain ties', () {
    final upper = torrent('ALPHA', seeders: 1);
    final lower = torrent('alpha', seeders: 99);
    expect(sortKeywordResults([upper, lower], field: 'name', ascending: true), [
      upper,
      lower,
    ]);
  });

  test('empty and singleton inputs work for every field', () {
    for (final field in [...ascending.keys, 'relevance', 'unknown']) {
      expect(sortKeywordResults([], field: field, ascending: false), isEmpty);
      expect(sortKeywordResults([first], field: field, ascending: true), [
        first,
      ]);
    }
  });

  test('only names default to ascending', () {
    expect(keywordSortAscendingByDefault('name'), isTrue);
    for (final field in ['seeders', 'size', 'date', 'relevance', 'unknown']) {
      expect(keywordSortAscendingByDefault(field), isFalse);
    }
  });
}
