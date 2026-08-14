import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/secret_vault.dart';
import '../../utils/app_storage.dart';
import '../../utils/platform_util.dart';
import 'device_key_provider.dart';
import 'profile_preference_budget.dart';
import 'profile_preferences.dart';
import 'profile_registry.dart';
import 'profile_scope.dart';

enum ProfileMigrationStage {
  notStarted,
  preflightPassed,
  registryCreated,
  resourcesConverted,
  preferencesCopied,
  databasesCopied,
  filesCopied,
  jobsTagged,
  verified,
  committed,
}

/// Idempotent, non-destructive conversion of the legacy single-user install.
/// The old keys/files remain untouched; only commitBootstrap changes authority.
class ProfileMigrationService {
  static const String migrationId = 'legacy-to-admin-v1';
  static const String adminProfileId = 'legacy-admin-v1';

  final ProfileRegistry registry;
  final DeviceSecretCipher cipher;

  ProfileMigrationService({required this.registry, required this.cipher});

  /// Keeps tvOS below CFPreferences' hard payload ceiling before profile
  /// migration starts duplicating legacy preferences into a scoped namespace.
  ///
  /// TVMaze entries are rebuildable API-response caches. Persisting them in
  /// UserDefaults is especially unsafe on tvOS: a populated legacy cache can
  /// already approach the platform limit, and the first scoped copy then
  /// aborts the process inside CFPreferences instead of returning an error.
  /// Remove both legacy entries and partial scoped copies left by an
  /// interrupted migration. No user setting, activity, or credential matches
  /// these prefixes.
  static Future<int> pruneTvOsTransientPreferenceCaches({
    required SharedPreferences preferences,
    bool? tvOs,
  }) async {
    if (!(tvOs ?? PlatformUtil.isTvOS)) return 0;
    final keys = preferences.getKeys().where(_isTvMazeCacheKey).toList()
      ..sort(
        (left, right) => _preferenceFootprint(
          preferences.get(right),
        ).compareTo(_preferenceFootprint(preferences.get(left))),
      );
    var removed = 0;
    for (final key in keys) {
      final success = await preferences.remove(key);
      if (!success && preferences.containsKey(key)) {
        throw StateError('Unable to release the tvOS preference cache budget');
      }
      removed++;
    }
    return removed;
  }

  /// Refuses a migration that would push tvOS `UserDefaults` past its budget.
  ///
  /// Throws [ProfilePreferenceBudgetExceeded] rather than letting the copy loop
  /// discover the problem partway through. Migration writes are exempt from the
  /// runtime guard precisely because [_copyPreference] treats a refused write as
  /// fatal, so this preflight is the only bound on them — and monotonicity is
  /// what makes it sufficient: the loop only adds keys, so the total after the
  /// last copy is exactly what is projected here.
  static void _assertPreferenceBudget(
    SharedPreferences legacy,
    Set<String> profileKeys,
    UserProfile? existingAdmin,
  ) {
    if (!ProfilePreferenceBudget.enforced) return;
    final scope = ProfileScope(
      profileId: adminProfileId,
      dataGeneration: existingAdmin?.visibleDataGeneration ?? 1,
      sessionEpoch: 0,
    );
    var projected = ProfilePreferenceBudget.measure(legacy);
    for (final key in profileKeys) {
      final physical = scope.preferenceKey(key);
      // An interrupted run may have copied this key already; recopying it adds
      // nothing, so counting it would only overestimate.
      if (legacy.containsKey(physical)) continue;
      projected += ProfilePreferenceBudget.entryFootprint(
        physical,
        legacy.get(key),
      );
    }
    // Projected against the reserved ceiling, not the full limit: migrating to
    // exactly the limit would leave an install that refuses every write from
    // its first launch onward.
    if (projected > ProfilePreferenceBudget.migrationLimitBytes) {
      throw ProfilePreferenceBudgetExceeded(
        projectedBytes: projected,
        limitBytes: ProfilePreferenceBudget.migrationLimitBytes,
      );
    }
  }

