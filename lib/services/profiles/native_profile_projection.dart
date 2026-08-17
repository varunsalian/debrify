import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_preferences.dart';
import 'profile_bootstrap.dart';
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
    'stremio_addons_v1',
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
