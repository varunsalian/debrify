import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'episode cache separates configurations with the same addon ID',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var reads = 0;
      server.listen((request) async {
        reads++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'meta': {
              'videos': [
                {
                  'season': 1,
                  'episode': 1,
                  'title': request.uri.pathSegments.first,
                },
              ],
            },
          }),
        );
        await request.response.close();
      });
      StremioAddon addon(String config) {
        final base = 'http://127.0.0.1:${server.port}/$config';
        return StremioAddon(
          id: 'same.manifest.id',
          name: 'Configured addon',
          baseUrl: base,
          manifestUrl: '$base/manifest.json',
          resources: const ['meta'],
          types: const ['series'],
        );
      }

      try {
        final first = await StremioService.instance.fetchSeriesMeta(
          addon('first'),
          'tt1234567',
        );
        final second = await StremioService.instance.fetchSeriesMeta(
          addon('second'),
          'tt1234567',
        );
        final cached = await StremioService.instance.fetchSeriesMeta(
          addon('first'),
          'tt1234567',
        );
        expect(first!.single['title'], 'first');
        expect(second!.single['title'], 'second');
        expect(cached!.single['title'], 'first');
        expect(reads, 2);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
