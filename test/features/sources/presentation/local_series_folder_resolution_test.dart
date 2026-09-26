import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/models/local_source_file.dart';
import 'package:debrify/features/sources/presentation/local_series_folder_resolution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext page;
  Future<void> host(WidgetTester tester) async {
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

  final folder = Directory('/fixture/Show');
  final candidates = [
    LocalSeriesFolderCandidate(
      directory: folder,
      folderName: 'Show',
      score: 10,
    ),
    LocalSeriesFolderCandidate(
      directory: Directory('/fixture/Other'),
      folderName: 'Other',
      score: 5,
    ),
  ];
  Future<Directory?> resolve(
    Future<LocalSeriesFolderLookup?> Function() lookup, {
    bool Function()? active,
  }) => resolveLocalSeriesFolder(
    page,
    title: 'Show',
    pickedFolderName: 'Parent',
    lookup: lookup,
    canContinue: active,
  );

  for (final direct in [false, true]) {
    testWidgets('one matching folder returns without dialog: direct=$direct', (
      tester,
    ) async {
      await host(tester);
      final result = await resolve(
        () async => (
          direct: direct ? folder : null,
          candidates: direct
              ? const <LocalSeriesFolderCandidate>[]
              : [candidates.first],
        ),
      );
      expect(result, same(folder));
      expect(Navigator.of(page).canPop(), isFalse);
    });
  }

  testWidgets('unavailable lookup returns without folder help', (tester) async {
    await host(tester);
    expect(await resolve(() async => null), isNull);
    expect(Navigator.of(page).canPop(), isFalse);
  });

  testWidgets('late matching lookup is rejected after retirement', (
    tester,
  ) async {
    await host(tester);
    final lookup = Completer<LocalSeriesFolderLookup?>();
    var active = true;
    final pending = resolve(() => lookup.future, active: () => active);
    active = false;
    lookup.complete((
      direct: folder,
      candidates: const <LocalSeriesFolderCandidate>[],
    ));
    expect(await pending, isNull);
    expect(Navigator.of(page).canPop(), isFalse);
  });

  testWidgets('retired entry does not start lookup', (tester) async {
    await host(tester);
    var calls = 0;
    expect(
      await resolve(() async {
        calls++;
        return null;
      }, active: () => false),
      isNull,
    );
    expect(calls, 0);
  });

  for (final retired in [false, true]) {
    testWidgets('multiple-match choice preserves ownership: retired=$retired', (
      tester,
    ) async {
      await host(tester);
      var active = true;
      final pending = resolve(
        () async => (direct: null, candidates: candidates),
        active: () => active,
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose Series Folder'), findsOneWidget);
      if (retired) active = false;
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(await pending, retired ? isNull : same(candidates.last.directory));
    });
  }

  testWidgets('empty matches show help and never select parent', (
    tester,
  ) async {
    await host(tester);
    final pending = resolve(
      () async =>
          (direct: null, candidates: const <LocalSeriesFolderCandidate>[]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose the Show Folder'), findsOneWidget);
    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    expect(await pending, isNull);
  });
}
