import '../../../models/iptv_source_result.dart';
import '../../../models/addon_search_status.dart';

/// Request state for one Sources view. Rendered/frozen rows have a separate
/// presentation lifetime; a final response does not imply immediate adoption.
class SourceSearchState {
  final bool searching;
  final String? error;
  final List<AddonSearchStatus> addonStatuses;
  final List<IptvSourceResult> iptv;

  SourceSearchState({
    this.searching = false,
    this.error,
    List<AddonSearchStatus> addonStatuses = const [],
    List<IptvSourceResult> iptv = const [],
  }) : addonStatuses = List.unmodifiable(addonStatuses),
       iptv = List.unmodifiable(iptv);
}
