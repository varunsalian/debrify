import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../models/profiles/connection_resource.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../models/profiles/user_profile.dart';
import '../../../utils/app_storage.dart';
import '../../secret_vault.dart';
import '../connection_resource_service.dart';
import '../device_key_provider.dart';
import '../profile_authorization.dart';
import '../profile_cache_ledger.dart';
import '../profile_database_snapshot.dart';
import '../profile_preferences.dart';
import '../profile_registry.dart';
import '../profile_runtime.dart';
import '../profile_scope.dart';

/// DEV-ONLY. A shareable inventory of what every profile actually holds.
///
/// Built to answer the question that cost hours on the IPTV empty-`url` bug —
/// "what keys does this profile's record actually have?" — without shipping a
/// single value to whoever reads the report.
///
/// **No value ever leaves.** Each is replaced by a hash over a salt generated
/// fresh for this export and written nowhere. Within one report identical
/// values collide, so cross-profile duplication is visible; outside it the
/// hashes are noise. Key names that embed an id (`series_source_tt…` names a
/// title someone watched) collapse to a pattern with a count.
///
/// Delete with `lib/services/profiles/dev/` and `lib/screens/profiles/dev/`.
/// [ProfileCacheLedger] is the one part meant to outlive it.
abstract final class ProfileAuditReport {
  static const int schemaVersion = 1;

  /// Keys whose NAME carries user data. Collapsed to the pattern plus a count,
  /// with one hash over the whole collection.
  static final List<({RegExp pattern, String label})> _idBearingKeys = [
    (pattern: RegExp(r'^series_source_.+$'), label: 'series_source_<imdbId>'),
    (
      pattern: RegExp(r'^iptv_hidden_categories_.+$'),
      label: 'iptv_hidden_categories_<catalog>',
    ),
    (pattern: RegExp(r'^engine_.+_.+$'), label: 'engine_<id>_<setting>'),
  ];

  /// Required non-null keys per resource type, taken from each model's
  /// `fromJson`. A granted resource missing one of these is the IPTV bug.
  static const Map<ConnectionResourceType, List<String>> _requiredSecretKeys = {
    ConnectionResourceType.iptvM3u: <String>['name', 'url', 'addedAt'],
    ConnectionResourceType.iptvXtream: <String>['name', 'url', 'addedAt'],
    ConnectionResourceType.stremioAddon: <String>[
      'id',
      'name',
      'manifest_url',
      'base_url',
    ],
  };

  static Future<Map<String, Object?>> collect(ProfileRegistry registry) async {
    final salt = _newSalt();
    final profiles = await registry.listProfiles(includeDisabled: true);
    // Pseudonyms are assigned in registry order and used everywhere a profile
    // id would otherwise appear — including inside scope keys.
    final aliases = <String, String>{
      for (var i = 0; i < profiles.length; i++)
        profiles[i].id: 'profile-${i + 1}',
    };

    final findings = <Map<String, Object?>>[];
    final preferences = <String, Object?>{};
    for (final profile in profiles) {
      preferences[aliases[profile.id]!] = await _preferencesFor(
        profile,
        salt,
        aliases,
        findings,
      );
    }

    final report = <String, Object?>{
      'schemaVersion': schemaVersion,
      'generatedBy': 'debrify-profile-audit',
      'runtime': _runtime(aliases),
      'registry': await registry.privacySafeDiagnostics(),
      'profiles': [for (final p in profiles) _profile(p, aliases)],
      'generations': await _generations(profiles, aliases),
      'preferences': preferences,
      'devicePreferences': await _devicePreferences(salt, findings),
      'resources': await _resources(registry, aliases, findings),
      'stores': await _stores(profiles, aliases),
      'caches': _caches(aliases, findings),
    };
    // Findings last: every section above contributes to them.
    report['findings'] = findings;
    return report;
  }

  static Future<String> collectJson(ProfileRegistry registry) async =>
      const JsonEncoder.withIndent('  ').convert(await collect(registry));

  // ─── sections ────────────────────────────────────────────────────────────

  static Map<String, Object?> _runtime(Map<String, String> aliases) {
    if (!ProfileRuntime.isInitialized) {
      return <String, Object?>{'mode': 'uninitialized'};
    }
    if (!ProfileRuntime.isProfileCommitted) {
      return <String, Object?>{'mode': 'legacyCompatibility'};
    }
    final scope = ProfileRuntime.capture();
    return <String, Object?>{
      'mode': 'committed',
      'activeScope': _aliasScopeKey(ProfileCacheLedger.keyFor(scope), aliases),
      'activeProfile': aliases[scope.profileId] ?? 'unknown',
    };
  }