  Future<UserProfile> migrate() async {
    final support = await AppStorage.support();
    await support.create(recursive: true);
    final lock = await File(
      p.join(support.path, '.profiles-migration-v1.lock'),
    ).open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    try {
      if (await registry.isMigrationCommitted()) {
        return (await registry.getProfile(adminProfileId))!;
      }
      final legacy = await SharedPreferences.getInstance();
      await pruneTvOsTransientPreferenceCaches(preferences: legacy);
      final classified = _classifyKeys(legacy.getKeys());

      // Migration is non-destructive: legacy keys stay while scoped copies are
      // added, so the defaults database holds both afterwards. That duplication
      // is what crossed the tvOS platform limit and aborted the process. Decide
      // before the registry or the scoped namespace is touched, so a refusal
      // leaves the install exactly as it was — barring the rebuildable TVMaze
      // caches the prune above already dropped.
      var admin = await registry.getProfile(adminProfileId);
      _assertPreferenceBudget(legacy, classified.profile, admin);

      await _journal(ProfileMigrationStage.preflightPassed, <String, dynamic>{
        'profileKeys': classified.profile.length,
        'resourceKeys': classified.resource.length,
        'deviceKeys': classified.device.length,
      });

      admin ??= await registry.createProfile(
        id: adminProfileId,
        name: 'Admin',
        role: UserProfileRole.admin,
        policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
        setupComplete: legacy.getBool('initial_setup_complete_v1') ?? false,
        lifecycle: UserProfileLifecycle.staging,
      );
      await _journal(ProfileMigrationStage.registryCreated);

      final resources = await _convertResources(
        legacy,
        admin.id,
        classified.resource,
      );
      await _journal(
        ProfileMigrationStage.resourcesConverted,
        <String, dynamic>{
          'resources': resources.count,
          'sourceDispositions': resources.sourceDispositions,
          'resourceIds': resources.resourceIds,
        },
      );

      final scope = ProfileScope(
        profileId: admin.id,
        dataGeneration: admin.visibleDataGeneration,
        sessionEpoch: 0,
      );
      final destination = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.migration,
      );
      var copiedPreferences = 0;
      for (final key in classified.profile) {
        await _copyPreference(legacy, destination, key);
        copiedPreferences++;
      }
      await _journal(ProfileMigrationStage.preferencesCopied, <String, dynamic>{
        'copied': copiedPreferences,
      });

      final dbManifest = await _copyDatabases(scope);
      await _journal(ProfileMigrationStage.databasesCopied, <String, dynamic>{
        'databases': dbManifest,
      });
      final fileManifest = await _copyFiles(scope);
      await _journal(ProfileMigrationStage.filesCopied, <String, dynamic>{
        'files': fileManifest,
      });

      // Owner-aware backends deterministically treat old records as this ID;
      // the durable ledger reconciler performs physical tagging after launch.
      await _journal(ProfileMigrationStage.jobsTagged, <String, dynamic>{
        'legacyOwnerProfileId': adminProfileId,
      });
      await _verify(
        legacy: legacy,
        destination: destination,
        expectedPreferenceKeys: classified.profile,
        expectedResourceSourceKeys: classified.resource,
        resourceReport: resources,
        dbManifest: dbManifest,
        fileManifest: fileManifest,
      );
      await _journal(ProfileMigrationStage.verified);
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
        migrationPayload: <String, Object?>{
          'resourceSourceDispositions': resources.sourceDispositions,
          'resourceIds': resources.resourceIds,
          'profilePreferenceCount': copiedPreferences,
          'databaseCount': dbManifest.length,
          'fileCount': fileManifest.length,
        },
      );
      return (await registry.getProfile(admin.id))!;
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<_ResourceMigrationReport> _convertResources(
    SharedPreferences legacy,
    String ownerProfileId,
    Set<String> sourceKeys,
  ) async {
    var count = 0;
    final resourceIds = <String>[];
    final scalarValues = <String, String?>{};
    // Validate every present scalar envelope up front, including superseded
    // WebDAV compatibility keys. An unreadable source can never disappear
    // merely because a newer collection key also exists.
    for (final key in sourceKeys.where(_scalarResourceKeys.contains)) {
      scalarValues[key] = await SecretVault.getStringStrict(legacy, key);
    }

    Future<String?> add(
      String stableName,
      ConnectionResourceType type,
      String label,
      String slot,
      Map<String, dynamic> secrets, {
      Map<String, dynamic> public = const <String, dynamic>{},
      bool enabled = true,
    }) async {
      // Two separate jobs, previously tangled into one removeWhere: decide
      // whether this record is worth a resource at all, and drop absent
      // fields. Testing emptiness WITHOUT mutating is the difference — an
      // empty string can be structurally required (an Xtream provider stores
      // `url: ''` because its endpoint is `serverUrl`), and stripping it left
      // the sealed record missing a key its reader casts non-null. That threw
      // for the whole collection, not just the one entry, and migration is a
      // one-way door so the damage outlived the build that caused it.
      if (secrets.values.every((value) => value == null || value == '')) {
        return null;
      }
      secrets.removeWhere((_, value) => value == null);
      final id = 'resource-legacy-$stableName';
      if (await registry.getResource(id) == null) {
        final aad = utf8.encode(
          'debrify-resource|id=$id|type=${type.name}|owner=$ownerProfileId|'
          'public=1|secret=1',
        );
        final sealed = await cipher.seal(
          utf8.encode(jsonEncode(secrets)),
          associatedData: aad,
        );
        await registry.insertResource(
          resource: ConnectionResource(
            id: id,
            type: type,
            label: label,
            ownerProfileId: ownerProfileId,
            publicConfig: <String, dynamic>{'schemaVersion': 1, ...public},
            authorizationRevision: 1,
            enabled: enabled,
          ),
          sealedSecretPayload: sealed,
          secretPayloadVersion: 1,
          ownerPermissions: ResourcePermission.values.fold<int>(
            0,
            (mask, permission) => mask | permission.bit,
          ),
        );
      }
      if (enabled) {
        await registry.bindResource(
          profileId: ownerProfileId,
          slot: slot,
          resourceId: id,
        );
      }
      count++;
      resourceIds.add(id);
      return id;
    }

    Future<String?> secret(String key) =>
        SecretVault.getStringStrict(legacy, key);

    await add(
      'real-debrid',
      ConnectionResourceType.realDebrid,
      'Real-Debrid',
      'provider.realDebrid',
      <String, dynamic>{'apiKey': await secret('real_debrid_api_key')},
    );
    await add(
      'torbox',
      ConnectionResourceType.torbox,
      'TorBox',
      'provider.torbox',
      <String, dynamic>{'apiKey': await secret('torbox_api_key')},
    );
    await add(
      'premiumize',
      ConnectionResourceType.premiumize,
      'Premiumize',
      'provider.premiumize',
      <String, dynamic>{'apiKey': await secret('premiumize_api_key')},
    );
    await add(
      'all-debrid',
      ConnectionResourceType.allDebrid,
      'AllDebrid',
      'provider.allDebrid',
      <String, dynamic>{'apiKey': await secret('alldebrid_api_key')},
    );
    await add(
      'mdblist',
      ConnectionResourceType.mdblist,
      'MDBList',
      'tracker.mdblist',
      <String, dynamic>{
        'apiKey': await secret('mdblist_api_key'),
        'username': legacy.getString('mdblist_username'),
      },
    );
    await add(
      'trakt',
      ConnectionResourceType.trakt,
      'Trakt',
      'tracker.trakt',
      <String, dynamic>{
        'accessToken': await secret('trakt_access_token'),
        'refreshToken': await secret('trakt_refresh_token'),
        'username': legacy.getString('trakt_username'),
        'expiryMs': legacy.getInt('trakt_token_expiry'),
      },
    );
    await add(
      'simkl',
      ConnectionResourceType.simkl,
      'Simkl',
      'tracker.simkl',
      <String, dynamic>{
        'accessToken': await secret('simkl_access_token'),
        'username': legacy.getString('simkl_username'),
      },
    );
    await add(
      'reddit-quarantine',
      ConnectionResourceType.reddit,
      'Reddit (disabled)',
      'tracker.reddit.quarantine',
      <String, dynamic>{
        'accessToken': await secret('reddit_access_token'),
        'refreshToken': await secret('reddit_refresh_token'),
        'username': legacy.getString('reddit_username'),
      },
      enabled: false,
    );
    await add(
      'pikpak',
      ConnectionResourceType.pikpak,
      'PikPak',
      'provider.pikpak',
      <String, dynamic>{
        'email': await secret('pikpak_email'),
        'password': await secret('pikpak_password'),
        'accessToken': await secret('pikpak_access_token'),
        'refreshToken': await secret('pikpak_refresh_token'),
        'deviceId': await secret('pikpak_device_id'),
        'captchaToken': await secret('pikpak_captcha_token'),
        'userId': await secret('pikpak_user_id'),
      },
    );

    final webDavRaw = await secret('webdav_servers_v1');
    if (webDavRaw != null) {
      final decoded = jsonDecode(webDavRaw);
      if (decoded is! List) throw const FormatException('Invalid WebDAV data');
      var index = 0;
      for (final item in decoded) {
        if (item is! Map) throw const FormatException('Invalid WebDAV entry');
        final map = Map<String, dynamic>.from(item);
        await add(
          'webdav-$index',
          ConnectionResourceType.webDav,
          (map['name'] as String?)?.trim().isNotEmpty == true
              ? map['name'] as String
              : 'WebDAV',
          'provider.webDav.$index',
          map,
          public: <String, dynamic>{'accountLabel': map['name'] ?? 'WebDAV'},
        );
        index++;
      }
    } else {
      await add(
        'webdav-legacy',
        ConnectionResourceType.webDav,
        'WebDAV',
        'provider.webDav.legacy',
        <String, dynamic>{
          'baseUrl': await secret('webdav_base_url'),
          'username': await secret('webdav_username'),
          'password': await secret('webdav_password'),
        },
      );
    }
    final indexers = await SecretVault.getStringListStrict(
      legacy,
      'indexer_manager_configs_v1',
    );
    for (var index = 0; index < indexers.length; index++) {
      final decoded = jsonDecode(indexers[index]);
      if (decoded is! Map) {
        throw const FormatException('Invalid indexer manager entry');
      }
      final map = Map<String, dynamic>.from(decoded);
      final isProwlarr = map['type'] == 'prowlarr';
      await add(
        'indexer-$index',
        isProwlarr
            ? ConnectionResourceType.prowlarr
            : ConnectionResourceType.jackett,
        (map['name'] as String?)?.trim().isNotEmpty == true
            ? map['name'] as String
            : (isProwlarr ? 'Prowlarr' : 'Jackett'),
        'indexer.$index',
        map,
        public: <String, dynamic>{
          'managerName': map['name'] ?? (isProwlarr ? 'Prowlarr' : 'Jackett'),
        },
      );
    }

    final playlists =
        legacy.getStringList('iptv_playlists') ?? const <String>[];
    for (var index = 0; index < playlists.length; index++) {
      final decoded = jsonDecode(playlists[index]);
      if (decoded is! Map) throw const FormatException('Invalid IPTV entry');
      final item = await SecretVault.openFieldsStrict(
        Map<String, dynamic>.from(decoded),
        const <String>['url', 'serverUrl', 'username', 'password', 'epgUrl'],
      );
      final xtream = (item['serverUrl']?.toString().isNotEmpty ?? false);
      final name = item['name']?.toString().trim();
      await add(
        'iptv-$index',
        xtream
            ? ConnectionResourceType.iptvXtream
            : ConnectionResourceType.iptvM3u,
        name?.isNotEmpty == true ? name! : 'IPTV',
        'iptv.$index',
        item,
        public: <String, dynamic>{
          'playlistName': name?.isNotEmpty == true ? name! : 'IPTV',
          'providerKind': xtream ? 'xtream' : 'm3u',
        },
      );
    }

    final addonsRaw = legacy.getString('stremio_addons_v1');
    if (addonsRaw != null && addonsRaw.isNotEmpty) {
      final decoded = jsonDecode(addonsRaw);
      if (decoded is! List) throw const FormatException('Invalid addon data');
      for (var index = 0; index < decoded.length; index++) {
        final value = decoded[index];
        if (value is! Map) throw const FormatException('Invalid addon entry');
        final addon = Map<String, dynamic>.from(value);
        final name = addon['name']?.toString().trim();
        await add(
          'stremio-$index',
          ConnectionResourceType.stremioAddon,
          name?.isNotEmpty == true ? name! : 'Stremio addon',
          'stremio.$index',
          addon,
          public: <String, dynamic>{
            'addonName': name?.isNotEmpty == true ? name! : 'Stremio addon',
            'contentKinds': addon['types'] is List
                ? List<Object?>.from(addon['types'] as List)
                : const <Object?>[],
          },
        );
      }
    }
    final ids = resourceIds.toSet();
    final dispositions = <String, String>{};
    for (final key in sourceKeys) {
      final target = _scalarResourceTargets[key];
      if (target != null) {
        if (scalarValues[key]?.isEmpty ?? true) {
          dispositions[key] = 'emptySource';
          continue;
        }
        if (const <String>{
              'webdav_base_url',
              'webdav_username',
              'webdav_password',
            }.contains(key) &&
            sourceKeys.contains('webdav_servers_v1')) {
          dispositions[key] = 'supersededBy:webdav_servers_v1';
        } else if (ids.contains(target)) {
          dispositions[key] = key.startsWith('reddit_')
              ? 'quarantined:$target'
              : 'converted:$target';
        } else {
          dispositions[key] = 'emptySource';
        }
        continue;
      }
      final prefix = switch (key) {
        'webdav_servers_v1' => 'resource-legacy-webdav-',
        'indexer_manager_configs_v1' => 'resource-legacy-indexer-',
        'iptv_playlists' => 'resource-legacy-iptv-',
        'stremio_addons_v1' => 'resource-legacy-stremio-',
        _ => null,
      };
      if (prefix == null) {
        throw StateError('Missing migration disposition for $key');
      }
      final destinations = ids.where((id) => id.startsWith(prefix)).toList()
        ..sort();
      dispositions[key] = destinations.isEmpty
          ? 'emptyCollection'
          : 'converted:${destinations.join(',')}';
    }
    if (dispositions.keys.toSet().difference(sourceKeys).isNotEmpty ||
        sourceKeys.difference(dispositions.keys.toSet()).isNotEmpty) {
      throw StateError('Resource migration inventory is incomplete');
    }
    return _ResourceMigrationReport(
      count: count,
      resourceIds: resourceIds,
      sourceDispositions: dispositions,
    );
  }

