import 'dart:async';

import 'package:debrify/features/sources/presentation/android_local_source_picker.dart';
import 'package:debrify/models/local_source_document.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

LocalSourceDocument document(String name, {bool folder = false}) =>
    LocalSourceDocument(
      uri: 'content://opaque/$name',
      name: name,
      relativePath: 'Folder/$name',
      isDirectory: folder,
      sizeBytes: 123,
      modifiedAt: 456,
    );

void main() {
  late BuildContext page;
  late List<bool> picks;
  late List<String> scans;
  late LocalSourceDocument? picked;
  late List<LocalSourceDocument> videos;
  late int count;
  late AndroidLocalSourcePicker picker;
  Future<void> host(WidgetTester tester) async {
    picks = [];
    scans = [];
    picked = document('Folder', folder: true);
    videos = [document('B.mkv'), document('A.mkv')];
    count = 2;
    picker = AndroidLocalSourcePicker(
      pick: ({required directory}) async {
        picks.add(directory);
        return picked;
      },
      scan: (uri) async {
        scans.add(uri);
        return videos;
      },
      isVideoFile: (name) => name.endsWith('.mkv'),
      episodeCount: (_) => count,
    );
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

  for (final series in [false, true]) {
    testWidgets('cancelled native pick does not scan: series=$series', (
      tester,
    ) async {
      await host(tester);
      picked = null;
      final pending = series
          ? picker.pickSeries(page, 'Show')
          : picker.pickMovie(page, folder: true);
      await tester.pumpAndSettle();
      expect(await pending, isNull);
      expect(picks, [true]);
      expect(scans, isEmpty);
    });
    testWidgets('retired entry does not open native picker: series=$series', (
      tester,
    ) async {
      await host(tester);
      final pending = series
          ? picker.pickSeries(page, 'Show', canContinue: () => false)
          : picker.pickMovie(page, folder: false, canContinue: () => false);
      expect(await pending, isNull);
      expect(picks, isEmpty);
      expect(scans, isEmpty);
    });
  }

  for (final invalid in ['folder', 'text']) {
    testWidgets('movie file rejects $invalid', (tester) async {
      await host(tester);
      picked = document(
        invalid == 'folder' ? 'Folder.mkv' : 'Readme.txt',
        folder: invalid == 'folder',
      );
      final pending = picker.pickMovie(page, folder: false);
      await tester.pumpAndSettle();
      expect(await pending, isNull);
      expect(find.text('Please select a video file.'), findsOneWidget);
      expect(scans, isEmpty);
    });
  }

  testWidgets('movie file produces the opaque document binding without scan', (
    tester,
  ) async {
    await host(tester);
    picked = document('Movie.mkv');
    final result = await picker.pickMovie(page, folder: false);
    expect(result!.localUri, picked!.uri);
    expect(result.localKind, SeriesSource.localKindMovieFile);
    expect(result.localSizeBytes, 123);
    expect(result.localModifiedAt, 456);
    expect(picks, [false]);
    expect(scans, isEmpty);
  });

  testWidgets('movie folder sorts documents before presenting selection', (
    tester,
  ) async {
    await host(tester);
    final pending = picker.pickMovie(page, folder: true);
    await tester.pumpAndSettle();
    expect(scans, [picked!.uri]);
    expect(videos.map((video) => video.name), ['A.mkv', 'B.mkv']);
    expect(Focus.of(tester.element(find.text('A.mkv'))).hasFocus, isTrue);
    await tester.tap(find.text('B.mkv'));
    await tester.pumpAndSettle();
    expect((await pending)!.localUri, videos.last.uri);
  });

  for (final series in [false, true]) {
    testWidgets('empty scan reports the existing message: series=$series', (
      tester,
    ) async {
      await host(tester);
      videos = [];
      count = 0;
      final pending = series
          ? picker.pickSeries(page, 'Show')
          : picker.pickMovie(page, folder: true);
      await tester.pumpAndSettle();
      expect(await pending, isNull);
      expect(
        find.text(
          series
              ? 'No episodes found. Select this show’s folder with episode filenames such as S01E01.'
              : 'No video files found in that folder.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('series confirmation binds folder after episode classification', (
    tester,
  ) async {
    await host(tester);
    count = 7;
    final pending = picker.pickSeries(page, 'Show');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Folder\n7 episodes found.\n\nChoose a folder containing only this series.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Use folder'));
    await tester.pumpAndSettle();
    final result = await pending;
    expect(result!.localUri, picked!.uri);
    expect(result.localKind, SeriesSource.localKindSeriesFolder);
  });

  for (final stage in ['pick', 'scan', 'choice']) {
    testWidgets('retirement during $stage rejects movie binding', (
      tester,
    ) async {
      await host(tester);
      var active = true;
      final pick = Completer<LocalSourceDocument?>();
      final scan = Completer<List<LocalSourceDocument>>();
      var scanCalls = 0;
      picker = AndroidLocalSourcePicker(
        pick: ({required directory}) => pick.future,
        scan: (_) {
          scanCalls++;
          return scan.future;
        },
        isVideoFile: (_) => true,
        episodeCount: (_) => 1,
      );
      final pending = picker.pickMovie(
        page,
        folder: true,
        canContinue: () => active,
      );
      if (stage == 'pick') active = false;
      pick.complete(picked);
      await tester.pump(const Duration(milliseconds: 300));
      if (stage == 'scan') active = false;
      scan.complete(videos);
      await tester.pumpAndSettle();
      if (stage == 'choice') {
        active = false;
        await tester.tap(find.text('A.mkv'));
        await tester.pumpAndSettle();
      }
      expect(await pending, isNull);
      expect(scanCalls, stage == 'pick' ? 0 : 1);
      expect(find.text('Reading local folder…'), findsNothing);
    });
  }

  for (final series in [false, true]) {
    for (final unavailable in [false, true]) {
      testWidgets(
        'native failure feedback: series=$series unavailable=$unavailable',
        (tester) async {
          await host(tester);
          picker = AndroidLocalSourcePicker(
            pick: ({required directory}) async => throw (unavailable
                ? const LocalSourceUnavailable('Permission lost')
                : PlatformException(code: 'failure')),
            scan: (_) async => [],
            isVideoFile: (_) => true,
            episodeCount: (_) => 0,
          );
          final pending = series
              ? picker.pickSeries(page, 'Show')
              : picker.pickMovie(page, folder: false);
          await tester.pumpAndSettle();
          expect(await pending, isNull);
          expect(
            find.text(
              unavailable
                  ? 'Permission lost'
                  : series
                  ? 'Local folder could not be opened.'
                  : 'Local source could not be opened.',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
}
