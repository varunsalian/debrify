import 'package:flutter/foundation.dart';

import '../../../models/iptv_playlist.dart';

/// The preview state the IPTV results view owns, handed to the stage widgets
/// as one object instead of a dozen constructor parameters.
///
/// Every field is a listenable or a getter, never a snapshot. The stage's
/// nested [ValueListenableBuilder]s re-read [previewEnabled],
/// [startupLaunchActive] and [resolveTicket] at *builder* time, and at least
/// one host path depends on exactly that: the preview re-arm clears the
/// startup suppression WITHOUT a setState and relies on the [epoch] bump that
/// follows to rebuild the stage. A bool snapshotted when the host last built
/// would still say "suppressed" there, and the preview would never come back.
@immutable
class IptvStageState {
  const IptvStageState({
    required this.shown,
    required this.epoch,
    required this.showing,
    required this.streamUrl,
    required this.previewEnabled,
    required this.startupLaunchActive,
    required this.resolveTicket,
    required this.onMarkWinner,
    required this.onPlaybackFailed,
  });

  /// The channel the stage is showing. Null = nothing focused yet, which is
  /// the stage's empty floor.
  final ValueListenable<IptvChannel?> shown;

  /// Bumped after returning from real playback so the stage remounts fresh
  /// (HeroTrailerBackdrop latches itself off for the rest of a page visit once
  /// real content playback launches — a new instance is the supported way to
  /// re-arm it).
  final ValueListenable<int> epoch;

  /// Flips when the embedded player actually has frames. This one is the
  /// notifier and not a read-only view of it because the preview surface
  /// writes it back itself.
  final ValueNotifier<bool> showing;

  /// The URL the preview actually plays. For M3U/Xtream channels this is just
  /// the channel URL; for Stremio-addon channels it is the current rung of the
  /// candidate ladder. Null = nothing to play, only the static floor shows.
  final ValueListenable<String?> streamUrl;

  /// The user's "preview channels while browsing" setting.
  final ValueGetter<bool> previewEnabled;

  /// True while a startup launch owns the screen — the stage's dwell would
  /// otherwise open a SECOND live stream under the launching player.
  final ValueGetter<bool> startupLaunchActive;

  /// The ladder generation the preview's post-frame callbacks belong to; they
  /// can fire after focus has moved to another channel.
  final ValueGetter<int> resolveTicket;

  /// First frames arrived on this ticket — remember the winning candidate.
  final ValueChanged<int> onMarkWinner;

  /// The candidate on this ticket failed — walk to the next rung.
  final ValueChanged<int> onPlaybackFailed;
}
