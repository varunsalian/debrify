import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets('built-in guide deep link, Play and Sources (TV=$television)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      SecretVault.debugReset(deviceIdOverride: 'native-flow');
      addTearDown(SecretVault.debugReset);
      AdvancedSearchSelection? played;
      AdvancedSearchSelection? browsed;
      EpisodesPanelView? panel;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: AppThemeScope(
                theme: AppThemes.legacy,
                child: Scaffold(
                  body: EpisodesPanel(
                    show: const StremioMeta(
                      id: 'tt0118360',
                      imdbId: 'tt0118360',
                      type: 'series',
                      name: 'Johnny Bravo',
                    ),
                    addon: NativeSeriesMetadataService.addon,
                    initialSeason: 2,
                    initialEpisode: 3,
                    isTelevision: television,
                    onQuickPlay: (selection) => played = selection,
                    onItemSelected: (selection) => browsed = selection,
                    contentBuilder: (_, view) {
                      panel = view;
                      return const SizedBox();
                    },
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 30 && panel?.landing == null; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(panel?.unavailable, isFalse);
          expect(panel?.selectedSeasonNumber, 2);
          expect(panel?.landing?.number, 3);
          panel!.play(panel!.landing!);
          expect(played?.imdbId, 'tt0118360');
          expect(played?.season, 2);
          expect(played?.episode, 3);
          expect(played?.hasStremioEpisodeIdentity, isFalse);

          panel!.options(panel!.landing!);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Sources'));
          await tester.pumpAndSettle();
          expect(browsed?.imdbId, played?.imdbId);
          expect(browsed?.season, played?.season);
          expect(browsed?.episode, played?.episode);
          expect(browsed?.hasStremioEpisodeIdentity, isFalse);

          final meta = PlaybackMeta.catalog(
            imdbId: played!.imdbId,
            contentType: 'series',
            title: played!.title,
            season: played!.season,
            episode: played!.episode,
            addonId: NativeSeriesMetadataService.addon.id,
          );
          expect(
            TorrentPlaybackService.seriesFetcherFor(
              meta: meta,
            )?.resolveAdjacentEpisode,
            isNotNull,
          );
          // Exercise the callback shared by Flutter and the Android TV bridge,
          // not merely its presence: a forward-only resolver breaks Previous.
          final resolve = TorrentPlaybackService.seriesFetcherFor(
            meta: meta,
          )!.resolveAdjacentEpisode!;
          expect(await tester.runAsync(() => resolve(2, 3, -1)), (
            season: 1,
            episode: 1,
          ));
          expect(await tester.runAsync(() => resolve(1, 1, -1)), isNull);
          expect(await tester.runAsync(() => resolve(1, 1, 1)), (
            season: 2,
            episode: 3,
          ));
          expect(
            TorrentPlaybackService.seriesFetcherFor(
              meta: const PlaybackMeta.catalog(
                imdbId: 'tt0118360',
                contentType: 'series',
                season: 2,
                episode: 3,
                addonId: 'ordinary-catalog',
              ),
            )?.resolveAdjacentEpisode,
            isNotNull,
          );
          final args = TorrentPlaybackService.playerArgsForTesting(meta);
          expect(args.contentImdbId, 'tt0118360');
          expect(args.contentSeason, 2);
          expect(args.contentEpisode, 3);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path == '/shows/tt0118360/seasons') {
            return http.Response(
              jsonEncode([
                {
                  'number': 1,
                  'episodes': [
                    {'season': 1, 'number': 1, 'title': 'Pilot', 'rating': 8.0},
                  ],
                },
                {
                  'number': 2,
                  'episodes': [
                    {
                      'season': 2,
                      'number': 3,
                      'title': 'Resume episode',
                      'rating': 8.0,
                    },
                  ],
                },
              ]),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
    });
  }
}
