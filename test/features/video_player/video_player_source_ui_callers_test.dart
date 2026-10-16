import 'dart:async';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/display_defaults_reads.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
// Existing resolved test transport; app dependencies remain frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/startup_driver.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets(
      'P16 ${television ? 'TV' : 'desktop'} source buttons and Back/Escape share the live source sheet callbacks',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        PlatformUtil.debugSetAndroidTvCached(television);
        final a = startupSource('ui-a'), b = startupSource('ui-b');
        try {
          await d.begin(
            d.screen(sources: [a, b], resolve: (s) async => s.directUrl),
          );
          await d.initialized();
          if (television) {
            t.widget<TvControls>(find.byType(TvControls)).onShowSources!();
          } else {
            playerControls(t).onShowStremioSources!();
          }
          await d.tick(const Duration(milliseconds: 300));
          expect(find.byType(SourceSheet), findsOneWidget);
          final first = t.widget<SourceSheet>(find.byType(SourceSheet));
          expect(first.sources, [a, b]);
          if (!television) {
            final opacity = t.widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(Controls),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            );
            expect(opacity.opacity, 0);
          }
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await d.tick();
          expect(find.byType(SourceSheet), findsNothing);
          await t.sendKeyEvent(LogicalKeyboardKey.keyS);
          await d.tick(const Duration(milliseconds: 300));
          expect(find.byType(SourceSheet), findsOneWidget);
          final second = t.widget<SourceSheet>(find.byType(SourceSheet));
          expect(second.onClose == first.onClose, isTrue);
          expect(second.onSourceSelected == first.onSourceSelected, isTrue);
          await t.sendKeyEvent(
            LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await d.tick();
          expect(find.byType(SourceSheet), findsNothing);
          if (television) {
            await d.sheet();
            await t.binding.handlePopRoute();
            await d.tick();
            expect(find.byType(SourceSheet), findsNothing);
            expect(d.routeReturned, isFalse);
          }
          expect(d.opens, [a.directUrl]);
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
  testWidgets(
    'P16 source-sheet growth feeds the facade effective list and selects the merged row',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('grow-a'),
          b = startupSource('grow-b'),
          c = startupSource('grow-c');
      try {
        await d.begin(
          d.screen(sources: [a, b], resolve: (s) async => s.directUrl),
        );
        await d.initialized();
        final sheet = await d.sheet();
        expect(sheet.onSourcesMerged, isNotNull);
        sheet.onSourcesMerged!([a, b, c]);
        await d.tick();
        final grown = t.widget<SourceSheet>(find.byType(SourceSheet));
        expect(grown.sources, [a, b, c]);
        expect(grown.currentSourceIndex, 0);
        final url = (await d.f.finish(t, grown.resolveSource(c)))!;
        final action = d.select(grown, 2, url);
        await d.f.finish(t, action.future);
        expect(d.commits, [a, c]);
        final selected = await d.sheet();
        expect(selected.sources, [a, b, c]);
        expect(selected.currentSourceIndex, 2);
      } finally {
        await d.close();
      }
    },
  );
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 TV ${playlist ? 'playlist' : 'direct'} source choice abandons a rendered scrub and starts its transition before pause returns',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        PlatformUtil.debugSetAndroidTvCached(true);
        final a = startupSource('scrub-a'), b = startupSource('scrub-b');
        final pause = Completer<void>();
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              resolve: (s) async => s.directUrl,
              playlist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: b.directUrl!, title: 'Incoming'),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          final controls = t.widget<TvControls>(find.byType(TvControls));
          controls.progressFocusNode.requestFocus();
          await d.tick();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await d.tick();
          final scrubbing = t.widget<TvControls>(find.byType(TvControls));
          expect(scrubbing.scrubPreview, isNotNull);
          final oldTarget = scrubbing.scrubPreview;
          scrubbing.onShowSources!();
          await d.tick(const Duration(milliseconds: 300));
          final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          d.player.delays['pause'] = pause;
          final before = d.player.calls.where((c) => c.$1 == 'pause').length;
          final action = d.select(sheet, 1, url);
          await d.f.until(
            t,
            () => d.player.calls.where((c) => c.$1 == 'pause').length > before,
          );
          await d.tick();
          expect(action.isCompleted, isFalse);
          final pending = t.widget<TvControls>(find.byType(TvControls));
          expect(pending.scrubPreview, isNull);
          expect(pending.isTransitioning, isTrue);
          expect(find.byType(TransitionOverlay), findsOneWidget);
          expect(find.byType(SourceSheet), findsNothing);
          pause.complete();
          await d.f.finish(t, action.future);
          expect(
            d.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            isNot(contains(oldTarget)),
          );
          expect(
            t.widget<TvControls>(find.byType(TvControls)).isTransitioning,
            isFalse,
          );
          t.widget<TvControls>(find.byType(TvControls)).onShowSources!();
          await d.tick(const Duration(milliseconds: 300));
          expect(
            t.widget<SourceSheet>(find.byType(SourceSheet)).currentSourceIndex,
            1,
          );
          expect(d.commits, [a, b]);
        } finally {
          pause.completeIfPending();
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 early ${playlist ? 'playlist' : 'direct'} source selection before defaults pins the player error, partial identity and later completion gate',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final oldStore = SharedPreferencesStorePlatform.instance;
        DisplayDefaultsReads? reads;
        final a = startupSource('early-a'), b = startupSource('early-b');
        try {
          reads = await t.runAsync(DisplayDefaultsReads.install);
          t.view.physicalSize = const Size(1280, 800);
          t.view.devicePixelRatio = 1;
          await d.observe(
            () => t.pumpWidget(
              MaterialApp(
                navigatorKey: d.f.navigator,
                theme: ThemeData.dark(),
                home: d.screen(
                  id: 'tt9200016',
                  sources: [a, b],
                  resolve: (s) async => s.directUrl,
                  playlist: playlist
                      ? (s, {canContinue}) async => [
                          PlaylistEntry(url: b.directUrl!, title: 'Incoming'),
                        ]
                      : null,
                ),
              ),
            ),
          );
          await d.f.until(t, () => reads!.entered);
          expect(d.f.creationOrder, ['media-kit-init']);
          expect(d.f.players, isEmpty);
          final sheet = await d.sheet();
          expect(sheet.currentSourceIndex, 0);
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          expect(url, b.directUrl);
          Object? error;
          final action = d.observe(
            () => d.f.actions.start('early original source callback', () async {
              try {
                final dynamic callback = sheet.onSourceSelected;
                final dynamic result = callback(1, url);
                if (result is Future) await result;
              } catch (e) {
                error = e;
              }
            }, held: true),
          );
          await d.f.finish(t, action.future);
          if (playlist) {
            expect(error, isNull);
          } else {
            expect(error, isA<Error>());
            expect(error.toString(), contains("Field '_player"));
            expect(error.toString(), contains('has not been initialized'));
          }
          await d.tick();
          expect(find.byType(SourceSheet), findsNothing);
          expect(d.f.players, isEmpty);
          expect(d.opens, isEmpty);
          expect(d.commits, isEmpty);
          expect(reads!.writes, isEmpty);
          final rejected = d.logs
              .where(
                (s) => s.startsWith(
                  playlist
                      ? 'Player: manual playlist source rejected'
                      : 'Player: manual Stremio source rejected',
                ),
              )
              .toList();
          expect(
            rejected,
            playlist
                ? ['Player: manual playlist source rejected (LateError)']
                : isEmpty,
          );
          expect(
            find.text('This source is unavailable. Choose another source.'),
            playlist ? findsOneWidget : findsNothing,
          );
          expect(d.errors, isEmpty);
          reads.unblock();
          await d.f.until(t, () => d.f.players.isNotEmpty);
          d.player.deliverReady();
          await d.initialized();
          expect(d.opens, [playlist ? b.directUrl : a.directUrl]);
          expect(d.commits, [b]);
          expect(
            find.byType(mkv.Video),
            playlist ? findsOneWidget : findsNothing,
            reason:
                'The direct early error retains the black transition surface; the playlist catch clears it before initialization renders video',
          );
          d.player.emit('position', const Duration(minutes: 17));
          await d.settle();
          expect(
            await d.f.finish(
              t,
              MovieProgressStorage.isMovieFinished('tt9200016'),
            ),
            playlist,
            reason:
                'The direct error escapes before its finally and leaves validation armed; the playlist catch clears it',
          );
        } finally {
          reads?.unblock();
          await d.close();
          SharedPreferencesStorePlatform.instance = oldStore;
        }
      },
    );
  }
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 ${playlist ? 'playlist' : 'direct'} source selection swallows a rejected pause and still opens and commits its choice',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('pause-failure-a'),
            b = startupSource('pause-failure-b');
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              resolve: (s) async => s.directUrl,
              playlist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: s.directUrl!, title: s.name),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          d.player.failures['pause'] = StateError('fixture pause rejection');
          Object? failure;
          final action = d.observe(
            () => d.f.actions.start(
              'public selection after pause error',
              () async {
                try {
                  final dynamic callback = sheet.onSourceSelected;
                  final dynamic result = callback(1, url);
                  if (result is Future) await result;
                } catch (e) {
                  failure = e;
                }
              },
            ),
          );
          await d.f.finish(t, action.future);
          expect(failure, isNull);
          expect(d.errors, isEmpty);
          expect(d.opens, [a.directUrl, b.directUrl]);
          expect(d.commits, [a, b]);
          expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 player-root keyboard fallback closes an open source sheet after the sheet relinquishes focus',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('root-key-a');
      try {
        await d.begin(
          d.screen(sources: [a], resolve: (s) async => s.directUrl),
        );
        await d.initialized();
        await d.sheet();
        final root = t
            .widgetList<Focus>(find.byType(Focus))
            .singleWhere((w) => w.focusNode?.debugLabel == 'tvPlayerRoot')
            .focusNode!;
        root.requestFocus();
        await d.tick();
        expect(root.hasPrimaryFocus, isTrue);
        expect(find.byType(SourceSheet), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await d.tick();
        expect(find.byType(SourceSheet), findsNothing);
        expect(d.routeReturned, isFalse);
        expect(d.opens, [a.directUrl]);
      } finally {
        await d.close();
      }
    },
  );
}