  _ClassifiedKeys _classifyKeys(Set<String> keys) {
    final profile = <String>{};
    final resource = <String>{};
    final device = <String>{};
    for (final key in keys) {
      if (key.startsWith('p.') ||
          key.startsWith('flutter.') ||
          key.startsWith('firebase_') ||
          key.startsWith('pug_')) {
        continue;
      }
      if (_deviceKeys.contains(key)) {
        device.add(key);
      } else if (_resourceKeys.contains(key)) {
        resource.add(key);
      } else if (_unknownSecretPattern.hasMatch(key)) {
        throw StateError('Unclassified credential-like legacy key: $key');
      } else if (!_obsoleteKeys.contains(key)) {
        profile.add(key);
      }
    }
    return _ClassifiedKeys(
      profile: profile,
      resource: resource,
      device: device,
    );
  }

  Future<List<Map<String, dynamic>>> _copyDatabases(ProfileScope scope) async {
    final root = await AppStorage.documents();
    final out = <Map<String, dynamic>>[];
    for (final name in const <String>['debrify_tv.db', 'iptv_catalog.db']) {
      final source = File(p.join(root.path, name));
      if (!await source.exists()) continue;
      final destination = scope.fileIn(root, 'documents', name);
      await destination.parent.create(recursive: true);
      final temp = File('${destination.path}.migration.tmp');
      if (await temp.exists()) await temp.delete();

      // The legacy services are not mounted while bootstrap runs, but SQLite
      // may still have left committed pages in a WAL after the prior process.
      // Checkpoint and validate the source before taking the byte snapshot.
      final sourceDb = await openDatabase(source.path);
      try {
        await sourceDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        final integrity = await sourceDb.rawQuery('PRAGMA integrity_check');
        if (integrity.isEmpty || integrity.first.values.first != 'ok') {
          throw StateError('$name legacy source failed integrity check');
        }
      } finally {
        await sourceDb.close();
      }
      final sourceBytes = await source.length();
      final sourceHash = await _fileHash(source);
      await source.copy(temp.path);
      final tempHandle = await temp.open(mode: FileMode.append);
      try {
        await tempHandle.flush();
      } finally {
        await tempHandle.close();
      }
      if (await temp.length() != sourceBytes ||
          await _fileHash(temp) != sourceHash) {
        throw StateError('$name database snapshot changed during copy');
      }
      // A checkpointed database can still retain WAL mode in its header. A
      // bare copied image has no matching -wal/-shm files, so SQLite cannot
      // open it read-only (SQLITE_CANTOPEN) even though all committed pages
      // are present. Open the private copy read/write so SQLite may create
      // empty companions for validation; the main-file hash below still
      // proves that the validation did not alter the snapshot.
      final db = await openDatabase(temp.path, singleInstance: false);
      try {
        final integrity = await db.rawQuery('PRAGMA integrity_check');
        if (integrity.isEmpty || integrity.first.values.first != 'ok') {
          throw StateError('$name failed integrity check');
        }
      } finally {
        await db.close();
        for (final suffix in const <String>['-wal', '-shm', '-journal']) {
          final companion = File('${temp.path}$suffix');
          if (await companion.exists()) await companion.delete();
        }
      }
      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);
      final destinationHash = await _fileHash(destination);
      if (await destination.length() != sourceBytes ||
          destinationHash != sourceHash) {
        throw StateError('$name database publication mismatch');
      }
      out.add(<String, dynamic>{
        'name': name,
        'bytes': sourceBytes,
        'sha256': destinationHash,
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _copyFiles(ProfileScope scope) async {
    final root = await AppStorage.documents();
    final source = Directory(p.join(root.path, 'engines'));
    if (!await source.exists()) return const <Map<String, dynamic>>[];
    final destination = scope.storageDirectory(root, 'documents');
    final manifest = <Map<String, dynamic>>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) throw StateError('Symlinks are not migratable');
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root.path);
      final target = File(p.join(destination.path, relative));
      await target.parent.create(recursive: true);
      final sourceBytes = await entity.length();
      final sourceHash = await _fileHash(entity);
      await entity.copy(target.path);
      final targetHandle = await target.open(mode: FileMode.append);
      try {
        await targetHandle.flush();
      } finally {
        await targetHandle.close();
      }
      final targetHash = await _fileHash(target);
      if (await target.length() != sourceBytes || targetHash != sourceHash) {
        throw StateError('Private file changed during migration: $relative');
      }
      manifest.add(<String, dynamic>{
        'path': relative,
        'bytes': sourceBytes,
        'sha256': targetHash,
      });
    }
    return manifest;
  }

