import '../../../services/profiles/profile_session_memory.dart';

/// A favourites workflow belongs to one mounted view in one profile session.
/// The view supplies a fresh Object as its identity; callbacks are not key data.
typedef HomeFavoritesSession = ({
  ProfileSessionOwner owner,
  Object viewIdentity,
});
