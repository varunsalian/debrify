import 'dart:io';

import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_safety_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late _FakeBackupSource source;
  late LocalWebDavSyncSafetyBackupStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'webdav-sync-safety-',
    );
    source = _FakeBackupSource(await _package());
    store = LocalWebDavSyncSafetyBackupStore(
      source: source,
      directoryProvider: () async => temporaryDirectory,
      encoder: (package, passphrase) =>
          PortableProfilePackage.encodeEncryptedBytes(
            package,
            passphrase,
            memory: 8,
            iterations: 1,
          ),
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('publishes only a decrypt-probed recoverable safety backup', () async {
    final backup = await store.createVerified(
      adoptionId: 'adoption-1',
      passphrase: 'circle-secret',
      authorization: _authorization,
    );

    expect(await File(backup.path).exists(), isTrue);
    expect(backup.path, contains('webdav-sync/pre-join-backups'));
    expect(backup.sha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(source.events, <String>['export', 'revalidate']);
    final decoded = await PortableProfilePackage.decryptFile(
      backup.path,
      'circle-secret',
    );
    expect(decoded.mode, 'deviceGraph');
  });

  test('accepts the bounded IPTV and Debrify TV fallback', () async {
    final base = source.package;
    source.package = PortableProfilePackage(
      mode: base.mode,
      createdAt: base.createdAt,
      profiles: base.profiles,
      resources: base.resources,
      sections: base.sections,
      omissions: <String, dynamic>{
        'rebuildableDatabaseCachesOmitted': 'Admin: iptv_catalog.db',
        DebrifyTvBackupOmission.key: const DebrifyTvBackupOmission(
          channels: 2,
          savedHashes: 5,
          profilesAffected: 1,
        ).toJson(),
      },
    );

    final backup = await store.createVerified(
      adoptionId: 'adoption-compact',
      passphrase: 'circle-secret',
      authorization: _authorization,
    );
    final decoded = await PortableProfilePackage.decryptFile(
      backup.path,
      'circle-secret',
    );

    expect(
      decoded.omissions['rebuildableDatabaseCachesOmitted'],
      'Admin: iptv_catalog.db',
    );
    expect(
      DebrifyTvBackupOmission.fromOmissions(decoded.omissions)?.channels,
      2,
    );
  });

  test('rejects an unknown safety-backup omission', () async {
    final base = source.package;
    source.package = PortableProfilePackage(
      mode: base.mode,
      createdAt: base.createdAt,
      profiles: base.profiles,
      resources: base.resources,
      sections: base.sections,
      omissions: const <String, dynamic>{
        'futureDurableDatabaseRowsOmitted': true,
      },
    );

    await expectLater(
      store.createVerified(
        adoptionId: 'adoption-unknown',
        passphrase: 'circle-secret',
        authorization: _authorization,
      ),
      throwsFormatException,
    );
  });

  test(
    'an existing crash-window file is reverified, not overwritten',
    () async {
      final first = await store.createVerified(
        adoptionId: 'adoption-1',
        passphrase: 'circle-secret',
        authorization: _authorization,
      );
      source.events.clear();

      final resumed = await store.createVerified(
        adoptionId: 'adoption-1',
        passphrase: 'circle-secret',
        authorization: _authorization,
      );

      expect(resumed.path, first.path);
      expect(resumed.sha256Hex, first.sha256Hex);
      expect(source.events, isEmpty);
    },
  );

  test('retained backup verification detects later corruption', () async {
    final backup = await store.createVerified(
      adoptionId: 'adoption-1',
      passphrase: 'circle-secret',
      authorization: _authorization,
    );

    expect(await store.verifyRetained(backup), isTrue);
    await File(backup.path).writeAsString('corrupt', flush: true);
    expect(await store.verifyRetained(backup), isFalse);
  });

  test('retention keeps only the three newest verified backups', () async {
    final created = <WebDavSyncSafetyBackup>[];
    for (var index = 0; index < 4; index++) {
      created.add(
        await store.createVerified(
          adoptionId: 'adoption-$index',
          passphrase: 'circle-secret',
          authorization: _authorization,
        ),
      );
      await File(
        created.last.path,
      ).setLastModified(DateTime.utc(2026, 1, index + 1));
    }

    final retained = await Directory(
      '${temporaryDirectory.path}/webdav-sync/pre-join-backups',
    ).list().where((entity) => entity is File).toList();
    expect(retained, hasLength(3));
    expect(await File(created.first.path).exists(), isFalse);
    expect(await File(created.last.path).exists(), isTrue);
  });

  test(
    'an incomplete export is rejected before a recovery point is published',
    () async {
      source.package = PortableProfilePackage(
        mode: 'deviceGraph',
        createdAt: DateTime.utc(2026, 1, 1),
        profiles: const <Map<String, dynamic>>[
          <String, dynamic>{'backupId': 'profile-0', 'name': 'Admin'},
        ],
        resources: const <Map<String, dynamic>>[],
        sections: const <String, dynamic>{},
      );

      await expectLater(
        store.createVerified(
          adoptionId: 'adoption-1',
          passphrase: 'circle-secret',
          authorization: _authorization,
        ),
        throwsFormatException,
      );
      expect(
        await Directory(
          '${temporaryDirectory.path}/webdav-sync/pre-join-backups',
        ).list().toList(),
        isEmpty,
      );
    },
  );
}

const _authorization = ProfileAuthorizationContextForTest();

/// The source owns authorization validation; the store only transports the
/// opaque context, so tests use a non-runtime sentinel implementation.
final class ProfileAuthorizationContextForTest
    implements ProfileAuthorizationContext {
  const ProfileAuthorizationContextForTest();

  @override
  int get authorizationRevision => 0;

  @override
  String get profileId => 'admin';

  @override
  int get sessionEpoch => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeBackupSource implements WebDavSyncSafetyBackupSource {
  _FakeBackupSource(this.package);

  PortableProfilePackage package;
  final List<String> events = <String>[];

  @override
  Future<PortableProfilePackage> export(
    ProfileAuthorizationContext authorization,
  ) async {
    events.add('export');
    return package;
  }

  @override
  Future<void> revalidate(ProfileAuthorizationContext authorization) async {
    events.add('revalidate');
  }
}

Future<PortableProfilePackage> _package() async {
  final preferences = await PortableProfilePackage.buildSection(
    const <String, Object?>{'theme_mode': 'dark'},
  );
  return PortableProfilePackage(
    mode: 'deviceGraph',
    createdAt: DateTime.utc(2026, 1, 1),
    profiles: const <Map<String, dynamic>>[
      <String, dynamic>{
        'backupId': 'profile-0',
        'name': 'Admin',
        'role': 'admin',
        'policy': 'manageProfiles,backupRestore',
        'preferencesSection': 'profile-0-preferences',
      },
    ],
    resources: const <Map<String, dynamic>>[],
    sections: <String, dynamic>{'profile-0-preferences': preferences},
  );
}
