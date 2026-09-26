import 'dart:async';

import 'package:debrify/features/sources/presentation/iptv_source_binding.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
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
  SeriesSource? descriptor = const SeriesSource(
    torrentHash: '',
    torrentName: 'Fixture',
    debridService: SeriesSource.iptvDirectService,
    debridTorrentId: '',
    boundAt: 1,
    iptvPlaylistId: 'playlist',
    iptvCatalogType: 'series',
    iptvEntryKey: 'entry',
  );
  final events =
      <
        ({
          String event,
          String? catalog,
          String? outcome,
          Object? error,
          Torrent? source,
        })
      >[];
  Future<void> Function(Torrent) authorize = (_) async {};
  Future<bool> Function(SeriesSource) save = (_) async => true;
  bool active = true;
  bool movie = false;
  String imdb = 'tt1';
  int descriptions = 0;
  late BuildContext context;

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

  Future<bool> run() => presentIptvSourceBinding(
    context,
    torrent,
    imdbId: imdb,
    isMovie: movie,
    canContinue: () => active,
    authorize: authorize,
    describe: (_) {
      descriptions++;
      return descriptor;
    },
    save: save,
    log: (event, {source, catalogType, outcome, error}) => events.add((
      event: event,
      source: source,
      catalog: catalogType,
      outcome: outcome,
      error: error,
    )),
  );
}

void main() {
  testWidgets('retired entry has no operation or diagnostic', (tester) async {
    final f = Fixture()..active = false;
    f.authorize = (_) => throw StateError('Unexpected authorization');
    await f.mount(tester);
    expect(await f.run(), isFalse);
    expect(f.events, isEmpty);
    expect(f.descriptions, 0);
  });

  testWidgets('missing identity reports before authorization', (tester) async {
    final f = Fixture()..imdb = '';
    f.authorize = (_) => throw StateError('Unexpected authorization');
    await f.mount(tester);
    expect(await f.run(), isFalse);
    await tester.pump();
    expect(f.events.map((e) => e.event), [
      'manual_pin_started',
      'manual_pin_completed',
    ]);
    expect(f.events.last.outcome, 'imdb_missing');
    expect(find.text("No IMDb match — can't pin a source."), findsOneWidget);
  });

  for (final retired in [false, true]) {
    testWidgets(
      'authorization failure diagnostics survive retirement=$retired',
      (tester) async {
        final f = Fixture();
        final authorization = Completer<void>();
        f.authorize = (_) => authorization.future;
        await f.mount(tester);
        final work = f.run();
        f.active = !retired;
        final error = StateError('Connection changed');
        authorization.completeError(error);
        expect(await work, isFalse);
        await tester.pump();
        expect(f.events.last.outcome, 'authorization_rejected');
        expect(f.events.last.error, same(error));
        expect(f.descriptions, 0);
        expect(
          find.text('IPTV connection changed. Search sources again.'),
          retired ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  for (final closeView in [false, true]) {
    testWidgets(
      'post-authorization retirement identifies view closure=$closeView',
      (tester) async {
        final f = Fixture();
        final authorization = Completer<void>();
        f.authorize = (_) => authorization.future;
        await f.mount(tester);
        final work = f.run();
        if (closeView) {
          await tester.pumpWidget(const SizedBox());
        } else {
          f.active = false;
        }
        authorization.complete();
        expect(await work, isFalse);
        expect(
          f.events.last.outcome,
          closeView ? 'view_closed' : 'session_retired',
        );
        expect(f.descriptions, 0);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('missing provenance prevents saving and reports outcome', (
    tester,
  ) async {
    final f = Fixture()..descriptor = null;
    f.save = (_) => throw StateError('Unexpected save');
    await f.mount(tester);
    expect(await f.run(), isFalse);
    await tester.pump();
    expect(f.events.last.outcome, 'provenance_missing');
    expect(
      find.text('This IPTV source cannot be refreshed from its catalog.'),
      findsOneWidget,
    );
  });

  testWidgets('rejected save reports retirement without success', (
    tester,
  ) async {
    final f = Fixture()..save = (_) async => false;
    await f.mount(tester);
    expect(await f.run(), isFalse);
    expect(f.events.last.outcome, 'session_retired');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('storage failure is logged and rethrown unchanged', (
    tester,
  ) async {
    final error = StateError('Storage unavailable');
    final f = Fixture()..save = (_) async => throw error;
    await f.mount(tester);
    await expectLater(f.run(), throwsA(same(error)));
    expect(f.events.last.outcome, 'storage_failed');
    expect(f.events.last.error, same(error));
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final movie in [false, true]) {
    testWidgets('successful pin preserves catalog and feedback, movie=$movie', (
      tester,
    ) async {
      final f = Fixture()..movie = movie;
      SeriesSource? written;
      f.save = (source) async {
        written = source;
        return true;
      };
      await f.mount(tester);
      expect(await f.run(), isTrue);
      await tester.pump();
      expect(written, same(f.descriptor));
      expect(f.events.first.catalog, movie ? 'vod' : 'series');
      expect(f.events.last.outcome, 'saved');
      expect(f.events.every((e) => identical(e.source, f.torrent)), isTrue);
      expect(
        find.text(
          movie
              ? 'IPTV movie source pinned.'
              : 'IPTV series source pinned for every episode.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('save completion after retirement logs saved without feedback', (
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
    expect(f.events.last.outcome, 'saved');
    expect(find.byType(SnackBar), findsNothing);
  });
}
