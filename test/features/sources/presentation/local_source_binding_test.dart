import 'dart:async';

import 'package:debrify/features/sources/presentation/local_source_binding.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pin = SeriesSource(
  torrentHash: '',
  torrentName: 'Local',
  debridService: SeriesSource.localService,
  debridTorrentId: '',
  boundAt: 1,
  localPath: '/fixture/movie.mkv',
  localKind: SeriesSource.localKindMovieFile,
);

class Fixture {
  late BuildContext context;
  bool active = true;
  String imdb = 'tt1';
  Future<SeriesSource?> Function() pick = () async => pin;
  Future<bool> Function(SeriesSource) save = (_) async => true;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
  }

  Future<bool> run() => presentLocalSourceBinding(
    context,
    imdbId: imdb,
    pick: pick,
    save: save,
    canContinue: () => active,
  );
}

void main() {
  testWidgets('retired entry does not open picker', (tester) async {
    final f = Fixture()..active = false;
    f.pick = () => throw StateError('Unexpected picker');
    await f.mount(tester);
    expect(await f.run(), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('missing identity reports before opening picker', (tester) async {
    final f = Fixture()..imdb = '';
    f.pick = () => throw StateError('Unexpected picker');
    await f.mount(tester);
    expect(await f.run(), isFalse);
    await tester.pump();
    expect(find.text("No IMDb match — can't pin a source."), findsOneWidget);
  });

  for (final outcome in ['cancel', 'retire', 'close']) {
    testWidgets('picker completion $outcome cannot save', (tester) async {
      final f = Fixture();
      final picking = Completer<SeriesSource?>();
      f.pick = () => picking.future;
      f.save = (_) => throw StateError('Unexpected save');
      await f.mount(tester);
      final work = f.run();
      if (outcome == 'retire') f.active = false;
      if (outcome == 'close') await tester.pumpWidget(const SizedBox());
      picking.complete(outcome == 'cancel' ? null : pin);
      expect(await work, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  for (final accepted in [false, true]) {
    testWidgets(
      'save result and descriptor identity survive, accepted=$accepted',
      (tester) async {
        final f = Fixture();
        SeriesSource? written;
        f.save = (source) async {
          written = source;
          return accepted;
        };
        await f.mount(tester);
        expect(await f.run(), accepted);
        await tester.pump();
        expect(written, same(pin));
        expect(
          find.text('Local source pinned.'),
          accepted ? findsOneWidget : findsNothing,
        );
        if (accepted) {
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).duration,
            const Duration(seconds: 3),
          );
        }
      },
    );
  }

  testWidgets('successful save after retirement has no feedback', (
    tester,
  ) async {
    final f = Fixture();
    final saving = Completer<bool>();
    f.save = (_) => saving.future;
    await f.mount(tester);
    final work = f.run();
    await tester.pump();
    f.active = false;
    saving.complete(true);
    expect(await work, isTrue);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final stage in ['picker', 'save']) {
    testWidgets('$stage errors propagate unchanged', (tester) async {
      final error = StateError('Unavailable');
      final f = Fixture();
      if (stage == 'picker') {
        f.pick = () async => throw error;
      } else {
        f.save = (_) async => throw error;
      }
      await f.mount(tester);
      await expectLater(f.run(), throwsA(same(error)));
      expect(find.byType(SnackBar), findsNothing);
    });
  }
}
