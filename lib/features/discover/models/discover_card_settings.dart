import '../../../services/profiles/profile_session_memory.dart';

typedef DiscoverCardSettings = ({
  bool showTypeTags,
  bool showRatings,
  bool showTitles,
});
const defaultDiscoverCardSettings = (
  showTypeTags: true,
  showRatings: true,
  showTitles: true,
);
typedef DiscoverCardSettingsSession = ({
  ProfileSessionOwner owner,
  Object viewIdentity,
});
typedef DiscoverCardSettingsReader = DiscoverCardSettings? Function();
