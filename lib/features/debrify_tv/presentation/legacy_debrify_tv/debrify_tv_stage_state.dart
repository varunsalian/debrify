import 'dart:async';

import 'package:debrify/models/debrify_tv/channel_stats.dart';

class DebrifyTvStageState {
  // ── Spotlight stage data (rail cheap, stage lazy — plan §7) ─────────
  Map<String, DebrifyTvRailHealth> spotlightRailHealth = const {};
  final Map<String, DebrifyTvChannelStats> spotlightStats = {};
  Timer? spotlightStatsDebounce;
  String? spotlightFocusedId;
}
