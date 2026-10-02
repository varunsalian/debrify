import 'package:debrify/models/profiles/connection_resource.dart';

bool shouldApplyPendingCredentialOverride({
  required Set<ConnectionResourceType> pendingTypes,
  required Set<ConnectionResourceType> providerTypes,
  required bool ownCredentialPresent,
}) => !ownCredentialPresent && pendingTypes.any(providerTypes.contains);
