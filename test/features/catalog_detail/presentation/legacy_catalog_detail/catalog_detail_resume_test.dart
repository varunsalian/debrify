import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/catalog_detail_fixture.dart';

void main() {
  for (final c in [
    (
      type: 'movie',
      loaded: false,
      started: false,
      season: null,
      episode: null,
      label: 'Play',
    ),
    (
      type: 'movie',
      loaded: true,
      started: false,
      season: null,
      episode: null,
      label: 'Play',
    ),
    (
      type: 'movie',
      loaded: true,
      started: true,
      season: null,
      episode: null,
      label: 'Resume',
    ),
    (
      type: 'series',
      loaded: true,
      started: false,
      season: null,
      episode: null,
      label: 'Start Watching',
    ),
    (
      type: 'series',
      loaded: true,
      started: true,
      season: null,
      episode: null,
      label: 'Resume',
    ),
    (
      type: 'series',
      loaded: true,
      started: true,
      season: 3,
      episode: 4,
      label: 'Resume · S3E4',
    ),
  ]) {
    testWidgets(
      'R resume ${c.type} loaded=${c.loaded} started=${c.started} ${c.label}',
      (t) async {
        await catalogDetailCase(t, (f) async {
          f.item = f.meta(type: c.type);
          f.resumeEnabled = c.loaded;
          f.resume = (started: c.started, season: c.season, episode: c.episode);
          await f.mount(t);
          expect(find.text(c.label), findsOneWidget);
          f.calls.clear();
          await f.tap(t, c.label);
          expect(f.calls, ['play']);
        });
      },
    );
  }
  testWidgets('R O pending spinner resolves to the series resume label', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.item = f.meta(type: 'series');
      f.heldResume = Completer<CatalogResume>();
      await f.mount(t, wait: false);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Start Watching'), findsNothing);
      expect(f.calls.where((x) => x == 'resume'), ['resume']);
      f.heldResume!.complete((started: true, season: 1, episode: 7));
      await f.finish(t);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Resume · S1E7'), findsOneWidget);
    });
  });
  testWidgets('R failed resume clears spinner and retains static Play', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.failResume = true;
      await f.mount(t);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      expect(f.calls.where((x) => x == 'resume'), ['resume']);
    });
  });
  testWidgets('R twelve second fake-time timeout clears unanswered resume', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.heldResume = Completer<CatalogResume>();
      await f.mount(t, wait: false);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(milliseconds: 11999));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      f.heldResume!.complete((started: true, season: null, episode: null));
      await t.pump();
      expect(find.text('Resume'), findsNothing);
    });
  });
}
