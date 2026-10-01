import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/home/application/home_playback_providers.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response position() => http.Response(
  jsonEncode([
    {
      'id': 971,
      'progress': 42.0,
      'paused_at': '2026-09-28T00:00:00Z',
      'movie': {
        'title': 'Fixture',
        'year': 2026,
        'ids': {'imdb': 'tt97123', 'trakt': 971},
      },
    },
  ]),
  200,
  headers: {'x-pagination-page-count': '1'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'tracker-resume-fixture');
    await TraktStorage.setTraktAccessToken('fixture-token');
    TraktService.instance.resetProfileScope();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });
  HomeCatalogSession session() => HomeCatalogSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  );

  test(
    'production reader memo belongs to its view and ends with provider disposal',
    () async {
      final container = ProviderContainer.test();
      final first = container.listen(
        homeTrackerResumeRepositoryProvider(session()),
        (_, _) {},
      );
      final second = container.listen(
        homeTrackerResumeRepositoryProvider(session()),
        (_, _) {},
      );
      final retained = first.read();
      var requests = 0;
      final client = MockClient((request) async {
        expect(request.url.path, '/sync/playback/movies');
        requests++;
        return position();
      });
      await http.runWithClient(() async {
        expect(await retained.traktMovie('tt97123', isCurrent: () => true), 42);
        expect(await retained.traktMovie('tt97123', isCurrent: () => true), 42);
        expect(requests, 1);
        expect(
          await second.read().traktMovie('tt97123', isCurrent: () => true),
          42,
        );
        expect(requests, 2);
        first.close();
        await container.pump();
        expect(
          await retained.traktMovie('tt97123', isCurrent: () => true),
          isNull,
        );
        expect(requests, 2);
      }, () => client);
    },
  );

  for (final retire in ['profile', 'provider']) {
    test(
      'late actual Trakt response is rejected after $retire retirement',
      () async {
        final container = ProviderContainer.test();
        final subscription = container.listen(
          homeTrackerResumeRepositoryProvider(session()),
          (_, _) {},
        );
        final repository = subscription.read();
        final entered = Completer<void>(),
            response = Completer<http.Response>();
        var requests = 0;
        final client = MockClient((_) {
          requests++;
          entered.complete();
          return response.future;
        });
        await http.runWithClient(() async {
          final operation = repository.traktMovie(
            'tt97123',
            isCurrent: () => true,
          );
          await entered.future;
          if (retire == 'profile') {
            ProfileSessionMemory.clearAll();
          } else {
            subscription.close();
            await container.pump();
          }
          response.complete(position());
          expect(await operation, isNull);
          expect(
            await repository.traktMovie('tt97123', isCurrent: () => true),
            isNull,
          );
          expect(requests, 1);
        }, () => client);
      },
    );
  }
}
