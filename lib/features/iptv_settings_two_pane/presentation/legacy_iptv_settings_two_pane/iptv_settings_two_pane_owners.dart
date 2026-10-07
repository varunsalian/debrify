import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';
import 'package:debrify/services/iptv_source_stats.dart' show IptvSourceStats;
import 'package:debrify/theme/app_theme.dart';
import 'package:flutter/material.dart';

class IptvSettingsTwoPaneOwners {
  /// Rows in the busiest pane (a source: refresh, default, edit, guide,
  /// delete) plus headroom for the lists pane, which grows with the user's
  /// lists and is capped by the pool below.
  static const int _panePoolSize = 24;

  /// The active theme, cached by [build] for every `_buildX` helper. Assigned
  /// before first use because `build` always runs before them.
  late AppTheme app;

  final ValueNotifier<IptvTwoPaneDest> dest = ValueNotifier(
    const IptvTwoPaneAddDest(),
  );

  /// One node per rail entry, rebuilt when the entry count changes.
  final List<FocusNode> railNodes = [];

  final List<FocusNode> paneNodes = List.generate(
    _panePoolSize,
    (i) => FocusNode(debugLabel: 'iptv-2p-pane-$i'),
  );

  final ScrollController railScroll = ScrollController();

  /// Cached per-source stats, keyed by playlist id. Recomputed only when the
  /// playlist set or a refresh changes — a DPAD move must not re-query on a
  /// weak TV box.
  Map<String, IptvSourceStats> sourceStats = const {};

  String statsSignature = '';
}
