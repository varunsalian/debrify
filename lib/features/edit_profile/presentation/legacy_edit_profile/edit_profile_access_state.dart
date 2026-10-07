import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';

class EditProfileAccessState {
  List<ConnectionResource>? resources;
  List<ProfileEngineAssignment>? engines;
  final Set<String> selectedResources = <String>{};
  final Set<String> selectedEngines = <String>{};
  final Map<String, Set<ResourcePermission>> resourcePermissions =
      <String, Set<ResourcePermission>>{};
  String? setupLoadError;
}
