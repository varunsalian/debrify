import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_diagnostics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfileAdminActions {
  final EditProfileDependencies _deps;
  EditProfileAdminActions(this._deps);
  EditProfileSections get _sections => _deps.sections();
  Future<void> transferOwnership(ConnectionResource resource) async {
    final target = _deps.profile();
    if (target == null || target.id == resource.ownerProfileId) return;
    final operationActor = _deps.authorization;
    await _sections.admin.validateManagingAdmin(operationActor);
    if (!_deps.mounted()) return;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Transfer connection ownership?'),
        content: Text(
          '${target.name} will become the owner of ${resource.label}. '
          'Existing profiles keep their current grants, and the previous '
          'owner becomes a borrower.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _sections.admin.validateManagingAdmin(operationActor);
      await ConnectionResourceService(
        registry: _deps.registry(),
        cipher: DeviceKeyProvider.cipher,
      ).transferOwnership(
        actor: operationActor,
        resourceId: resource.id,
        newOwnerProfileId: target.id,
      );
      _deps.authorization = await _sections.admin.refreshSameManagingAdmin(
        operationActor.profileId,
      );
      await _sections.setup.loadResources();
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Connection ownership transferred')),
      );
    } catch (_) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Connection could not be transferred')),
      );
    }
  }

  Future<void> showDiagnostics() async {
    final report = await ProfileDiagnosticsService.collectJson(
      _deps.registry(),
    );
    if (!_deps.mounted()) return;
    await showDialog<void>(
      context: _deps.context(),
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

  Future<void> removePinAsAdmin() async {
    await _sections.adminActions._removePinAsAdminLocally();
  }

  Future<void> _removePinAsAdminLocally() async {
    try {
      final operationActor = _deps.authorization;
      await _sections.admin.validateManagingAdmin(operationActor);
      await _deps.pins().removePinAsAdmin(
        actor: operationActor,
        targetProfileId: _deps.profile()!.id,
      );
      _deps.authorization = await _sections.admin.refreshSameManagingAdmin(
        operationActor.profileId,
      );
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(const SnackBar(content: Text('PIN protection removed')));
    } catch (_) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('PIN protection was not changed')),
      );
    }
  }
}
