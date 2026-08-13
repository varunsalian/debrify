import 'package:flutter/widgets.dart';

import '../../../models/debrify_tv/channel.dart';

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
  final bool busy;

  final VoidCallback onQuickPlay;
  final VoidCallback onAdd;
  final VoidCallback onImport;
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

  const DebrifyTvView({
    required this.channels,
    required this.favoriteIds,
    required this.busy,
    required this.onQuickPlay,
    required this.onAdd,
    required this.onImport,
    required this.onSettings,
    required this.onWatch,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onChannelFocused,
  });
}
