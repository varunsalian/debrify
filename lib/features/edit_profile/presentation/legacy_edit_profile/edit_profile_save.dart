import 'package:debrify/features/edit_profile/models/edit_profile_snapshot.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_avatar_ingest.dart';
import 'package:debrify/services/profiles/profile_avatar_mutation.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';

class EditProfileSave {
  final EditProfileDependencies _deps;
  EditProfileSave(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();

  /// Shown exactly once, right after a PIN is set: the code exists only in
  /// this dialog — the app stores a hash. Every PIN change mints a new one.
  Future<void> _showRecoveryCode(String profileName, String code) async {
    await showDialog<void>(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save this recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If the PIN for $profileName is ever forgotten, this code '
              'removes it from the profile screen. It is shown only this '
              'once — write it down or save it in a password manager.',
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('I saved it'),
          ),
        ],
      ),
    );
  }

  Future<void> save() async {
    if (_owners.form.saving || _owners.form.name.text.trim().isEmpty) return;
    if (_owners.access.resources == null ||
        _owners.access.engines == null ||
        _owners.access.setupLoadError != null) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text(
            _owners.access.setupLoadError ??
                'Profile options are still loading',
          ),
        ),
      );
      return;
    }
    if (_owners.form.pin.text.isNotEmpty &&
        !RegExp(r'^\d{4,8}$').hasMatch(_owners.form.pin.text)) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('PIN must contain 4–8 digits')),
      );
      return;
    }
    // The paired features follow their toggle only when the answer moved
    // from where this session started (the ProfileSetupFlow rule).
    final effectiveFeatures = Set<ProfileFeature>.from(_owners.form.features);
    void follow(bool moved, bool on, ProfileFeature paired) {
      if (!moved) return;
      on ? effectiveFeatures.add(paired) : effectiveFeatures.remove(paired);
    }

    final downloadsOn = _owners.form.features.contains(
      ProfileFeature.downloads,
    );
    final remoteOn = _owners.form.features.contains(
      ProfileFeature.remoteControl,
    );
    follow(
      downloadsOn != _owners.form.seedDownloads,
      downloadsOn,
      ProfileFeature.recordings,
    );
    follow(
      remoteOn != _owners.form.seedRemote,
      remoteOn,
      ProfileFeature.remoteTransfer,
    );
    // Clamp through the role ceiling BEFORE encoding: decode strips
    // ceiling-denied bits, so a raw set carrying one (e.g. remoteTransfer
    // paired onto a Kid) would never round-trip — and _save's persisted
    // encode comparison would misreport a committed save as failed.
    final ceilingLens = ProfilePolicy(enabled: effectiveFeatures);
    final clampedFeatures = <ProfileFeature>{
      for (final feature in effectiveFeatures)
        if (ceilingLens.allows(_owners.form.role, feature)) feature,
    };
    final snapshot = EditProfileSnapshot(
      name: _owners.form.name.text,
      pin: _owners.form.pin.text,
      role: _owners.form.role,
      features: Set<ProfileFeature>.unmodifiable(clampedFeatures),
      copyDefaults: _owners.form.copyDefaults,
      lockOnResume: _owners.form.lockOnResume,
      inactivityMinutes: _owners.form.inactivityMinutes,
      avatarKey: _owners.form.avatarKey,
      pendingAvatarBytes: _owners.form.pendingAvatarBytes,
      resources: List<ConnectionResource>.unmodifiable(
        _owners.access.resources!,
      ),
      selectedResources: Set<String>.unmodifiable(
        _owners.access.selectedResources,
      ),
      resourcePermissions: Map<String, Set<ResourcePermission>>.unmodifiable({
        for (final entry in _owners.access.resourcePermissions.entries)
          entry.key: Set<ResourcePermission>.unmodifiable(entry.value),
      }),
      selectedEngines: Set<String>.unmodifiable(_owners.access.selectedEngines),
    );
    _deps.setState(() => _owners.form.saving = true);
    PreparedProfileAvatar? preparedAvatar;
    String? mintedRecoveryCode;
    try {
      if (snapshot.pendingAvatarBytes != null) {
        preparedAvatar = await ProfileAvatarIngest.prepare(
          snapshot.pendingAvatarBytes!,
        );
      }
      final savedAvatarKey =
          preparedAvatar?.avatar.format() ?? snapshot.avatarKey;
      var operationActor = _deps.authorization;
      await _sections.admin.validateManagingAdmin(operationActor);
      final policy = _deps.policyFor(
        role: snapshot.role,
        selected: snapshot.features,
        existing: _deps.profile()?.policy,
        // A role change is authorship too: the Pages pane reseeded to the
        // new role's policy, and the save must write what it displayed.
        controlsShown:
            _deps.showFeaturePolicyControls ||
            _owners.form.policyTouched ||
            (_deps.profile() != null && _deps.profile()!.role != snapshot.role),
      );
      final existing = _deps.profile();
      late final String savedProfileId;
      if (existing == null) {
        final creation = ProfileCreationService(_deps.registry());
        final staged = await creation.createStaged(
          actor: operationActor,
          name: snapshot.name,
          role: snapshot.role,
          policy: policy,
          copyDefaultsFromActive: snapshot.copyDefaults,
          // A picked file is not authoritative until its bytes have been
          // durably staged below. Keep the pre-pick selection during staging.
          avatarKey: snapshot.avatarKey,
        );
        savedProfileId = staged.id;
        var stagedPublished = false;
        try {
          await ProfileAvatarMutation.runExclusive(staged.id, () async {
            await ProfileAvatarMutation.begin(staged.id, savedAvatarKey);
            if (preparedAvatar != null) {
              await ProfileAvatarIngest.writeCandidate(
                profileId: staged.id,
                prepared: preparedAvatar,
              );
            }
            if (snapshot.pin.isNotEmpty) {
              mintedRecoveryCode = await _deps.pins().setPinAsAdmin(
                actor: operationActor,
                targetProfileId: staged.id,
                pin: snapshot.pin,
              );
            }
            await _deps.registry().updateProfile(
              id: staged.id,
              avatarKey: savedAvatarKey,
              lockOnResume: snapshot.lockOnResume,
              inactivityTimeoutMinutes: snapshot.inactivityMinutes == 0
                  ? null
                  : snapshot.inactivityMinutes,
              clearInactivityTimeout: snapshot.inactivityMinutes == 0,
              actingProfileId: operationActor.profileId,
              actingAuthorizationRevision: operationActor.authorizationRevision,
              actingSessionEpoch: operationActor.sessionEpoch,
            );
            operationActor = await _sections.admin.refreshSameManagingAdmin(
              operationActor.profileId,
            );
            operationActor = await _sections.grants.applyResourceGrants(
              staged.id,
              snapshot,
              operationActor,
            );
            await _sections.grants.applyEngineAssignments(
              staged.id,
              snapshot.selectedEngines,
              operationActor,
            );
            // Visibility is the last registry step. Completion reconciles a
            // recovery-checkpoint exception against the committed row.
            await creation.completeStaged(
              profileId: staged.id,
              actor: operationActor,
            );
            stagedPublished = true;
            try {
              await ProfileAvatarIngest.commit(
                profileId: staged.id,
                avatarKey: savedAvatarKey,
              );
              await ProfileAvatarMutation.complete(staged.id);
            } catch (_) {
              // The profile is already visible and its selected file exists.
              // Keep the intent so bootstrap can finish cleanup idempotently.
            }
          });
        } catch (error, stackTrace) {
          final persisted = await _deps.registry().getProfile(staged.id);
          if (!stagedPublished &&
              persisted?.lifecycle != UserProfileLifecycle.active) {
            await creation.rollbackStaged(staged.id);
            await ProfileAvatarMutation.complete(staged.id);
          }
          // An active projection whose recovery checkpoint still fails is not
          // safe to finalize: retain its avatar intent so bootstrap can either
          // roll forward the durable active row or remove the durable staging
          // row. `completeStaged` is the only path that may set published=true.
          Error.throwWithStackTrace(error, stackTrace);
        }
      } else {
        savedProfileId = existing.id;
        final expectedTimeout = snapshot.inactivityMinutes == 0
            ? null
            : snapshot.inactivityMinutes;
        await ProfileAvatarIngest.publish(
          registry: _deps.registry(),
          profileId: existing.id,
          avatarKey: savedAvatarKey,
          prepared: preparedAvatar,
          persist: () async {
            await _deps.registry().updateProfile(
              id: existing.id,
              name: snapshot.name,
              avatarKey: savedAvatarKey,
              role: snapshot.role,
              policy: policy,
              lockOnResume: snapshot.lockOnResume,
              inactivityTimeoutMinutes: expectedTimeout,
              clearInactivityTimeout: expectedTimeout == null,
              actingProfileId: operationActor.profileId,
              actingAuthorizationRevision: operationActor.authorizationRevision,
              actingSessionEpoch: operationActor.sessionEpoch,
            );
          },
          wasPersisted: () async {
            final persisted = await _deps.registry().getProfile(existing.id);
            return persisted?.name == snapshot.name.trim() &&
                persisted?.avatarKey == savedAvatarKey &&
                persisted?.role == snapshot.role &&
                persisted?.policy.encode() == policy.encode() &&
                persisted?.lockOnResume == snapshot.lockOnResume &&
                persisted?.inactivityTimeoutMinutes == expectedTimeout;
          },
        );
        operationActor = await _sections.admin.refreshSameManagingAdmin(
          operationActor.profileId,
        );
        if (snapshot.pin.isNotEmpty) {
          mintedRecoveryCode = await _deps.pins().setPinAsAdmin(
            actor: operationActor,
            targetProfileId: existing.id,
            pin: snapshot.pin,
          );
          operationActor = await _sections.admin.refreshSameManagingAdmin(
            operationActor.profileId,
          );
        }
        operationActor = await _sections.grants.applyResourceGrants(
          savedProfileId,
          snapshot,
          operationActor,
        );
        await _sections.grants.applyEngineAssignments(
          savedProfileId,
          snapshot.selectedEngines,
          operationActor,
        );
      }
      _deps.authorization = operationActor;
      if (!_deps.mounted()) return;
      _owners.form.avatarKey = savedAvatarKey;
      _owners.form.features = Set<ProfileFeature>.from(policy.enabled);
      _owners.form.seedDownloads = _owners.form.features.contains(
        ProfileFeature.downloads,
      );
      _owners.form.seedRemote = _owners.form.features.contains(
        ProfileFeature.remoteControl,
      );
      _owners.form.policyTouched = false;
      _owners.form.pendingAvatarBytes = null;
      _owners.form.pin.clear();
      // Saving the SIGNED-IN profile never crosses the gate, so the policy
      // mirrors (MainPage tab gating + ProfilePolicyGuard) must be told.
      if (ProfileRuntime.isProfileCommitted &&
          _deps.profile()?.id == ProfileRuntime.capture().profileId) {
        MainPageBridge.reloadProfilePolicy?.call();
      }
      final recoveryCode = mintedRecoveryCode;
      if (recoveryCode != null) {
        await _sections.save._showRecoveryCode(snapshot.name, recoveryCode);
        if (!_deps.mounted()) return;
      }
      if (!_deps.mounted()) return;
      Navigator.of(_deps.context()).pop(true);
    } on ProfileAvatarRejected catch (rejected) {
      if (!_deps.mounted()) return;
      _deps.setState(() => _owners.form.saving = false);
      _sections.tvNav.restoreTvSaveFocus();
      // The one failure with a user-actionable cause: name it instead of the
      // generic message.
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text(rejected.message)));
    } catch (_) {
      if (!_deps.mounted()) return;
      _deps.setState(() => _owners.form.saving = false);
      _sections.tvNav.restoreTvSaveFocus();
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Could not save this profile')),
      );
    }
  }
}
