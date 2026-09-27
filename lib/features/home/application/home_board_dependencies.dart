import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/hide_watched_prefs.dart';
import '../../../services/home_collections_store.dart';
import '../../../services/home_list_rows.dart';
import '../../../services/watched_status_service.dart';
import '../data/home_board_services.dart';

final homeBoardServicesProvider = Provider<HomeBoardServices>(
  (ref) => HomeBoardServices(
    hideWatched: () => HideWatchedPrefs.enabled,
    startWatched: () => WatchedStatusService.instance.ensureStarted(),
    firstWatchedSnapshot: () => WatchedStatusService.instance.firstSnapshot,
    resolveLists:
        (extras, {required previous, required isCurrent, required onUpdate}) =>
            HomeListRowsService.instance.resolve(
              extras,
              previous: previous,
              isCurrent: isCurrent,
              onUpdate: onUpdate,
            ),
    claimedCatalogs: HomeCollectionsStore.claimedCatalogKeys,
  ),
  dependencies: const [],
);
