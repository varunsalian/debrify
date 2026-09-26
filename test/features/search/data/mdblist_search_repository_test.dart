import 'dart:async';

import 'package:debrify/features/search/data/mdblist_search_repository.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileSessionMemory.debugReset();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.debugReset();
  });

  test(
    'credential lookup stays in captured scope across a profile switch',
    () async {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(origin);
      final continueRead = Completer<void>();
      final scopes = <ProfileScope>[];
      var credentialReads = 0;
      var requests = 0;
      final service = MdblistService.forTesting(
        client: MockClient((_) async {
          requests++;
          return http.Response('[]', 200);
        }),
        apiKeyProvider: () async {
          credentialReads++;
          scopes.add(ProfileRuntime.capture());
          await continueRead.future;
          scopes.add(ProfileRuntime.capture());
          return 'test-key';
        },
      );
      final repository = MdblistSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        service: service,
        source: MdblistListSource.forTesting(service),
      );
      final auth = repository.isAuthenticated();
      ProfileRuntime.publish(
        ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 2),
      );
      continueRead.complete();
      await auth;
      expect(scopes, [origin, origin]);
      expect(repository.isCurrent, isFalse);
      expect(await repository.isAuthenticated(), isFalse);
      expect(
        (await repository.search('movies')).kind,
        MdblistResultKind.unauthenticated,
      );
      expect(credentialReads, 1);
      expect(requests, 0);
    },
  );

  test(
    'session lifecycle invalidation rejects calls even in legacy mode',
    () async {
      ProfileRuntime.initializeLegacy();
      var reads = 0;
      final service = MdblistService.forTesting(
        client: MockClient(
          (_) async => throw StateError('Unexpected network request'),
        ),
        apiKeyProvider: () async {
          reads++;
          return 'test-key';
        },
      );
      final repository = MdblistSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        service: service,
        source: MdblistListSource.forTesting(service),
      );
      expect(await repository.isAuthenticated(), isTrue);
      ProfileSessionMemory.clearAll();
      expect(repository.isCurrent, isFalse);
      expect(await repository.isAuthenticated(), isFalse);
      await repository.search('movies');
      expect(reads, 1);
    },
  );
}
