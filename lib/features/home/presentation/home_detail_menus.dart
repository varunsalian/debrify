import 'package:flutter/material.dart';

import '../../../models/custom_series_identity.dart';
import '../../../models/media_identity.dart';
import '../../../services/trakt/trakt_service.dart' show TraktTitleStatus;
import '../../../services/simkl/simkl_service.dart' show SimklTitleStatus;
import '../../../services/mdblist/mdblist_models.dart' show MdblistTitleStatus;
import '../../../services/simkl/simkl_menu_helpers.dart'
    show SimklMenuOption, buildSimklMenuOptions;
import '../../../services/mdblist/mdblist_menu_helpers.dart'
    show MdblistMenuOption, buildMdblistMenuOptions;
import '../../../widgets/trakt/trakt_menu_helpers.dart'
    show TraktMenuOption, TraktItemMenuAction, buildTraktAddOnlyMenuOptions;

/// Opening-time menus plus live status builders for the same detail route.
/// Membership flags and theme color are snapshots; auth, bindings and Simkl
/// pause eligibility retain the original live reads when a status rebuilds.
class HomeDetailMenus {
  HomeDetailMenus({
    required this.type,
    required this.identity,
    required this.removalColor,
    required this.inLocalContinueWatching,
    required this.inTraktContinueWatching,
    required this.inMdblistContinueWatching,
    required this.hasBoundSource,
    required this.traktAuthenticated,
    required this.simklAuthenticated,
    required this.mdblistAuthenticated,
    required this.hasSimklPause,
  }) {
    initialTrakt = trakt(null);
    initialSimkl = simkl(null);
    initialMdblist = mdblist(null);
  }

  final String type;
  final String? identity;
  final Color removalColor;
  final bool inLocalContinueWatching,
      inTraktContinueWatching,
      inMdblistContinueWatching;
  final bool Function() hasBoundSource,
      traktAuthenticated,
      simklAuthenticated,
      mdblistAuthenticated,
      hasSimklPause;
  late final List<TraktMenuOption> initialTrakt;
  late final List<SimklMenuOption> initialSimkl;
  late final List<MdblistMenuOption> initialMdblist;

  List<TraktMenuOption> trakt(TraktTitleStatus? status) => [
    ...buildTraktAddOnlyMenuOptions(
      isSeries: type == 'series',
      isMovie: type == 'movie',
      hasBoundSource: hasBoundSource(),
      isTraktAuthenticated:
          traktAuthenticated() &&
          identity != null &&
          MediaIdentity.isImdb(identity) &&
          !CustomSeriesIdentity.isCustom(identity),
      status: status,
    ),
    if (inLocalContinueWatching)
      TraktMenuOption(
        action: TraktItemMenuAction.removeFromPlayback,
        icon: Icons.delete_sweep_rounded,
        color: removalColor,
        label: 'Remove from Continue Watching',
        caption: 'Remove',
      ),
    if (inTraktContinueWatching)
      TraktMenuOption(
        action: TraktItemMenuAction.removeFromTraktPlayback,
        icon: Icons.remove_circle_outline_rounded,
        color: removalColor,
        label: 'Remove from Trakt Continue Watching',
        caption: 'Remove',
        isTrakt: true,
      ),
  ];

  List<SimklMenuOption> simkl(SimklTitleStatus? status) =>
      buildSimklMenuOptions(
        isSeries: type == 'series',
        isSimklAuthenticated:
            simklAuthenticated() &&
            identity != null &&
            !CustomSeriesIdentity.isCustom(identity),
        // An Up Next entry has no paused playback to remove.
        inContinueWatching: identity != null && hasSimklPause(),
        status: status,
      );

  List<MdblistMenuOption> mdblist(MdblistTitleStatus? status) =>
      buildMdblistMenuOptions(
        authenticated:
            mdblistAuthenticated() &&
            identity != null &&
            MediaIdentity.isImdb(identity) &&
            !CustomSeriesIdentity.isCustom(identity),
        isSeries: type == 'series',
        inContinueWatching: inMdblistContinueWatching,
        status: status,
      );
}
