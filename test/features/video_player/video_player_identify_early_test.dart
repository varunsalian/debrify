import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'video_player_source_test.dart' show source;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
// Existing resolved transport; app package files remain unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/display_defaults_reads.dart';
import 'support/identify_title_driver.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final title in <String?>['Early.Content.2025.mkv', '   ', null]) {
    testWidgets(
      'identify early tracks caller title fallback "$title" cannot run before defaults and uses dynamic title after readiness',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        final oldStore = SharedPreferencesStorePlatform.instance;
        DisplayDefaultsReads? reads;
        final screen = VideoPlayerScreen(
          videoUrl: 'https://player.test/early-identity.mp4',
          title: 'Widget.Fallback.2024.mkv',
          contentTitle: title,
          contentImdbId: 'tt1200001',
          contentType: 'movie',
        );
        try {
          reads = await t.runAsync(DisplayDefaultsReads.install);
          t.view.physicalSize = const Size(1280, 800);
          t.view.devicePixelRatio = 1;
          await d.observe(
            () => t.pumpWidget(
              MaterialApp(
                navigatorKey: d.f.navigator,
                theme: ThemeData.dark(),
                home: screen,
              ),
            ),
          );
          await d.f.until(t, () => reads!.entered);
          expect(d.f.creationOrder, ['media-kit-init']);
          expect(d.f.players, isEmpty);
          expect(find.byType(Controls), findsNothing);
          expect(find.byType(TvControls), findsNothing);
          expect(find.byType(PlayerMenuPanel), findsNothing);
          expect(find.text('FIX THE TITLE'), findsNothing);
          expect(d.catalogQueries, isEmpty);
          expect(d.subtitlePaths, isEmpty);
          expect(d.logs.any((v) => v.contains('Opening TracksSheet')), isFalse);
          expect(reads!.writes, isEmpty);
          reads.unblock();
          await d.mountIdentity(screen: screen);
          final menu = await d.menu();
          expect(menu.subtitleIdentityLabel, 'Detected: Widget Fallback');
          final pending = d.start(menu);
          await d.found('Chosen title');
          expect(d.catalogQueries, ['Widget Fallback']);
          await d.dismiss();
          expect(await d.f.finish(t, pending), isNull);
          expect(d.errors, isEmpty);
        } finally {
          reads?.unblock();
          await removeFixture(d);
          SharedPreferencesStorePlatform.instance = oldStore;
        }
      },
    );
  }

  testWidgets(
    'identify early Stremio guide handoff retains partial title after player error and defaults overwrite the dynamic title',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      final reads = CompletionDelivery('loadPlayerDefaults', (v) => v is int);
      final original = source(
        'Original',
        'https://player.test/early-guide.mp4',
      );
      final replacement = source(
        'Replacement',
        'https://player.test/recovery-source.mp4',
      );
      final commits = <String>[];
      final screen = VideoPlayerScreen(
        videoUrl: 'https://player.test/early-guide.mp4',
        title: '',
        stremioSources: [original, replacement],
        stremioCurrentSourceIndex: 0,
        resolveStremioSource: (v) async => v.directUrl,
        onStremioSourceCommitted: (v) async {
          commits.add(v.name);
        },
        contentTitle: 'Wrong content fallback',
        stremioTvChannels: const [
          {'id': 'a', 'name': 'A'},
          {'id': 'b', 'name': 'B'},
        ],
        stremioTvCurrentChannelId: 'a',
        stremioTvChannelSwitchProvider: (_) async => null,
      );
      try {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await reads.run(
          () => d.observe(
            () => t.pumpWidget(
              MaterialApp(
                navigatorKey: d.f.navigator,
                theme: ThemeData.dark(),
                home: screen,
              ),
            ),
          ),
        );
        await d.f.until(t, () => reads.pending.isNotEmpty);
        expect(d.f.players, isEmpty);
        expect(
          reads.values,
          hasLength(1),
          reason: 'One defaults read is intercepted before any player exists',
        );
        await d.f.key(t, LogicalKeyboardKey.keyG);
        expect(find.byType(StremioTvGuideSheet), findsOneWidget);
        final dynamic callback = t
            .widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet))
            .onChannelSwitched;
        Object? failure;
        var completed = false;
        d.observe(() {
          final dynamic action = callback(
            'b',
            'https://player.test/early-b.mp4',
            'Stremio.Title.2025.mkv',
            contentImdbId: 'tt1200009',
            contentType: 'movie',
          );
          (action as Future<void>).then<void>(
            (_) {
              completed = true;
            },
            onError: (Object e) {
              failure = e;
              completed = true;
            },
          );
        });
        await d.f.until(t, () => completed);
        expect(failure, isA<Error>());
        expect(failure.toString(), contains("Field '_player"));
        expect(failure.toString(), contains('has not been initialized'));
        expect(d.f.players, isEmpty);
        reads.release();
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        expect(d.player.readyDelivered, isFalse);
        d.player.deliverReady();
        await d.f.until(t, () => d.player.calls.any((v) => v.$1 == 'open'));
        // The attempted early guide switch started both transition phases.
        // Wait for their real completion; the ordinary fixture's two-second
        // smoke assertion runs before this three-second overlay has ended.
        for (
          var i = 0;
          i < 200 && find.byType(mkv.Video).evaluate().isEmpty;
          i++
        ) {
          await d.f.advance(t, const Duration(milliseconds: 20));
        }
        // The failed early switch leaves the transition latch set as-is.
        expect(find.byType(mkv.Video), findsNothing);
        expect(d.player.calls.where((v) => v.$1 == 'open'), hasLength(1));
        await d.f.key(t, LogicalKeyboardKey.keyS);
        expect(find.byType(SourceSheet), findsOneWidget);
        final sourceSheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = await d.f.finish(t, sourceSheet.resolveSource(replacement));
        expect(url, replacement.directUrl);
        sourceSheet.onSourceSelected(1, url!);
        await d.f.until(t, () => commits.isNotEmpty);
        expect(commits, ['Replacement']);
        for (
          var i = 0;
          i < 200 && find.byType(mkv.Video).evaluate().isEmpty;
          i++
        ) {
          await d.f.advance(t, const Duration(milliseconds: 20));
        }
        expect(find.byType(mkv.Video), findsOneWidget);
        d.publish();
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        final menu = await d.menu();
        expect(menu.subtitleIdentityLabel, 'Detected: Stremio Title');
        final pending = d.start(menu);
        await d.found('Chosen title');
        expect(d.catalogQueries, ['Stremio Title']);
        await d.dismiss();
        expect(await d.f.finish(t, pending), isNull);
        expect(d.errors, isEmpty);
      } finally {
        reads.release();
        await removeFixture(d);
      }
    },
  );
}
