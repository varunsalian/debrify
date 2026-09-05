import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/local_backup/local_backup_archive.dart';
import 'package:debrify/services/profiles/local_backup/local_backup_zip.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String profileId;
  late ProfileScope scope;
  late ConnectionResourceService resources;
  late ProfilePackageService packages;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'local-backup-archive-test-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    final cache = Directory(p.join(temporaryDirectory.path, 'cache'));
    await documents.create(recursive: true);
    await support.create(recursive: true);
    await cache.create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    profileId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: profileId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => 250 - i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    scope = ProfileScope(
      profileId: profileId,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('p.$profileId.g.1.theme_mode', 'archived');
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
    packages = ProfilePackageService(registry: registry, resources: resources);
  });

  tearDown(() async {
    await DebrifyTvDatabase.instance.closeScope();
    IptvMediaStore.debugResetMigration();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> seedDebrifyTv(ProfileScope target, {int hashes = 400}) async {
    final file = target.fileIn(documents, 'documents', 'debrify_tv.db');
    await file.parent.create(recursive: true);
    final db = await openDatabase(file.path);
    await db.execute(
      'CREATE TABLE tv_channels (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE tv_cached_torrents (hash TEXT PRIMARY KEY, payload BLOB)',
    );
    await db.insert('tv_channels', <String, Object?>{'id': 1, 'name': 'Docs'});
    final batch = db.batch();
    for (var i = 0; i < hashes; i++) {
      batch.insert('tv_cached_torrents', <String, Object?>{
        'hash': 'hash-$i',
        'payload': Uint8List.fromList(List<int>.filled(4096, i & 0xff)),
      });
    }
    await batch.commit(noResult: true);
    await db.close();
  }

  Future<void> seedCatalog(ProfileScope target) async {
    final file = target.fileIn(documents, 'documents', 'iptv_catalog.db');
    await file.parent.create(recursive: true);
    final db = await openDatabase(file.path);
    await db.execute('CREATE TABLE channels (id TEXT PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE epg_programmes (id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE hidden_groups (catalog_key TEXT, group_name TEXT)',
    );
    await db.execute(
      'CREATE TABLE channel_manual_orders (catalog_key TEXT, position INTEGER)',
    );
    for (var i = 0; i < 500; i++) {
      await db.insert('channels', <String, Object?>{
        'id': 'ch-$i',
        'name': 'Cache $i',
      });
    }
    await db.insert('epg_programmes', <String, Object?>{'id': 'prog-1'});
    await db.insert('hidden_groups', <String, Object?>{
      'catalog_key': 'cat',
      'group_name': 'Shopping',
    });
    await db.insert('channel_manual_orders', <String, Object?>{
      'catalog_key': 'cat',
      'position': 3,
    });
    await db.close();
  }

  String bigPlaylist({int lines = 40000}) {
    final buffer = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < lines; i++) {
      buffer
        ..write('#EXTINF:-1 tvg-id="c$i",Channel $i ünïcode\n')
        ..write('https://example.invalid/stream/$i.m3u8\n');
    }
    return buffer.toString();
  }

  Future<String> createImportedPlaylist(String content) async {
    final created = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.iptvM3u,
      label: 'Imported',
      publicConfig: const <String, dynamic>{},
      secretConfig: <String, dynamic>{
        'id': 'imported-1',
        'name': 'Imported',
        'enabled': true,
        'url': '',
        'content': content,
        'addedAt': '2026-08-01T00:00:00.000Z',
      },
    );
    return created.id;
  }

  Future<Map<String, Object?>> tableRows(File file, String table) async {
    final db = await openDatabase(file.path, readOnly: true);
    try {
      final count = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table',
      )).single['c'];
      return <String, Object?>{'count': count};
    } finally {
      await db.close();
    }
  }

  for (final allProfiles in [false, true]) {
    test(
      'playlist Unicode chunk boundaries round trip (all=$allProfiles)',
      () async {
        final text = StringBuffer('#EXTM3U\n');
        // Exercise both the first boundary and the shifted next boundary
        // after preserving the previous surrogate pair.
        text.write('a' * (65535 - text.length));
        text.write('😀');
        text.write('b' * (131070 - text.length));
        text.write('𠮷');
        text.write('\nhttps://example.invalid/🎬\n');
        final playlist = text.toString();
        await createImportedPlaylist(playlist);
        final result = await LocalBackupExporter(service: packages).export(
          context: await ProfileAuthorizationContext.capture(registry),
          staging: await LocalBackupScratch.create('export'),
          allProfiles: allProfiles,
          scope: allProfiles ? null : scope,
        );
        final inspection = await LocalBackupRestorer.inspect(result.archive);
        final stage = await LocalBackupRestorer.stage(
          archive: result.archive,
          staging: await LocalBackupScratch.create('restore'),
          inspection: inspection,
        );
        try {
          final content =
              (stage.package.resources.single['secretConfig']
                  as Map)['content'];
          expect(content, playlist);
        } finally {
          await stage.dispose();
        }
      },
    );
  }

  for (final cancelAt in ['Checking backup…', 'Backup verified']) {
    test('cancel at $cancelAt prevents a successful restore stage', () async {
      await createImportedPlaylist(
        '#EXTM3U\nhttps://example.invalid/channel\n',
      );
      final result = await LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: await LocalBackupScratch.create('export'),
        allProfiles: false,
        scope: scope,
      );
      final inspection = await LocalBackupRestorer.inspect(result.archive);
      final cancel = LocalBackupCancellation();
      final staging = await LocalBackupScratch.create('restore');
      try {
        await expectLater(
          LocalBackupRestorer.stage(
            archive: result.archive,
            staging: staging,
            inspection: inspection,
            cancellation: cancel,
            onStage: (stage) {
              if (stage == cancelAt) cancel.cancel();
            },
          ),
          throwsA(isA<LocalBackupCancelledException>()),
        );
      } finally {
        await LocalBackupScratch.delete(staging);
      }
      expect(await staging.exists(), isFalse);
    });
  }

  test(
    'export streams databases and playlists into a verified archive',
    () async {
      await seedDebrifyTv(scope);
      await seedCatalog(scope);
      final playlist = bigPlaylist();
      await createImportedPlaylist(playlist);

      final staging = await LocalBackupScratch.create('export');
      final stages = <String>[];
      final result = await LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: staging,
        allProfiles: false,
        scope: scope,
        onStage: stages.add,
        now: DateTime.utc(2026, 9, 5, 10),
      );
      expect(result.fileName, 'debrify-profile-2026-09-05.debrify');
      expect(result.archive.existsSync(), isTrue);
      expect(result.cachesPruned, isTrue);
      expect(stages.first, 'Preparing backup…');
      expect(stages, contains('Checking backup…'));
      expect(
        DebrifyTvBackupOmission.fromOmissions(result.package.omissions),
        isNull,
      );

      // Package records reference entries; nothing large is inline.
      final databases =
          (result.package.sections['profile-0-databases'] as Map)['values']
              as Map;
      expect(
        databases.keys,
        containsAll(<String>['debrify_tv.db', 'iptv_catalog.db']),
      );
      for (final record in databases.values) {
        expect((record as Map)['encoding'], 'file');
        expect(record.containsKey('data'), isFalse);
      }
      final resource = result.package.resources.single;
      final secret = resource['secretConfig'] as Map;
      expect(secret.containsKey('content'), isFalse);
      expect(
        (secret[ProfilePackageFileSinks.contentAttachmentKey] as Map)['entry'],
        'attachments/resource-0.m3u',
      );
      final manifestJson = utf8.encode(jsonEncode(result.package.toJson()));
      expect(manifestJson.length, lessThan(512 * 1024));

      // Staged inputs were released once packed; only the archive remains.
      expect(
        staging
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.basename(f.path)),
        unorderedEquals(<String>[
          result.fileName,
          LocalBackupManifest.manifestEntry,
          LocalBackupManifest.digestEntry,
        ]),
      );

      // Independent read-back: the archive is a plain stored ZIP.
      final inspection = await LocalBackupRestorer.inspect(result.archive);
      final manifest = inspection.manifest;
      expect(manifest.mode, 'singleProfile');
      expect(inspection.digest, isNotEmpty);
      expect(
        manifest.entries.map((e) => e.name),
        unorderedEquals(<String>[
          'databases/profile-0/debrify_tv.db',
          'databases/profile-0/iptv_catalog.db',
          'attachments/resource-0.m3u',
        ]),
      );
      final reader = await LocalBackupZipReader.open(result.archive);
      try {
        final extractedCatalog = File(
          p.join(temporaryDirectory.path, 'cat.db'),
        );
        await reader.extract(
          reader.find('databases/profile-0/iptv_catalog.db')!,
          extractedCatalog,
        );
        expect(await tableRows(extractedCatalog, 'channels'), {'count': 0});
        expect(await tableRows(extractedCatalog, 'epg_programmes'), {
          'count': 0,
        });
        expect(await tableRows(extractedCatalog, 'hidden_groups'), {
          'count': 1,
        });
        expect(await tableRows(extractedCatalog, 'channel_manual_orders'), {
          'count': 1,
        });
        final extractedTv = File(p.join(temporaryDirectory.path, 'tv.db'));
        await reader.extract(
          reader.find('databases/profile-0/debrify_tv.db')!,
          extractedTv,
        );
        expect(await tableRows(extractedTv, 'tv_cached_torrents'), {
          'count': 400,
        });
        final playlistBytes = await reader.readSmall(
          reader.find('attachments/resource-0.m3u')!,
          maxBytes: 64 * 1024 * 1024,
        );
        expect(utf8.decode(playlistBytes), playlist);
      } finally {
        await reader.close();
      }
      await LocalBackupScratch.delete(staging);
    },
  );

  test(
    'archive restores through the coordinator with caches rebuilt later',
    () async {
      await seedDebrifyTv(scope, hashes: 50);
      await seedCatalog(scope);
      final playlist = bigPlaylist(lines: 2000);
      final originalResourceId = await createImportedPlaylist(playlist);

      final exportStaging = await LocalBackupScratch.create('export');
      final exported = await LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: exportStaging,
        allProfiles: false,
        scope: scope,
      );
      final saved = File(p.join(temporaryDirectory.path, exported.fileName));
      await exported.archive.copy(saved.path);
      await LocalBackupScratch.delete(exportStaging);

      // Simulate the source being gone: restore must not depend on it.
      await scope.fileIn(documents, 'documents', 'debrify_tv.db').delete();
      await scope.fileIn(documents, 'documents', 'iptv_catalog.db').delete();

      final restoreStaging = await LocalBackupScratch.create('restore');
      final inspection = await LocalBackupRestorer.inspect(saved);
      // A different archive swapped in under the same path must be refused
      // when staging reuses an earlier inspection.
      final other = File(p.join(temporaryDirectory.path, 'other.debrify'));
      await LocalBackupZip.write(
        output: other,
        sources: const <LocalBackupZipSource>[],
        modified: DateTime.utc(2026),
      );
      await expectLater(
        LocalBackupRestorer.stage(
          archive: other,
          staging: restoreStaging,
          inspection: inspection,
        ),
        throwsA(isA<LocalBackupFormatException>()),
      );
      final stage = await LocalBackupRestorer.stage(
        archive: saved,
        staging: restoreStaging,
        inspection: inspection,
      );
      try {
        final secret = stage.package.resources.single['secretConfig'] as Map;
        expect(secret['content'], playlist);
        expect(
          secret.containsKey(ProfilePackageFileSinks.contentAttachmentKey),
          isFalse,
        );
        expect(
          stage.resolveDatabase('databases/profile-0/debrify_tv.db'),
          isNotNull,
        );
        expect(stage.resolveDatabase('../etc/passwd'), isNull);

        final coordinator = ProfileRestoreCoordinator(
          registry: registry,
          cipher: cipher,
        );
        final report = await coordinator.restore(
          package: stage.package,
          destinationProfileId: profileId,
          authorization: await ProfileAuthorizationContext.capture(registry),
          databaseFileResolver: stage.resolveDatabase,
        );
        expect(report.resourcesImported, 1);
        final restoredScope = ProfileScope(
          profileId: profileId,
          dataGeneration: report.publishedGeneration,
          sessionEpoch: 1,
        );
        final tv = restoredScope.fileIn(
          documents,
          'documents',
          'debrify_tv.db',
        );
        final catalog = restoredScope.fileIn(
          documents,
          'documents',
          'iptv_catalog.db',
        );
        expect(tv.existsSync(), isTrue);
        expect(catalog.existsSync(), isTrue);
        expect(await tableRows(tv, 'tv_cached_torrents'), {'count': 50});
        expect(await tableRows(tv, 'tv_channels'), {'count': 1});
        expect(await tableRows(catalog, 'hidden_groups'), {'count': 1});
        expect(await tableRows(catalog, 'channels'), {'count': 0});

        final granted = await registry.listGrantedResourcesIncludingDisabled(
          profileId,
        );
        final imported = granted.where(
          (resource) =>
              resource.type == ConnectionResourceType.iptvM3u &&
              resource.id != originalResourceId,
        );
        expect(imported, hasLength(1));
        final revealed = await resources.revealOwnedSecretForProfileBackup(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: imported.single.id,
        );
        expect(revealed['content'], playlist);
      } finally {
        await stage.dispose();
      }
      expect(restoreStaging.existsSync(), isFalse);
    },
  );

  test(
    'damaged, tampered, and future archives are refused before staging',
    () async {
      await seedDebrifyTv(scope, hashes: 20);
      final exportStaging = await LocalBackupScratch.create('export');
      final exported = await LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: exportStaging,
        allProfiles: false,
        scope: scope,
      );
      final good = File(p.join(temporaryDirectory.path, 'good.debrify'));
      await exported.archive.copy(good.path);
      await LocalBackupScratch.delete(exportStaging);

      Future<void> expectRefused(File archive, Matcher matcher) async {
        final staging = await LocalBackupScratch.create('restore');
        try {
          await expectLater(() async {
            final inspection = await LocalBackupRestorer.inspect(archive);
            return LocalBackupRestorer.stage(
              archive: archive,
              staging: staging,
              inspection: inspection,
            );
          }(), throwsA(matcher));
          expect(
            staging.listSync(recursive: true).whereType<File>(),
            isEmpty,
            reason: 'no partial extraction survives a refusal',
          );
        } finally {
          await LocalBackupScratch.delete(staging);
        }
      }

      // Flip one byte inside the database entry.
      final flipped = File(p.join(temporaryDirectory.path, 'flipped.debrify'));
      await good.copy(flipped.path);
      final raf = await flipped.open(mode: FileMode.append);
      await raf.setPosition(4096);
      final byte = (await raf.read(1)).single;
      await raf.setPosition(4096);
      await raf.writeByte(byte ^ 0xff);
      await raf.close();
      await expectRefused(flipped, isA<LocalBackupFormatException>());

      // Truncate.
      final truncated = File(p.join(temporaryDirectory.path, 'short.debrify'));
      await good.copy(truncated.path);
      final shortRaf = await truncated.open(mode: FileMode.append);
      await shortRaf.truncate((await good.length()) ~/ 2);
      await shortRaf.close();
      await expectRefused(truncated, isA<LocalBackupFormatException>());

      // Rebuild the archive with an extra entry not listed in the manifest and
      // with a manifest from the future.
      final reader = await LocalBackupZipReader.open(good);
      final rebuildDir = Directory(p.join(temporaryDirectory.path, 'rebuild'));
      await rebuildDir.create();
      final sources = <LocalBackupZipSource>[];
      try {
        for (final entry in reader.entries) {
          final file = File(p.join(rebuildDir.path, entry.name));
          await reader.extract(entry, file);
          sources.add(
            LocalBackupZipSource(
              name: entry.name,
              file: file,
              bytes: entry.bytes,
            ),
          );
        }
      } finally {
        await reader.close();
      }
      final stray = File(p.join(rebuildDir.path, 'stray.bin'))
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final withStray = File(p.join(temporaryDirectory.path, 'stray.debrify'));
      await LocalBackupZip.write(
        output: withStray,
        sources: <LocalBackupZipSource>[
          ...sources,
          LocalBackupZipSource(name: 'stray.bin', file: stray, bytes: 3),
        ],
        modified: DateTime.utc(2026),
      );
      await expectRefused(withStray, isA<LocalBackupFormatException>());

      final manifestFile = File(
        p.join(rebuildDir.path, LocalBackupManifest.manifestEntry),
      );
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      manifest['version'] = LocalBackupManifest.version + 1;
      final futureBytes = utf8.encode(jsonEncode(manifest));
      await manifestFile.writeAsBytes(futureBytes, flush: true);
      await File(
        p.join(rebuildDir.path, LocalBackupManifest.digestEntry),
      ).writeAsString(await StreamedSha256.ofFile(manifestFile));
      final future = File(p.join(temporaryDirectory.path, 'future.debrify'));
      await LocalBackupZip.write(
        output: future,
        sources: <LocalBackupZipSource>[
          for (final source in sources)
            LocalBackupZipSource(
              name: source.name,
              file: source.file,
              bytes: await source.file.length(),
            ),
        ],
        modified: DateTime.utc(2026),
      );
      await expectRefused(
        future,
        isA<LocalBackupFormatException>().having(
          (error) => error.message,
          'message',
          contains('newer Debrify'),
        ),
      );
    },
  );

  test('cancellation during packing leaves no archive', () async {
    await seedDebrifyTv(scope, hashes: 600);
    final staging = await LocalBackupScratch.create('export');
    final cancellation = LocalBackupCancellation();
    await expectLater(
      LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: staging,
        allProfiles: false,
        scope: scope,
        cancellation: cancellation,
        onBytes: (_, done, _) {
          if (done > 256 * 1024) cancellation.cancel();
        },
      ),
      throwsA(isA<LocalBackupCancelledException>()),
    );
    expect(
      staging
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith(LocalBackupManifest.fileExtension),
          ),
      isEmpty,
    );
    await LocalBackupScratch.delete(staging);
  });

  test(
    'file-backed database records are rejected by the ordinary decoder',
    () async {
      await seedDebrifyTv(scope, hashes: 5);
      final staging = await LocalBackupScratch.create('export');
      final exported = await LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: staging,
        allProfiles: false,
        scope: scope,
      );
      final envelope = await PortableProfilePackage.withIntegrity(
        exported.package,
      );
      await expectLater(
        PortableProfilePackage.decodeMap(envelope),
        throwsA(isA<FormatException>()),
      );
      final decoded = await PortableProfilePackage.decodeFileBackedMap(
        envelope,
      );
      expect(
        decoded.profiles.single['databasesSection'],
        'profile-0-databases',
      );
      await LocalBackupScratch.delete(staging);
    },
  );

  test('unclassified catalog tables fail the export loudly', () async {
    final file = scope.fileIn(documents, 'documents', 'iptv_catalog.db');
    await file.parent.create(recursive: true);
    final db = await openDatabase(file.path);
    await db.execute('CREATE TABLE brand_new_cache (id TEXT PRIMARY KEY)');
    await db.close();
    final staging = await LocalBackupScratch.create('export');
    await expectLater(
      LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: staging,
        allProfiles: false,
        scope: scope,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('brand_new_cache'),
        ),
      ),
    );
    await LocalBackupScratch.delete(staging);
  });

  test('base64 snapshot export and restore are unchanged', () async {
    await seedDebrifyTv(scope, hashes: 3);
    final export = await ProfileDatabaseSnapshot.export(scope);
    final record = export.attachments['debrify_tv.db'] as Map;
    expect(record['encoding'], 'base64');
    final destination = ProfileScope(
      profileId: profileId,
      dataGeneration: 7,
      sessionEpoch: 1,
    );
    expect(
      await ProfileDatabaseSnapshot.restore(destination, export.attachments),
      1,
    );
    expect(
      await tableRows(
        destination.fileIn(documents, 'documents', 'debrify_tv.db'),
        'tv_cached_torrents',
      ),
      {'count': 3},
    );
  });
}
