import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/app_storage.dart';
import 'profile_preferences.dart';
import 'native_profile_projection.dart';
import 'device_key_provider.dart';
import 'tvos_profile_recovery_store.dart';
import 'profile_migration_service.dart';
import 'profile_data_generation.dart';
import 'profile_cleanup_ledger.dart';
import 'profile_avatar_mutation.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

/// Establishes exactly one storage mode before any profile-sensitive service
/// is allowed to warm. The registry commit is the authority; preference flags
/// are only repairable mirrors for native/diagnostic readers.
class ProfileBootstrap {
  ProfileBootstrap._();

  static const bool profilesEnabled = bool.fromEnvironment(
    'DEBRIFY_PROFILES',
    defaultValue: true,
  );
  static const bool migrationRolloutReady = bool.fromEnvironment(
    'DEBRIFY_PROFILES_MIGRATION_READY',
    defaultValue: true,
  );

  static const String migratedAdminId = ProfileMigrationService.adminProfileId;
  static const String freshAdminId = 'profile-initial-admin-v1';
  static const String recoveryAdminId = 'profile-recovery-admin-v1';

  static ProfileRegistry? _registry;
  static _LinuxPendingBootstrap? _linuxPending;
  static ProfileRegistry get registry =>
      _registry ?? (throw StateError('ProfileBootstrap is not initialized'));

  @visibleForTesting
  static void debugInstallRegistry(ProfileRegistry? registry) {
    _registry = registry;
  }

  static bool get requiresLinuxVault =>
      Platform.isLinux &&
      (_linuxPending != null ||
          (ProfileRuntime.isInitialized &&
              ProfileRuntime.isProfileCommitted &&
              !DeviceKeyProvider.isUnlocked));

  static bool get linuxVaultAlreadyConfigured =>
      _linuxPending?.hasWrappedKey ??
      (Platform.isLinux &&
          ProfileRuntime.isInitialized &&
          ProfileRuntime.isProfileCommitted);

  static Future<void> initialize({bool? enabled}) async {
    if (ProfileRuntime.isInitialized) return;
    final requested = enabled ?? profilesEnabled;
    final hasRegistry = await ProfileRegistry.defaultRegistryExists();
    final registryCommitted =
        hasRegistry && await ProfileRegistry.defaultAuthorityIsCommitted();
    final tvOsRecovery = await TvOsProfileRecoveryStore.read();
    final device = await DevicePreferences.instance();
    final committedOnce = device.getBool('profiles_committed_once_v1') ?? false;
    final hasAuthority = registryCommitted || tvOsRecovery != null;
    if (committedOnce && !hasAuthority) {
      throw const ProfileBootstrapRecoveryRequired(
        'Committed profile authority is missing; restore or recover the registry',
      );
    }
    if ((!requested || !migrationRolloutReady) && !hasAuthority) {
      ProfileRuntime.initializeLegacy();
      return;
    }

    await DeviceKeyProvider.initialize();

    ProfileRegistry opened;
    try {
      opened = await ProfileRegistry.open();
    } catch (error) {
      if (tvOsRecovery == null) {
        throw ProfileBootstrapRecoveryRequired(
          'The committed profile registry is unreadable',
          cause: error,
        );
      }
      // tvOS keeps the authoritative recovery envelope in device-only
      // Keychain; profiles.db is merely a purgeable cache projection.
      await ProfileRegistry.discardDefaultCacheProjection();
      opened = await ProfileRegistry.open();
    }
    _registry = opened;
    _installAuthorityCallback(opened);
    await ProfileCleanupLedger.resume(opened);
    TvOsProfileRecoveryStore.checkpointCallback = opened.checkpointTvOsRecovery;
    if (tvOsRecovery != null) {
      await opened.importRecoverySnapshot(tvOsRecovery);
    } else if (TvOsProfileRecoveryStore.supported &&
        await opened.isMigrationCommitted()) {
      throw const ProfileBootstrapRecoveryRequired(
        'tvOS profile recovery authority is missing; refusing cache projection',
      );
    }
    if (await opened.isMigrationCommitted()) {
      await ProfileAvatarMutation.recover(opened);
      await opened.recoverInterruptedActivation();
      final interrupted = await opened.recoverInterruptedRestores();
      for (final recovery in interrupted) {
        for (final generation in recovery.abandoned) {
          await ProfileDataGenerationManager.deleteGenerationData(
            generation.profileId,
            generation.generation,
          );
        }
        await opened.completeInterruptedRestoreRecovery(recovery);
      }
      await opened.repairUnambiguousSingletonBindings();
      final retiredCutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      for (final generation in await opened.retiredGenerationsEligibleForGc(
        olderThanMs: retiredCutoff,
      )) {
        await ProfileDataGenerationManager.deleteGenerationData(
          generation.profileId,
          generation.generation,
        );
        await opened.forgetRetiredGeneration(
          generation.profileId,
          generation.generation,
        );
      }
      final active = await opened.activeProfile();
      if (active == null) {
        throw const ProfileBootstrapRecoveryRequired(
          'Committed profile registry has no active profile',
        );
      }
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: active.id,
          dataGeneration: active.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );
      await _repairRuntimeMirror();
      await NativeProfileProjection.publish(ProfileRuntime.capture());
      return;
    }

