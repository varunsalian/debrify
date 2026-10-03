import 'package:debrify/models/iptv_playlist.dart';

class IptvPlayerState {
  /// Bumped by every cancellation. The whole launch re-checks it after each
  /// await — consuming the pending payload is NOT cancellation, because the
  /// async chain owns the attempt from that moment on.
  int startupAttempt = 0;

  /// True while a startup launch is in flight. Holds the preview stage off:
  /// `previewRearmPending` only parks a RE-arm, it does nothing about the
  /// initial 900ms dwell, which would happily open a second live stream
  /// underneath the launching player.
  bool startupLaunchActive = false;

  /// Cap on the channel list handed to the player. On TV the whole list is
  /// serialized over the platform channel at launch (one JSON map per channel
  /// for the native guide) — a 10k-channel playlist froze the UI for hundreds
  /// of ms right on OK. A window this size is far more guide than anyone
  /// DPADs through while still launching instantly.
  static const int kMaxPlayerChannels = 1500;

  static const int kPlayerZapPageSize = 200;

  List<IptvChannel> playerSeriesEpisodes = const [];

  String? playerSeriesEpisodeSourceId;

  String? playerSeriesTitle;

  /// Latch across the resolve+launch window: resolving a Stremio channel
  /// takes real time, and repeated OK presses on a seemingly-idle row must
  /// not stack player launches.
  bool launchingChannel = false;

  /// How long the launch may spend waiting for a catalog. Deliberately under
  /// the overlay's 30s timeout so the failure is ours (with a message) rather
  /// than the overlay's silent give-up.
  static const Duration startupResolveDeadline = Duration(seconds: 24);
}
