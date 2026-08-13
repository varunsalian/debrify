import '../debrify_tv_cache.dart';

/// Rail-cheap health for one channel: everything the rail's pip and captions
/// need, resolved from grouped queries — never a per-row name classify.
///
/// The rule (DEBRIFY_TV_STYLE_PLAN.md §7): the rail is cheap, the stage is
/// lazy. This type carries only what three GROUP BY queries can answer.
class DebrifyTvRailHealth {
  final int pooled;
  final int deadKeywords;
  final String status;
  final int fetchedAt;

  const DebrifyTvRailHealth({
    required this.pooled,
    required this.deadKeywords,
    required this.status,
    required this.fetchedAt,
  });

  static const DebrifyTvRailHealth empty = DebrifyTvRailHealth(
    pooled: 0,
    deadKeywords: 0,
    status: DebrifyTvCacheStatus.warming,
    fetchedAt: 0,
  );
}

/// The focused channel's stage numbers. Computed only for the channel under
/// the cursor, debounced on focus change, and memoised — a pool does not
/// change while you are looking at it. Never computed for all channels on
/// page load.
class DebrifyTvChannelStats {
  /// The channel this snapshot was computed FOR. Consumers must check it
  /// against the channel they are drawing: focus can move faster than the
  /// debounced pass, and stats worn by the wrong channel are not a flicker —
  /// a plate activated in that window would queue another channel's torrent.
  final String channelId;

  final int pooled;

  /// How many of the pool survive the user's quality filter, counted with the
  /// same name-classify the playback path applies to the cache pre-shuffle.
  /// Quality ONLY — size is a per-file rule the pool rows cannot answer
  /// (mock §3), so it is deliberately not counted here.
  final int atYourQuality;

  /// Pool composition by tier: [2160p, 1080p, everything else].
  final List<int> qualityMix;

  /// Keywords whose searches returned nothing — why a channel is thin.
  final List<String> deadKeywords;

  /// Titles fetched per keyword (normalised), for the stage's keyword chips.
  final Map<String, int> keywordYield;

  final DateTime? fetchedAt;
  final String status;

  /// A sample of the pool, for the stage's strip. Inventory, not schedule:
  /// playback shuffles, so nothing here may be presented as a running order.
  final List<CachedTorrent> sample;

  const DebrifyTvChannelStats({
    required this.channelId,
    required this.pooled,
    required this.atYourQuality,
    required this.qualityMix,
    required this.deadKeywords,
    required this.keywordYield,
    required this.fetchedAt,
    required this.status,
    required this.sample,
  });
}
