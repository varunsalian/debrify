import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/channel_stats.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/widgets/torrent_result_row.dart'
    show qualityTierForName;

class DebrifyTvSpotlightStage {
  final DebrifyTvDependencies _deps;
  DebrifyTvSpotlightStage(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  /// The Spotlight layout's window onto this state. Paint only: every
  /// callback is an existing method, every playback path is shared verbatim.
  DebrifyTvView buildSpotlightView() {
    return DebrifyTvView(
      channels: _owners.library.channels,
      favoriteIds: _owners.library.favoriteChannelIds,
      railHealth: _owners.stage.spotlightRailHealth,
      stats: _owners.stage.spotlightFocusedId == null
          ? null
          : _owners.stage.spotlightStats[_owners.stage.spotlightFocusedId],
      busy: _owners.session.isBusy,
      onQuickPlay: _sections.dialogs.showQuickPlayDialog,
      onAdd: _sections.actions.handleAddChannel,
      onImport: _sections.channelImport.handleImportChannels,
      onExport: _sections.channelExport.handleExportChannels,
      onDeleteAll: _sections.actions.handleDeleteAllChannels,
      onSettings: _sections.dialogs.showGlobalSettingsDialog,
      onWatch: _sections.channelWatch.watchChannel,
      onEdit: _sections.actions.handleEditChannel,
      onShare: _sections.share.handleShareChannelAsMagnet,
      onDelete: _sections.actions.handleDeleteChannel,
      onToggleFavorite: _sections.library.toggleChannelFavorite,
      onChannelFocused: _sections.stage._onSpotlightChannelFocused,
      onWatchOne: (channel, torrent) =>
          _sections.channelWatch.watchChannel(channel, leadWith: torrent),
    );
  }

  Future<void> loadSpotlightRailHealth() async {
    final health = await DebrifyTvCacheService.loadRailHealth();
    if (!_deps.mounted()) return;
    _deps.setState(() => _owners.stage.spotlightRailHealth = health);
  }

  /// Focus moved to a channel row. The stage's numbers need a per-row name
  /// classify over the pool, so: debounced (a DPAD glide crosses many rows),
  /// computed only for the channel that focus RESTS on, and memoised — a
  /// pool does not change while you are looking at it.
  void _onSpotlightChannelFocused(DebrifyTvChannel channel) {
    // Cancel FIRST, unconditionally: a memo hit must still kill a pending
    // timer for the previous channel, or gliding B→A (A memoised) classifies
    // B off-focus.
    _owners.stage.spotlightStatsDebounce?.cancel();
    _owners.stage.spotlightFocusedId = channel.id;
    // Rebuild NOW either way. On a miss the view's stats go null and the
    // stage draws placeholders — never another channel's numbers, which a
    // plate press would turn into another channel's torrent.
    _deps.setState(() {});
    if (_owners.stage.spotlightStats.containsKey(channel.id)) return;
    _owners.stage.spotlightStatsDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _sections.stage._computeSpotlightStats(channel),
    );
  }

  /// Wipe every memoised stage snapshot and recompute the focused channel's.
  /// For when the numbers' INPUTS change — the quality filter — rather than
  /// one channel's pool.
  void invalidateSpotlightStats() {
    if (_owners.library.debrifyTvStyle != 'spotlight') return;
    _owners.stage.spotlightStats.clear();
    _sections.stage.refreshSpotlightStatsIfFocused(
      _owners.stage.spotlightFocusedId,
    );
  }

  /// A channel's pool (or the filter over it) changed; if it is the one the
  /// stage is showing, schedule fresh numbers — memo removal alone leaves
  /// the stage on its placeholder forever, since only a focus MOVE computes.
  void refreshSpotlightStatsIfFocused(String? channelId) {
    if (_owners.library.debrifyTvStyle != 'spotlight' || channelId == null)
      return;
    if (_owners.stage.spotlightFocusedId != channelId) return;
    final channel = _owners.library.channels.firstWhereOrNull(
      (c) => c.id == channelId,
    );
    if (channel != null) _sections.stage._onSpotlightChannelFocused(channel);
  }

  Future<void> _computeSpotlightStats(DebrifyTvChannel channel) async {
    if (!_deps.mounted() ||
        _owners.stage.spotlightStats.containsKey(channel.id))
      return;
    final entry = await _sections.library.ensureCacheEntry(channel.id);
    // Focus may have moved during the read; bail rather than classify an
    // off-focus pool. The entry stays in _channelCache, so a return visit
    // pays only the classify.
    if (!_deps.mounted() || _owners.stage.spotlightFocusedId != channel.id)
      return;
    final torrents = entry?.torrents ?? const <CachedTorrent>[];

    // ONE pass classifies every name: the quality count and the mix buckets
    // share it. Quality only — size is a per-file rule the pool rows cannot
    // answer, and counting it here would promise what playback can't keep.
    final hasQuality = _owners.settings.tvFilters.hasQuality;
    int uhd = 0, fhd = 0, rest = 0, atQuality = 0;
    for (final t in torrents) {
      switch (qualityTierForName(t.name)) {
        case QualityTier.ultraHd:
          uhd++;
        case QualityTier.fullHd:
          fhd++;
        case QualityTier.hd:
        case QualityTier.sd:
          rest++;
      }
      if (!hasQuality ||
          _owners.settings.tvFilters.qualityMatchesName(t.name)) {
        atQuality++;
      }
    }

    final keywordYield = <String, int>{
      for (final kw in entry?.normalizedKeywords ?? const <String>[])
        kw: entry?.keywordStats[kw]?.totalFetched ?? 0,
    };
    final dead = [
      for (final e in keywordYield.entries)
        if (e.value == 0) e.key,
    ];

    final sample = [...torrents]..shuffle(Random());

    final stats = DebrifyTvChannelStats(
      channelId: channel.id,
      pooled: torrents.length,
      atYourQuality: atQuality,
      qualityMix: [uhd, fhd, rest],
      deadKeywords: dead,
      keywordYield: keywordYield,
      fetchedAt: (entry?.fetchedAt ?? 0) > 0
          ? DateTime.fromMillisecondsSinceEpoch(entry!.fetchedAt)
          : null,
      status: entry?.status ?? DebrifyTvCacheStatus.warming,
      sample: sample.take(4).toList(),
    );
    _deps.setState(() {
      _owners.stage.spotlightStats[channel.id] = stats;
    });
  }
}
