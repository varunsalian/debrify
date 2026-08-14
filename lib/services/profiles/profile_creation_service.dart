import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import 'profile_preferences.dart';
import 'profile_authorization.dart';
import 'profile_cleanup_ledger.dart';
import 'profile_data_generation.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

class ProfileCreationService {
  final ProfileRegistry registry;

  const ProfileCreationService(this.registry);

  /// Reviewed value-copy allowlist. It intentionally excludes identity,
  /// secrets, connection state, activity/history, jobs, paths/grants,
  /// the retired onboarding preference, policies, and migration state. The
  /// registry marks the staged profile ready only after its Admin finishes
  /// the creation form.
  static const Set<String> copyablePreferenceKeys = <String>{
    'app_theme',
    'text_brightness',
    'tv_ui_scale_percent',
    'tv_home_style',
    'tv_sidebar_style',
    'desktop_sidebar_style',
    'discover_layout',
    'detail_page_style',
    'detail_theme',
    'parents_guide_style',
    'launch_animation',
    'launch_ident_palette',
    'ui_sounds',
    'ui_haptics',
    'player_start_portrait',
    'player_default_aspect_index_tv',
    'player_night_mode_index',
    'player_system_audio_effects',
    'player_default_subtitle_language',
    'player_default_audio_language',
    'subtitle_auto_sync_enabled',
    'iptv_player_guide_style',
    'recording_engine_enabled',
    'tv_hero_artwork_quality',
  };

  Future<UserProfile> createStaged({
    required ProfileAuthorizationContext actor,
    required String name,
    required UserProfileRole role,
    required ProfilePolicy policy,
    required bool copyDefaultsFromActive,
    String? avatarKey,
  }) async {
    final admin = await actor.validate(registry);
    if (admin.role != UserProfileRole.admin ||
        !admin.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Profile creation requires an Admin');
    }
    final sourceScope = ProfileRuntime.capture();
    final staged = await registry.createProfile(
      name: name,
      role: role,
      policy: policy,
      avatarKey: avatarKey,
      lifecycle: UserProfileLifecycle.staging,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    try {
      if (copyDefaultsFromActive) {
        final source = await ProfilePreferences.forCapturedScope(
          sourceScope,
          CapturedProfilePreferenceAccess.profileCreation,
        );
        final target = await ProfilePreferences.forCapturedScope(
          ProfileScope(
            profileId: staged.id,
            dataGeneration: staged.visibleDataGeneration,
            sessionEpoch: 0,
          ),
          CapturedProfilePreferenceAccess.profileCreation,
        );
        for (final key in copyablePreferenceKeys) {
          await actor.validate(registry);
          await _copyValue(source, target, key);
        }
      }
      await actor.validate(registry);
      return staged;
    } catch (_) {
      await ProfileCleanupLedger.scheduleProfile(staged.id);
      await registry.deleteProfile(staged.id);
      await ProfileDataGenerationManager.deleteAllProfileData(staged.id);
      await ProfileCleanupLedger.completeProfile(staged.id);
      rethrow;
    }
  }

  static Future<void> _copyValue(
    ProfilePreferences source,
    ProfilePreferences target,
    String key,
  ) async {
    final value = source.get(key);
    switch (value) {
      case bool value:
        await target.setBool(key, value);
      case int value:
        await target.setInt(key, value);
      case double value:
        await target.setDouble(key, value);
      case String value:
        await target.setString(key, value);
      case List<String> value:
        await target.setStringList(key, value);
    }
  }
}
