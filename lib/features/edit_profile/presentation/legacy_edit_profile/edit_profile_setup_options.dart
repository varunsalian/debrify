import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';

class EditProfileSetupOptions {
  final EditProfileDependencies _deps;
  EditProfileSetupOptions(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Future<void> loadSetupOptions() async {
    try {
      final actor = await _deps.authorization.validate(_deps.registry());
      final (resources, engines) = _deps.setupOptionsLoader() != null
          ? await _deps.setupOptionsLoader()!()
          : (
              await _deps.registry().listGrantedResources(actor.id),
              await ProfileEngineAssignmentService(
                _deps.registry(),
              ).listForTarget(
                actor: _deps.authorization,
                targetProfileId: _deps.profile()?.id,
              ),
            );
      final selectedResources = <String>{};
      final resourcePermissions = <String, Set<ResourcePermission>>{};
      final targetId = _deps.profile()?.id;
      if (targetId != null) {
        for (final resource in resources) {
          final grant = await _deps.registry().getGrant(targetId, resource.id);
          if (grant != null) {
            selectedResources.add(resource.id);
            resourcePermissions[resource.id] = {
              for (final permission in ResourcePermission.values)
                if (grant.allows(permission)) permission,
            }..add(ResourcePermission.use);
          }
        }
      }
      await _sections.admin.validateManagingAdmin(_deps.authorization);
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.access.resources = resources;
        _owners.access.engines = engines;
        _owners.access.selectedResources
          ..clear()
          ..addAll(selectedResources);
        _owners.access.resourcePermissions
          ..clear()
          ..addAll(resourcePermissions);
        _owners.access.selectedEngines
          ..clear()
          ..addAll(
            _deps.profile() == null
                ? engines.map((engine) => engine.id)
                : engines
                      .where((engine) => engine.assignedToTarget)
                      .map((engine) => engine.id),
          );
        _owners.access.setupLoadError = null;
      });
    } catch (_) {
      if (!_deps.mounted()) return;
      _deps.setState(
        () => _owners.access.setupLoadError =
            'Profile options could not be loaded',
      );
    }
  }

  Future<void> loadResources() async {
    try {
      final actor = await _deps.authorization.validate(_deps.registry());
      final resources = await _deps.registry().listGrantedResources(actor.id);
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.access.resources = resources;
        _owners.access.setupLoadError = null;
      });
    } catch (_) {
      if (!_deps.mounted()) return;
      _deps.setState(
        () =>
            _owners.access.setupLoadError = 'Connections could not be reloaded',
      );
    }
  }
}
