import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/secret_vault.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final directory = Directory('$root/documents');
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final directory = Directory('$root/support');
    await directory.create(recursive: true);
    return directory.path;
  }
}

// Fast KDF params so the suite doesn't spend seconds in Argon2id.
const _fastKdf = BackupKdfParams(memory: 64, iterations: 1, parallelism: 1);

Map<String, dynamic> _samplePayload() => {
  'version': 1,
  'createdAt': '2026-08-13T00:00:00.000Z',
  'realDebridApiKey': 'rdKeyABC',
  'trakt': {'access_token': 'ta', 'refresh_token': 'tr'},
  'iptvPlaylists': [
    {'id': 'p1', 'name': 'Prov', 'url': 'http://x/get.php?username=u'},
  ],
};

void main() {
  group('encryptBackup/decryptBackup', () {
    test('round-trips the payload', () async {
      final envelope = await BackupRestoreService.encryptBackup(
        _samplePayload(),
        'correct horse',
        kdfParams: _fastKdf,
      );
      expect(envelope['version'], 2);
      expect(envelope['encrypted'], isTrue);
      expect(envelope['createdAt'], '2026-08-13T00:00:00.000Z');
      expect(envelope['ciphertext'], isNot(contains('rdKeyABC')));

      final inner = await BackupRestoreService.decryptBackup(
        envelope,
        'correct horse',
      );
      expect(inner, _samplePayload());
      // Inner payload flows through the normal v1 machinery.
      expect(BackupRestoreService.summarize(inner).hasRealDebrid, isTrue);
    });

    test('wrong passphrase throws BackupPassphraseException', () async {
      final envelope = await BackupRestoreService.encryptBackup(
        _samplePayload(),
        'right',
        kdfParams: _fastKdf,
      );
      expect(
        () => BackupRestoreService.decryptBackup(envelope, 'wrong'),
        throwsA(isA<BackupPassphraseException>()),
      );
    });

    test('malformed envelope throws FormatException', () async {
      expect(
        () => BackupRestoreService.decryptBackup({
          'version': 2,
          'encrypted': true,
        }, 'x'),
        throwsFormatException,
      );
      final envelope = await BackupRestoreService.encryptBackup(
        _samplePayload(),
        'x',
        kdfParams: _fastKdf,
      );
      expect(
        () => BackupRestoreService.decryptBackup({
          ...envelope,
          'ciphertext': '@@not-base64@@',
        }, 'x'),
        throwsFormatException,
      );
    });

    test('unknown KDF algo throws FormatException', () async {
      final envelope = await BackupRestoreService.encryptBackup(
        _samplePayload(),
        'x',
        kdfParams: _fastKdf,
      );
      final kdf = Map<String, dynamic>.from(envelope['kdf'] as Map);
      kdf['algo'] = 'scrypt';
      expect(
        () =>
            BackupRestoreService.decryptBackup({...envelope, 'kdf': kdf}, 'x'),
        throwsFormatException,
      );
    });

    test('crafted KDF costs are rejected before any derivation', () async {
      final envelope = await BackupRestoreService.encryptBackup(
        _samplePayload(),
        'x',
        kdfParams: _fastKdf,
      );
      Future<void> expectRejected(Map<String, dynamic> kdfOverride) {
        final kdf = {
          ...Map<String, dynamic>.from(envelope['kdf'] as Map),
          ...kdfOverride,
        };
        return expectLater(
          BackupRestoreService.decryptBackup({...envelope, 'kdf': kdf}, 'x'),
          throwsFormatException,
        );
      }

      // A hostile file must not be able to request gigabytes of Argon2
      // memory (OOM after the user types a passphrase), absurd iteration
      // counts, or non-numeric garbage.
      await expectRejected({'m': 1 << 30});
      await expectRejected({'m': 0});
      await expectRejected({'t': 10000});
      await expectRejected({'p': 64});
      await expectRejected({'m': 'huge'});
      // Both individually in-bounds, but Argon2 needs m ≥ 8·p — must be a
      // FormatException here, not an ArgumentError out of the KDF.
      await expectRejected({'p': 8, 'm': 8});
    });

    test(
      'decrypted inner payload passes the same version gate as parse',
      () async {
        // An envelope wrapping a future or version-less payload must fail the
        // way its plaintext twin would — decryptBackup bypasses parse().
        final futuristic = {..._samplePayload(), 'version': 99};
        final envelope = await BackupRestoreService.encryptBackup(
          futuristic,
          'pw',
          kdfParams: _fastKdf,
        );
        expect(
          () => BackupRestoreService.decryptBackup(envelope, 'pw'),
          throwsFormatException,
        );

        final versionless = Map<String, dynamic>.from(_samplePayload())
          ..remove('version');
        final envelope2 = await BackupRestoreService.encryptBackup(
          versionless,
          'pw',
          kdfParams: _fastKdf,
        );
        expect(
          () => BackupRestoreService.decryptBackup(envelope2, 'pw'),
          throwsFormatException,
        );
      },
    );
  });

  group('parse version gates', () {
    test('v1 plain payload still parses', () {
      final map = BackupRestoreService.parse(
        '{"version":1,"torboxApiKey":"t"}',
      );
      expect(BackupRestoreService.isEncrypted(map), isFalse);
      expect(map['torboxApiKey'], 't');
    });

    test('v2 envelope parses and is flagged encrypted', () async {
      final envelope = await BackupRestoreService.encryptBackup(
        _samplePayload(),
        'p',
        kdfParams: _fastKdf,
      );
      final reparsed = BackupRestoreService.parse(jsonEncode(envelope));
      expect(BackupRestoreService.isEncrypted(reparsed), isTrue);
    });

    test('v3 is still rejected', () {
      expect(
        () => BackupRestoreService.parse('{"version":3}'),
        throwsFormatException,
      );
    });
  });

  group('buildBackup includeCredentials: false', () {
    late Directory storageRoot;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      storageRoot = await Directory.systemTemp.createTemp('backup_strip');
      PathProviderPlatform.instance = _FakePathProvider(storageRoot.path);
      IptvMediaStore.debugResetMigration();
    });

    tearDownAll(() async {
      await DebrifyTvDatabase.instance.closeScope();
      IptvMediaStore.debugResetMigration();
      await storageRoot.delete(recursive: true);
    });

    test('strips account secrets, keeps sharable config', () async {
      SecretVault.debugReset(deviceIdOverride: 'backup-test-device');
      SharedPreferences.setMockInitialValues({
        'real_debrid_api_key': 'rdSecret',
        'trakt_access_token': 'traktAccess',
        'trakt_refresh_token': 'traktRefresh',
        'webdav_servers_v1': jsonEncode([
          {
            'id': 's1',
            'name': 'NAS',
            'baseUrl': 'http://nas.local/dav',
            'username': 'admin',
            'password': 'hunter2',
          },
        ]),
        'indexer_manager_configs_v1': [
          jsonEncode({
            'type': 'jackett',
            'base_url': 'http://jackett.local:9117',
            'api_key': 'indexerSecret',
          }),
        ],
        'iptv_playlists': [
          // Xtream provider: every travel-able field embeds the account.
          jsonEncode({
            'id': 'p1',
            'name': 'Xtream provider',
            'url': 'http://host/get.php?username=u1&password=p1',
            'serverUrl': 'http://host',
            'username': 'u1',
            'password': 'p1',
            'addedAt': DateTime(2026, 1, 1).toIso8601String(),
          }),
          // Plain M3U provider: the URL is the config, kept by design.
          jsonEncode({
            'id': 'p2',
            'name': 'M3U provider',
            'url': 'https://example.com/playlist.m3u',
            'addedAt': DateTime(2026, 1, 1).toIso8601String(),
          }),
        ],
      });

      final stripped = await BackupRestoreService.buildBackup(
        includeCredentials: false,
      );
      final json = jsonEncode(stripped);
      expect(json, isNot(contains('rdSecret')));
      expect(json, isNot(contains('traktAccess')));
      expect(json, isNot(contains('hunter2')));
      expect(json, isNot(contains('indexerSecret')));
      // Nothing that EMBEDS credentials survives either: no Xtream provider
      // fragments, and whole categories whose entries carry keyed URLs
      // (addons, indexers, favorites, custom lists) are omitted.
      expect(json, isNot(contains('get.php')));
      expect(json, isNot(contains('p1')));
      expect(stripped.containsKey('realDebridApiKey'), isFalse);
      expect(stripped.containsKey('trakt'), isFalse);
      expect(stripped.containsKey('indexerManagers'), isFalse);
      expect(stripped.containsKey('addonManifestUrls'), isFalse);
      expect(stripped.containsKey('iptvFavorites'), isFalse);
      expect(stripped.containsKey('iptvLists'), isFalse);
      // Sharable structure survives.
      expect((stripped['webDavServers'] as List), hasLength(1));
      expect(
        (stripped['webDavServers'] as List).first['baseUrl'],
        'http://nas.local/dav',
      );
      final playlists = (stripped['iptvPlaylists'] as List).cast<Map>();
      expect(playlists, hasLength(1));
      expect(playlists.single['name'], 'M3U provider');
      expect(playlists.single['url'], 'https://example.com/playlist.m3u');

      // Control: the same store with credentials on does include them.
      final full = await BackupRestoreService.buildBackup();
      expect(full['realDebridApiKey'], 'rdSecret');
      expect((full['webDavServers'] as List).first['password'], 'hunter2');
      expect(
        (full['indexerManagers'] as List).first['api_key'],
        'indexerSecret',
      );
      expect((full['iptvPlaylists'] as List), hasLength(2));
    });
  });
}
