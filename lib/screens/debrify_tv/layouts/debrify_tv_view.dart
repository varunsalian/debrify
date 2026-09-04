import 'package:flutter/widgets.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../models/debrify_tv/channel_stats.dart';
import '../../../models/debrify_tv_cache.dart' show CachedTorrent;

/// Below this many pooled titles the rail pip goes amber. A product number,
/// not a correctness one — nothing may branch on it except the pip colour.
/// Start at 25; tune on a real panel in the fidelity pass.
const int kThinPoolThreshold = 25;

/// A narrow window over `_DebrifyTVScreenState` for the Spotlight layout.
///
/// The layout is a VIEW over the screen's existing state, never a fork of it:
/// every callback here is an existing method on the state, and every playback
/// path — `_watch`, `_watchChannel`, the five provider flows, prefetch,
/// cancel, deep-link auto-play — is shared verbatim with the grid. If the
/// Spotlight arm needs something the state does not expose, expose it here —
/// do not reimplement it in the layout.
class DebrifyTvView {
  final List<DebrifyTvChannel> channels;
  final Set<String> favoriteIds;

  /// Rail-cheap health per channel id (grouped queries, loaded once per
  /// mount). The pip and rail captions resolve from this ALONE — never from
  /// a per-row name classify.
  final Map<String, DebrifyTvRailHealth> railHealth;

  /// The focused channel's stage numbers, once its debounced pass has run.
  /// Null while computing (the stage shows quiet placeholders, not zeros).
  final DebrifyTvChannelStats? stats;

  final bool busy;

  final VoidCallback onQuickPlay;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onDeleteAll;
  final VoidCallback onSettings;

  final void Function(DebrifyTvChannel) onWatch;
  final void Function(DebrifyTvChannel) onEdit;
  final void Function(DebrifyTvChannel) onShare;
  final void Function(DebrifyTvChannel) onDelete;
  final void Function(DebrifyTvChannel) onToggleFavorite;

  /// The seam the stage stands on: focus lives in the rail, INSIDE the
  /// layout, but per-channel stage stats are computed by the state. The rail
  /// calls this on every focus move; the state debounces, computes, memoises
  /// and rebuilds with fresh stats.
  final void Function(DebrifyTvChannel) onChannelFocused;

  /// OK on a sample plate: play THAT title. Carries the channel as well as
  /// the pick so the state can build the rest of the queue from the right
  /// pool. Where a promise is impossible (mock §3), offer a choice instead.
  final void Function(DebrifyTvChannel, CachedTorrent) onWatchOne;

  const DebrifyTvView({
    required this.channels,
    required this.favoriteIds,
    required this.railHealth,
    required this.stats,
    required this.busy,
    required this.onQuickPlay,
    required this.onAdd,
    required this.onImport,
    required this.onExport,
    required this.onDeleteAll,
    required this.onSettings,
    required this.onWatch,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onChannelFocused,
    required this.onWatchOne,
  });
}
