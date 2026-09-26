import 'dart:io';

import 'package:debrify/features/sources/models/local_source_file.dart';
import 'package:debrify/features/sources/presentation/local_movie_pick_mode_sheet.dart';
import 'package:debrify/features/sources/presentation/local_source_choice_dialogs.dart';
import 'package:debrify/features/sources/presentation/local_series_folder_help.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> host(WidgetTester tester) async {
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
  return page;
}

void main() {
  for (final android in [false, true]) {
    testWidgets(
      'movie mode preserves wording and directional selection: $android',
      (tester) async {
        final page = await host(tester);
        final choice = showLocalMoviePickMode(
          page,
          androidFolderSelection: android,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            android
                ? 'Choose a movie file inside a folder'
                : 'Match by filename, then use the largest match',
          ),
          findsOneWidget,
        );
        expect(
          Focus.of(tester.element(find.text('Pick Video File'))).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          Focus.of(tester.element(find.text('Pick Folder'))).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(await choice, LocalMoviePickMode.folder);
        expect(Navigator.of(page).canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'movie mode file selection and Back return the original results',
    (tester) async {
      final page = await host(tester);
      final picked = showLocalMoviePickMode(
        page,
        androidFolderSelection: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick Video File'));
      await tester.pumpAndSettle();
      expect(await picked, LocalMoviePickMode.file);
      final cancelled = showLocalMoviePickMode(
        page,
        androidFolderSelection: false,
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await cancelled, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'folder choice retains order, 40-row limit and selected identity',
    (tester) async {
      final page = await host(tester);
      final candidates = List.generate(
        42,
        (i) => LocalSeriesFolderCandidate(
          directory: Directory('/fixture/$i'),
          folderName: 'Folder $i',
          score: 42 - i,
        ),
      );
      final choice = showLocalSeriesFolderChoice(
        page,
        title: 'Fixture',
        candidates: candidates,
      );
      await tester.pumpAndSettle();
      expect(find.text('Multiple folders matched "Fixture".'), findsOneWidget);
      expect(find.text('Folder 0'), findsOneWidget);
      expect(find.text('/fixture/0'), findsOneWidget);
      final list = find.byType(ListView);
      expect(
        tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
        79,
      );
      await tester.drag(list, const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(find.text('Folder 39'), findsOneWidget);
      expect(find.text('Folder 40'), findsNothing);
      await tester.tap(find.text('Folder 39'));
      await tester.pumpAndSettle();
      expect(await choice, same(candidates[39]));
      expect(candidates, hasLength(42));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file choice retains size labels, 80-row limit and selected identity',
    (tester) async {
      final page = await host(tester);
      final candidates = List.generate(
        82,
        (i) => LocalVideoCandidate(
          file: File('/fixture/$i.mkv'),
          fileName: 'File $i',
          sizeBytes: i == 0 ? 0 : 1024 * 1024,
          modifiedAt: 1,
        ),
      );
      final choice = showLocalFileChoice(page, candidates);
      await tester.pumpAndSettle();
      expect(find.text('Unknown size'), findsOneWidget);
      expect(find.text('1.0 MB'), findsWidgets);
      final list = find.byType(ListView);
      expect(
        tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
        159,
      );
      await tester.drag(list, const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.text('File 79'), findsOneWidget);
      expect(find.text('File 80'), findsNothing);
      await tester.tap(find.text('File 79'));
      await tester.pumpAndSettle();
      expect(await choice, same(candidates[79]));
      expect(candidates, hasLength(82));
      expect(tester.takeException(), isNull);
    },
  );

  for (final folders in [false, true]) {
    testWidgets('empty chooser Cancel returns null (folders: $folders)', (
      tester,
    ) async {
      final page = await host(tester);
      final Future<Object?> choice = folders
          ? showLocalSeriesFolderChoice(page, title: 'Fixture', candidates: [])
          : showLocalFileChoice(page, []);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await choice, isNull);
      expect(Navigator.of(page).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final picked in ['', 'Downloads']) {
    testWidgets('folder guidance retains examples and dismisses: $picked', (
      tester,
    ) async {
      final page = await host(tester);
      final closed = showLocalSeriesFolderHelp(
        page,
        title: 'The Office',
        pickedFolderName: picked,
      );
      await tester.pumpAndSettle();
      expect(find.text('TV Shows/The Office/'), findsOneWidget);
      expect(
        find.text(picked.isEmpty ? 'TV Shows/' : 'Downloads/'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await closed;
      expect(Navigator.of(page).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
