import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/features/video_player/models/vp_season_episode_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

const identifyRaceScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/identify.mp4',
  title: 'First title',
  viewMode: PlaylistViewMode.raw,
  playlist: [
    PlaylistEntry(
      url: 'https://player.test/identify.mp4',
      title: 'First title',
    ),
    PlaylistEntry(
      url: 'https://player.test/identify-next.mp4',
      title: 'Second title',
    ),
  ],
);
Future<void> identifyBoundary(
  IdentifyTitleDriver d,
  String event, {
  bool modal = true,
}) async {
  if (event == 'dismiss') {
    if (modal) {
      await d.dismiss();
    } else if (find.byType(PlayerMenuPanel).evaluate().isNotEmpty) {
      d.panel.onClose();
      await d.f.advance(d.t);
    }
  } else if (event == 'profile') {
    await incomingProfile(d.t, d.f);
  } else if (event == 'dispose') {
    await d.removePlayer(modalExpected: modal);
  } else {
    final count = d.player.calls.where((c) => c.$1 == 'open').length;
    final dynamic next = playerControls(d.t).onNext;
    final dynamic task = d.observe<dynamic>(() => next());
    if (task is Future) await d.f.finish<dynamic>(d.t, task);
    await d.f.until(
      d.t,
      () => d.player.calls.where((c) => c.$1 == 'open').length > count,
    );
  }
}

