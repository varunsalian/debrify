import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final retireAfter in ['createtorrent', 'mylist', 'requestdl', 'none']) {
    testWidgets('TorBox acquisition stops after $retireAfter retirement', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      final paths = <String>[];
      final pins = <SeriesSource>[];
      var active = true;
      var finished = false;
      bool? result;
      Object? error;
      String? createBody;
      final client = MockClient((request) async {
        final action = request.url.pathSegments.last;
        paths.add(action);
        if (action == retireAfter) active = false;
        final Object data;
        switch (action) {
          case 'createtorrent':
            createBody = request.body;
            data = {'torrent_id': 7};
          case 'mylist':
            data = {
              'id': 7,
              'name': 'Fixture',
              'download_state': 'cached',
              'created_at': '2025-01-01T00:00:00Z',
              'updated_at': '2025-01-01T00:00:00Z',
              'files': [
                {
                  'id': 9,
                  'name': 'Fixture.mkv',
                  'short_name': 'Fixture.mkv',
                  'size': 1024,
                },
              ],
            };
          case 'requestdl':
            data = 'https://example.test/fixture.mkv';
          default:
            throw StateError('Unexpected fixture request: $action');
        }
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      });
      addTearDown(client.close);
      addTearDown(SecretVault.debugReset);
      await tester.runAsync(() async {
        SecretVault.debugReset(deviceIdOverride: 'acquisition-fixture');
        SharedPreferences.setMockInitialValues({
          'torbox_api_key': 'fixture-token',
        });
        unawaited(
          http
              .runWithClient(
                () => const SourceBindingBridge().pin(
                  context,
                  Torrent(
                    rowid: 0,
                    infohash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                    name: 'Fixture',
                    sizeBytes: 1024,
                    createdUnix: 0,
                    seeders: 0,
                    leechers: 0,
                    completed: 0,
                    scrapedDate: 0,
                  ),
                  imdbId: 'tt-fixture',
                  isMovie: true,
                  addonCatalogId: 'catalog',
                  addonCatalogKey: 'configuration',
                  canContinue: () => active,
                  saveBinding: (source) async {
                    pins.add(source);
                    return true;
                  },
                ),
                () => client,
              )
              .then(
                (value) {
                  result = value;
                  finished = true;
                },
                onError: (Object caught) {
                  error = caught;
                  finished = true;
                },
              ),
        );
      });
      for (var i = 0; i < 100 && !finished; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(finished, isTrue);
      expect(error, isNull);
      await tester.pumpAndSettle();
      final expected = ['createtorrent', 'mylist', 'requestdl'];
      expect(
        paths,
        retireAfter == 'none'
            ? expected
            : expected.take(expected.indexOf(retireAfter) + 1).toList(),
      );
      expect(createBody, contains('name="add_only_if_cached"'));
      expect(
        createBody,
        contains(
          'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
      expect(result, retireAfter == 'none');
      expect(pins, hasLength(retireAfter == 'none' ? 1 : 0));
      if (pins.isNotEmpty) {
        expect(pins.single.debridService, 'torbox');
        expect(pins.single.addonCatalogId, 'catalog');
        expect(pins.single.addonCatalogKey, 'configuration');
      }
      expect(Navigator.of(context).canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
