import 'home_catalog_session.dart';

enum HomeTracker { trakt, simkl, mdblist }

typedef HomeTrackerAuthSession = ({
  HomeCatalogSession view,
  HomeTracker tracker,
});
typedef HomeTrackerAuthReader = Future<bool> Function();
