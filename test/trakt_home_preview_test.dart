import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
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
      'trakt_access_token': 'test-token',
    });
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'strict directory distinguishes empty, failed, and later pages',
    () async {
      var status = 200;
      var empty = true;
      final pages = <String?>[];
      await http.runWithClient(
        () async {
          expect(
            await TraktService.instance.fetchCustomLists(strict: true),
            isEmpty,
          );
          status = 503;
          await expectLater(
            TraktService.instance.fetchCustomLists(strict: true),
            throwsStateError,
          );
          status = 200;
          empty = false;
          pages.clear();
          expect(
            await TraktService.instance.fetchCustomLists(strict: true),
            hasLength(2),
          );
          expect(pages, ['1', '2']);
        },
        () => MockClient((request) async {
          pages.add(request.url.queryParameters['page']);
          return http.Response(
            empty ? '[]' : '[{"ids":{"trakt":7}}]',
            status,
            headers: {'x-pagination-page-count': empty ? '0' : '2'},
          );
        }),
      );
    },
  );

  for (final liked in [false, true]) {
    test(
      'Trakt preview stops at first page; full list still pages (liked=$liked)',
      () async {
        final requests = <http.Request>[];
        await http.runWithClient(
          () async {
            Future<List<dynamic>?> fetch(bool preview) => liked
                ? TraktService.instance.fetchLikedListItemsOrderedOrNull({
                    'ids': {'trakt': 42},
                  }, preview: preview)
                : TraktService.instance.fetchCustomListItemsOrderedOrNull(
                    'mine',
                    preview: preview,
                  );
            expect(await fetch(true), hasLength(1));
            expect(requests, hasLength(1));
            expect(requests.single.url.queryParameters['limit'], '100');
            expect(await fetch(false), hasLength(3));
            expect(requests, hasLength(4));
          },
          () => MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode([
                {
                  'type': 'movie',
                  'movie': {'title': 'Title'},
                },
              ]),
              200,
              headers: {'x-pagination-page-count': '3'},
            );
          }),
        );
      },
    );
  }
}
