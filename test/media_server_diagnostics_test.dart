import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mpv error categories never return raw messages', () {
    expect(
      mediaServerPlayerErrorCategory('HTTP error 401 private-token'),
      'http_auth',
    );
    expect(
      mediaServerPlayerErrorCategory('decoder failed private-token'),
      'decoder',
    );
    expect(
      mediaServerPlayerErrorCategory('https://private-host/private-token'),
      'player_error',
    );
  });

  test(
    'playback request logs status without server or credential content',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'media-log-test-',
      );
      final log = DiagnosticLog.instance;
      await log.debugReset();
      await log.initialize(directoryOverride: directory);
      final client = MediaServerClient(
        client: MockClient((_) async => http.Response('PRIVATE_RESPONSE', 403)),
      );
      try {
        await expectLater(
          client.mediaSources(
            const MediaServerAccount(
              kind: MediaServerKind.emby,
              baseUrl: 'https://private-host.example/private-path/',
              userId: 'private-user',
              token: 'private-token',
              serverId: 'private-server',
              deviceId: 'private-device',
            ),
            'private-item',
          ),
          throwsA(isA<MediaServerException>()),
        );
        final exported = utf8.decode((await log.exportLastWindow()).bytes);
        final events = exported
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map);
        final event = events.singleWhere((e) => e['source'] == 'media_server');
        expect(event['fields']['status'], 403);
        expect(event['fields']['kind'], 'emby');
        expect(event['fields']['operation'], 'playback_info');
        expect(event['fields']['outcome'], 'failed');
        expect(exported, isNot(contains('private-')));
        expect(exported, isNot(contains('PRIVATE_RESPONSE')));
      } finally {
        client.close();
        await log.debugReset();
        await directory.delete(recursive: true);
      }
    },
  );
}
