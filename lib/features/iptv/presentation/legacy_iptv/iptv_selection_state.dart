import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_identity.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';

class IptvSelectionState {
  int gridColumns = 1;

  double gridRowExtent = 72;

  bool spotlightSourcesExpanded = false;

  /// Last committed responsive Spotlight mode. Focus handoffs happen outside
  /// layout, so they consult this rather than repeating a width heuristic.
  IptvSpotlightLayoutMode spotlightLayoutMode = IptvSpotlightLayoutMode.classic;

  String lastSearchQuery = '';

  /// Channel whose programme schedule is open. TV and large touch tablets
  /// swap the two-pane layout's right side for the schedule while the preview
  /// keeps playing; classic and desktop-pointer layouts use a bottom sheet.
  IptvChannel? scheduleChannel;

  /// Whether the last build used the TV two-pane layout. The in-place
  /// schedule pane only exists there — on the classic fallback (narrow TV
  /// canvas) RIGHT must open the bottom sheet instead, or it sets state
  /// nothing renders (a silent dead key).
  bool tvTwoPaneActive = false;

  bool touchTabletTwoPaneActive = false;

  /// The fixed tablet cursor owns a logical channel, not a List position.
  /// Progressive Stremio batches and filters replace the List object while
  /// retaining its rows; keeping both identity and the last index makes the
  /// common append-only update O(1), while still finding a moved row.
  int tabletSelectedIndex = 0;

  TabletChannelIdentity? tabletSelectedIdentity;

  Timer? searchDebounce;

  Timer? contentTypeDebounce;

  static const String kSpotlightAllCategory =
      '__debrify_spotlight_all_categories__';

  static const String kAddPlaylistSentinel = '__iptv_add_playlist__';

  static const String kNewListSentinel = '__iptv_new_list__';

  static const String kAddAddonSentinel = '__iptv_add_addon__';
}
