import '../../../models/simkl_continue_watching_item.dart';

/// Existing service contract: empty feeds clear shelves; null retains them.
typedef HomeSimklContinuationRows = ({
  List<SimklContinueWatchingItem> movies,
  List<SimklContinueWatchingItem> shows,
});

typedef HomeSimklContinuationReader =
    Future<HomeSimklContinuationRows?> Function();
