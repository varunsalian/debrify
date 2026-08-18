import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import 'connection_resource_service.dart';
import 'profile_collection_resource_facade.dart';
import 'profile_preferences.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

/// Publishes the native readers' active-profile view as one JSON value.
///
/// Android activities and services cannot safely reconstruct generation keys,
/// and reading many independently updated mirrors would expose mixed profile
/// state. A single SharedPreferences string gives native code an atomic
/// revisioned snapshot while `profiles.db` remains authoritative.
class NativeProfileProjection {
  NativeProfileProjection._();

  static const String deviceKey = 'profiles_native_projection_v1';
  static const String sequenceKey = 'profiles_native_projection_sequence_v1';
  static Future<void> _publicationQueue = Future<void>.value();
  @visibleForTesting
  static Future<void> Function(int publication)? debugAfterInvalidation;
  @visibleForTesting
  static Future<void> Function()? debugBeforeAddonRead;
  static const MethodChannel _privacyChannel = MethodChannel(
    'com.debrify.app/profile_privacy',
  );

  static const Set<String> logicalKeys = <String>{
    'tv_trailer_underlay_enabled',
    'tv_ui_scale_percent',
    'tv_low_res_render',
    'recording_engine_enabled',
    'iptv_player_guide_style',
    'subtitle_auto_sync_enabled',
    'player_default_aspect_index_tv',
    'player_night_mode_index',
    'player_system_audio_effects',
    'skip_segments_enabled',
    'skip_segment_provider',
    'player_default_subtitle_language',
    'player_default_audio_language',
  };

