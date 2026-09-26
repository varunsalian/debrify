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
  for (final retireAfter in [
    'add',
    'task',
    'details',
    'folder',
    'link',
    'none',
    'single',
    'failed',
    'processing',
  ]) {
    testWidgets('PikPak binding preparation $retireAfter', (tester) async {
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
      Map<String, dynamic>? createBody;
      String? linkedFileId;
      final client = MockClient((request) async {
        final isSingle = retireAfter == 'single';
        final action = request.method == 'POST'
            ? 'add'
            : request.url.path.contains('/tasks/')
            ? 'task'
            : request.url.queryParameters.containsKey('parent_id')
            ? 'folder'
            : request.url.path.endsWith('/root') && !paths.contains('details')
            ? 'details'
            : 'link';
        paths.add(action);
        if (action == retireAfter) active = false;
        final Map<String, dynamic> data;
        switch (action) {
          case 'add':
            createBody = jsonDecode(request.body) as Map<String, dynamic>;
            data = {
              'task': {'file_id': 'root', 'id': 'task'},
            };
          case 'task':
            data = {
              'phase': retireAfter == 'failed'
                  ? 'PHASE_TYPE_ERROR'
                  : 'PHASE_TYPE_COMPLETE',
            };
          case 'details':
            data = {
              'id': 'root',
              'name': 'Fixture.mkv',
              'size': '1024',
              'phase': 'PHASE_TYPE_COMPLETE',
              'kind': isSingle || retireAfter == 'processing'
                  ? 'drive#file'
                  : 'drive#folder',
              'mime_type': isSingle ? 'video/x-matroska' : '',
            };
          case 'folder':
            data = {
              'files': [
                {
                  'id': 'episode2',
                  'name': 'Fixture.S01E02.mkv',
                  'mime_type': 'video/x-matroska',
                },
                {
                  'id': 'episode1',
                  'name': 'Fixture.S01E01.mkv',
                  'mime_type': 'video/x-matroska',
                },
              ],
            };
          case 'link':
            linkedFileId = request.url.pathSegments.last;
            data = {'web_content_link': 'https://example.test/fixture.mkv'};
          default:
            throw StateError('Unexpected fixture request: $action');
        }
        return http.Response(jsonEncode(data), 200);
      });
      addTearDown(client.close);
      addTearDown(SecretVault.debugReset);
      await tester.runAsync(() async {
        SecretVault.debugReset(deviceIdOverride: 'acquisition-fixture');
        SharedPreferences.setMockInitialValues({
          'pikpak_enabled': true,
          'pikpak_email': 'fixture@example.test',
          'pikpak_access_token': 'fixture-access',
          'pikpak_refresh_token': 'fixture-refresh',
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
      final succeeds = retireAfter == 'none' || retireAfter == 'single';
      final expected = [
        'add',
        'task',
        'details',
        if (retireAfter != 'single') 'folder',
        'link',
      ];
      expect(
        paths,
        succeeds
            ? expected
            : retireAfter == 'failed'
            ? ['add', 'task']
            : retireAfter == 'processing'
            ? ['add', 'task', 'details']
            : expected.take(expected.indexOf(retireAfter) + 1).toList(),
      );
      expect(createBody?['parent_id'], '');
      expect(createBody?['upload_type'], 'UPLOAD_TYPE_URL');
      expect(
        createBody?['url']['url'],
        contains(
          'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
      if (paths.contains('link')) {
        expect(linkedFileId, retireAfter == 'single' ? 'root' : 'episode1');
      }
      if (retireAfter == 'failed') {
        expect(find.text('Download failed on PikPak.'), findsOneWidget);
      } else if (retireAfter == 'processing') {
        expect(
          find.text(
            "Added to PikPak — it's still downloading. Pin it again once ready.",
          ),
          findsOneWidget,
        );
      }
      expect(result, succeeds);
      expect(pins, hasLength(succeeds ? 1 : 0));
      if (pins.isNotEmpty) {
        expect(pins.single.debridService, 'pikpak');
        expect(pins.single.addonCatalogId, 'catalog');
        expect(pins.single.addonCatalogKey, 'configuration');
      }
      expect(Navigator.of(context).canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
