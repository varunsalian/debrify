import 'dart:convert';

import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/mdblist/mdblist_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MdblistService _service(Future<http.Response> Function(http.Request) handler) =>
    MdblistService.forTesting(
      client: MockClient(handler),
      apiKeyProvider: () async => 'key',
      featureEnabled: () => true,
    );

Map<String, dynamic> _activities(String serverTime, {String? watchedAt}) => {
  'server_time': serverTime,
  'watched_at': watchedAt ?? serverTime,
  'journal_at': serverTime,
};

void main() {
  test(
    'first poll requires a full sync and advances only after commit',
    () async {
      Map<String, dynamic>? stored;
      final coordinator = MdblistSyncCoordinator(
        service: _service(
          (_) async => http.Response(
            jsonEncode(_activities('2026-08-22T00:00:00Z')),
            200,
          ),
        ),
        readCheckpoint: () async => stored,
        writeCheckpoint: (value) async => stored = value,
        readAuthority: () async => null,
      );

      final poll = await coordinator.poll();
      expect(poll.fullSyncRequired, isTrue);
      expect(stored, isNull);
      expect(await coordinator.commit(poll), isTrue);
      expect(stored?['server_time'], '2026-08-22T00:00:00.000Z');
    },
  );

  test('replays every journal cursor and commits the server clock', () async {
    final seen = <Uri>[];
    Map<String, dynamic>? stored = {
      'resource_id': 'legacy-profile-scope',
      'authorization_revision': 0,
      'server_time': '2026-08-21T00:00:00.000Z',
      'activities': _activities('2026-08-21T00:00:00Z'),
    };
    final coordinator = MdblistSyncCoordinator(
      service: _service((request) async {
        seen.add(request.url);
        if (request.url.path == '/sync/last_activities') {
          return http.Response(
            jsonEncode(_activities('2026-08-22T00:00:00Z')),
            200,
          );
        }
        final cursor = request.url.queryParameters['cursor'];
        return http.Response(
          jsonEncode({
            'journal': [
              {'category': 'watched', 'status': 'added', 'page': cursor ?? '1'},
            ],
            'pagination': {'next_cursor': cursor == null ? 'next' : null},
          }),
          200,
        );
      }),
      readCheckpoint: () async => stored,
      writeCheckpoint: (value) async => stored = value,
      readAuthority: () async => null,
    );

    final poll = await coordinator.poll();
    expect(poll.fullSyncRequired, isFalse);
    expect(poll.journal, hasLength(2));
    expect(seen[1].queryParameters['since'], '2026-08-21T00:00:00.000Z');
    expect(seen[2].queryParameters['cursor'], 'next');
    expect(seen[2].queryParameters, isNot(contains('since')));
    expect(await coordinator.commit(poll), isTrue);
    expect(stored?['server_time'], '2026-08-22T00:00:00.000Z');
  });

  test('expired server journal requests a fresh full snapshot', () async {
    final coordinator = MdblistSyncCoordinator(
      service: _service(
        (_) async =>
            http.Response(jsonEncode(_activities('2026-08-22T00:00:00Z')), 200),
      ),
      readCheckpoint: () async => {
        'resource_id': 'legacy-profile-scope',
        'authorization_revision': 0,
        'server_time': '2026-07-01T00:00:00.000Z',
        'activities': const <String, dynamic>{},
      },
      writeCheckpoint: (_) async {},
      readAuthority: () async => null,
    );
    expect((await coordinator.poll()).fullSyncRequired, isTrue);
  });

  test('synchronization invalidates before advancing the checkpoint', () async {
    Map<String, dynamic>? stored;
    final order = <String>[];
    final coordinator = MdblistSyncCoordinator(
      service: _service(
        (_) async =>
            http.Response(jsonEncode(_activities('2026-08-22T00:00:00Z')), 200),
      ),
      readCheckpoint: () async => stored,
      writeCheckpoint: (value) async {
        order.add('commit');
        stored = value;
      },
      readAuthority: () async => null,
      invalidate: (buckets, all) {
        expect(all, isTrue);
        order.add('invalidate');
      },
    );

    expect(await coordinator.synchronizeInvalidations(), isTrue);
    expect(order, ['invalidate', 'commit']);
    expect(stored?['server_time'], '2026-08-22T00:00:00.000Z');
  });
}
