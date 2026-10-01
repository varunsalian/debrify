import 'dart:convert';

import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A Real-Debrid add whose action retires after the torrent exists must not
// leave that torrent behind (often still waiting for file selection). Each add
// creates a new RD entry, so only that entry is removed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  Future<List<String>> run({required String retireOn}) async {
    var active = true;
    final calls = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path.replaceFirst('/rest/1.0', '');
      calls.add('${request.method} $path');
      if (path == retireOn) active = false;
      return switch (path) {
        '/torrents/addMagnet' => http.Response(jsonEncode({'id': 'T1'}), 201),
        '/torrents/info/T1' => http.Response(
          jsonEncode({
            'files': [
              {'id': 1, 'path': '/movie.mkv', 'bytes': 1},
            ],
          }),
          200,
        ),
        _ => http.Response('', 204),
      };
    });
    addTearDown(client.close);
    await http.runWithClient(() async {
      await expectLater(
        DebridService.addTorrentToDebrid(
          'key',
          'magnet:?xt=fixture',
          canContinue: () => active,
        ),
        throwsA(isA<Exception>()),
      );
    }, () => client);
    return calls;
  }

  for (final retireOn in ['/torrents/addMagnet', '/torrents/info/T1']) {
    test('retirement after $retireOn deletes the added torrent', () async {
      final calls = await run(retireOn: retireOn);
      expect(calls.last, 'DELETE /torrents/delete/T1');
      expect(calls.where((c) => c.startsWith('DELETE')), hasLength(1));
    });
  }

  test('retirement before the add deletes nothing', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      return http.Response('', 204);
    });
    addTearDown(client.close);
    await http.runWithClient(() async {
      await expectLater(
        DebridService.addTorrentToDebrid(
          'key',
          'magnet:?xt=fixture',
          canContinue: () => false,
        ),
        throwsA(isA<Exception>()),
      );
    }, () => client);
    expect(calls, isEmpty);
  });
}
