import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_local_adapter.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import '../services/webdav_sync/connector_test_fakes.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_backup.dart';
import 'package:debrify/services/webdav_backup_archive.dart';
import 'package:debrify/services/transfer/streaming_encrypted_file.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_large_section_io.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_snapshot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
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

  test(
    'first join baselines preserve peer updates and subsequent local edits',
    () async {
      final repository = ConnectorMemoryStateRepository();
      const circleProfile = 'profile-circle';
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: {circleProfile: profileId},
        circleToLocalResources: const {},
      );
      final prefs = await ProfilePreferences.instance();
      await prefs.setString('theme_mode', 'dark');
      repository.state = repository.state.copyWith(
        circleToLocalProfiles: maps.circleToLocalProfiles,
        circleToLocalResources: maps.circleToLocalResources,
      );
      final descriptor = WebDavSyncSnapshotDescriptor(
        contentHash: 'a' * 64,
        size: 1000,
        semanticDigest: 'b' * 64,
        databaseDigest: 'c' * 64,
        profileMap: {'profile-0': circleProfile},
        resourceMap: const {},
      );
      final source = DefaultWebDavSyncSeedSource(
        graphBuilder: WebDavSyncGraphBuilder(packages),
        stateRepository: repository,
        localAdapter: ProfileWebDavSyncLocalAdapter(registry),
      );
      final auth = await ProfileAuthorizationContext.capture(registry);
      final first = await source.prepare(
        namespaceId: 'join',
        deviceId: 'new-device',
        authorization: auth,
        localNowMs: 10000,
        serverNowMs: 10000,
        clockOffsetMs: 0,
        reuseBootstrap: descriptor,
      );
      final imported = first.profileStates[circleProfile]!.baseline!;
      expect(imported.scalars.entries['theme_mode']!.stamp.normalizedTimeMs, 0);
      final peer = WebDavSyncHotMerge.build(
        WebDavSyncBuildInput(
          circleProfileId: circleProfile,
          deviceId: 'older-peer',
          rawPreferences: const {'theme_mode': 'light'},
          portablePreferences: const {'theme_mode': 'light'},
          identityMaps: maps,
          localNowMs: 5000,
          serverNowMs: 5000,
          clockOffsetMs: 0,
        ),
      ).document;
      final merged = WebDavSyncHotMerge.merge(
        local: imported,
        peers: [peer],
        tombstoneDocuments: const [],
        nowMs: 10000,
      ).document;
      expect(merged.scalars.values['theme_mode'], 'light');
      await prefs.setString('theme_mode', 'system');
      final retry = await source.prepare(
        namespaceId: 'join',
        deviceId: 'new-device',
        authorization: auth,
        localNowMs: 11000,
        serverNowMs: 11000,
        clockOffsetMs: 0,
        reuseBootstrap: descriptor,
      );
      final edited = retry.profileStates[circleProfile]!.baseline!;
      expect(edited.scalars.values['theme_mode'], 'system');
      expect(
        edited.scalars.entries['theme_mode']!.stamp.normalizedTimeMs,
        11000,
      );
      expect(
        await (await LocalBackupScratch.root()).exists(),
        isFalse,
        reason: 'reused bootstrap must not export another archive',
      );
    },
  );

  test(
    'paged Unicode preferences restore and reject a changed page before publication',
    () async {
      final value = '${'x' * 16383}😀中\n' * 24;
      final prefs = await ProfilePreferences.instance();
      await prefs.setString('saved_search_notes', value);
      const priority = '["addon:config-b","embedded","addon:config-a"]';
      await prefs.setString('subtitle_source_priority_v1', priority);
      final auth = await ProfileAuthorizationContext.capture(registry);
      final exported = await LocalBackupExporter(service: packages).export(
        context: auth,
        staging: await LocalBackupScratch.create('paged-export'),
        allProfiles: true,
        separateMetadata: true,
      );
      final inspection = await LocalBackupRestorer.inspect(exported.archive);
      final pages = inspection.manifest.entries
          .where((entry) => entry.kind == LocalBackupEntryKind.metadata)
          .toList();
      expect(inspection.manifest.archiveVersion, 2);
      expect(pages.length, greaterThan(2));
      expect(pages.every((entry) => entry.bytes <= 128 * 1024), isTrue);
      expect(jsonEncode(inspection.manifest.toJson()).length, lessThan(16000));
      final staged = await LocalBackupRestorer.stage(
        archive: exported.archive,
        staging: await LocalBackupScratch.create('paged-restore'),
        inspection: inspection,
      );
      final coordinator = ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      );
      final report = await coordinator.restoreDeviceGraph(
        package: staged.package,
        authorization: auth,
        databaseFileResolver: staged.resolveDatabase,
      );
      final restoredPrefs = await ProfilePreferences.forCapturedScope(
        ProfileScope(
          profileId: report.importedProfileIds.single,
          dataGeneration: 1,
          sessionEpoch: 0,
        ),
        CapturedProfilePreferenceAccess.diagnosticsReadOnly,
      );
      expect(restoredPrefs.getString('saved_search_notes'), value);
      expect(restoredPrefs.getString('subtitle_source_priority_v1'), priority);
      final before = (await registry.listProfiles()).map((p) => p.id).toSet();
      final changed = staged.resolveDatabase(pages.first.name)!;
      final bytes = await changed.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 1;
      await changed.writeAsBytes(bytes);
      await expectLater(
        coordinator.restoreDeviceGraph(
          package: staged.package,
          authorization: await ProfileAuthorizationContext.capture(registry),
          databaseFileResolver: staged.resolveDatabase,
        ),
        throwsFormatException,
      );
      expect((await registry.listProfiles()).map((p) => p.id).toSet(), before);
      await staged.dispose();
    },
  );

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

  test(
    'large playlist attachments stay lazy and publish valid sealed secrets',
    () async {
      final playlist = bigPlaylist(lines: 2000);
      final resourceId = await createImportedPlaylist(playlist);
      final exported = await LocalBackupExporter(service: packages).export(
        context: await ProfileAuthorizationContext.capture(registry),
        staging: await LocalBackupScratch.create('lazy-export'),
        allProfiles: true,
        separateMetadata: true,
      );
      final stage = await LocalBackupRestorer.stage(
        archive: exported.archive,
        staging: await LocalBackupScratch.create('lazy-restore'),
        inspection: await LocalBackupRestorer.inspect(exported.archive),
        lazyAttachments: true,
      );
      for (final resource in stage.package.resources) {
        expect(resource['secretConfig'] as Map, isNot(contains('content')));
      }
      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restoreDeviceGraph(
            package: stage.package,
            authorization: await ProfileAuthorizationContext.capture(registry),
            databaseFileResolver: stage.resolveDatabase,
          );
      final original = stage.package.resources.singleWhere(
        (r) => r['sourceResourceId'] == resourceId,
      );
      final id = report.importedResourceIdsByBackupId[original['backupId']]!;
      final record = await registry.getResource(id);
      final importedScope = ProfileScope(
        profileId: record!.ownerProfileId,
        dataGeneration: 1,
        sessionEpoch: scope.sessionEpoch + 1,
      );
      await registry.setActiveProfile(record.ownerProfileId);
      ProfileRuntime.publish(importedScope);
      final revealed = await resources.revealOwnedSecretForProfileBackup(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: id,
      );
      expect(revealed['content'], playlist);
      expect(
        (await LocalBackupScratch.root()).list().where(
          (e) => p.basename(e.path).startsWith('restore-secrets-'),
        ),
        emitsDone,
      );
      await stage.dispose();
    },
  );

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

  test(
    'WebDAV encrypted archive restores file-backed databases and prunes only caches',
    () async {
      await seedDebrifyTv(scope);
      await seedCatalog(scope);
      await createImportedPlaylist(
        '#EXTM3U\n#EXTINF:-1,News\nhttps://example.test/live\n',
      );
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final staging = await LocalBackupScratch.create('webdav-export');
      final exported =
          await WebDavBackupArchive(
            LocalBackupExporter(service: packages),
          ).export(
            context: authorization,
            staging: staging,
            passphrase: 'archive-passphrase',
            captureSync: (_, _) async => const WebDavSyncBackup(),
          );
      expect(exported.cachesPruned, isTrue);
      expect(await StreamingEncryptedFile.looksLike(exported.file), isTrue);
      expect(
        await File(
          exported.file.path.replaceFirst(RegExp(r'\.enc$'), ''),
        ).exists(),
        isFalse,
      );
      final archive = File('${staging.path}/unlocked.debrify');
      await WebDavBackupArchive.decrypt(
        source: exported.file,
        destination: archive,
        passphrase: 'archive-passphrase',
      );
      final inspection = await LocalBackupRestorer.inspect(archive);
      expect(inspection.manifest.webDavSync, isNotNull);
      final restored = await LocalBackupRestorer.stage(
        archive: archive,
        staging: await LocalBackupScratch.create('webdav-restore'),
        inspection: inspection,
      );
      addTearDown(restored.dispose);
      addTearDown(() => LocalBackupScratch.delete(staging));
      final databaseSection = restored.package.sections.values
          .whereType<Map>()
          .firstWhere(
            (section) =>
                (section['values'] as Map?)?.containsKey('debrify_tv.db') ==
                true,
          );
      final records = databaseSection['values'] as Map;
      expect((records['debrify_tv.db'] as Map)['encoding'], 'file');
      final tv = await openDatabase(
        restored
            .resolveDatabase(
              (records['debrify_tv.db'] as Map)['entry'] as String,
            )!
            .path,
      );
      expect(
        (await tv.rawQuery(
          'SELECT COUNT(*) AS count FROM tv_cached_torrents',
        )).single['count'],
        400,
      );
      await tv.close();
      final catalog = await openDatabase(
        restored
            .resolveDatabase(
              (records['iptv_catalog.db'] as Map)['entry'] as String,
            )!
            .path,
      );
      expect(
        (await catalog.rawQuery(
          'SELECT COUNT(*) AS count FROM channels',
        )).single['count'],
        0,
      );
      await catalog.close();
      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restoreDeviceGraph(
            package: restored.package,
            authorization: authorization,
            databaseFileResolver: restored.resolveDatabase,
          );
      expect(report.importedProfileIds, hasLength(1));
    },
  );

  test(
    'a second device reuses the shared bootstrap after the original device is deleted',
    () async {
      await seedDebrifyTv(scope);
      await createImportedPlaylist('#EXTM3U\nhttps://example.test/live\n');
      final allResources = await registry.listAllResourcesIncludingDisabled();
      final maps = WebDavSyncGraphIdentityPlanner.ensure(
        localProfileIds: [profileId],
        localResourceIds: allResources.map((resource) => resource.id),
      ).maps;
      final graph = await WebDavSyncGraphBuilder(packages).build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: await ProfileAuthorizationContext.capture(registry),
        identityMaps: maps,
      );
      expect(graph.snapshot, isNotNull);
      addTearDown(graph.snapshot!.dispose);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final stored = <String, File>{};
      var archiveUploads = 0;
      var archiveDownloads = 0;
      server.listen((request) async {
        final path = request.uri.path;
        try {
          switch (request.method) {
            case 'MKCOL':
              request.response.statusCode = HttpStatus.created;
            case 'PUT':
              if (stored.containsKey(path) &&
                  request.headers.value(HttpHeaders.ifNoneMatchHeader) == '*') {
                await request.drain<void>();
                request.response.statusCode = HttpStatus.preconditionFailed;
              } else {
                final file = File(
                  '${temporaryDirectory.path}/remote-${stored.length}',
                );
                final sink = file.openWrite();
                await sink.addStream(request);
                await sink.close();
                stored[path] = file;
                if (path.contains('/objects/')) archiveUploads++;
                request.response.statusCode = HttpStatus.created;
              }
            case 'GET':
              if (path.contains('/objects/')) archiveDownloads++;
              final file = stored[path];
              if (file == null) {
                request.response.statusCode = HttpStatus.notFound;
              } else {
                request.response.contentLength = await file.length();
                await request.response.addStream(file.openRead());
              }
            case 'DELETE':
              stored.removeWhere(
                (key, _) => key == path || key.startsWith('$path/'),
              );
              request.response.statusCode = HttpStatus.noContent;
            default:
              request.response.statusCode = HttpStatus.methodNotAllowed;
          }
        } catch (_) {
          request.response.statusCode = HttpStatus.internalServerError;
        }
        await request.response.close();
      });
      final transport = ProtocolWebDavSyncTransport(
        location: WebDavSyncFolderLocation(
          endpoint: 'http://${server.address.address}:${server.port}/dav',
          folderPath: '',
          serverName: 'Test',
        ),
        credentials: const WebDavCredentials(username: '', password: ''),
      );
      addTearDown(transport.close);
      final codec = WebDavSyncCodec();
      final marker = await codec.sealRoot(
        passphrase: 'sync-secret',
        circleId: 'circle-test',
        createdAt: DateTime.utc(2026),
        memoryKiB: 8,
        iterations: 1,
      );
      final root = await codec.openRoot(marker, 'sync-secret');
      final io = WebDavSyncLargeSectionIo(codec: codec);
      final first = await io.sealWriteVerify(
        transport: transport,
        key: root.key,
        circleId: 'circle-test',
        deviceId: 'device-first',
        logicalName: 'bootstrap',
        schemaVersion: WebDavSyncSnapshotDescriptor.schemaVersion,
        payload: graph.snapshot!,
        semanticDigest: graph.semanticDigest,
        updatedAtMs: 1,
        maxBytes: WebDavSyncSnapshotDescriptor.maxDescriptorBytes,
      );
      final downloadsBeforeRetry = archiveDownloads;
      final retryReference = await WebDavSyncGraphReader.read(
        transport: transport,
        codec: codec,
        key: root.key,
        circleId: 'circle-test',
        deviceId: 'device-first',
        kind: WebDavSyncGraphKind.bootstrap,
        reference: first,
        profileMap: graph.profileMap,
        resourceMap: graph.resourceMap,
        materializeBootstrap: false,
      );
      expect(retryReference.snapshot, isNotNull);
      expect(retryReference.restoreStage, isNull);
      expect(() => retryReference.package, throwsStateError);
      expect(archiveDownloads, downloadsBeforeRetry);
      final opened = await WebDavSyncGraphReader.read(
        transport: transport,
        codec: codec,
        key: root.key,
        circleId: 'circle-test',
        deviceId: 'device-first',
        kind: WebDavSyncGraphKind.bootstrap,
        reference: first,
        profileMap: graph.profileMap,
        resourceMap: graph.resourceMap,
      );
      addTearDown(opened.dispose);
      expect(opened.restoreStage, isNotNull);
      final second = await io.sealWriteVerify(
        transport: transport,
        key: root.key,
        circleId: 'circle-test',
        deviceId: 'device-second',
        logicalName: 'bootstrap',
        schemaVersion: WebDavSyncSnapshotDescriptor.schemaVersion,
        payload: opened.snapshot!.toJson(),
        semanticDigest: graph.semanticDigest,
        updatedAtMs: 2,
        maxBytes: WebDavSyncSnapshotDescriptor.maxDescriptorBytes,
      );
      await transport.deleteDeviceDirectory('device-first');
      await Directory(
        '${support.path}/webdav-sync/object-cache',
      ).delete(recursive: true);
      final joined = await WebDavSyncGraphReader.read(
        transport: transport,
        codec: codec,
        key: root.key,
        circleId: 'circle-test',
        deviceId: 'device-second',
        kind: WebDavSyncGraphKind.bootstrap,
        reference: second,
        profileMap: const {},
        resourceMap: const {},
      );
      addTearDown(joined.dispose);
      expect(joined.semanticDigest, graph.semanticDigest);
      expect(joined.snapshot!.contentHash, opened.snapshot!.contentHash);
      expect(archiveUploads, 1);
      expect(
        stored.keys.where((key) => key.contains('/objects/')),
        hasLength(1),
      );
      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restoreDeviceGraph(
            package: joined.package,
            authorization: await ProfileAuthorizationContext.capture(registry),
            databaseFileResolver: joined.restoreStage!.resolveDatabase,
          );
      expect(report.importedProfileIds, hasLength(1));
    },
  );

  for (final allProfiles in [false, true]) {
    test(
      'sync snapshot is included in archive integrity and identities (all=$allProfiles)',
      () async {
        final authorization = await ProfileAuthorizationContext.capture(
          registry,
        );
        final staging = await LocalBackupScratch.create('sync-backup');
        addTearDown(() => LocalBackupScratch.delete(staging));
        var captured = false;
        final exported = await LocalBackupExporter(service: packages).export(
          context: authorization,
          staging: staging,
          allProfiles: allProfiles,
          scope: allProfiles ? null : scope,
          captureSync: (profiles, resources) async {
            expect(profiles[profileId], 'profile-0');
            captured = true;
            return const WebDavSyncBackup();
          },
        );
        expect(captured, isTrue);
        final inspection = await LocalBackupRestorer.inspect(exported.archive);
        expect(inspection.manifest.webDavSync, isNotNull);
        expect(inspection.manifest.webDavSync!.connection, isNull);
        final restoreStaging = await LocalBackupScratch.create('sync-restore');
        final stage = await LocalBackupRestorer.stage(
          archive: exported.archive,
          staging: restoreStaging,
          inspection: inspection,
        );
        addTearDown(stage.dispose);
        Map<String, int>? generations;
        Future<void> prepared(
          Map<String, String> profiles,
          Map<String, String> connections,
          Map<String, int> expected,
        ) async {
          expect(profiles.keys, contains('profile-0'));
          generations = expected;
          for (final entry in expected.entries) {
            final before = await registry.getProfile(entry.key);
            expect(
              before == null ||
                  before.lifecycle.name != 'active' ||
                  before.visibleDataGeneration != entry.value,
              isTrue,
            );
          }
        }

        final coordinator = ProfileRestoreCoordinator(
          registry: registry,
          cipher: cipher,
        );
        if (allProfiles) {
          await coordinator.restoreDeviceGraph(
            package: stage.package,
            authorization: authorization,
            databaseFileResolver: stage.resolveDatabase,
            beforePublish: prepared,
          );
        } else {
          await coordinator.restore(
            package: stage.package,
            destinationProfileId: profileId,
            authorization: authorization,
            databaseFileResolver: stage.resolveDatabase,
            beforePublish: prepared,
          );
        }
        expect(generations, isNotNull);
        for (final entry in generations!.entries) {
          expect(
            (await registry.getProfile(entry.key))!.visibleDataGeneration,
            entry.value,
          );
        }
      },
    );
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