  static Map<String, Object?> _profile(
    UserProfile profile,
    Map<String, String> aliases,
  ) => <String, Object?>{
    'id': aliases[profile.id],
    'role': profile.role.name,
    'generation': profile.visibleDataGeneration,
    'authorizationRevision': profile.authorizationRevision,
    'lifecycle': profile.lifecycle.name,
    'enabled': profile.isEnabled,
    'setupComplete': profile.setupComplete,
    'hasPin': profile.hasPin,
    'pinResetRequired': profile.pinResetRequired,
    'lockOnResume': profile.lockOnResume,
    'inactivityTimeoutMinutes': profile.inactivityTimeoutMinutes,
    'features': (profile.policy.enabled.map((f) => f.name).toList()..sort()),
    // Names are user-chosen and can identify a household. Length only.
    'nameLength': profile.name.length,
  };

  /// Generations as they exist ON DISK, not as the registry believes.
  ///
  /// The registry has no public per-profile generation query, and adding one
  /// would mean editing a 4000-line security-relevant file for a throwaway
  /// tool. Walking the directories is cheaper AND strictly more informative:
  /// it reports what storage actually holds, so a generation the registry
  /// forgot still shows up. `visible` is derived from the profile row, so a
  /// directory with no matching row reads as `retired-or-orphaned` — which is
  /// exactly the state the 7-day GC is supposed to be clearing.
  static Future<List<Map<String, Object?>>> _generations(
    List<UserProfile> profiles,
    Map<String, String> aliases,
  ) async {
    final out = <Map<String, Object?>>[];
    final documents = await AppStorage.documents();
    for (final profile in profiles) {
      final root = Directory('${documents.path}/profiles/${profile.id}/g');
      if (!await root.exists()) continue;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final generation = int.tryParse(entity.path.split('/').last);
        if (generation == null) continue;
        out.add(<String, Object?>{
          'profile': aliases[profile.id],
          'generation': generation,
          'state': generation == profile.visibleDataGeneration
              ? 'visible'
              : 'retired-or-orphaned',
          'bytes': await _directoryBytes(entity),
          'ageDays': DateTime.now()
              .difference((await entity.stat()).modified)
              .inDays,
        });
      }
    }
    out.sort((a, b) {
      final byProfile = (a['profile']! as String).compareTo(
        b['profile']! as String,
      );
      return byProfile != 0
          ? byProfile
          : (a['generation']! as int).compareTo(b['generation']! as int);
    });
    return out;
  }

  static Future<int> _directoryBytes(Directory directory) async {
    var total = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
    } catch (_) {
      // A partially deleted generation is exactly the thing worth reporting;
      // it must not abort the export.
    }
    return total;
  }

  static Future<List<Map<String, Object?>>> _preferencesFor(
    UserProfile profile,
    List<int> salt,
    Map<String, String> aliases,
    List<Map<String, Object?>> findings,
  ) async {
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      // Inspection only; nothing here is bound to a live session.
      sessionEpoch: 0,
    );
    final prefs = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.diagnosticsReadOnly,
    );

    final plain = <Map<String, Object?>>[];
    final collapsed = <String, List<String>>{};
    for (final key in prefs.getKeys()) {
      final pattern = _idBearingKeys
          .where((entry) => entry.pattern.hasMatch(key))
          .map((entry) => entry.label)
          .firstOrNull;
      if (pattern != null) {
        (collapsed[pattern] ??= <String>[]).add(key);
        continue;
      }
      final value = prefs.get(key);
      final sealed = SecretVault.isSealed(value is String ? value : null);
      if (_looksLikeCredential(key)) {
        findings.add(<String, Object?>{
          'id': 'credential-residue',
          'severity': 'high',
          'profile': aliases[profile.id],
          'detail':
              'credential-shaped key "$key" sits in a profile namespace; '
              'migration converts these to connection resources',
        });
      }
      plain.add(<String, Object?>{
        'key': key,
        'type': _typeOf(value),
        'bytes': _byteLength(value),
        'hash': _hash(salt, value),
        if (sealed) 'sealed': true,
      });
    }

    for (final entry in collapsed.entries) {
      final keys = entry.value..sort();
      plain.add(<String, Object?>{
        'key': entry.key,
        'type': 'collapsed',
        'count': keys.length,
        // One hash over the whole collection: enough to see two profiles
        // holding the same set, without naming a single title.
        'hash': _hash(salt, [for (final k in keys) prefs.get(k)].join(' ')),
      });
    }
    plain.sort((a, b) => (a['key']! as String).compareTo(b['key']! as String));
    return plain;
  }

  static Future<List<Map<String, Object?>>> _devicePreferences(
    List<int> salt,
    List<Map<String, Object?>> findings,
  ) async {
    final device = await DevicePreferences.instance();
    final out = <Map<String, Object?>>[];
    for (final key in DevicePreferences.allowedKeys.toList()..sort()) {
      final value = _readDevicePreference(device, key);
      if (value == null) continue;
      out.add(<String, Object?>{
        'key': key,
        'type': _typeOf(value),
        'hash': _hash(salt, value),
      });
    }
    return out;
  }

  /// Reads a device preference without knowing its type.
  ///
  /// [DevicePreferences] only exposes typed getters, and `getString` on a bool
  /// throws rather than returning null — so chaining `??` across the accessors
  /// crashes on the first non-String key, which on a real device is
  /// `remote_control_enabled`. The allowlist is a schema of names, not of
  /// types, so the reader has to probe.
  static Object? _readDevicePreference(DevicePreferences device, String key) {
    final readers = <Object? Function()>[
      () => device.getString(key),
      () => device.getBool(key),
      () => device.getInt(key),
      () => device.getStringList(key),
    ];
    for (final read in readers) {
      try {
        final value = read();
        if (value != null) return value;
      } catch (_) {
        // Wrong accessor for this key's stored type; try the next.
      }
    }
    return null;
  }

  static Future<List<Map<String, Object?>>> _resources(
    ProfileRegistry registry,
    Map<String, String> aliases,
    List<Map<String, Object?>> findings,
  ) async {
    final out = <Map<String, Object?>>[];
    if (!ProfileRuntime.isProfileCommitted) return out;

    final context = await ProfileAuthorizationContext.capture(registry);
    final service = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final granted = <String>{
      for (final r in await registry.listGrantedResources(context.profileId))
        r.id,
    };

    for (final profile in aliases.keys) {
      for (final resource in await registry.listGrantedResources(profile)) {
        if (out.any((row) => row['id'] == resource.id)) continue;
        final grants = <String, Object?>{};
        for (final other in aliases.keys) {
          final grant = await registry.getGrant(other, resource.id);
          if (grant != null) grants[aliases[other]!] = grant.permissions;
        }

        // Key names only, and only where the ACTIVE profile is authorized.
        // Reading a resource it cannot use would mean bypassing the grant
        // model for a dev convenience.
        List<String>? secretKeys;
        if (granted.contains(resource.id)) {
          try {
            final secret = await service.resolveSecretForUse(
              context: context,
              resourceId: resource.id,
              feature: _featureFor(resource.type),
            );
            secretKeys = secret.keys.toList()..sort();
            final required = _requiredSecretKeys[resource.type];
            if (required != null) {
              final missing = required
                  .where((key) => !secret.containsKey(key))
                  .toList();
              if (missing.isNotEmpty) {
                findings.add(<String, Object?>{
                  'id': 'resource-missing-required-key',
                  'severity': 'high',
                  'resource': resource.id,
                  'type': resource.type.name,
                  'detail':
                      'secret is missing ${missing.join(", ")}, which the '
                      'model casts non-null — one such row throws for the '
                      'whole collection',
                });
              }
            }
          } catch (error) {
            secretKeys = null;
            debugPrint('ProfileAuditReport: secret unreadable ($error)');
          }
        }

        out.add(<String, Object?>{
          'id': resource.id,
          'type': resource.type.name,
          'owner': aliases[resource.ownerProfileId] ?? 'unknown',
          'enabled': resource.enabled,
          'authorizationRevision': resource.authorizationRevision,
          'grants': grants,
          'secretKeysReadable': secretKeys != null,
          if (secretKeys != null) 'secretKeys': secretKeys,
        });
      }
    }
    out.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    return out;
  }

  static Future<List<Map<String, Object?>>> _stores(
    List<UserProfile> profiles,
    Map<String, String> aliases,
  ) async {
    final out = <Map<String, Object?>>[];
    if (!ProfileRuntime.isProfileCommitted) return out;
    final documents = await AppStorage.documents();

    for (final profile in profiles) {
      final scope = ProfileScope(
        profileId: profile.id,
        dataGeneration: profile.visibleDataGeneration,
        sessionEpoch: 0,
      );
      for (final name in ProfileDatabaseSnapshot.databaseNames) {
        final file = scope.fileIn(documents, 'documents', name);
        final row = <String, Object?>{
          'profile': aliases[profile.id],
          'name': name,
        };
        if (!await file.exists()) {
          out.add(row..['health'] = 'absent');
          continue;
        }
        // Opened directly rather than through the scoped services, whose scope
        // machinery would correctly refuse a foreign profile. A WAL-header
        // database can fail read-only when its companions are missing
        // (see 16a8392d), so any failure lands in "unavailable" — a
        // diagnostic must never be the thing that throws.
        Database? database;
        try {
          database = await openDatabase(
            file.path,
            readOnly: true,
            singleInstance: false,
          );
          final check = await database.rawQuery('PRAGMA quick_check');
          row['health'] = check.isNotEmpty && check.first.values.first == 'ok'
              ? 'ok'
              : 'unhealthy';
          row['tables'] = await _tableCounts(database);
        } catch (error) {
          row['health'] = 'unavailable';
          debugPrint('ProfileAuditReport: $name unavailable ($error)');
        } finally {
          await database?.close();
        }
        out.add(row);
      }
    }
    return out;
  }

  static Future<Map<String, Object?>> _tableCounts(Database database) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final counts = <String, Object?>{};
    for (final row in tables) {
      final name = row['name'];
      if (name is! String) continue;
      try {
        final result = await database.rawQuery(
          'SELECT COUNT(*) AS n FROM "$name"',
        );
        counts[name] = (result.single['n'] as num?)?.toInt() ?? 0;
      } catch (_) {
        counts[name] = 'unreadable';
      }
    }
    return counts;
  }

  static List<Map<String, Object?>> _caches(
    Map<String, String> aliases,
    List<Map<String, Object?>> findings,
  ) {
    final active =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileCacheLedger.keyFor(ProfileRuntime.capture())
        : null;
    final out = <Map<String, Object?>>[];
    for (final entry in ProfileCacheLedger.snapshot().entries) {
      final matches = active != null && entry.value == active;
      out.add(<String, Object?>{
        'name': entry.key,
        'warmedFor': _aliasScopeKey(entry.value, aliases),
        'matchesActive': matches,
      });
      if (active != null && !matches) {
        findings.add(<String, Object?>{
          'id': 'cache-scope-stale',
          'severity': 'high',
          'cache': entry.key,
          'detail':
              '${entry.key} holds ${_aliasScopeKey(entry.value, aliases)} '
              'while ${_aliasScopeKey(active, aliases)} is active',
        });
      }
    }
    return out;
  }

  // ─── helpers ─────────────────────────────────────────────────────────────

  static List<int> _newSalt() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  /// First 8 hex of SHA-256(salt ‖ value). Truncated deliberately: enough to
  /// distinguish values within one report, short enough to read in a diff.
  static String _hash(List<int> salt, Object? value) {
    if (value == null) return 'absent';
    final bytes = <int>[...salt, ...utf8.encode(_stringify(value))];
    return sha256.convert(bytes).toString().substring(0, 8);
  }

  static String _stringify(Object value) =>
      value is List ? value.join(' ') : value.toString();

  static String _typeOf(Object? value) => switch (value) {
    null => 'absent',
    bool _ => 'bool',
    int _ => 'int',
    double _ => 'double',
    String _ => 'str',
    List _ => 'list',
    _ => 'other',
  };

  static int _byteLength(Object? value) =>
      value == null ? 0 : utf8.encode(_stringify(value)).length;

  static final RegExp _credentialShaped = RegExp(
    r'(api.?key|password|access.?token|refresh.?token|credential|secret)',
    caseSensitive: false,
  );

  static bool _looksLikeCredential(String key) =>
      _credentialShaped.hasMatch(key);

  /// Replaces real profile ids inside a `p.<id>.g.<n>.e.<n>` scope key.
  static String _aliasScopeKey(String key, Map<String, String> aliases) {
    var out = key;
    for (final entry in aliases.entries) {
      out = out.replaceAll('p.${entry.key}.', 'p.${entry.value}.');
    }
    return out;
  }

  static ProfileFeature _featureFor(ConnectionResourceType type) =>
      switch (type) {
        ConnectionResourceType.iptvM3u ||
        ConnectionResourceType.iptvXtream => ProfileFeature.iptv,
        ConnectionResourceType.stremioAddon => ProfileFeature.addonsAndEngines,
        ConnectionResourceType.jackett ||
        ConnectionResourceType.prowlarr => ProfileFeature.torrentSearch,
        ConnectionResourceType.trakt ||
        ConnectionResourceType.simkl ||
        ConnectionResourceType.mdblist => ProfileFeature.trackersAndDiscovery,
        _ => ProfileFeature.cloud,
      };
}
