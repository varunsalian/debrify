import 'dart:convert';

import 'package:debrify/services/trakt/trakt_watched_history_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('unpaginated history is read once with seasons excluded', () async {
    var calls = 0;
    final rows = List.generate(300, (i) => {'show': i});
    final result = await readTraktWatchedShowHistory((path) async {
      calls++;
      expect(Uri.parse(path).queryParameters['extended'], 'noseasons');
      if (calls > 1) throw StateError('redundant request');
      return http.Response(jsonEncode(rows), 200);
    });
    expect(result, rows);
    expect(calls, 1);
  });

  test('explicit pagination fetches every page exactly once', () async {
    var calls = 0;
    final result = await readTraktWatchedShowHistory((path) async {
      calls++;
      expect(Uri.parse(path).queryParameters['page'], '$calls');
      return http.Response(
        '[{"show":$calls}]',
        200,
        headers: {
          'x-pagination-page-count': '3',
          'x-pagination-page': '$calls',
        },
      );
    });
    expect(result, [
      {'show': 1},
      {'show': 2},
      {'show': 3},
    ]);
    expect(calls, 3);
  });

  test('failed required page does not publish partial history', () async {
    var calls = 0;
    final result = await readTraktWatchedShowHistory((_) async {
      calls++;
      return calls == 1
          ? http.Response(
              '[{}]',
              200,
              headers: {'x-pagination-page-count': '2'},
            )
          : http.Response('unavailable', 503);
    });
    expect(result, isNull);
    expect(calls, 2);
  });

  test('empty history succeeds with or without pagination headers', () async {
    for (final headers in [
      <String, String>{},
      {'x-pagination-page-count': '0'},
    ]) {
      expect(
        await readTraktWatchedShowHistory(
          (_) async => http.Response('[]', 200, headers: headers),
        ),
        isEmpty,
      );
    }
  });

  test(
    'invalid responses and ambiguous pagination fail conservatively',
    () async {
      for (final response in [
        http.Response('{}', 200),
        http.Response('bad json', 200),
        http.Response('[]', 401),
        http.Response('[{}]', 200, headers: {'x-pagination-page-count': 'bad'}),
        http.Response('[{}]', 200, headers: {'x-pagination-limit': '100'}),
        http.Response('[{}]', 200, headers: {'x-pagination-page-count': '0'}),
      ]) {
        expect(
          await readTraktWatchedShowHistory((_) async => response),
          isNull,
        );
      }
      expect(await readTraktWatchedShowHistory((_) async => null), isNull);
      expect(
        await readTraktWatchedShowHistory(
          (_) async => throw StateError('offline'),
        ),
        isNull,
      );
    },
  );

  test(
    'later page losing pagination headers is not accepted as complete',
    () async {
      var calls = 0;
      expect(
        await readTraktWatchedShowHistory((_) async {
          calls++;
          return http.Response(
            '[{}]',
            200,
            headers: calls == 1 ? {'x-pagination-page-count': '2'} : {},
          );
        }),
        isNull,
      );
    },
  );
}
