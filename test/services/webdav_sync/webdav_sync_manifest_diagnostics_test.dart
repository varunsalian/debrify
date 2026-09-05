import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('known codec failures have distinct fixed categories', () {
    expect(
      WebDavSyncManifestFailure(
        WebDavSyncManifestReadStage.decode,
        const FormatException('WebDAV sync document authentication failed'),
      ).category,
      'authentication',
    );
    expect(
      WebDavSyncManifestFailure(
        WebDavSyncManifestReadStage.decode,
        const FormatException('WebDAV sync document identity mismatch'),
      ).category,
      'identity',
    );
  });
  test(
    'manifest diagnostics retain only stage and fixed failure category',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'manifest-diagnostics-',
      );
      await DiagnosticLog.instance.initialize(directoryOverride: directory);
      try {
        for (final stage in WebDavSyncManifestReadStage.values) {
          recordWebDavSyncDiagnostic(
            'Ignored an invalid WebDAV sync peer manifest',
            WebDavSyncManifestFailure(
              stage,
              const FormatException(
                'https://private.test/token=secret',
                'private payload',
              ),
            ),
          );
        }
        recordWebDavSyncDiagnostic(
          'Ignored an invalid WebDAV sync peer manifest',
          WebDavSyncManifestFailure(
            WebDavSyncManifestReadStage.decode,
            Exception('private exception text'),
          ),
        );
        final export = await DiagnosticLog.instance.exportLastWindow();
        final text = utf8.decode(export.bytes);
        final notes = const LineSplitter()
            .convert(text)
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .where((entry) => entry['event'] == 'engine_note')
            .toList();
        expect(notes, hasLength(6));
        for (var i = 0; i < 5; i++) {
          expect(notes[i]['fields'], {
            'message': 'ignored_an_invalid_webdav_sync_peer_manifest',
            'stage': WebDavSyncManifestReadStage.values[i].name,
            'category': 'format',
          });
          expect(notes[i]['level'], 'warning');
        }
        expect(notes.last['fields']['category'], 'exception');
        expect(text, isNot(contains('private')));
        expect(text, isNot(contains('secret')));
      } finally {
        await DiagnosticLog.instance.debugReset();
        await directory.delete(recursive: true);
      }
    },
  );
}
