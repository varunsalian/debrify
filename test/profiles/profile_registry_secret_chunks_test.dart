import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Android's OS SQLite aborts any read whose ROW exceeds the ~2MB
/// CursorWindow, and a file-imported IPTV playlist seals its whole M3U body
/// into `sealed_secret_payload` — so one big playlist made every resource of
/// the profile unreadable and stranded migrating installs in legacy mode.
/// These pin the fix: oversized envelopes live in chunk tables, the column
/// carries a marker, and every path — create, rotate, staging, publication,
/// and the v4→v5 repair of rows written before chunking existed — round-trips
/// the envelope byte-for-byte.
void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;

  // Comfortably beyond the inline ceiling, deliberately NOT a multiple of the
  // chunk size so the tail chunk is partial.
  final bigEnvelope = 'E${'x' * (1300 * 1024)}Z';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('chunk-test-');
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    );
    adminId = admin.id;
  });

  tearDown(() async {
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> insert(String id, String envelope) => registry.insertResource(
    resource: ConnectionResource(
      id: id,
      type: ConnectionResourceType.iptvM3u,
      label: 'Playlist $id',
      ownerProfileId: adminId,
      publicConfig: const <String, dynamic>{'schemaVersion': 1},
      authorizationRevision: 1,
      enabled: true,
    ),
    sealedSecretPayload: envelope,
    secretPayloadVersion: 1,
    ownerPermissions: ResourcePermission.values.fold<int>(
      0,
      (mask, permission) => mask | permission.bit,
    ),
  );

  // singleInstance: false, or the factory hands back the registry's OWN
  // handle and closing "our" connection closes the registry out from under
  // the test.
  Future<Database> raw() => databaseFactory.openDatabase(
    p.join(temporaryDirectory.path, 'profiles.db'),
    options: OpenDatabaseOptions(singleInstance: false),
  );

  String withoutV7Columns(String statement) => statement
      .replaceAll('      secret_pending INTEGER NOT NULL DEFAULT 0,\n', '')
      .replaceAll('      updated_at_ms INTEGER NOT NULL DEFAULT 0,\n', '');

  test('an oversized envelope spills to chunks and round-trips', () async {
    await insert('res-big', bigEnvelope);

    final db = await raw();
    final column =
        (await db.rawQuery(
              'SELECT sealed_secret_payload AS v FROM connection_resources '
              "WHERE id = 'res-big'",
            )).single['v']!
            as String;
    expect(column, startsWith('@chunks:v1:'));
    expect(column.length, lessThan(64), reason: 'the row must stay tiny');
    final chunkCount =
        (await db.rawQuery(
              "SELECT COUNT(*) AS n FROM resource_secret_chunks "
              "WHERE resource_id = 'res-big'",
            )).single['n']!
            as int;
    expect(chunkCount, greaterThan(1));
    await db.close();

    final record = await registry.getSealedResourceSecret('res-big');
    expect(record!.envelope, bigEnvelope);
  });

  test('a small envelope stays inline with no chunk rows', () async {
    await insert('res-small', 'tiny-envelope');

    final db = await raw();
    final column =
        (await db.rawQuery(
              'SELECT sealed_secret_payload AS v FROM connection_resources '
              "WHERE id = 'res-small'",
            )).single['v']!
            as String;
    expect(column, 'tiny-envelope');
    final chunkCount =
        (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM resource_secret_chunks',
            )).single['n']!
            as int;
    expect(chunkCount, 0);
    await db.close();
  });

  test('rotation replaces chunks in both directions', () async {
    await insert('res-rotate', bigEnvelope);

    // big → small: the chunks must not linger.
    await registry.updateResourceSecret(
      resourceId: 'res-rotate',
      sealedSecretPayload: 'rotated-small',
      secretPayloadVersion: 2,
    );
    var db = await raw();
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM resource_secret_chunks',
      )).single['n'],
      0,
    );
    await db.close();
    expect(
      (await registry.getSealedResourceSecret('res-rotate'))!.envelope,
      'rotated-small',
    );

    // small → big: spills again and serves the new body.
    await registry.updateResourceSecret(
      resourceId: 'res-rotate',
      sealedSecretPayload: bigEnvelope,
      secretPayloadVersion: 3,
    );
    expect(
      (await registry.getSealedResourceSecret('res-rotate'))!.envelope,
      bigEnvelope,
    );
  });

  test('deleting the resource row cascades the chunks away', () async {
    await insert('res-cascade', bigEnvelope);

    // The guarantee under test is the SCHEMA's: every existing delete of a
    // resource row — profile deletion, collection replacement, revocation —
    // must shed the chunk rows through the foreign key with no code
    // remembering to. Exercise the cascade directly.
    final db = await raw();
    await db.execute('PRAGMA foreign_keys = ON');
    await db.delete(
      'profile_resource_grants',
      where: "resource_id = 'res-cascade'",
    );
    await db.delete('connection_resources', where: "id = 'res-cascade'");
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM resource_secret_chunks',
      )).single['n'],
      0,
    );
    await db.close();
  });

  test(
    'listing survives and excludes nothing while a big envelope exists',
    () async {
      await insert('res-list-big', bigEnvelope);
      await insert('res-list-small', 'tiny');

      final listed = await registry.listGrantedResources(adminId);
      expect(listed.map((r) => r.id).toSet(), {
        'res-list-big',
        'res-list-small',
      });
    },
  );

  test(
    'v4 database upgrades: tables appear and oversized rows are repaired',
    () async {
      // Build a v4-shaped database by hand: no chunk tables, one oversized
      // INLINE envelope — exactly what a 0.8.2 install that file-imported a
      // big playlist is sitting on.
      await registry.close();
      final dbPath = p.join(temporaryDirectory.path, 'v4.db');
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      for (final current in ProfileRegistry.debugSchemaStatements) {
        // v4 predates the chunk tables — build everything except them.
        if (current.contains('_secret_chunks')) continue;
        await db.execute(withoutV7Columns(current));
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('user_profiles', <String, Object?>{
        'id': 'admin-v4',
        'name': 'Admin',
        'role': 'admin',
        'policy_json': '{}',
        'policy_schema_version': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      await db.insert('connection_resources', <String, Object?>{
        'id': 'res-v4-big',
        'type': ConnectionResourceType.iptvM3u.name,
        'label': 'Old playlist',
        'owner_profile_id': 'admin-v4',
        'public_config_json': '{"schemaVersion":1}',
        'sealed_secret_payload': bigEnvelope,
        'secret_payload_version': 1,
        'authorization_revision': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      // The staging table can hold oversized inline envelopes too (a restore
      // captured on v4); the repair must cover it as well.
      await db.insert('profile_restore_resources', <String, Object?>{
        'restore_id': 'restore-v4',
        'resource_id': 'res-v4-staged',
        'backup_id': 'backup-v4',
        'type': ConnectionResourceType.iptvM3u.name,
        'label': 'Staged playlist',
        'owner_profile_id': 'admin-v4',
        'public_config_json': '{"schemaVersion":1}',
        'sealed_secret_payload': bigEnvelope,
        'secret_payload_version': 1,
        'permissions': 1,
      });
      await db.execute('PRAGMA user_version = 4');
      await db.close();

      registry = await ProfileRegistry.open(path: dbPath);
      final reopened = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final column =
          (await reopened.rawQuery(
                'SELECT sealed_secret_payload AS v FROM connection_resources '
                "WHERE id = 'res-v4-big'",
              )).single['v']!
              as String;
      expect(
        column,
        startsWith('@chunks:v1:'),
        reason: 'the upgrade must have moved the body out of the row',
      );
      final stagedColumn =
          (await reopened.rawQuery(
                'SELECT sealed_secret_payload AS v FROM profile_restore_resources '
                "WHERE restore_id = 'restore-v4'",
              )).single['v']!
              as String;
      expect(stagedColumn, startsWith('@chunks:v1:'));
      final stagedChunks =
          (await reopened.rawQuery(
                'SELECT COUNT(*) AS n FROM restore_secret_chunks '
                "WHERE restore_id = 'restore-v4' AND backup_id = 'backup-v4'",
              )).single['n']!
              as int;
      expect(stagedChunks, greaterThan(1));
      await reopened.close();

      expect(
        (await registry.getSealedResourceSecret('res-v4-big'))!.envelope,
        bigEnvelope,
      );
    },
  );

  test('v5 database upgrades restore-resource settings columns', () async {
    await registry.close();
    final dbPath = p.join(temporaryDirectory.path, 'v5.db');
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final current in ProfileRegistry.debugSchemaStatements) {
      final statement = withoutV7Columns(current);
      final v5Statement =
          statement.contains('CREATE TABLE profile_restore_resources')
          ? statement.replaceAll(
              '      profile_enabled INTEGER,\n'
                  '      profile_settings_json TEXT,\n'
                  '      resource_enabled INTEGER NOT NULL DEFAULT 1,\n',
              '',
            )
          : statement;
      await db.execute(v5Statement);
    }
    await db.execute('PRAGMA user_version = 5');
    await db.close();

    registry = await ProfileRegistry.open(path: dbPath);
    final reopened = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final columns = (await reopened.rawQuery(
      'PRAGMA table_info(profile_restore_resources)',
    )).map((row) => row['name']).toSet();
    expect(
      columns,
      containsAll(<String>{
        'profile_enabled',
        'profile_settings_json',
        'resource_enabled',
      }),
    );
    expect(
      (await reopened.rawQuery('PRAGMA user_version')).single['user_version'],
      ProfileRegistry.schemaVersion,
    );
    await reopened.close();
  });

  test(
    'a rejected rotation leaves the old chunks and old secret intact',
    () async {
      await insert('res-guarded', bigEnvelope);

      await expectLater(
        () => registry.updateResourceSecret(
          resourceId: 'res-guarded',
          sealedSecretPayload: 'would-be-new',
          secretPayloadVersion: 2,
          actingProfileId: adminId,
          actingAuthorizationRevision: 999999,
          expectedResourceAuthorizationRevision: 999999,
        ),
        throwsA(anything),
      );

      expect(
        (await registry.getSealedResourceSecret('res-guarded'))!.envelope,
        bigEnvelope,
        reason: 'a refused write must not have touched the chunk rows',
      );
    },
  );

  test(
    'a zero-count marker is refused, never served as an empty secret',
    () async {
      await insert('res-corrupt', 'legit-envelope');
      final db = await raw();
      await db.rawUpdate(
        "UPDATE connection_resources SET sealed_secret_payload = '@chunks:v1:0' "
        "WHERE id = 'res-corrupt'",
      );
      await db.close();

      await expectLater(
        () => registry.getSealedResourceSecret('res-corrupt'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'an envelope that LOOKS like a marker is spilled, not misparsed',
    () async {
      const impostor = '@chunks:v1:9999-actually-payload-bytes';
      await insert('res-impostor', impostor);

      final db = await raw();
      final column =
          (await db.rawQuery(
                'SELECT sealed_secret_payload AS v FROM connection_resources '
                "WHERE id = 'res-impostor'",
              )).single['v']!
              as String;
      expect(column, '@chunks:v1:1', reason: 'forced spill of the lookalike');
      await db.close();

      expect(
        (await registry.getSealedResourceSecret('res-impostor'))!.envelope,
        impostor,
      );
    },
  );

  test('the recovery snapshot round-trips chunked secrets', () async {
    await insert('res-snap', bigEnvelope);

    final snapshot = await registry.exportRecoverySnapshot();
    await registry.importRecoverySnapshot(snapshot);

    expect(
      (await registry.getSealedResourceSecret('res-snap'))!.envelope,
      bigEnvelope,
    );
  });

  test(
    'a v4 snapshot still imports — and its inline envelope gets chunked',
    () async {
      // The boot-brick case: the Keychain snapshot on an updated device was
      // written by the previous build. It says schemaVersion 4, has no chunk
      // tables, and can carry the envelope INLINE — the import must accept it
      // and normalize it, not throw out of bootstrap forever.
      await insert('res-v4snap', 'placeholder');
      final snapshot =
          jsonDecode(await registry.exportRecoverySnapshot())
              as Map<String, dynamic>;
      snapshot['schemaVersion'] = 4;
      final tables = snapshot['tables'] as Map<String, dynamic>;
      tables.remove('resource_secret_chunks');
      tables.remove('restore_secret_chunks');
      final resources = tables['connection_resources'] as List;
      (resources.single as Map<String, dynamic>)['sealed_secret_payload'] =
          bigEnvelope;

      await registry.importRecoverySnapshot(jsonEncode(snapshot));

      final db = await raw();
      final column =
          (await db.rawQuery(
                'SELECT sealed_secret_payload AS v FROM connection_resources '
                "WHERE id = 'res-v4snap'",
              )).single['v']!
              as String;
      expect(column, startsWith('@chunks:v1:'));
      await db.close();
      expect(
        (await registry.getSealedResourceSecret('res-v4snap'))!.envelope,
        bigEnvelope,
      );
    },
  );

  test('a snapshot newer than this build is still refused', () async {
    await insert('res-future', 'x');
    final snapshot =
        jsonDecode(await registry.exportRecoverySnapshot())
            as Map<String, dynamic>;
    snapshot['schemaVersion'] = ProfileRegistry.schemaVersion + 1;
    await expectLater(
      () => registry.importRecoverySnapshot(jsonEncode(snapshot)),
      throwsA(isA<FormatException>()),
    );
  });
}