void main() {
  TraktTestTransport.install();
  for (final event in ['dismiss', 'reset', 'profile', 'dispose']) {
    testWidgets(
      'identify held catalog response across $event checks sheet and mounted, not profile or content',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        final gate = Completer<http.Response>();
        d.catalog = (_) => gate.future;
        try {
          await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
          final pending = d.start(await d.menu());
          await d.f.until(t, () => d.catalogQueries.isNotEmpty);
          final field = d.searchField;
          expect(d.catalogQueries, ['First title']);
          expect(field.controller.text, 'First title');
          await identifyBoundary(d, event);
          expect(gate.isCompleted, isFalse);
          gate.complete(d.response(d.metas));
          await d.f.actions.settle(t);
          expect(
            find.text('Chosen title'),
            ['reset', 'profile'].contains(event)
                ? findsOneWidget
                : findsNothing,
          );
          if (event != 'dismiss') await d.dismiss();
          expect(await d.f.finish(t, pending), isNull);
          expect(() => field.controller.addListener(() {}), throwsFlutterError);
          expect(() => field.focusNode!.addListener(() {}), throwsFlutterError);
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete(d.response([]));
          await removeFixture(d);
        }
      },
    );
  }
  for (final boundary in ['selection', 'episode']) {
    for (final event in ['dismiss', 'reset', 'profile', 'dispose']) {
      testWidgets(
        'identify held $boundary completion across $event preserves precommit guard',
        (t) async {
          final d = IdentifyTitleDriver(t);
          await d.setupIdentity();
          d.metas = [
            IdentifyTitleDriver.identityMeta(
              'Chosen title',
              type: boundary == 'episode' ? 'series' : 'movie',
            ),
          ];
          final delivery = CompletionDelivery(
            'identifyTitleAndFetchSubtitles',
            (v) => boundary == 'selection'
                ? v is StremioMeta
                : v is VpSeasonEpisodeSelection,
          );
          var returned = false;
          try {
            await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
            final menu = await d.menu();
            final pending = delivery.run(() => d.start(menu));
            pending.then((_) => returned = true);
            await d.found('Chosen title');
            await t.tap(find.text('Chosen title'));
            if (boundary == 'episode') await d.episode('2', '7');
            await d.f.until(t, () => delivery.pending.isNotEmpty);
            expect(returned, isFalse);
            expect(d.subtitlePaths, isEmpty);
            await identifyBoundary(d, event, modal: false);
            expect(returned, isFalse);
            expect(delivery.pending, hasLength(1));
            delivery.release();
            final accepted = await d.f.finish(t, pending);
            if (event == 'reset' || event == 'dispose') {
              expect(accepted, isNull);
              expect(d.subtitlePaths, isEmpty);
            } else {
              expect(accepted?.imdbId, 'tt1200002');
              expect(accepted?.season, boundary == 'episode' ? 2 : null);
              expect(accepted?.episode, boundary == 'episode' ? 7 : null);
              expect(
                accepted?.identityLabel,
                boundary == 'episode'
                    ? 'Subtitles for Chosen title S2E7'
                    : 'Subtitles for Chosen title',
              );
              expect(d.subtitlePaths, hasLength(1));
            }
            expect(d.errors, isEmpty);
          } finally {
            delivery.release();
            await removeFixture(d);
          }
        },
      );
    }
  }
  for (final boundary in ['discovery', 'autoselection']) {
    for (final event in ['dismiss', 'reset', 'profile', 'dispose']) {
      testWidgets(
        'identify held $boundary across $event pins manual commit and cache return timing',
        (t) async {
          final d = IdentifyTitleDriver(t);
          await d.setupIdentity();
          await d.order(language: 'eng');
          final gate = Completer<http.Response>();
          if (boundary == 'discovery') d.discovery = (_) => gate.future;
          final delivery = CompletionDelivery(
            'identifyTitleAndFetchSubtitles',
            (v) => v == null,
          );
          var returned = false;
          try {
            await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
            final menu = await d.menu();
            final pending = delivery.run(() => d.start(menu));
            pending.then((_) => returned = true);
            await d.found('Chosen title');
            await t.tap(find.text('Chosen title'));
            await d.f.until(
              t,
              () => boundary == 'discovery'
                  ? d.subtitlePaths.isNotEmpty
                  : delivery.pending.isNotEmpty || returned,
            );
            expect(returned, isFalse);
            expect(d.subtitlePaths, ['/subtitles/movie/tt1200002.json']);
            expect(find.text('Which episode?'), findsNothing);
            if (boundary == 'autoselection') {
              expect(d.player.state.track.subtitle.uri, isTrue);
              expect(d.requests(d.caption('identify')), 1);
            }
            await identifyBoundary(d, event, modal: false);
            expect(returned, isFalse);
            if (boundary == 'discovery') {
              gate.complete(d.slots('identify'));
              if (event != 'reset' && event != 'dispose') {
                await d.f.until(
                  t,
                  () => delivery.pending.isNotEmpty || returned,
                );
                expect(returned, isFalse);
              }
            }
            delivery.release();
            final accepted = await d.f.finish(t, pending);
            final rejected =
                boundary == 'discovery' &&
                (event == 'reset' || event == 'dispose');
            expect(accepted?.imdbId, rejected ? isNull : 'tt1200002');
            if (!rejected) {
              expect(accepted?.identityLabel, 'Subtitles for Chosen title');
              expect(accepted?.slots, hasLength(1));
              expect(accepted?.subtitles, hasLength(1));
              expect(accepted?.subtitles.single.id, 'identify');
            }
            expect(d.catalogQueries, ['First title']);
            expect(d.errors, isEmpty);
          } finally {
            if (!gate.isCompleted) gate.complete(d.slots('identify'));
            delivery.release();
            await removeFixture(d);
          }
        },
      );
    }
  }

  testWidgets(
    'identify result tile after player disposal uses live State context and modal resources remain owned until dismissal',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
        final pending = d.start(await d.menu());
        await d.found('Chosen title');
        final field = d.searchField;
        await d.removePlayer();
        expect(() => field.controller.addListener(() {}), returnsNormally);
        await t.tap(find.text('Chosen title'));
        final error = t.takeException();
        expect(error, isA<FlutterError>());
        expect(error.toString(), contains('State no longer has a context'));
        expect(find.text('FIX THE TITLE'), findsOneWidget);
        expect(d.subtitlePaths, isEmpty);
        await t.tap(find.byIcon(Icons.close_rounded));
        expect(t.takeException(), isNull);
        await d.f.advance(t);
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.text('FIX THE TITLE'), findsNothing);
        expect(await d.f.finish(t, pending), isNull);
        expect(() => field.controller.addListener(() {}), throwsFlutterError);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'identify saved public menu callback after disposal returns null without allocating another sheet',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
        final menu = await d.menu();
        await d.removePlayer(modalExpected: false);
        Object? failure;
        Object? value = 'pending';
        var completed = false;
        final task = d.f.actions.start(
          'retired identify callback',
          () => d.observe(
            () => menu.onIdentifyTitle!().then<void>(
              (v) {
                value = v;
                completed = true;
              },
              onError: (Object e) {
                failure = e;
                completed = true;
              },
            ),
          ),
          held: true,
        );
        await d.f.until(t, () => completed);
        await d.f.finish(t, task.future);
        expect(failure, isNull);
        expect(value, isNull);
        expect(find.text('FIX THE TITLE'), findsNothing);
        expect(d.catalogQueries, isEmpty);
        expect(d.subtitlePaths, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  for (final handoff in ['reset', 'reopening menu']) {
    testWidgets(
      'identify held A discovery cannot return after $handoff and a completed B identification',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        final heldA = Completer<http.Response>();
        d.discovery = (request) => request.url.path.contains('tt1200002')
            ? heldA.future
            : d.slots('identify');
        var aReturned = false;
        try {
          await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
          final a = d.start(await d.menu());
          a.then((_) => aReturned = true);
          await d.found('Chosen title');
          await t.tap(find.text('Chosen title'));
          await d.f.until(
            t,
            () => d.subtitlePaths.contains('/subtitles/movie/tt1200002.json'),
          );
          expect(aReturned, isFalse);
          if (handoff == 'reset') {
            await identifyBoundary(d, 'reset', modal: false);
          } else {
            d.panel.onClose();
          }
          await d.f.advance(t);
          d.metas = [
            IdentifyTitleDriver.identityMeta('New identity B', id: 'tt1200003'),
          ];
          final b = d.start(await d.menu());
          await d.found('New identity B');
          await t.tap(find.text('New identity B'));
          final chosen = await d.f.finish(t, b);
          expect(chosen?.imdbId, 'tt1200003');
          expect(chosen?.identityLabel, 'Subtitles for New identity B');
          expect(aReturned, isFalse);
          expect(heldA.isCompleted, isFalse);
          heldA.complete(d.slots('identify'));
          expect(await d.f.finish(t, a), isNull);
          expect(d.panel.subtitleIdentityLabel, 'Subtitles for New identity B');
          expect(d.errors, isEmpty);
        } finally {
          if (!heldA.isCompleted) heldA.complete(d.slots('identify'));
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'identify dismissed suffix response cannot invoke the disposed sheet setter',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      final gate = Completer<http.Response>();
      d.catalog = (_) => gate.future;
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/stale-sheet.mp4',
            title: '',
          ),
          rooted: true,
        );
        final pending = d.start(await d.menu());
        await d.sheet();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final field = d.searchField;
        await d.type('held');
        await d.observeFuture(d.suffix);
        await d.f.until(t, () => d.catalogQueries.isNotEmpty);
        expect(gate.isCompleted, isFalse);
        await d.dismiss();
        expect(await d.f.finish(t, pending), isNull);
        gate.complete(d.response(d.metas));
        await d.f.actions.settle(t);
        expect(d.errors, isEmpty);
        expect(t.takeException(), isNull);
        expect(find.text('FIX THE TITLE'), findsNothing);
        expect(d.catalogQueries, ['held']);
        expect(() => field.controller.addListener(() {}), throwsFlutterError);
      } finally {
        if (!gate.isCompleted) gate.complete(d.response([]));
        await removeFixture(d);
      }
    },
  );
}
