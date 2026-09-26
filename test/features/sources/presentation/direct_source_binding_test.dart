import 'dart:async';

import 'package:debrify/features/sources/presentation/direct_source_binding.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final torrent = Torrent(
  rowid: 0,
  infohash: 'url:fixture',
  name: 'Fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: StreamType.directUrl,
);
const pin = SeriesSource(
  torrentHash: '',
  torrentName: 'Fixture',
  debridService: SeriesSource.addonDirectService,
  addonId: 'addon',
  addonKey: 'configuration',
  debridTorrentId: '',
  boundAt: 1,
);

Future<BuildContext> mount(WidgetTester tester) async {
  late BuildContext context;
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
  return context;
}

void main() {
  testWidgets('retired entry invokes no data operation', (tester) async {
    final context = await mount(tester);
    expect(
      await presentDirectSourceBinding(
        context,
        torrent,
        imdbId: 'tt1',
        canContinue: () => false,
        authorize: (_) => throw StateError('Unexpected authorization'),
        describe: (_) => throw StateError('Unexpected descriptor'),
        save: (_) => throw StateError('Unexpected save'),
      ),
      isFalse,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final retire in [false, true]) {
    testWidgets('authorization rejection feedback, retired=$retire', (
      tester,
    ) async {
      final context = await mount(tester);
      final authorization = Completer<void>();
      var active = true;
      final work = presentDirectSourceBinding(
        context,
        torrent,
        imdbId: 'tt1',
        canContinue: () => active,
        authorize: (_) => authorization.future,
        describe: (_) => throw StateError('Unexpected descriptor'),
        save: (_) => throw StateError('Unexpected save'),
      );
      active = !retire;
      authorization.completeError(StateError('Changed connection'));
      expect(await work, isFalse);
      await tester.pump();
      expect(
        find.text('Connection changed. Search sources again.'),
        retire ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final saved in [false, true]) {
    testWidgets('retired save retains result without feedback, saved=$saved', (
      tester,
    ) async {
      final context = await mount(tester);
      final saving = Completer<bool>();
      var active = true;
      var saveStarted = false;
      SeriesSource? savedSource;
      final work = presentDirectSourceBinding(
        context,
        torrent,
        imdbId: 'tt1',
        canContinue: () => active,
        authorize: (_) async {},
        describe: (_) => pin,
        save: (source) {
          savedSource = source;
          saveStarted = true;
          return saving.future;
        },
      );
      await tester.pump();
      expect(saveStarted, isTrue);
      expect(savedSource, same(pin));
      active = false;
      saving.complete(saved);
      expect(await work, saved);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('legacy missing identity still authorizes before reporting it', (
    tester,
  ) async {
    final context = await mount(tester);
    var authorized = false;
    expect(
      await presentDirectSourceBinding(
        context,
        torrent,
        imdbId: '',
        authorize: (_) async {
          authorized = true;
        },
        describe: (_) => throw StateError('Unexpected descriptor'),
        save: (_) => throw StateError('Unexpected save'),
      ),
      isFalse,
    );
    expect(authorized, isTrue);
    await tester.pump();
    expect(find.text("No IMDb match — can't pin a source."), findsOneWidget);
  });
}
