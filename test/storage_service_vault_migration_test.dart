import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies the lazy plaintext→ciphertext migration for real credential keys:
/// an upgrade with existing plaintext credentials keeps every getter's return
/// value while re-writing the stored bytes into the `enc1:` envelope.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SecretVault.debugReset(deviceIdOverride: 'migration-test-device');
  });

  test('standalone key: plaintext read once, then sealed at rest', () async {
    SharedPreferences.setMockInitialValues(
        {'real_debrid_api_key': 'legacyRdKey40charsAAAAAAAAAAAAAAAAAAAAAA'});
    expect(await StorageService.getApiKey(),
        'legacyRdKey40charsAAAAAAAAAAAAAAAAAAAAAA');
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('real_debrid_api_key')!;
    expect(stored, startsWith(SecretVault.prefix));
    // Still readable after the rewrite.
    expect(await StorageService.getApiKey(),
        'legacyRdKey40charsAAAAAAAAAAAAAAAAAAAAAA');
  });

  test('iptv playlist: secret fields sealed, content untouched', () async {
    final legacy = jsonEncode({
      'id': 'p1',
      'name': 'Provider',
      'url': 'http://host/get.php?username=u1&password=p1',
      'serverUrl': 'http://host',
      'username': 'u1',
      'password': 'p1',
      'content': '#EXTM3U\n#EXTINF:-1,Ch\nhttp://host/live/u1/p1/1.ts\n',
      'addedAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    SharedPreferences.setMockInitialValues({
      'iptv_playlists': [legacy],
    });

    final playlists = await StorageService.getIptvPlaylists();
    expect(playlists, hasLength(1));
    expect(playlists.first.username, 'u1');
    expect(playlists.first.password, 'p1');
    expect(playlists.first.url, 'http://host/get.php?username=u1&password=p1');

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getStringList('iptv_playlists')!.single)
        as Map<String, dynamic>;
    expect(stored['username'], startsWith(SecretVault.prefix));
    expect(stored['password'], startsWith(SecretVault.prefix));
    expect(stored['url'], startsWith(SecretVault.prefix));
    // Bulk M3U body deliberately stays plaintext (perf; see storage_service).
    expect(stored['content'], startsWith('#EXTM3U'));

    // Round-trips through the sealed form.
    final again = await StorageService.getIptvPlaylists();
    expect(again.single.password, 'p1');
  });

  test('webdav servers blob: sealed whole, values preserved', () async {
    final legacy = jsonEncode([
      {
        'id': 's1',
        'name': 'NAS',
        'baseUrl': 'http://nas.local/dav',
        'username': 'admin',
        'password': 'hunter2',
      }
    ]);
    SharedPreferences.setMockInitialValues({'webdav_servers_v1': legacy});

    final servers = await StorageService.getWebDavServers();
    expect(servers, hasLength(1));
    expect(servers.first.password, 'hunter2');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_servers_v1'),
        startsWith(SecretVault.prefix));
    expect((await StorageService.getWebDavServers()).single.password,
        'hunter2');
  });

  test('device-ID change turns credentials into clean signed-out', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.saveApiKey('boundKey');
    expect(await StorageService.getApiKey(), 'boundKey');
    SecretVault.debugReset(deviceIdOverride: 'a-different-device');
    expect(await StorageService.getApiKey(), isNull);
    // A fresh save under the new device works.
    await StorageService.saveApiKey('newKey');
    expect(await StorageService.getApiKey(), 'newKey');
  });
}
