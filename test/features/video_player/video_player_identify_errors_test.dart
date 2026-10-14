import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'support/identify_inventory_store.dart';
import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final stage in ['catalog', 'subtitles']) {
    testWidgets(
      'identify stable inventory failure at $stage shows its error and preserves original commit point',
      (t) async {
        final d = IdentifyTitleDriver(t, committed: false);
        await d.setupIdentity();
        IdentifyInventoryStore? storage;
        try {
          await d.mountIdentity(
            screen: stage == 'subtitles'
                ? const VideoPlayerScreen(
                    videoUrl: 'https://player.test/cache-a.mp4',
                    title: 'Launch Title',
                    contentImdbId: 'tt1200001',
                    contentType: 'movie',
                  )
                : identifyScreen,
          );
          await d.f.actions.settle(t);
          final pending = d.start(await d.menu());
          await d.found('Chosen title');
          StremioService.instance.invalidateCache();
          storage = await t.runAsync(IdentifyInventoryStore.install);
          if (stage == 'catalog') {
            await d.submit('another');
            await d.found('Search failed. Try again.');
            final error = t.widget<Text>(
              find.text('Search failed. Try again.'),
            );
            expect(error.style!.fontSize, 14);
            expect(error.style!.color, Colors.white.withValues(alpha: .65));
            expect(d.catalogQueries, ['Launch Title']);
            expect(find.text('No IMDb-backed results found'), findsNothing);
            expect(find.text('Chosen title'), findsNothing);
            await d.submit(' ');
            expect(find.text('Search failed. Try again.'), findsNothing);
            expect(find.text('No IMDb-backed results found'), findsNothing);
            final cleared = find
                .ancestor(
                  of: find.text('FIX THE TITLE'),
                  matching: find.byType(SafeArea),
                )
                .first;
            final clearedList = find.descendant(
              of: cleared,
              matching: find.byType(ListView),
            );
            expect(clearedList, findsOneWidget);
            expect(
              find.descendant(of: clearedList, matching: find.byType(InkWell)),
              findsNothing,
            );
            storage!.restore();
            await d.submit('retry');
            await d.found('Chosen title');
            expect(d.catalogQueries, ['Launch Title', 'retry']);
            await d.dismiss();
            expect(await d.f.finish(t, pending), isNull);
            expect(d.panel.subtitleIdentityLabel, 'Detected: Launch Title');
          } else {
            await t.tap(find.text('Chosen title'));
            expect(await d.f.finish(t, pending), isNull);
            expect(find.text('Subtitle search failed'), findsOneWidget);
            expect(
              d.logs,
              contains(
                'VideoPlayer: Search subtitle fetch failed: Bad state: Synthetic stable addon inventory storage failure',
              ),
            );
            storage!.restore();
            // The action committed manual identity before the failing discovery.
            d.panel.onClose();
            await d.f.advance(t, const Duration(milliseconds: 350));
            final reopened = await d.menu();
            expect(
              reopened.subtitleIdentityLabel,
              'Subtitles for Chosen title',
            );
            expect(reopened.cachedAddonSlots, isNull);
            expect(
              d.subtitlePaths,
              contains('/subtitles/movie/tt1200001.json'),
            );
            StremioService.instance.invalidateCache();
            final retried = await d.f.finish(
              t,
              StremioSubtitleService.instance.fetchSubtitleSlots(
                type: 'movie',
                imdbId: 'tt1200002',
              ),
            );
            // The actual menu cache-publication callback receives the real
            // service result; no private State fields are injected.
            reopened.onAddonSlotsFetched!(retried);
            await d.f.advance(t);
            reopened.onClose();
            await d.f.advance(t);
            final warmed = await d.menu();
            expect(warmed.cachedAddonSlots, isNotNull);
            expect(
              warmed.cachedAddonSlots!.single.subtitles.single.id,
              'identify',
            );
          }
          expect(storage.reads, greaterThanOrEqualTo(1));
        } finally {
          storage?.restore();
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'identify nonempty retry clears the stable inventory error before publishing success',
    (t) async {
      final d = IdentifyTitleDriver(t, committed: false);
      await d.setupIdentity();
      IdentifyInventoryStore? storage;
      final retry = Completer<http.Response>();
      try {
        await d.mountIdentity();
        final pending = d.start(await d.menu());
        await d.found('Chosen title');
        StremioService.instance.invalidateCache();
        storage = await t.runAsync(IdentifyInventoryStore.install);
        await d.submit('failed');
        await d.found('Search failed. Try again.');
        storage!.restore();
        StremioService.instance.invalidateCache();
        d.catalog = (_) => retry.future;
        await d.submit('retry');
        await d.f.until(t, () => d.catalogQueries.contains('retry'));
        expect(retry.isCompleted, isFalse);
        expect(find.text('Search failed. Try again.'), findsNothing);
        expect(find.text('Chosen title'), findsNothing);
        retry.complete(
          d.response([IdentifyTitleDriver.identityMeta('Successful retry')]),
        );
        await d.found('Successful retry');
        expect(find.text('Search failed. Try again.'), findsNothing);
        expect(d.catalogQueries, ['Launch Title', 'retry']);
        await d.dismiss();
        expect(await d.f.finish(t, pending), isNull);
        expect(d.errors, isEmpty);
      } finally {
        storage?.restore();
        if (!retry.isCompleted) retry.complete(d.response([]));
        await removeFixture(d);
      }
    },
  );
}