    // A rollout flag can pause an incomplete candidate, but it must never
    // return an already-committed install to stale legacy data.
    if (!requested || !migrationRolloutReady) {
      await opened.close();
      _registry = null;
      TvOsProfileRecoveryStore.checkpointCallback = null;
      ProfileRuntime.initializeLegacy();
      return;
    }

    await _createOrMigrateInitialAdmin(opened);
  }

  static void _installAuthorityCallback(ProfileRegistry opened) {
    opened.authorityWillChangeCallback = () async {
      if (!ProfileRuntime.isInitialized ||
          !ProfileRuntime.isProfileCommitted ||
          ProfileRuntime.isInMaintenance) {
        return;
      }
      await NativeProfileProjection.invalidate();
    };
    opened.authorityChangedCallback = () async {
      if (!ProfileRuntime.isInitialized ||
          !ProfileRuntime.isProfileCommitted ||
          ProfileRuntime.isInMaintenance) {
        return;
      }
      if (await opened.activationInProgress()) return;
      final scope = ProfileRuntime.capture();
      final active = await opened.activeProfile();
      if (active == null ||
          active.id != scope.profileId ||
          active.visibleDataGeneration != scope.dataGeneration) {
        return;
      }
      await NativeProfileProjection.publish(scope);
    };
  }

  static Future<void> _createOrMigrateInitialAdmin(
    ProfileRegistry registry,
  ) async {
    final legacy = await SharedPreferences.getInstance();
    final legacyKeys = legacy.getKeys().where(_isDebrifyLegacyKey).toSet();
    final isExistingInstall =
        legacyKeys.isNotEmpty ||
        _hasLegacyDeviceJobAuthority(legacy) ||
        await _hasLegacyFileAuthority() ||
        await _hasLegacyNativeJobAuthority();
    if (Platform.isLinux && !DeviceKeyProvider.isUnlocked) {
      _linuxPending = _LinuxPendingBootstrap(
        existingInstall: isExistingInstall,
        hasWrappedKey: await DeviceKeyProvider.linuxHasWrappedKey(),
      );
      await registry.close();
      _registry = null;
      TvOsProfileRecoveryStore.checkpointCallback = null;
      ProfileRuntime.initializeLegacy();
      return;
    }
    if (isExistingInstall) {
      if (!DeviceKeyProvider.isUnlocked) {
        await registry.close();
        _registry = null;
        TvOsProfileRecoveryStore.checkpointCallback = null;
        ProfileRuntime.initializeLegacy();
        return;
      }
      final profile = await ProfileMigrationService(
        registry: registry,
        cipher: DeviceKeyProvider.cipher,
      ).migrate();
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: profile.id,
          dataGeneration: profile.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );
      await _repairRuntimeMirror();
      await NativeProfileProjection.publish(ProfileRuntime.capture());
      return;
    }

    await _createFreshAdmin(registry);
  }

  static Future<bool> _hasLegacyFileAuthority() async {
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
    ];
    final checked = <String>{};
    for (final root in roots) {
      if (!checked.add(root.absolute.path)) continue;
      for (final name in const <String>[
        'debrify_tv.db',
        'iptv_catalog.db',
        'downloads_db_v1.json',
      ]) {
        if (await File('${root.path}${Platform.pathSeparator}$name').exists()) {
          return true;
        }
      }
      final engines = Directory('${root.path}${Platform.pathSeparator}engines');
      if (await engines.exists() &&
          (await engines.list().take(1).toList()).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static bool _hasLegacyDeviceJobAuthority(SharedPreferences legacy) =>
      const <String>{
        'desktop_recording_schedules_v1',
        'pending_download_queue_v1',
        'paused_download_queue_v1',
        'android_download_history_v1',
      }.any((key) => legacy.containsKey(key));

  static Future<bool> _hasLegacyNativeJobAuthority() async {
    if (!Platform.isAndroid) return false;
    final value = await const MethodChannel(
      'com.debrify.app/profile_privacy',
    ).invokeMethod<bool>('hasLegacyProfileAuthority');
    if (value == null) {
      throw StateError('Native profile-authority inventory is unavailable');
    }
    return value;
  }

  static Future<void> _createFreshAdmin(ProfileRegistry registry) async {
    var profile = await registry.getProfile(freshAdminId);
    profile ??= await registry.createProfile(
      id: freshAdminId,
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: false,
      lifecycle: UserProfileLifecycle.staging,
    );
    await registry.commitBootstrap(
      activeProfileId: profile.id,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: profile.id,
        dataGeneration: profile.visibleDataGeneration,
        sessionEpoch: 1,
      ),
    );
    await _repairRuntimeMirror();
    await NativeProfileProjection.publish(ProfileRuntime.capture());
  }

  /// Establishes an empty, explicit recovery Admin after bootstrap has proved
  /// that the committed registry cannot be mounted. The unusable SQLite family
  /// is quarantined, never deleted. No legacy preference or file is mounted or
  /// migrated by this path.
  static Future<ProfileRegistry> initializeRecoveryAuthority({
    String? linuxVaultPassphrase,
  }) async {
    if (ProfileRuntime.isInitialized) {
      if (ProfileRuntime.isProfileCommitted && _registry != null) {
        return _registry!;
      }
      throw StateError('Recovery authority requires an uninitialized runtime');
    }

    final openedBeforeFailure = _registry;
    _registry = null;
    TvOsProfileRecoveryStore.checkpointCallback = null;
    if (openedBeforeFailure != null) await openedBeforeFailure.close();

    await DeviceKeyProvider.initialize();
    if (Platform.isLinux && !DeviceKeyProvider.isUnlocked) {
      final passphrase = linuxVaultPassphrase;
      if (passphrase == null || passphrase.isEmpty) {
        throw StateError(
          'The Linux device vault must be unlocked for recovery',
        );
      }
      if (await DeviceKeyProvider.linuxHasWrappedKey()) {
        await DeviceKeyProvider.unlockLinuxVault(passphrase);
      } else {
        await DeviceKeyProvider.createLinuxVault(passphrase);
      }
    }

    await ProfileRegistry.quarantineDefaultProjection();
    final opened = await ProfileRegistry.open();
    _registry = opened;
    _installAuthorityCallback(opened);
    TvOsProfileRecoveryStore.checkpointCallback = opened.checkpointTvOsRecovery;
    var profile = await opened.getProfile(recoveryAdminId);
    profile ??= await opened.createProfile(
      id: recoveryAdminId,
      name: 'Recovery Admin',
      role: UserProfileRole.admin,
      setupComplete: false,
      lifecycle: UserProfileLifecycle.staging,
    );
    await opened.commitBootstrap(
      activeProfileId: profile.id,
      migratedLegacyInstall: false,
      migrationPayload: const <String, Object?>{'recoveryAuthority': true},
    );
    profile = (await opened.getProfile(profile.id))!;
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    await _repairRuntimeMirror();
    await NativeProfileProjection.publish(scope);
    return opened;
  }

  /// Completes the interactive Linux bootstrap without exposing a partially
  /// migrated profile tree. The app child has not mounted while this runs.
  static Future<void> completeLinuxVault(String passphrase) async {
    if (!Platform.isLinux) throw UnsupportedError('Linux only');
    if (!DeviceKeyProvider.isUnlocked) {
      if (await DeviceKeyProvider.linuxHasWrappedKey()) {
        await DeviceKeyProvider.unlockLinuxVault(passphrase);
      } else {
        await DeviceKeyProvider.createLinuxVault(passphrase);
      }
    }
    final pending = _linuxPending;
    if (pending == null) return;
    final opened = await ProfileRegistry.open();
    _registry = opened;
    _installAuthorityCallback(opened);
    TvOsProfileRecoveryStore.checkpointCallback = opened.checkpointTvOsRecovery;
    UserProfile profile;
    if (pending.existingInstall) {
      profile = await ProfileMigrationService(
        registry: opened,
        cipher: DeviceKeyProvider.cipher,
      ).migrate();
    } else {
      var created = await opened.getProfile(freshAdminId);
      created ??= await opened.createProfile(
        id: freshAdminId,
        name: 'Admin',
        role: UserProfileRole.admin,
        setupComplete: false,
        lifecycle: UserProfileLifecycle.staging,
      );
      await opened.commitBootstrap(
        activeProfileId: created.id,
        migratedLegacyInstall: false,
      );
      profile = (await opened.getProfile(created.id))!;
    }
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: 1,
    );
    ProfileRuntime.promoteLegacyToCommitted(scope);
    _linuxPending = null;
    await _repairRuntimeMirror();
    await NativeProfileProjection.publish(scope);
  }

  static bool _isDebrifyLegacyKey(String key) {
    if (key.startsWith('p.')) return false;
    if (_deviceOwnedLegacyKeys.contains(key)) return false;
    // Plugin-owned values are not part of Debrify's profile namespace.
    if (key.startsWith('flutter.') ||
        key.startsWith('firebase_') ||
        key.startsWith('pug_')) {
      return false;
    }
    return true;
  }

  static const Set<String> _deviceOwnedLegacyKeys = <String>{
    ...DevicePreferences.nativeLaunchSnapshotKeys,
    'profiles_runtime_mode_v1',
    'profiles_feature_enabled_v1',
    'profiles_native_mirror_v1',
    'app_onboarding_complete_v1',
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

  static Future<void> _repairRuntimeMirror() async {
    final device = await DevicePreferences.instance();
    await device.setString('profiles_runtime_mode_v1', 'profileCommitted');
    await device.setBool('profiles_committed_once_v1', true);
    await device.setBool('profiles_feature_enabled_v1', true);
  }

  static Future<void> close() async {
    final opened = _registry;
    _registry = null;
    if (opened != null) await opened.close();
    TvOsProfileRecoveryStore.checkpointCallback = null;
  }
}

class ProfileBootstrapRecoveryRequired implements Exception {
  final String message;
  final Object? cause;

  const ProfileBootstrapRecoveryRequired(this.message, {this.cause});

  @override
  String toString() => message;
}

class _LinuxPendingBootstrap {
  final bool existingInstall;
  final bool hasWrappedKey;

  const _LinuxPendingBootstrap({
    required this.existingInstall,
    required this.hasWrappedKey,
  });
}
