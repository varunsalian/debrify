import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart' show HomeCardOrientation;

/// Scalar preference values; record equality avoids redundant presentation work.
typedef HomeDisplayPreferences = ({
  HomeCardOrientation orientation,
  bool hideTitlesAndRatings,
  bool hideCatalogAddonNames,
  bool hideCollectionNames,
  bool spotlightFocusDetails,
  bool animationsEnabled,
  String animationStyle,
});

/// Legacy values before storage returns (stored focus-details defaults to true).
const initialHomeDisplayPreferences = (
  orientation: HomeCardOrientation.landscape,
  hideTitlesAndRatings: false,
  hideCatalogAddonNames: false,
  hideCollectionNames: false,
  spotlightFocusDetails: false,
  animationsEnabled: false,
  animationStyle: 'snowy_mountain',
);

/// Cached presentation is seeded before the first frame, without provider writes.
typedef HomeDisplaySession = ({
  ProfileSessionOwner owner,
  Object viewIdentity,
  HomeDisplayPreferences initial,
});
