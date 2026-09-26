import 'dart:async';
import 'dart:io';

import 'package:debrify/models/series_source.dart';
import 'package:debrify/services/local_bound_source_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DirectoryPicker extends FilePicker {
  DirectoryPicker(this.path);
  final String? path;
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => path;
}

void main() {
  setUpAll(() => FilePicker.platform = DirectoryPicker(null));
  for (final series in [false, true]) {
    testWidgets('local folder picker uses extracted files (series: $series)', (
      tester,
    ) async {
      final originalPicker = FilePicker.platform;
      late Directory root;
      late File chosen;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('picker-files-fixture-');
        if (series) {
          final folder = await Directory('${root.path}/The Office').create();
          chosen = await File(
            '${folder.path}/The.Office.S01E01.mkv',
          ).writeAsBytes([1, 2]);
          await Directory('${root.path}/Unrelated').create();
        } else {
          chosen = await File(
            '${root.path}/Arrival.2016.mkv',
          ).writeAsBytes([1, 2]);
          await File(
            '${root.path}/Arrival.2017.mkv',
          ).writeAsBytes(List.filled(10, 0));
        }
        FilePicker.platform = DirectoryPicker(root.path);
      });
      addTearDown(() async {
        FilePicker.platform = originalPicker;
        await root.delete(recursive: true);
      });
      late BuildContext page;
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
      SeriesSource? result;
      Object? error;
      var finished = false;
      await tester.runAsync(() async {
        final pending = series
            ? LocalBoundSourceService.pickSeriesSource(
                page,
                title: 'The Office',
              )
            : LocalBoundSourceService.pickMovieSource(
                page,
                title: 'Arrival',
                year: '2016',
              );
        unawaited(
          pending.then(
            (source) {
              result = source;
              finished = true;
            },
            onError: (Object caught) {
              error = caught;
              finished = true;
            },
          ),
        );
      });
      if (!series) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick Folder'));
      }
      for (var attempt = 0; attempt < 100 && !finished; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(finished, isTrue);
      expect(error, isNull);
      expect(result, isNotNull);
      expect(result!.localPath, series ? chosen.parent.path : chosen.path);
      expect(
        result!.localKind,
        series
            ? SeriesSource.localKindSeriesFolder
            : SeriesSource.localKindMovieFile,
      );
      expect(result!.localSizeBytes, series ? 1 : 2);
      await tester.pumpAndSettle();
      expect(Navigator.of(page).canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
