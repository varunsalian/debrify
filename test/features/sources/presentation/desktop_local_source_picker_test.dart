import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/models/local_source_file.dart';
import 'package:debrify/features/sources/presentation/desktop_local_source_picker.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext page;
  late bool active;
  late String? path;
  late List<String> calls;
  late List<LocalVideoCandidate> candidates;
  late List<LocalSeriesEpisodeFile> episodes;
  late LocalVideoCandidate? matched;
  LocalVideoCandidate? described;
  const source = SeriesSource(
    torrentHash: 'fixture',
    torrentName: 'Fixture',
    debridService: 'local',
    debridTorrentId: '/fixture',
    boundAt: 1,
  );
  final folder = Directory('/fixture/Show');
  Future<void> host(WidgetTester tester) async {
    active = true;
    path = '/fixture';
    calls = [];
    described = null;
    candidates = [
      for (final name in ['First', 'Second'])
        LocalVideoCandidate(
          file: File('/fixture/$name.mkv'),
          fileName: '$name.mkv',
          sizeBytes: 10,
          modifiedAt: 0,
        ),
    ];
    matched = candidates.first;
    episodes = [
      LocalSeriesEpisodeFile(
        file: File('/fixture/Show/S01E01.mkv'),
        relativePath: 'S01E01.mkv',
        fileName: 'S01E01.mkv',
        season: 1,
        episode: 1,
        sizeBytes: 10,
        modifiedAt: 0,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const Scaffold();
          },
        ),
      ),
    );
  }

  Future<String?> pick() async {
    calls.add('pick');
    return path;
  }

  Future<SeriesSource?> movie({
    Future<List<LocalVideoCandidate>> Function(String)? scan,
  }) => pickDesktopMovieFolder(
    page,
    pickDirectory: pick,
    scan:
        scan ??
        (path) async {
          calls.add('scan:$path');
          return candidates;
        },
    match: (rows) {
      calls.add('match');
      return matched;
    },
    describe: (row) async {
      calls.add('describe');
      described = row;
      return source;
    },
    canContinue: () => active,
  );
  Future<SeriesSource?> series({
    Future<Directory?> Function(String)? resolve,
  }) => pickDesktopSeriesFolder(
    page,
    pickDirectory: pick,
    resolve:
        resolve ??
        (path) async {
          calls.add('resolve:$path');
          return folder;
        },
    scan: (path) async {
      calls.add('scan:$path');
      return episodes;
    },
    describe: (selected, count) async {
      calls.add('describe:${selected.path}:$count');
      return source;
    },
    canContinue: () => active,
  );

  for (final isSeries in [false, true]) {
    testWidgets(
      'retired desktop entry performs no operations: series=$isSeries',
      (tester) async {
        await host(tester);
        active = false;
        expect(await (isSeries ? series() : movie()), isNull);
        expect(calls, isEmpty);
      },
    );
    testWidgets(
      'cancelled and blank paths stop before scan: series=$isSeries',
      (tester) async {
        await host(tester);
        for (final value in [null, '', '  ']) {
          calls.clear();
          path = value;
          expect(await (isSeries ? series() : movie()), isNull);
          expect(calls, ['pick']);
        }
      },
    );
    testWidgets(
      'empty inventory retains feedback without describing: series=$isSeries',
      (tester) async {
        await host(tester);
        candidates = [];
        episodes = [];
        final pending = isSeries ? series() : movie();
        await tester.pumpAndSettle();
        expect(await pending, isNull);
        expect(
          find.text(
            isSeries
                ? 'No episodes found in that folder'
                : 'No video files found in that folder',
          ),
          findsOneWidget,
        );
        expect(calls.any((call) => call.startsWith('describe')), isFalse);
      },
    );
  }

  testWidgets('automatic movie match bypasses choice and preserves identity', (
    tester,
  ) async {
    await host(tester);
    expect(await movie(), same(source));
    expect(described, same(candidates.first));
    expect(calls, ['pick', 'scan:/fixture', 'match', 'describe']);
    expect(Navigator.of(page).canPop(), isFalse);
  });

  for (final retired in [false, true]) {
    testWidgets(
      'unmatched movie choice retains action ownership: retired=$retired',
      (tester) async {
        await host(tester);
        matched = null;
        final pending = movie();
        await tester.pumpAndSettle();
        if (retired) active = false;
        await tester.tap(find.text('Second.mkv'));
        await tester.pumpAndSettle();
        expect(await pending, retired ? isNull : same(source));
        expect(described, retired ? isNull : same(candidates.last));
      },
    );
  }

  testWidgets('series scans resolved path before describing episode count', (
    tester,
  ) async {
    await host(tester);
    expect(await series(), same(source));
    expect(calls, [
      'pick',
      'resolve:/fixture',
      'scan:/fixture/Show',
      'describe:/fixture/Show:1',
    ]);
  });

  testWidgets('retired folder resolution prevents series scan', (tester) async {
    await host(tester);
    final result = Completer<Directory?>();
    final pending = series(resolve: (_) => result.future);
    await tester.pump();
    active = false;
    result.complete(folder);
    expect(await pending, isNull);
    expect(calls, ['pick']);
  });

  testWidgets('retired movie scan prevents matching and description', (
    tester,
  ) async {
    await host(tester);
    final result = Completer<List<LocalVideoCandidate>>();
    final pending = movie(scan: (_) => result.future);
    await tester.pump();
    active = false;
    result.complete(candidates);
    expect(await pending, isNull);
    expect(calls, ['pick']);
  });
}
