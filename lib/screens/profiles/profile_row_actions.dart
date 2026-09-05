import '../../services/webdav_sync/webdav_sync_save_feedback.dart';
import '../../widgets/webdav_sync/webdav_save_status.dart';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/live_recording_service.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_cleanup_ledger.dart';
import '../../services/profiles/profile_data_generation.dart';
import '../../services/profiles/profile_registry.dart';

/// Per-profile management actions (delete with dispositions, enable and
/// disable), shared between [ManageProfilesScreen] and the Profiles hub so
/// the hub can offer them at its first level. Every flow validates the
/// managing Admin up front and re-validates before each write, exactly as
/// the originals did; methods return true when something changed so callers
/// know to reload.
class ProfileRowActions {
  const ProfileRowActions({
    required this.context,
    required this.registry,
    required this.authorization,
  });

  final BuildContext context;
  final ProfileRegistry registry;
  final ProfileAuthorizationContext authorization;

  Future<bool> delete(UserProfile profile) async {
    final revision = WebDavSyncSaveFeedback.instance.revision;
    final changed = await _deleteLocally(profile);
    if (changed && context.mounted) {
      await showWebDavSaveProgress(context, revision);
    }
    return changed;
  }

  Future<bool> _deleteLocally(UserProfile profile) async {
    late final ProfileDeletionDependencies dependencies;
    late ProfileAuthorizationContext operationActor;
    try {
      operationActor = authorization;
      await _validateManagingAdmin(operationActor);
      dependencies = await registry.deletionDependencies(profile.id);
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile deletion is not authorized')),
      );
      return false;
    }
    if (!context.mounted) return false;
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
    if (confirmed != true) return false;
    try {
      await _validateManagingAdmin(operationActor);
      if (revokeShares) {
        await registry.revokeGrantsOnOwnedResources(
          ownerProfileId: profile.id,
          actingProfileId: operationActor.profileId,
          actingAuthorizationRevision: operationActor.authorizationRevision,
          actingSessionEpoch: operationActor.sessionEpoch,
        );
        // Revocation bumps every BORROWER's authorization revision — and
        // under default-on sharing the acting admin is almost always one of
        // them, so its captured context just went stale. Re-capture (same
        // session, same profile) or every later authority check fails.
        final refreshed = await ProfileAuthorizationContext.capture(registry);
        if (refreshed.profileId != operationActor.profileId) {
          throw StateError('Managing profile session changed');
        }
        operationActor = refreshed;
        await _validateManagingAdmin(operationActor);
        // The delete transaction re-verifies shared == 0, so a racing
        // re-grant safely re-blocks rather than slipping through.
      }
      if (!retainPublicFiles) {
        final artifacts = await registry.listOwnedArtifacts(profile.id);
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
        await registry.removeOwnedArtifactRecords(
          ownerProfileId: profile.id,
          actingProfileId: operationActor.profileId,
          actingAuthorizationRevision: operationActor.authorizationRevision,
          actingSessionEpoch: operationActor.sessionEpoch,
        );
      }
      await _validateManagingAdmin(operationActor);
      await ProfileCleanupLedger.scheduleProfile(profile.id);
      await _validateManagingAdmin(operationActor);
      await registry.deleteProfileWithDisposition(
        id: profile.id,
        deleteOwnedResources: deleteConnections,
        detachPublicArtifacts: retainPublicFiles,
        actingProfileId: operationActor.profileId,
        actingAuthorizationRevision: operationActor.authorizationRevision,
        actingSessionEpoch: operationActor.sessionEpoch,
      );
      await ProfileDataGenerationManager.deleteAllProfileData(profile.id);
      await ProfileCleanupLedger.completeProfile(profile.id);
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile deletion failed')));
      return false;
    }
  }

  Future<bool> toggleEnabled(UserProfile profile) async {
    final revision = WebDavSyncSaveFeedback.instance.revision;
    final changed = await _toggleEnabledLocally(profile);
    if (changed && context.mounted) {
      await showWebDavSaveProgress(context, revision);
    }
    return changed;
  }

  Future<bool> _toggleEnabledLocally(UserProfile profile) async {
    try {
      final actor = authorization;
      await _validateManagingAdmin(actor);
      if (profile.isEnabled) {
        await registry.disableProfile(
          profile.id,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
      } else {
        await registry.enableProfile(
          profile.id,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
      }
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile status could not be changed')),
      );
      return false;
    }
  }

  Future<UserProfile> _validateManagingAdmin(
    ProfileAuthorizationContext context,
  ) async {
    final actor = await context.validate(registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Profile management is not authorized');
    }
    return actor;
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
}
