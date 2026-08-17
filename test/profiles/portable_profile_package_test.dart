import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/legacy_backup_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'avatar_fixtures.dart';

void main() {
  Future<PortableProfilePackage> package({
    String mode = 'singleProfile',
    Map<String, Object?> preferences = const <String, Object?>{
      'app_theme': 'spotlight',
    },
    Map<String, Object?>? files,
    List<Map<String, dynamic>> resources = const <Map<String, dynamic>>[],
  }) async {
    final sections = <String, dynamic>{
      'preferences': await PortableProfilePackage.buildSection(preferences),
      if (files != null)
        'files': await PortableProfilePackage.buildSection(files),
    };
    return PortableProfilePackage(
      mode: mode,
      createdAt: DateTime.utc(2026, 8, 13),
      profiles: <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          if (mode != 'sanitizedSettings') 'name': 'Private profile',
          'preferencesSection': 'preferences',
          if (files != null) 'filesSection': 'files',
        },
      ],
      resources: resources,
      sections: sections,
    );
  }

  test('sensitive v3 package round-trips only through encryption', () async {
    final source = await package(
      preferences: const <String, Object?>{'account_label': 'private'},
    );
    final plain = await PortableProfilePackage.withIntegrity(source);

    await expectLater(
      PortableProfilePackage.decodeMap(plain),
      throwsA(isA<FormatException>()),
    );

    final encrypted = await PortableProfilePackage.encrypt(
      source,
      'correct horse',
      memory: 8,
      iterations: 1,
    );
    final restored = await PortableProfilePackage.decrypt(
      encrypted,
      'correct horse',
    );
    expect(restored.mode, 'singleProfile');
    expect(
      (restored.sections['preferences'] as Map)['values'],
      containsPair('account_label', 'private'),
    );
  });

  test(
    'avatar attachment does not change the legacy files section grammar',
    () async {
      final source = await package(
        files: <String, Object?>{
          'engines/example.json': <String, Object?>{
            'encoding': 'base64',
            'bytes': 2,
            'sha256': base64UrlEncode(
              (await Sha256().hash(utf8.encode('{}'))).bytes,
            ).replaceAll('=', ''),
            'data': base64Encode(utf8.encode('{}')),
          },
        },
      );
      final avatarDigest = base64UrlEncode(
        (await Sha256().hash(tinyGif)).bytes,
      ).replaceAll('=', '');
      source.profiles.single.addAll(<String, Object?>{
        'avatarKey': 'file:avatars/current.gif#4A90D9',
        // Older v3 builds ignore unknown profile fields, but would reject an
        // `avatars/` key inside filesSection and abort the entire restore.
        'avatarFile': <String, Object?>{
          'path': 'avatars/current.gif',
          'encoding': 'base64',
          'bytes': tinyGif.length,
          'sha256': avatarDigest,
          'data': base64Encode(tinyGif),
        },
      });

      final encrypted = await PortableProfilePackage.encrypt(
        source,
        'correct horse',
        memory: 8,
        iterations: 1,
      );
      final restored = await PortableProfilePackage.decrypt(
        encrypted,
        'correct horse',
      );
      final files = (restored.sections['files'] as Map)['values'] as Map;
      expect(files.keys, <Object?>['engines/example.json']);
      expect(restored.profiles.single['avatarFile'], isA<Map>());
    },
  );

  test('off-main file pipeline probes, unlocks, and round-trips', () async {
    // The UI paths go through probeFile/decryptFile/decodeFile so the KDF and
    // whole-envelope JSON never run on the main isolate; this pins that the
    // worker-isolate pipeline matches the raw methods end to end.
    final directory = await Directory.systemTemp.createTemp('portable-pkg-');
    addTearDown(() => directory.delete(recursive: true));

    final source = await package(
      preferences: const <String, Object?>{'account_label': 'private'},
    );
    final encryptedBytes = await PortableProfilePackage.encodeEncryptedBytes(
      source,
      'correct horse',
      memory: 8,
      iterations: 1,
    );
    // Encrypted envelopes are compact-encoded — no pretty-print inflation.
    expect(utf8.decode(encryptedBytes), isNot(contains('\n')));
    final encryptedFile = File('${directory.path}/backup.json');
    await encryptedFile.writeAsBytes(encryptedBytes);

    final probe = await PortableProfilePackage.probeFile(encryptedFile.path);
    expect(probe.isProfilePackage, isTrue);
    expect(probe.encrypted, isTrue);
    expect(probe.legacySource, isNull);

    final restored = await PortableProfilePackage.decryptFile(
      encryptedFile.path,
      'correct horse',
    );
    expect(restored.profiles.single['name'], 'Private profile');
    expect(
      restored.sections['preferences']['values']['account_label'],
      'private',
    );
    await expectLater(
      PortableProfilePackage.decryptFile(encryptedFile.path, 'wrong horses'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Wrong passphrase or tampered backup',
        ),
      ),
    );

    final sanitized = await package(
      mode: 'sanitizedSettings',
      preferences: const <String, Object?>{'app_theme': 'spotlight'},
    );
    final plainBytes = await PortableProfilePackage.encodePlainBytes(sanitized);
    final plainFile = File('${directory.path}/sanitized.json');
    await plainFile.writeAsBytes(plainBytes);
    final plainProbe = await PortableProfilePackage.probeFile(plainFile.path);
    expect(plainProbe.isProfilePackage, isTrue);
    expect(plainProbe.encrypted, isFalse);
    final decoded = await PortableProfilePackage.decodeFile(plainFile.path);
    expect(decoded.mode, 'sanitizedSettings');

    final legacyFile = File('${directory.path}/legacy.json');
    await legacyFile.writeAsString('{"settings": {"theme": "dark"}}');
    final legacyProbe = await PortableProfilePackage.probeFile(legacyFile.path);
    expect(legacyProbe.isProfilePackage, isFalse);
    expect(legacyProbe.legacySource, contains('dark'));
  });

  test('wrong passphrase and unsafe KDF parameters fail closed', () async {
    final encrypted = await PortableProfilePackage.encrypt(
      await package(),
      'correct horse',
      memory: 8,
      iterations: 1,
    );
    await expectLater(
      PortableProfilePackage.decrypt(encrypted, 'wrong password'),
      throwsA(isA<FormatException>()),
    );

    final hostile = Map<String, dynamic>.from(encrypted);
    hostile['kdf'] = <String, dynamic>{
      ...Map<String, dynamic>.from(encrypted['kdf'] as Map),
      'memory': PortableProfilePackage.maxExpandedBytes,
    };
    await expectLater(
      PortableProfilePackage.decrypt(hostile, 'correct horse'),
      throwsA(isA<FormatException>()),
    );
  });

  test('ciphertext tampering is rejected', () async {
    final encrypted = await PortableProfilePackage.encrypt(
      await package(),
      'correct horse',
      memory: 8,
      iterations: 1,
    );
    final aead = Map<String, dynamic>.from(encrypted['aead'] as Map);
    final bytes = base64Decode(aead['ciphertext'] as String);
    bytes[0] ^= 1;
    aead['ciphertext'] = base64Encode(bytes);
    final tampered = <String, dynamic>{...encrypted, 'aead': aead};

    await expectLater(
      PortableProfilePackage.decrypt(tampered, 'correct horse'),
      throwsA(isA<FormatException>()),
    );
  });

  test('streaming backup reader stops at its byte budget', () async {
    final source = Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode('{"first":"ok"}'),
      List<int>.filled(64, 65),
    ]);

    await expectLater(
      PortableProfilePackage.readBoundedUtf8(source, maxBytes: 20),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'sanitized plain backup enforces its reviewed preference schema',
    () async {
      final safe = await package(
        mode: 'sanitizedSettings',
        preferences: const <String, Object?>{
          'app_theme': 'spotlight',
          'ui_sounds': true,
          'tv_ui_scale_percent': 90,
        },
      );
      final decoded = await PortableProfilePackage.decodeMap(
        await PortableProfilePackage.withIntegrity(safe),
      );
      expect(decoded.mode, 'sanitizedSettings');
      expect(
        (decoded.sections['preferences'] as Map)['values'],
        <String, Object?>{
          'app_theme': 'spotlight',
          'ui_sounds': true,
          'tv_ui_scale_percent': 90,
        },
      );

      const rejected = <String, Object?>{
        'series_source_tt1234567':
            '{"name":"Private.Release","infoHash":"secret"}',
        'continue_watching_v1': '[{"title":"Private title"}]',
        'playback_state_v1':
            '{"url":"http://host/movie/username/password/1.mkv"}',
        'future_innocent_name': 'credential-that-a-denylist-would-miss',
        'app_theme': 'https://example.invalid/token',
        'ui_sounds': 'true',
      };
      for (final entry in rejected.entries) {
        final private = await package(
          mode: 'sanitizedSettings',
          preferences: <String, Object?>{entry.key: entry.value},
        );
        await expectLater(
          PortableProfilePackage.decodeMap(
            await PortableProfilePackage.withIntegrity(private),
          ),
          throwsA(isA<FormatException>()),
          reason: '${entry.key} must not enter an unencrypted package',
        );
      }

      final mislabeledEncrypted = await PortableProfilePackage.encrypt(
        await package(
          mode: 'sanitizedSettings',
          preferences: const <String, Object?>{
            'playback_state_v1':
                '{"url":"http://host/movie/username/password/1.mkv"}',
          },
        ),
        'correct horse',
        memory: 8,
        iterations: 1,
      );
      await expectLater(
        PortableProfilePackage.decrypt(mislabeledEncrypted, 'correct horse'),
        throwsA(isA<FormatException>()),
        reason: 'sanitized mode must enforce its schema under any envelope',
      );

      final accountInventory = await package(
        mode: 'sanitizedSettings',
        resources: const <Map<String, dynamic>>[
          <String, dynamic>{
            'backupId': 'resource-0',
            'type': 'iptvXtream',
            'label': 'iptvXtream',
            'owned': true,
            'publicConfig': <String, dynamic>{'schemaVersion': 1},
            'permissions': 63,
          },
        ],
      );
      await expectLater(
        PortableProfilePackage.decodeMap(
          await PortableProfilePackage.withIntegrity(accountInventory),
        ),
        throwsA(isA<FormatException>()),
        reason: 'sanitized mode must not disclose connected account types',
      );
    },
  );

  test(
    'portable attachment traversal is rejected after authentication',
    () async {
      final attachment = <String, Object?>{
        'encoding': 'base64',
        'bytes': 2,
        'sha256': 'irrelevant-until-path-is-accepted',
        'data': base64Encode(const <int>[123, 125]),
      };
      final source = await package(
        files: <String, Object?>{'../outside.yaml': attachment},
      );
      final encrypted = await PortableProfilePackage.encrypt(
        source,
        'correct horse',
        memory: 8,
        iterations: 1,
      );

      await expectLater(
        PortableProfilePackage.decrypt(encrypted, 'correct horse'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('missing per-section digest is rejected', () async {
    final source = await package(mode: 'sanitizedSettings');
    final section = Map<String, dynamic>.from(
      source.sections['preferences'] as Map,
    )..remove('sha256');
    final malformed = PortableProfilePackage(
      mode: source.mode,
      createdAt: source.createdAt,
      profiles: source.profiles,
      resources: source.resources,
      sections: <String, dynamic>{'preferences': section},
    );

    await expectLater(
      PortableProfilePackage.decodeMap(
        await PortableProfilePackage.withIntegrity(malformed),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('legacy credentials and addon URLs become staged resources', () {
    final adapted = LegacyBackupAdapter.adapt(<String, dynamic>{
      'version': 1,
      'realDebridApiKey': 'secret-key',
      'addonManifestUrls': <String>[
        'https://example.invalid/secret/manifest.json',
      ],
      'searchEngineIds': <String>['engine-a'],
      'iptvFavorites': <Map<String, dynamic>>[
        <String, dynamic>{'url': 'https://provider.invalid/live/favorite-a'},
      ],
    });

    expect(
      adapted.resources.map((resource) => resource['type']),
      containsAll(<String>['realDebrid', 'stremioAddon']),
    );
    final followUp = Map<String, dynamic>.from(
      adapted.sections['legacyFollowUp'] as Map,
    );
    expect(followUp, isNot(contains('realDebridApiKey')));
    expect(followUp, isNot(contains('addonManifestUrls')));
    expect(followUp['searchEngineIds'], <String>['engine-a']);
    expect(followUp['iptvFavorites'], isNotEmpty);
    expect((adapted.sections['legacyInventory'] as Map)['resourceRecords'], 2);
  });

  test('0.8.1 v1 contract fixture adapts without dropping inventory', () {
    final payload = Map<String, dynamic>.from(
      jsonDecode(File('test/fixtures/backup_v1_0.8.1.json').readAsStringSync())
          as Map,
    );
    final adapted = LegacyBackupAdapter.adapt(payload);
    final inventory = adapted.sections['legacyInventory'] as Map;

    expect(adapted.resources, hasLength(4));
    expect(inventory['resourceRecords'], 4);
    expect(inventory['searchEngineRecords'], 1);
    expect(inventory['iptvFavoriteRecords'], 1);
    expect(inventory['iptvListRecords'], 1);
    expect(inventory['iptvListChannelRecords'], 1);
  });

  test('legacy adapter rejects malformed records instead of dropping them', () {
    final malformed = <Map<String, dynamic>>[
      <String, dynamic>{
        'version': 1,
        'pikpak': <String, dynamic>{'email': ''},
      },
      <String, dynamic>{
        'version': 1,
        'webDavServers': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Missing URL'},
        ],
      },
      <String, dynamic>{
        'version': 1,
        'iptvPlaylists': <Map<String, dynamic>>[
          <String, dynamic>{'url': 'https://provider.invalid/list.m3u'},
        ],
      },
      <String, dynamic>{
        'version': 1,
        'addonManifestUrls': <Object?>[null],
      },
      <String, dynamic>{
        'version': 1,
        'iptvLists': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Sports'},
        ],
      },
    ];

    for (final payload in malformed) {
      expect(
        () => LegacyBackupAdapter.adapt(payload),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('legacy adapter ignores future fields and normalizes empty labels', () {
    final adapted = LegacyBackupAdapter.adapt(<String, dynamic>{
      'version': 1,
      'futureOptionalFeature': <String, dynamic>{'enabled': true},
      'iptvPlaylists': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'xtream-empty-password',
          'name': '',
          'addedAt': '2026-08-13T00:00:00.000Z',
          'serverUrl': 'https://provider.invalid',
          'url': '',
          'username': 'subscriber',
          'password': '',
        },
      ],
      'iptvLists': <Map<String, dynamic>>[
        <String, dynamic>{'name': '', 'channels': <dynamic>[]},
      ],
    });

    expect(adapted.resources.single['label'], 'IPTV');
    final followUp = adapted.sections['legacyFollowUp'] as Map;
    expect((followUp['iptvLists'] as List).single['name'], 'Imported list 1');
  });
}
