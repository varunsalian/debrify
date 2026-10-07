import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';

class EditProfileSelection {
  final EditProfileDependencies _deps;
  EditProfileSelection(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  void setRole(UserProfileRole role) {
    if (_owners.form.saving) return;
    _deps.setState(() {
      _owners.form.role = role;
      // The ProfileSetupFlow rule: a role CHANGE is a re-preset (the new
      // role's defaults), while returning to the stored role restores the
      // stored policy — so what the Pages pane displays is always exactly
      // what a save would write.
      final existing = _deps.profile();
      _owners.form.features = Set<ProfileFeature>.from(
        existing != null && existing.role == role
            ? existing.policy.enabled
            : ProfilePolicy.defaultsFor(role).enabled,
      );
      // The pairs are re-coupled by the reseed above, so the
      // follow-only-when-moved baselines reset too.
      _owners.form.seedDownloads = _owners.form.features.contains(
        ProfileFeature.downloads,
      );
      _owners.form.seedRemote = _owners.form.features.contains(
        ProfileFeature.remoteControl,
      );
    });
  }

  Set<ResourcePermission> defaultResourcePermissions(
    UserProfileRole role, [
    Set<ProfileFeature>? features,
  ]) => <ResourcePermission>{
    ResourcePermission.use,
    if ((features ?? _owners.form.features).contains(
          ProfileFeature.downloads,
        ) ||
        (features ?? _owners.form.features).contains(ProfileFeature.recordings))
      ResourcePermission.download,
    if (role != UserProfileRole.child &&
        (features ?? _owners.form.features).contains(
          ProfileFeature.remoteTransfer,
        ))
      ResourcePermission.writeRemote,
  };

  /// The single toggle-on path for a connection row, shared by the row itself
  /// and the group's "All" action so the singleton-slot rule cannot diverge:
  /// selecting one credential of a singleton kind deselects its rivals.
  void selectResource(ConnectionResource resource) {
    final singletonSlot = resource.type.singletonCredentialBindingSlot;
    if (singletonSlot != null) {
      for (final other in _owners.access.resources!) {
        if (other.id != resource.id &&
            other.type.singletonCredentialBindingSlot == singletonSlot) {
          _owners.access.selectedResources.remove(other.id);
          _owners.access.resourcePermissions.remove(other.id);
        }
      }
    }
    _owners.access.selectedResources.add(resource.id);
    _owners.access.resourcePermissions.putIfAbsent(
      resource.id,
      () => _sections.selection.defaultResourcePermissions(_owners.form.role),
    );
  }

  void deselectResource(ConnectionResource resource) {
    _owners.access.selectedResources.remove(resource.id);
  }

  /// Rows the target profile does not own — the only ones whose grant is
  /// editable here. Owned rows are always granted.
  Iterable<ConnectionResource> editableIn(List<ConnectionResource> group) =>
      group.where((resource) => resource.ownerProfileId != _deps.profile()?.id);
}
