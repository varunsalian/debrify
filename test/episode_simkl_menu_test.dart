import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final native in [false, true]) {
    for (final isTelevision in [false, true]) {
      testWidgets(
        'Simkl ticks, menu and Sources (TV=$isTelevision, native=$native)',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          SecretVault.debugReset(deviceIdOverride: 'simkl-menu-test');
          SimklService.instance.resetProfileScope();
          addTearDown(SecretVault.debugReset);
          addTearDown(SimklService.instance.resetProfileScope);
          final id = native ? 'tmdb:237243' : 'tt1234567';
          final ids = native ? {'tmdb': 237243} : {'imdb': id};
          final show = StremioMeta(
            id: id,
            imdbId: native ? null : id,
            type: 'series',
            name: 'Test Show',
          );
          final addon = StremioAddon(
            id: 'simkl-menu-$native-$isTelevision',
            name: 'Test',
            baseUrl: 'https://fixture.invalid',
            manifestUrl: 'https://fixture.invalid/manifest.json',
            resources: const ['meta'],
            types: const ['series'],
          );
          AdvancedSearchSelection? selected;
          await http.runWithClient(
            () async {
              await tester.runAsync(() async {
                await StorageService.setSimklAccessToken('test-only-token');
                await StorageService.setTrackingScrobbleTargets({
                  TrackingSource.simkl,
                });
                expect(
                  await StremioService.instance.fetchSeriesMeta(addon, id),
                  hasLength(1),
                );
              });
              await tester.pumpWidget(
                MaterialApp(
                  home: AppThemeScope(
                    theme: AppThemes.legacy,
                    child: Scaffold(
                      body: EpisodesPanel(
                        show: show,
                        addon: addon,
                        isTelevision: isTelevision,
                        onItemSelected: (value) => selected = value,
                        contentBuilder: (context, view) => view.episodes.isEmpty
                            ? const SizedBox()
                            : Column(
                                children: [
                                  Text(
                                    'progress: ${view.progressOf(view.episodes.single)}',
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        view.options(view.episodes.single),
                                    child: const Text('Episode options'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              );
              for (var i = 0; i < 20; i++) {
                await tester.runAsync(
                  () => SimklService.instance.isAuthenticated(),
                );
                await tester.pump(const Duration(milliseconds: 50));
              }
              expect(find.text('progress: 100.0'), findsOneWidget);
              await tester.tap(find.text('Episode options'));
              await tester.pumpAndSettle();
              expect(find.text('Rate on Simkl'), findsNothing);
              expect(find.text('Mark as Unwatched'), findsOneWidget);
              expect(
                find.textContaining('Simkl and this device'),
                findsOneWidget,
              );
              expect(find.text('Play'), findsOneWidget);
              await tester.tap(find.text('Sources'));
              await tester.pumpAndSettle();
              expect(selected?.imdbId, id);
              expect(selected?.season, 1);
              expect(selected?.episode, 1);
              expect(selected?.hasStremioEpisodeIdentity, isFalse);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            },
            () => MockClient((request) async {
              if (request.url.host.contains('tvmaze')) {
                return http.Response('{}', 404);
              }
              Object body;
              if (request.url.host == 'fixture.invalid') {
                body = {
                  'meta': {
                    'videos': [
                      {
                        'id': '$id:1:1',
                        'season': 1,
                        'episode': 1,
                        'title': 'Pilot',
                      },
                    ],
                  },
                };
              } else if (request.url.path == '/sync/watched') {
                expect(jsonDecode(request.body), [
                  {...ids, 'type': 'show'},
                ]);
                body = [
                  {
                    'result': true,
                    'seasons': [
                      {
                        'number': 1,
                        'episodes': [
                          {'number': 1, 'watched': true},
                        ],
                      },
                    ],
                  },
                ];
              } else if (request.url.path == '/sync/all-items/all/all') {
                body = {
                  'shows': [
                    {
                      'show': {'title': 'Test Show', 'ids': ids},
                      'status': 'watching',
                    },
                  ],
                };
              } else {
                body = [];
              }
              return http.Response(jsonEncode(body), 200);
            }),
          );
        },
      );
    }
  }
}