  Future<void> _verify({
    required SharedPreferences legacy,
    required ProfilePreferences destination,
    required Set<String> expectedPreferenceKeys,
    required Set<String> expectedResourceSourceKeys,
    required _ResourceMigrationReport resourceReport,
    required List<Map<String, dynamic>> dbManifest,
    required List<Map<String, dynamic>> fileManifest,
  }) async {
    if (!destination.getKeys().containsAll(expectedPreferenceKeys) ||
        expectedPreferenceKeys.any(
          (key) => !_preferenceEquals(destination.get(key), legacy.get(key)),
        )) {
      throw StateError('Preference migration count mismatch');
    }
    for (final key in _resourceKeys) {
      if (destination.containsKey(key)) {
        throw StateError('Credential key escaped into profile preferences');
      }
    }
    if (resourceReport.sourceDispositions.keys
            .toSet()
            .difference(expectedResourceSourceKeys)
            .isNotEmpty ||
        expectedResourceSourceKeys
            .difference(resourceReport.sourceDispositions.keys.toSet())
            .isNotEmpty) {
      throw StateError('Credential migration disposition mismatch');
    }
    for (final id in resourceReport.resourceIds) {
      if (await registry.getResource(id) == null) {
        throw StateError('Migrated credential resource is missing');
      }
    }
    for (final entry in <Map<String, dynamic>>[
      ...dbManifest,
      ...fileManifest,
    ]) {
      final relative = entry['path'] ?? entry['name'];
      if (relative is! String || entry['sha256'] is! String) {
        throw StateError('Invalid migration manifest');
      }
    }
    // An existing install may be represented solely by a database, engine
    // file, or native job store after preferences were cleared. Those sources
    // are inventoried before migration and verified by their own manifests;
    // an empty preference authority is therefore valid, not data loss.
  }

