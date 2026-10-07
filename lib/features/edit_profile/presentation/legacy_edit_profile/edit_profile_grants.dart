import 'package:debrify/features/edit_profile/models/edit_profile_snapshot.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';

class EditProfileGrants {
  final EditProfileDependencies _deps;
  EditProfileGrants(this._deps);
  EditProfileSections get _sections => _deps.sections();
  Future<ProfileAuthorizationContext> applyResourceGrants(
    String targetProfileId,
    EditProfileSnapshot snapshot,
    ProfileAuthorizationContext operationActor,
  ) async {
    final resources = snapshot.resources;
    final service = ConnectionResourceService(
      registry: _deps.registry(),
      cipher: DeviceKeyProvider.cipher,
    );
    for (final resource in resources) {
      final existing = await _deps.registry().getGrant(
        targetProfileId,
        resource.id,
      );
      final selected = snapshot.selectedResources.contains(resource.id);
      final desired =
          snapshot.resourcePermissions[resource.id] ??
          _sections.selection.defaultResourcePermissions(
            snapshot.role,
            snapshot.features,
          );
      final desiredMask = desired.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      );
      final bindingSlot = resource.type.singletonCredentialBindingSlot;
      final bindingMatches =
          bindingSlot == null ||
          await _deps.registry().getBoundResourceId(
                targetProfileId,
                bindingSlot,
              ) ==
              resource.id;
      if (selected &&
          (existing == null ||
              existing.permissions != desiredMask ||
              !bindingMatches)) {
        await service.grant(
          actor: operationActor,
          targetProfileId: targetProfileId,
          resourceId: resource.id,
          permissions: desired,
        );
        operationActor = await _sections.admin.refreshSameManagingAdmin(
          operationActor.profileId,
        );
      } else if (!selected &&
          existing != null &&
          resource.ownerProfileId != targetProfileId) {
        await service.revokeGrant(
          actor: operationActor,
          targetProfileId: targetProfileId,
          resourceId: resource.id,
        );
        operationActor = await _sections.admin.refreshSameManagingAdmin(
          operationActor.profileId,
        );
      }
    }
    return operationActor;
  }

  Future<void> applyEngineAssignments(
    String targetProfileId,
    Set<String> selectedEngineIds,
    ProfileAuthorizationContext operationActor,
  ) => ProfileEngineAssignmentService(_deps.registry()).apply(
    actor: operationActor,
    targetProfileId: targetProfileId,
    selectedEngineIds: selectedEngineIds,
  );
}
