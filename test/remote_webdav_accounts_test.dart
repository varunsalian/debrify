import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/remote_control/remote_webdav_accounts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sync = WebDavConfig(
    id: 'sync',
    name: 'Sync',
    baseUrl: 'https://host/dav/',
    username: 'sync-user',
    password: 'sync-secret',
  );
  const other = WebDavConfig(
    id: 'other',
    name: 'Other',
    baseUrl: 'https://host/other',
    username: 'other-user',
    password: 'other-secret',
  );

  for (final url in [
    'https://host/dav',
    ' HTTPS://HOST/DAV/// ',
    'https://host/dav/',
  ]) {
    test('sync login wins receiver-equivalent endpoint: $url', () {
      final media = WebDavConfig(
        id: 'media',
        name: 'Media',
        baseUrl: url,
        username: 'media-user',
        password: 'media-secret',
      );
      final original = [media, other];
      final outgoing = preferRemoteWebDavSyncAccount(original, sync);
      expect(original, [media, other]);
      expect(outgoing, [other, sync]);
      // Simulate the receiver's first-entry-wins deduplication after encoding.
      final received = <String, WebDavConfig>{};
      for (final entry in outgoing) {
        final decoded = WebDavConfig.fromTransferJson(entry.toTransferJson());
        received.putIfAbsent(
          remoteWebDavEndpointKey(decoded.baseUrl),
          () => decoded,
        );
      }
      final selected = received[remoteWebDavEndpointKey(sync.baseUrl)]!;
      expect(selected.username, 'sync-user');
      expect(selected.password, 'sync-secret');
      expect(received.length, 2);
    });
  }
}
