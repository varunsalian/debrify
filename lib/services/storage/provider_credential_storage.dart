import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/webdav_storage.dart';

final class ProviderCredentialStorage {
  const ProviderCredentialStorage._();
  static const String _onboardingCompleteKey = 'initial_setup_complete_v1';

  /// Manual binding reads retain the initiating action across preferences,
  /// resource routing and lazy legacy credential migration.
  // Shared within lib/services/storage/.
  static Future<String?> readCurrentProviderCredential(
    String key,
    bool Function() canContinue, {
    required bool forRemoteTransfer,
  }) => ProfileRuntime.withoutCapturedScope(() async {
    if (!canContinue()) return null;
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        key,
      );
      if (!canContinue()) return null;
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    if (!canContinue()) return null;
    return SecretVault.getString(prefs, key, canContinue: canContinue);
  });

  // Shared within lib/services/storage/.
  static Future<bool> credentialConfigured(
    String key,
    Future<String?> Function() legacyRead, {
    bool Function()? canContinue,
  }) async {
    bool current() => canContinue?.call() ?? true;
    if (!current()) return false;
    final presence = await ProfileCredentialFacade.isConfigured(key);
    if (!current()) return false;
    if (presence.handled) return presence.configured;
    String? value;
    if (canContinue == null) {
      value = await legacyRead();
    } else {
      final prefs = await ProfilePreferences.instance();
      if (!current()) return false;
      value = await SecretVault.getString(prefs, key, canContinue: canContinue);
    }
    return current() && value != null && value.isNotEmpty;
  }

  static Future<bool> isInitialSetupComplete() async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      return prefs.getBool(_onboardingCompleteKey) ?? false;
    }

    final scope = ProfileRuntime.capture();
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (profile == null || !profile.isEnabled || profile.visibleDataGeneration != scope.dataGeneration) {
      throw StateError('Active profile onboarding state is unavailable');
    }

    // Builds that first introduced profiles wrote onboarding state to two
    // places. Honor an explicitly stored value once (notably `false` from a
    // profile reset), reconcile it into the registry, then remove the
    // compatibility value. If the key is absent, the registry was already
    // correct for migrated Admins and Admin-created profiles.
    if (!prefs.containsKey(_onboardingCompleteKey)) {
      return profile.setupComplete;
    }
    final compatibilityValue = prefs.getBool(_onboardingCompleteKey);
    if (compatibilityValue == null) {
      throw const FormatException('Invalid onboarding completion state');
    }
    if (compatibilityValue != profile.setupComplete) {
      final authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      if (ProfileRuntime.capture() != scope || authorization.profileId != scope.profileId) {
        throw StateError('Active profile onboarding session has changed');
      }
      await ProfileBootstrap.registry.setActiveProfileSetupComplete(
        profileId: authorization.profileId,
        setupComplete: compatibilityValue,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
    }
    if (!await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    return compatibilityValue;
  }

  static Future<void> setInitialSetupComplete(bool value) async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      await prefs.setBool(_onboardingCompleteKey, value);
      return;
    }

    final authorization = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await authorization.validate(ProfileBootstrap.registry);
    // Remove the retired compatibility value before the canonical write. If
    // authority changes, the stale scoped wrapper fails and no other profile
    // can be mutated. A later retry safely starts from the registry value.
    if (prefs.containsKey(_onboardingCompleteKey) && !await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    if (profile.setupComplete == value) return;
    await ProfileBootstrap.registry.setActiveProfileSetupComplete(
      profileId: authorization.profileId,
      setupComplete: value,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
  }

  /// Clear integration enabled states (RD, TorBox)
  static Future<void> clearAllIntegrationStates() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(RealDebridStorage.realDebridIntegrationEnabledKey);
    await prefs.remove(RealDebridStorage.realDebridHiddenFromNavKey);
    await prefs.remove(TorboxStorage.torboxIntegrationEnabledKey);
    await prefs.remove(TorboxStorage.torboxHiddenFromNavKey);
    await prefs.remove(PremiumizeStorage.premiumizeIntegrationEnabledKey);
    await prefs.remove(PremiumizeStorage.premiumizeHiddenFromNavKey);
    await prefs.remove(AllDebridStorage.allDebridIntegrationEnabledKey);
    await prefs.remove(AllDebridStorage.allDebridHiddenFromNavKey);
    await prefs.remove(WebdavStorage.webDavEnabledKey);
    await prefs.remove(WebdavStorage.webDavHiddenFromNavKey);
  }

  /// Clear post-torrent action preferences
  static Future<void> clearAllPostTorrentActions() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(RealDebridStorage.postTorrentActionKey);
    await prefs.remove(TorboxStorage.torboxPostTorrentActionKey);
    await prefs.remove(PikpakStorage.pikpakPostTorrentActionKey);
    await prefs.remove(PremiumizeStorage.premiumizePostTorrentActionKey);
    await prefs.remove(AllDebridStorage.allDebridPostTorrentActionKey);
  }
}
