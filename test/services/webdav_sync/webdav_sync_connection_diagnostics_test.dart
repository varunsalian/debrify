import 'dart:async';
import 'dart:io';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'connection diagnostics classify failures without exposing private data',
    () {
      final causes = <Object, String>{
        const SocketException('Failed host lookup: private.invalid'): 'dns',
        const SocketException(
          'secret endpoint',
          osError: OSError('private', 101),
        ): 'socket',
        const HandshakeException('private certificate'): 'tls',
        TimeoutException('private URL'): 'timeout',
        http.ClientException('WebDAV sync HTTP client generation is stale'):
            'stale_client',
        http.ClientException('HTTP request failed. Client is already closed.'):
            'closed_client',
        http.ClientException('https://user:password@private.invalid'):
            'http_client',
        StateError('private'): 'unknown',
      };
      for (final entry in causes.entries) {
        final fields = webDavConnectionFailureFields(
          WebDavException(
            kind: WebDavErrorKind.network,
            message: 'WebDAV response was interrupted',
            uri: Uri.parse('https://user:password@private.invalid'),
            cause: entry.key,
          ),
        );
        expect(
          (fields['connectionFailure'] as DiagnosticLabel).value,
          entry.value,
        );
        expect(
          (fields['connectionStage'] as DiagnosticLabel).value,
          'response_body',
        );
        final safe = fields.map(
          (k, v) => MapEntry(k, v is DiagnosticLabel ? v.value : v),
        );
        expect(safe.toString(), isNot(contains('private')));
        expect(safe.toString(), isNot(contains('password')));
        if (entry.value == 'socket') expect(fields['socketErrorCode'], 101);
      }
      final fields = webDavConnectionFailureFields(
        const WebDavException(
          kind: WebDavErrorKind.network,
          message: 'private arbitrary message',
        ),
      );
      expect((fields['connectionStage'] as DiagnosticLabel).value, 'unknown');
    },
  );
}
