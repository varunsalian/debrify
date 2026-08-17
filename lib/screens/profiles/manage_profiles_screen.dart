import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_data_generation.dart';
import '../../services/profiles/profile_cleanup_ledger.dart';
import '../../services/profiles/profile_diagnostics_service.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_registry.dart';
import '../../services/profiles/native_profile_projection.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/live_recording_service.dart';
import '../../services/tvos_top_shelf_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
// DEV-ONLY, delete with lib/{services,screens}/profiles/dev/.
import '../../services/profiles/dev/profile_audit_flag.dart';
import 'dev/profile_data_screen.dart';
import 'edit_profile_screen.dart';

class ManageProfilesScreen extends StatefulWidget {
  final ProfileRegistry registry;
  final ProfileAuthorizationContext authorization;

  const ManageProfilesScreen({
    super.key,
    required this.registry,
    required this.authorization,
  });

  @override
  State<ManageProfilesScreen> createState() => _ManageProfilesScreenState();
}

class _ManageProfilesScreenState extends State<ManageProfilesScreen> {
  late final ProfilePinService _pins = ProfilePinService(
    registry: widget.registry,
  );
  late ProfileAuthorizationContext _authorization = widget.authorization;
  List<UserProfile>? _profiles;
  bool _topShelfEnabled = false;
  bool _initialLoadFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialLoad());
  }

  Future<void> _initialLoad() async {
    try {
      await _load();
    } catch (_) {
      if (mounted) setState(() => _initialLoadFailed = true);
    }
  }

  Future<void> _load() async {
    final actor = await _authorization.validate(widget.registry);
    if (!actor.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Profile management is not authorized');
    }
    final profiles = await widget.registry.listProfiles(includeDisabled: true);
    final topShelfEnabled = PlatformUtil.isTvOS
        ? await TvosTopShelfService.instance
              .multiProfilePersonalizationEnabled()
        : false;
    await NativeProfileProjection.publish(ProfileRuntime.capture());
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _topShelfEnabled = topShelfEnabled;
      });
    }
  }

  void Function(String) _runProfileAction(UserProfile profile) => (action) {
    if (action == 'edit') _edit(profile);
    if (action == 'delete') _delete(profile);
    if (action == 'toggle') _toggleEnabled(profile);
  };

  /// TV replacement for the popup trailing: selecting a row opens its
  /// actions as a DPAD-navigable dialog.
  Future<void> _showProfileActions(UserProfile profile) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(profile.name),
        children: [
          if (profile.isEnabled)
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () => Navigator.of(dialogContext).pop('edit'),
            ),
          ListTile(
            autofocus: !profile.isEnabled,
            leading: Icon(
              profile.isEnabled
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
            ),
            title: Text(profile.isEnabled ? 'Disable' : 'Enable'),
            onTap: () => Navigator.of(dialogContext).pop('toggle'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Delete'),
            onTap: () => Navigator.of(dialogContext).pop('delete'),
          ),
        ],
      ),
    );
    if (action != null) _runProfileAction(profile)(action);
  }

  Future<void> _edit([UserProfile? profile]) async {
    try {
      final initiatingProfileId = _authorization.profileId;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EditProfileScreen(
            registry: widget.registry,
            pins: _pins,
            authorization: _authorization,
            profile: profile,
          ),
        ),
      );
      final refreshed = await ProfileAuthorizationContext.capture(
        widget.registry,
      );
      if (refreshed.profileId != initiatingProfileId) {
        throw StateError('Managing profile session changed');
      }
      await _validateManagingAdmin(refreshed);
      _authorization = refreshed;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile editor session expired')),
      );
    }
  }

  Future<void> _delete(UserProfile profile) async {
    late final ProfileDeletionDependencies dependencies;
    late final ProfileAuthorizationContext operationActor;
    try {
      operationActor = _authorization;
      await _validateManagingAdmin(operationActor);
      dependencies = await widget.registry.deletionDependencies(profile.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile deletion is not authorized')),
      );
      return;
    }
    if (!mounted) return;
    var deleteConnections = dependencies.ownedResources == 0;
    var revokeShares = false;
    var retainPublicFiles = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Delete ${profile.name}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active jobs: ${dependencies.activeJobs}\n'
                  'Owned connections: ${dependencies.ownedResources}'
                  '${dependencies.sharedResources == 0 ? '' : ' (${dependencies.sharedResources} shared)'}\n'
                  'Public media records: ${dependencies.publicArtifacts}',
                ),
                if (dependencies.activeJobs > 0)
                  const Text('\nFinish or cancel active jobs before deletion.'),
                if (dependencies.sharedResources > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: revokeShares,
                    title: Text(
                      'Revoke shared access '
                      '(${dependencies.sharedResources} connection'
                      '${dependencies.sharedResources == 1 ? '' : 's'})',
                    ),
                    subtitle: const Text(
                      'Other profiles lose access to the connections this '
                      'profile shares; connections they own themselves are '
                      'untouched.',
                    ),
                    onChanged: (value) => setDialogState(() {
                      revokeShares = value == true;
                      // Revoked shares leave the resources unshared —
                      // orphaning them isn't an option, so they go too.
                      if (revokeShares) deleteConnections = true;
                    }),
                  ),
                if (dependencies.ownedResources > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteConnections,
                    title: const Text('Delete unshared owned connections'),
                    onChanged: dependencies.sharedResources > 0
                        ? null
                        : (value) => setDialogState(
                            () => deleteConnections = value == true,
                          ),
                  ),
                if (dependencies.publicArtifacts > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: retainPublicFiles,
                    title: const Text('Keep downloaded and recorded files'),
                    subtitle: Text(
                      retainPublicFiles
                          ? 'Ownership is detached; files stay on this device.'
                          : 'Files are permanently deleted before the profile.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => retainPublicFiles = value == true),
                  ),
                const Text(
                  '\nPrivate settings, history, and databases are deleted.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  dependencies.activeJobs == 0 &&
                      (dependencies.sharedResources == 0 || revokeShares) &&
                      deleteConnections
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Delete profile'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _validateManagingAdmin(operationActor);
      if (revokeShares) {
        await widget.registry.revokeGrantsOnOwnedResources(
          ownerProfileId: profile.id,
          actingProfileId: operationActor.profileId,
          actingAuthorizationRevision: operationActor.authorizationRevision,
          actingSessionEpoch: operationActor.sessionEpoch,
        );
        // The delete transaction re-verifies shared == 0, so a racing
        // re-grant safely re-blocks rather than slipping through.
      }
      if (!retainPublicFiles) {
        final artifacts = await widget.registry.listOwnedArtifacts(profile.id);
        for (final artifact in artifacts) {
          final path = artifact['canonical_path']! as String;
          final deleted = Platform.isAndroid && path.contains('://')
              ? await LiveRecordingService.deleteRecordingFile(path)
              : await _deleteLocalArtifact(path);
          if (!deleted) {
            throw StateError('Could not delete a public media file');
          }
        }
        await _validateManagingAdmin(operationActor);
        await widget.registry.removeOwnedArtifactRecords(
          ownerProfileId: profile.id,
          actingProfileId: operationActor.profileId,
          actingAuthorizationRevision: operationActor.authorizationRevision,
          actingSessionEpoch: operationActor.sessionEpoch,
        );
      }
      await _validateManagingAdmin(operationActor);
      await ProfileCleanupLedger.scheduleProfile(profile.id);
      await _validateManagingAdmin(operationActor);
      await widget.registry.deleteProfileWithDisposition(
        id: profile.id,
        deleteOwnedResources: deleteConnections,
        detachPublicArtifacts: retainPublicFiles,
        actingProfileId: operationActor.profileId,
        actingAuthorizationRevision: operationActor.authorizationRevision,
        actingSessionEpoch: operationActor.sessionEpoch,
      );
      await ProfileDataGenerationManager.deleteAllProfileData(profile.id);
      await ProfileCleanupLedger.completeProfile(profile.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile deletion failed')));
    }
  }

  Future<bool> _deleteLocalArtifact(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggleEnabled(UserProfile profile) async {
    try {
      final actor = _authorization;
      await _validateManagingAdmin(actor);
      if (profile.isEnabled) {
        await widget.registry.disableProfile(
          profile.id,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
      } else {
        await widget.registry.enableProfile(
          profile.id,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile status could not be changed')),
      );
    }
  }

  Future<UserProfile> _validateManagingAdmin(
    ProfileAuthorizationContext context,
  ) async {
    final actor = await context.validate(widget.registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Profile management is not authorized');
    }
    return actor;
  }

  Future<void> _setTopShelfEnabled(bool enabled) async {
    try {
      await TvosTopShelfService.instance.setMultiProfilePersonalizationEnabled(
        enabled,
      );
      if (mounted) setState(() => _topShelfEnabled = enabled);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Top Shelf setting could not be changed')),
      );
    }
  }

  /// DEV-ONLY. Opens the per-profile key/value browser.
  Future<void> _openProfileData() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileDataScreen(registry: widget.registry),
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    final report = await ProfileDiagnosticsService.collectJson(widget.registry);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profile diagnostics'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Privacy-safe diagnostics',
            onPressed: profiles == null ? null : _showDiagnostics,
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
          // DEV-ONLY, delete with lib/{services,screens}/profiles/dev/.
          // kProfileAudit is a compile-time const defaulting to false, so a
          // build that did not opt in has neither this button nor the code
          // behind it — the tooling cannot ship by being forgotten. Opt in with
          // --dart-define=DEBRIFY_PROFILE_AUDIT=true.
          if (kProfileAudit)
            IconButton(
              tooltip: 'Profile data',
              onPressed: profiles == null ? null : _openProfileData,
              icon: const Icon(Icons.data_object_rounded),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: profiles == null ? null : _edit,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Create'),
      ),
      body: profiles == null
          ? Center(
              child: _initialLoadFailed
                  ? const Text('Profile management authorization expired')
                  : const CircularProgressIndicator(),
            )
          : Column(
              children: <Widget>[
                if (PlatformUtil.isTvOS && profiles.length > 1)
                  SwitchListTile(
                    value: _topShelfEnabled,
                    title: const Text('Personalized Top Shelf'),
                    subtitle: const Text(
                      'Show the unlocked active profile on the Apple TV Home Screen. Off is the privacy default.',
                    ),
                    onChanged: _setTopShelfEnabled,
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return ListTile(
                        autofocus: index == 0,
                        leading: SizedBox.square(
                          dimension: 40,
                          child: ClipOval(
                            child: ProfileAvatarView(
                              profileId: profile.id,
                              avatarKey: profile.avatarKey,
                              role: profile.role,
                              name: profile.name,
                              allowAnimation: false,
                            ),
                          ),
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          profile.isEnabled
                              ? profile.role.name
                              : '${profile.role.name} · disabled',
                        ),
                        // The popup trailing is unreachable by DPAD — it
                        // sits inside the focused tile's rect, so directional
                        // traversal never steps into it (and disabled rows
                        // weren't focusable at all). On TV the row itself
                        // opens an action dialog instead.
                        trailing: PlatformUtil.isTelevision
                            ? const Icon(Icons.more_horiz_rounded)
                            : PopupMenuButton<String>(
                                onSelected: _runProfileAction(profile),
                                itemBuilder: (_) => [
                                  if (profile.isEnabled)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Text(
                                      profile.isEnabled ? 'Disable' : 'Enable',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                        onTap: PlatformUtil.isTelevision
                            ? () => _showProfileActions(profile)
                            : profile.isEnabled
                            ? () => _edit(profile)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
