import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      'simkl_access_token': 'test-token',
    });
  });
  tearDown(ProfileRuntime.debugReset);

  testWidgets(
    'global movie reset is available without trackers and uses movie confirmation',
    (tester) async {
      expect(
        buildTraktAddOnlyMenuOptions(
          isMovie: true,
          isTraktAuthenticated: false,
        ).any((o) => o.action == TraktItemMenuAction.clearWatchProgress),
        isTrue,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => handleTraktMenuAction(
                  context,
                  const StremioMeta(id: 'tt001', type: 'movie', name: 'Movie'),
                  TraktItemMenuAction.clearWatchProgress,
                ),
                child: const Text('Reset'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Clear watched history and resume progress for Movie',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('permanently deletes its saved rating'),
        findsOneWidget,
      );
      expect(find.textContaining('every episode'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'reset is offered without Trakt and cancel performs no requests',
    (tester) async {
      expect(
        buildTraktAddOnlyMenuOptions(
          isSeries: true,
          isTraktAuthenticated: false,
        ).any((o) => o.action == TraktItemMenuAction.clearWatchProgress),
        isTrue,
      );
      var calls = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => handleTraktMenuAction(
                      context,
                      const StremioMeta(
                        id: 'tt001',
                        type: 'series',
                        name: 'Show',
                      ),
                      TraktItemMenuAction.clearWatchProgress,
                    ),
                    child: const Text('Reset'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Reset'));
          await tester.pumpAndSettle();
          expect(find.text('Clear watch progress?'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Clear watch progress?'), findsNothing);
        },
        () => MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }),
      );
      expect(calls, 0);
    },
  );

  test(
    'Simkl reset uses nested episodes including specials, never whole-library removal',
    () async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          expect(
            await SimklService.instance.clearSeriesHistory('tt001'),
            isTrue,
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/sync/watched') {
            return http.Response(
              jsonEncode([
                {
                  'seasons': [
                    {
                      'number': 0,
                      'episodes': [
                        {'number': 1, 'watched': true},
                      ],
                    },
                    {
                      'number': 1,
                      'episodes': [
                        {'number': 1, 'watched': true},
                        {'number': 2, 'watched': false},
                      ],
                    },
                  ],
                },
              ]),
              200,
            );
          }
          expect(request.url.path, '/sync/history/remove');
          expect(jsonDecode(request.body), {
            'shows': [
              {
                'ids': {'imdb': 'tt001'},
                'seasons': [
                  {
                    'number': 0,
                    'episodes': [
                      {'number': 1},
                    ],
                  },
                  {
                    'number': 1,
                    'episodes': [
                      {'number': 1},
                    ],
                  },
                ],
              },
            ],
          });
          return http.Response('{}', 200);
        }),
      );
      expect(requests, hasLength(2));
    },
  );

  for (final status in [200, 503]) {
    test('Simkl empty history versus failed read ($status)', () async {
      var calls = 0;
      await http.runWithClient(
        () async {
          expect(
            await SimklService.instance.clearSeriesHistory('tt001'),
            status == 200,
          );
        },
        () => MockClient((request) async {
          calls++;
          return http.Response('[]', status);
        }),
      );
      expect(calls, 1);
    });
  }
}
