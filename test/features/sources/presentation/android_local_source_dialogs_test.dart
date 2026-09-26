import 'package:debrify/features/sources/presentation/android_local_source_dialogs.dart';
import 'package:debrify/models/local_source_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const first = LocalSourceDocument(
  uri: 'content://tree/opaque%2Ffirst',
  name: 'First.mkv',
  relativePath: 'B/First.mkv',
  isDirectory: false,
  sizeBytes: 42,
  modifiedAt: 12,
);
const second = LocalSourceDocument(
  uri: 'content://tree/opaque%2Fsecond',
  name: 'Second.mkv',
  relativePath: 'A/Second.mkv',
  isDirectory: false,
  sizeBytes: 84,
  modifiedAt: 24,
);

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
  for (final keyboard in [false, true]) {
    testWidgets(
      'movie choice retains supplied order and document identity: keyboard=$keyboard',
      (tester) async {
        final page = await host(tester);
        final selected = showAndroidLocalMovieChoice(page, [first, second]);
        await tester.pumpAndSettle();
        expect(find.text('Choose movie file'), findsOneWidget);
        expect(find.text(first.relativePath), findsOneWidget);
        expect(find.text(second.relativePath), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(first.name)).dy,
          lessThan(tester.getTopLeft(find.text(second.name)).dy),
        );
        expect(
          Focus.of(tester.element(find.text(first.name))).hasFocus,
          isTrue,
        );
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text(second.name));
        }
        await tester.pumpAndSettle();
        expect(await selected, same(keyboard ? first : second));
        expect(Navigator.of(page).canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('movie Cancel and Back return no document', (tester) async {
    final page = await host(tester);
    for (final back in [false, true]) {
      final selected = showAndroidLocalMovieChoice(page, [first]);
      await tester.pumpAndSettle();
      if (back) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('Cancel'));
      }
      await tester.pumpAndSettle();
      expect(await selected, isNull);
      expect(Navigator.of(page).canPop(), isFalse);
    }
  });

  for (final accept in [false, true]) {
    testWidgets(
      'series confirmation preserves count and result: accept=$accept',
      (tester) async {
        final page = await host(tester);
        final selected = showAndroidLocalSeriesConfirmation(
          page,
          title: 'Fixture',
          folderName: 'Season folder',
          episodeCount: 12,
        );
        await tester.pumpAndSettle();
        expect(find.text('Use folder for Fixture?'), findsOneWidget);
        expect(
          find.text(
            'Season folder\n12 episodes found.\n\nChoose a folder containing only this series.',
          ),
          findsOneWidget,
        );
        expect(
          Focus.of(tester.element(find.text('Use folder'))).hasFocus,
          isTrue,
        );
        if (accept) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Cancel'));
        }
        await tester.pumpAndSettle();
        expect(await selected, accept);
        expect(Navigator.of(page).canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('series Back returns null rather than confirmation', (
    tester,
  ) async {
    final page = await host(tester);
    final selected = showAndroidLocalSeriesConfirmation(
      page,
      title: 'Fixture',
      folderName: 'Folder',
      episodeCount: 1,
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await selected, isNull);
    expect(Navigator.of(page).canPop(), isFalse);
  });
}