  static Future<void> publish(
    ProfileScope scope,
  ) => _serializePublication(() async {
    // Build the complete snapshot inside the publication queue. If an older
    // build were allowed to await registry reads outside this queue, it
    // could finish after a newer mutation and overwrite the newer native
    // authority with a stale but higher publication sequence.
    final profile = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.nativeProjectionReadOnly,
    );
    final values = <String, Object?>{};
    for (final key in logicalKeys) {
      final value = profile.get(key);
      if (value is bool ||
          value is int ||
          value is double ||
          value is String ||
          value is List<String>) {
        values[key] = value;
      }
    }
    // Stremio addons stopped being preferences when profiles made connection
    // resources authoritative. The native Android TV subtitle service still
    // consumes the collection from this atomic projection, so reconstruct its
    // compatibility JSON from the active profile's authorized resources.
    // Reading the old preference here produced no value after migration and
    // made the native player believe every subtitle addon had disappeared.
    if (ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        ProfileRuntime.scope.value == scope) {
      List<Map<String, dynamic>> addons;
      try {
        addons = await ProfileRuntime.withCapturedScope(scope, () async {
          await debugBeforeAddonRead?.call();
          return ProfileCollectionResourceFacade.read(
            types: const <ConnectionResourceType>{
              ConnectionResourceType.stremioAddon,
            },
            feature: ProfileFeature.addonUse,
          );
        });
      } on ResourceAuthorizationException {
        // Addon denial is a valid profile policy, not a failure to publish
        // native authority. Invalidation precedes publication, so allowing
        // this exception out would revoke every unrelated native preference
        // until another successful publication happened.
        addons = const <Map<String, dynamic>>[];
      }
      values['stremio_addons_v1'] = jsonEncode(
        addons.map(_nativeAddonRecord).toList(growable: false),
      );
    }
    final raw = await SharedPreferences.getInstance();
    final authorization = <String, Object?>{};
    int? activeAuthorizationRevision;
    for (final item in await ProfileBootstrap.registry.listProfiles(
      includeDisabled: true,
    )) {
      final resources = <String, Object?>{};
      for (final resource
          in await ProfileBootstrap.registry.listGrantedResources(item.id)) {
        if (resource.enabled) {
          final grant = await ProfileBootstrap.registry.getGrant(
            item.id,
            resource.id,
          );
          if (grant != null) {
            resources[resource.id] = <String, Object?>{
              'revision': resource.authorizationRevision,
              'permissions': grant.permissions,
            };
          }
        }
      }
      authorization[item.id] = <String, Object?>{
        'enabled': item.isEnabled,
        'revision': item.authorizationRevision,
        'features': item.policy.enabled.map((feature) => feature.name).toList(),
        'resources': resources,
      };
      if (item.id == scope.profileId) {
        activeAuthorizationRevision = item.authorizationRevision;
      }
    }
    if (Platform.isAndroid && scope.profileId == 'legacy-admin-v1') {
      final revision = activeAuthorizationRevision;
      if (revision == null ||
          await _privacyChannel.invokeMethod<bool>(
                'migrateLegacyProfileAuthority',
                <String, Object>{
                  'profileId': scope.profileId,
                  'authorizationRevision': revision,
                },
              ) !=
              true) {
        throw StateError('Android legacy job migration did not complete');
      }
    }
    // Resource decryption above is explicitly zone-bound to [scope]. Refuse
    // to attach those results to a snapshot if the process-global active
    // scope changed while any asynchronous read was in flight. The switch's
    // own publication will build the replacement snapshot.
    if (ProfileRuntime.scope.value != scope) {
      throw StateError('Profile scope changed during native publication');
    }
    final projection = <String, Object?>{
      'version': 2,
      'state': 'active',
      'profileId': scope.profileId,
      'dataGeneration': scope.dataGeneration,
      'sessionEpoch': scope.sessionEpoch,
      'authorization': authorization,
      'values': values,
    };
    final sequence = (raw.getInt(sequenceKey) ?? 0) + 1;
    projection['publication'] = sequence;
    // Sequence is the native reader's monotonic visibility authority. It is
    // advanced first, so a crash or failed JSON write makes the previous
    // snapshot stale and therefore denied rather than leaving it valid.
    if (!await raw.setInt(sequenceKey, sequence)) {
      throw StateError('Could not invalidate previous native profile view');
    }
    await debugAfterInvalidation?.call(sequence);
    if (!await raw.setString(deviceKey, jsonEncode(projection))) {
      throw StateError('Could not publish native profile view');
    }
  });

  /// Converts both canonical addon secrets and URL-only restore records into
  /// the one compatibility shape understood by Android's native player.
  ///
  /// Backup and remote-transfer restores intentionally persist only the
  /// manifest URL. Flutter hydrates those records before using them, but the
  /// native projection reads the authoritative resource directly. Retaining a
  /// normalized manifest URL here lets native perform the same hydration
  /// without making projection publication network-dependent.
  static Map<String, Object?> _nativeAddonRecord(Map<String, dynamic> addon) {
    final rawManifest = addon['manifest_url'] ?? addon['manifestUrl'];
    final manifestUrl = rawManifest is String ? rawManifest.trim() : '';
    final rawBaseUrl = addon['base_url'] ?? addon['baseUrl'];
    var baseUrl = rawBaseUrl is String ? rawBaseUrl.trim() : '';
    if (baseUrl.isEmpty && manifestUrl.endsWith('/manifest.json')) {
      baseUrl = manifestUrl.substring(
        0,
        manifestUrl.length - '/manifest.json'.length,
      );
    }
    List<String> stringList(Object? raw, {bool resourceNames = false}) {
      if (raw is! List) return const <String>[];
      return <String>[
        for (final value in raw)
          if (value is String)
            value
          else if (resourceNames && value is Map && value['name'] is String)
            value['name'] as String,
      ];
    }

    final id = addon['id']?.toString().trim();
    final rawName = addon['name']?.toString().trim();
    final host = Uri.tryParse(manifestUrl)?.host ?? '';
    return <String, Object?>{
      'id': id?.isNotEmpty == true ? id! : manifestUrl,
      'name': rawName?.isNotEmpty == true
          ? rawName!
          : (host.isNotEmpty ? host : 'Stremio addon'),
      'manifest_url': manifestUrl,
      'base_url': baseUrl,
      'resources': stringList(addon['resources'], resourceNames: true),
      'types': stringList(addon['types']),
      'enabled': addon['enabled'] is bool ? addon['enabled']! as bool : true,
    };
  }

  /// Invalidates native authority before a registry mutation or profile
  /// switch can reduce it. A later [publish] rolls forward to a complete
  /// snapshot; failure leaves native readers safely denied.
  static Future<void> invalidate() => _serializePublication(() async {
    final raw = await SharedPreferences.getInstance();
    final sequence = (raw.getInt(sequenceKey) ?? 0) + 1;
    if (!await raw.setInt(sequenceKey, sequence)) {
      throw StateError('Could not invalidate native profile authority');
    }
    await raw.setString(
      deviceKey,
      jsonEncode(<String, Object?>{
        'version': 2,
        'state': 'denied',
        'publication': sequence,
      }),
    );
  });

  static Future<T> _serializePublication<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _publicationQueue = _publicationQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<void> clear() => _serializePublication(() async {
    final raw = await SharedPreferences.getInstance();
    final sequence = (raw.getInt(sequenceKey) ?? 0) + 1;
    if (!await raw.setInt(sequenceKey, sequence)) {
      throw StateError('Could not revoke native profile authority');
    }
    await raw.remove(deviceKey);
  });

  /// Clears both the published native view and native-only migration state.
  /// The latter is stored outside Flutter's SharedPreferences namespace and
  /// must not survive a full device reset.
  static Future<void> clearDeviceAuthorities() async {
    if (Platform.isAndroid &&
        await _privacyChannel.invokeMethod<bool>(
              'clearLegacyProfileMigrationMarker',
            ) !=
            true) {
      throw StateError('Could not clear Android profile migration authority');
    }
    await clear();
  }
}
