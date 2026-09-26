import 'package:debrify/features/sources/presentation/local_source_picker.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext page;
  late bool active;
  late List<String> calls;
  late bool Function() guard;
  BuildContext? dispatchedContext;
  bool Function()? dispatchedGuard;
  const source = SeriesSource(
    torrentHash: 'fixture',
    torrentName: 'Fixture',
    debridService: 'local',
    debridTorrentId: '/fixture',
    boundAt: 1,
  );

  Future<void> host(WidgetTester tester) async {
    active = true;
    calls = [];
    dispatchedContext = null;
    dispatchedGuard = null;
    guard = () => active;
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

  LocalSourcePicker picker({bool android = false, String? disabledReason}) =>
      LocalSourcePicker(
        androidFolderSelection: android,
        disabledReason: disabledReason,
        file: (context, {canContinue}) async {
          dispatchedContext = context;
          dispatchedGuard = canContinue;
          calls.add('file');
          return source;
        },
        movieFolder: (context, {required title, year, canContinue}) async {
          dispatchedContext = context;
          dispatchedGuard = canContinue;
          calls.add('movie:$title:$year');
          return source;
        },
        seriesFolder: (context, {required title, canContinue}) async {
          dispatchedContext = context;
          dispatchedGuard = canContinue;
          calls.add('series:$title');
          return source;
        },
      );

  for (final series in [false, true]) {
    testWidgets('disabled picker gives feedback without IO: series=$series', (
      tester,
    ) async {
      await host(tester);
      final subject = picker(disabledReason: 'Unavailable on this device');
      final result = series
          ? subject.pickSeriesSource(page, title: 'Show', canContinue: guard)
          : subject.pickMovieSource(page, title: 'Movie', canContinue: guard);
      expect(await result, isNull);
      await tester.pump();
      expect(find.text('Unavailable on this device'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFFEF4444),
      );
      expect(calls, isEmpty);
      expect(Navigator.of(page).canPop(), isFalse);
    });

    testWidgets('retired entry suppresses disabled feedback: series=$series', (
      tester,
    ) async {
      await host(tester);
      active = false;
      final subject = picker(disabledReason: 'Unavailable on this device');
      expect(
        await (series
            ? subject.pickSeriesSource(page, title: 'Show', canContinue: guard)
            : subject.pickMovieSource(
                page,
                title: 'Movie',
                canContinue: guard,
              )),
        isNull,
      );
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(calls, isEmpty);
    });
  }

  for (final android in [false, true]) {
    for (final file in [false, true]) {
      testWidgets(
        'movie dispatch preserves inputs: android=$android file=$file',
        (tester) async {
          await host(tester);
          final pending = picker(android: android).pickMovieSource(
            page,
            title: 'Arrival',
            year: '2016',
            canContinue: guard,
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
          expect(calls, isEmpty);
          await tester.tap(find.text(file ? 'Pick Video File' : 'Pick Folder'));
          await tester.pumpAndSettle();
          expect(await pending, same(source));
          expect(calls, [file ? 'file' : 'movie:Arrival:2016']);
          expect(dispatchedContext, same(page));
          expect(dispatchedGuard, same(guard));
          expect(Navigator.of(page).canPop(), isFalse);
        },
      );
    }
  }

  for (final file in [false, true]) {
    testWidgets('retired mode choice starts no platform work: file=$file', (
      tester,
    ) async {
      await host(tester);
      final pending = picker().pickMovieSource(
        page,
        title: 'Arrival',
        canContinue: guard,
      );
      await tester.pumpAndSettle();
      active = false;
      await tester.tap(find.text(file ? 'Pick Video File' : 'Pick Folder'));
      await tester.pumpAndSettle();
      expect(await pending, isNull);
      expect(calls, isEmpty);
      expect(Navigator.of(page).canPop(), isFalse);
    });
  }

  testWidgets('mode cancellation starts no platform work', (tester) async {
    await host(tester);
    final pending = picker().pickMovieSource(
      page,
      title: 'Arrival',
      canContinue: guard,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await pending, isNull);
    expect(calls, isEmpty);
    expect(Navigator.of(page).canPop(), isFalse);
  });

  testWidgets('series dispatch skips movie mode and preserves guard', (
    tester,
  ) async {
    await host(tester);
    expect(
      await picker().pickSeriesSource(page, title: 'Show', canContinue: guard),
      same(source),
    );
    expect(calls, ['series:Show']);
    expect(dispatchedContext, same(page));
    expect(dispatchedGuard, same(guard));
    expect(Navigator.of(page).canPop(), isFalse);
  });
}
