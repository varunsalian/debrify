import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/profile_setup_flow.dart';
import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/screens/settings/profiles_settings_page.dart';
import 'package:debrify/screens/settings/sync_and_migrate_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsProfileActions {
  SettingsProfileActions(this._summaries, this._deps);
  final ({
    Future<bool> Function() activeProfileMayExportDiagnostics,
    Future<void> Function() loadSummaries,
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;
  final SettingsSummaries _summaries;

  /// Opens the Profiles hub (roster + switch + create). The bare
  /// switch-picker call moved onto the hub itself.
  Future<void> switchProfile() async {
    final context = _deps.context();
    await pushSettingsPage(context, const ProfilesSettingsPage());
    if (!context.mounted) return;
    final diagnosticExportVisible = await _deps
        .activeProfileMayExportDiagnostics();
    if (!context.mounted) return;
    _deps.setState(
      () => _summaries.diagnosticExportVisible = diagnosticExportVisible,
    );
  }

  /// The admin check the hub applies before its Create/Manage rows — the
  /// Profiles card's action rows share it, but answer with a spoken refusal
  /// instead of hiding: a card whose rows come and go with who is signed in
  /// reads as broken, not as policy.
  Future<bool> mayManageProfiles() async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    UserProfile? actor;
    try {
      actor = await authorization.validate(registry);
    } catch (_) {
      actor = null;
    }
    return actor != null &&
        actor.role == UserProfileRole.admin &&
        actor.allows(ProfileFeature.manageProfiles);
  }

  void profilesDenied(String action) {
    if (!_deps.mounted()) return;
    final context = _deps.context();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Only an admin can $action profiles.')),
    );
  }

  /// The Profiles card's "Add a profile" row — the hub's create flow without
  /// the detour through the hub.
  Future<void> addProfile() async {
    if (!await mayManageProfiles()) {
      profilesDenied('add');
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await ProfileSetupFlow.show(context);
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  /// The Profiles card's "Edit this profile" row — straight into the ACTIVE
  /// profile's editor, matching the hub's active-card Edit button.
  Future<void> editActiveProfile() async {
    final registry = ProfileBootstrap.registry;
    if (!await mayManageProfiles()) {
      profilesDenied('edit');
      return;
    }
    final profiles = await registry.listProfiles();
    final activeId = ProfileRuntime.capture().profileId;
    UserProfile? active;
    for (final profile in profiles) {
      if (profile.id == activeId) {
        active = profile;
        break;
      }
    }
    if (active == null) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await ProfileSetupFlow.show(context, profile: active);
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  /// Route checks are defense in depth; services still validate their own
  /// capabilities. Keeping this helper fail-closed also protects search/deep
  /// links that call an opener while a policy edit is propagating.
  Future<bool> ensureProfileFeature(ProfileFeature feature) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return true;
    }
    var allowed = false;
    try {
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      allowed = actor.allows(feature);
    } catch (_) {
      allowed = false;
    }
    if (!allowed && _deps.mounted()) {
      final context = _deps.context();
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This feature is disabled for this profile.'),
        ),
      );
    }
    return allowed;
  }

  Future<void> createProfileBackup() =>
      ProfileBackupFlows(_deps.context()).createProfileBackup();

  Future<void> restoreProfileBackup() async {
    final context = _deps.context();
    await ProfileBackupFlows(
      context,
      onRestored: () async {
        await _deps.loadSummaries();
        MainPageBridge.notifyIntegrationChanged();
      },
    ).restoreProfileBackup();
  }

  Future<void> openSyncAndMigrate() async {
    if (ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      if (_deps.mounted()) {
        final context = _deps.context();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sync and Migrate becomes available after Profiles setup.',
            ),
          ),
        );
      }
      return;
    }
    if (!await ensureProfileFeature(ProfileFeature.backupRestore)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const SyncAndMigratePage());
  }
}
