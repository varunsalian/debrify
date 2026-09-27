import '../../../models/metadata_preferences.dart';
import '../../../services/profiles/profile_session_memory.dart';

/// Discovery policy is also consumed by Catalog title suggestions.
typedef MetadataFeatureSession = ({
  ProfileSessionOwner owner,
  Object viewIdentity,
});
typedef MetadataFeaturePolicy = ({
  MetadataPreferences? preferences,
  bool ready,
});
typedef MetadataFeatureReader = Future<MetadataPreferences> Function();