  Future<void> _journal(
    ProfileMigrationStage stage, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) => registry.writeMigrationJournal(
    migrationId: migrationId,
    stage: stage.name,
    payload: payload,
  );

  static Future<void> _copyPreference(
    SharedPreferences source,
    ProfilePreferences destination,
    String key,
  ) async {
    final value = source.get(key);
    final success = switch (value) {
      bool value => await destination.setBool(key, value),
      int value => await destination.setInt(key, value),
      double value => await destination.setDouble(key, value),
      String value => await destination.setString(key, value),
      List<String> value => await destination.setStringList(key, value),
      null => true,
      _ => throw StateError('Unsupported legacy preference type for $key'),
    };
    if (!success) throw StateError('Failed to copy legacy preference $key');
  }

  static Future<String> _fileHash(File file) async {
    final hash = await Sha256().hash(await file.readAsBytes());
    return base64UrlEncode(hash.bytes).replaceAll('=', '');
  }

  static bool _preferenceEquals(Object? left, Object? right) {
    if (left is List<String> && right is List<String>) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (left[index] != right[index]) return false;
      }
      return true;
    }
    return left == right;
  }

  static bool _isTvMazeCacheKey(String key) =>
      key.startsWith('tvmaze_cache_') ||
      key.startsWith('tvmaze_timestamp_') ||
      (key.startsWith('p.') &&
          (key.contains('.tvmaze_cache_') ||
              key.contains('.tvmaze_timestamp_')));

  static int _preferenceFootprint(Object? value) => switch (value) {
    String value => value.length,
    List<String> value => value.fold<int>(0, (sum, item) => sum + item.length),
    _ => 16,
  };

  static final RegExp _unknownSecretPattern = RegExp(
    r'(api.?key|password|access.?token|refresh.?token|credential|secret)',
    caseSensitive: false,
  );

  static const Set<String> _deviceKeys = <String>{
    ...DevicePreferences.nativeLaunchSnapshotKeys,
    'initial_setup_complete_v1',
    'vault_key_source_v1',
    'remote_static_keypair_v1',
    'remote_paired_devices_v1',
    'remote_known_receivers_v1',
    'remote_control_enabled',
    'remote_intro_shown',
    'remote_tv_device_name',
    'remote_last_device',
    'update_auto_check_enabled',
    'update_ignored_version',
    'support_remote_config_cache_v1',
    'dismissed_donation_campaign_ids_v1',
    'recording_max_concurrent',
    'recording_battery_nudge_dismissed_at',
    'iptv_ios_recording_notice_dismissed',
    'desktop_recording_schedules_v1',
    'pending_download_queue_v1',
    'paused_download_queue_v1',
    'download_legacy_queue_imported_v2',
    'download_legacy_plugin_authority_v1',
    'android_download_history_v1',
    'subtitle_custom_fonts',
    'tvos_multi_profile_top_shelf_enabled',
  };

  static const Set<String> _obsoleteKeys = <String>{
    'profiles_runtime_mode_v1',
    'profiles_feature_enabled_v1',
    'profiles_native_mirror_v1',
  };

  static const Set<String> _resourceKeys = <String>{
    'real_debrid_api_key',
    'torbox_api_key',
    'premiumize_api_key',
    'alldebrid_api_key',
    'mdblist_api_key',
    'reddit_access_token',
    'reddit_refresh_token',
    'trakt_access_token',
    'trakt_refresh_token',
    'simkl_access_token',
    'pikpak_email',
    'pikpak_password',
    'pikpak_access_token',
    'pikpak_refresh_token',
    'pikpak_device_id',
    'pikpak_captcha_token',
    'pikpak_user_id',
    'webdav_base_url',
    'webdav_username',
    'webdav_password',
    'webdav_servers_v1',
    'indexer_manager_configs_v1',
    'iptv_playlists',
    'stremio_addons_v1',
  };

  static const Set<String> _scalarResourceKeys = <String>{
    'real_debrid_api_key',
    'torbox_api_key',
    'premiumize_api_key',
    'alldebrid_api_key',
    'mdblist_api_key',
    'reddit_access_token',
    'reddit_refresh_token',
    'trakt_access_token',
    'trakt_refresh_token',
    'simkl_access_token',
    'pikpak_email',
    'pikpak_password',
    'pikpak_access_token',
    'pikpak_refresh_token',
    'pikpak_device_id',
    'pikpak_captcha_token',
    'pikpak_user_id',
    'webdav_base_url',
    'webdav_username',
    'webdav_password',
    'webdav_servers_v1',
  };

  static const Map<String, String> _scalarResourceTargets = <String, String>{
    'real_debrid_api_key': 'resource-legacy-real-debrid',
    'torbox_api_key': 'resource-legacy-torbox',
    'premiumize_api_key': 'resource-legacy-premiumize',
    'alldebrid_api_key': 'resource-legacy-all-debrid',
    'mdblist_api_key': 'resource-legacy-mdblist',
    'reddit_access_token': 'resource-legacy-reddit-quarantine',
    'reddit_refresh_token': 'resource-legacy-reddit-quarantine',
    'trakt_access_token': 'resource-legacy-trakt',
    'trakt_refresh_token': 'resource-legacy-trakt',
    'simkl_access_token': 'resource-legacy-simkl',
    'pikpak_email': 'resource-legacy-pikpak',
    'pikpak_password': 'resource-legacy-pikpak',
    'pikpak_access_token': 'resource-legacy-pikpak',
    'pikpak_refresh_token': 'resource-legacy-pikpak',
    'pikpak_device_id': 'resource-legacy-pikpak',
    'pikpak_captcha_token': 'resource-legacy-pikpak',
    'pikpak_user_id': 'resource-legacy-pikpak',
    'webdav_base_url': 'resource-legacy-webdav-legacy',
    'webdav_username': 'resource-legacy-webdav-legacy',
    'webdav_password': 'resource-legacy-webdav-legacy',
  };
}

class _ResourceMigrationReport {
  final int count;
  final List<String> resourceIds;
  final Map<String, String> sourceDispositions;

  const _ResourceMigrationReport({
    required this.count,
    required this.resourceIds,
    required this.sourceDispositions,
  });
}

class _ClassifiedKeys {
  final Set<String> profile;
  final Set<String> resource;
  final Set<String> device;

  const _ClassifiedKeys({
    required this.profile,
    required this.resource,
    required this.device,
  });
}
