import '../../../services/storage_service.dart';

/// User-selected network presets for the Debrify (mpv) player — the escape
/// hatch for slow/unstable stream origins (Plex-backed addons, remote
/// seedboxes) that time out or stall under the player's stock configuration.
///
/// THE INVARIANT THIS CLASS EXISTS TO KEEP: 'standard' (the default for both
/// knobs) applies NOTHING — no property is set, and the code paths that run
/// today keep running byte-for-byte. Only a user who changes a preset gets
/// the new behavior, so untouched installs cannot regress.
///
/// Presets, not numbers, on purpose: numeric fields invite foot-gun values
/// (and TV keyboards make them miserable to enter); three vetted rungs per
/// knob cover the real cases.
///
/// Scope: VOD playback in both players. The Debrify (mpv) player consumes
/// [mpvProperties]/[vodLavfOptions] in `_openMedia`; the native Android TV
/// player receives the raw preset strings via the launch payload
/// (`networkPatience`/`networkBuffer`, injected in AndroidTvPlayerBridge)
/// and maps them to data-source timeouts + a DefaultLoadControl itself.
/// Live IPTV keeps its own tuned pipeline on both sides (ffmpeg-reconnect
/// flags / resilience ladder) — see the liveStream branch in `_openMedia`
/// and the `isIptvMode` guards in AndroidTvTorrentPlayerActivity.
/// Deliberately excluded: Magic TV's Torbox/RealDebrid launches route to
/// TorboxTvPlayerActivity, which keeps stock timeouts — the card copy's
/// "where the player supports them" hedge covers it; plumb it only if a
/// Magic TV user actually reports slow-origin timeouts.
class NetworkTuning {
  const NetworkTuning({required this.patience, required this.buffer});

  /// How long the player tolerates a slow/dropped connection, and whether it
  /// retries at the protocol layer.
  final String patience;

  /// How much video the demuxer reads ahead.
  final String buffer;

  static const String standard = 'standard';

  /// Dropdown value → label, in escalation order.
  static const Map<String, String> patienceOptions = {
    'standard': 'Standard',
    'extended': 'Extended (90s, auto-retry)',
    'patient': 'Patient (3min, auto-retry)',
  };

  // Labeled by read-ahead TIME, not bytes: both players share the 120s/300s
  // targets, but the byte ceiling differs by player (mpv's demuxer cache is
  // native memory; the TV player's is Java heap and clamps much lower), so a
  // byte figure here would overpromise on one of them.
  static const Map<String, String> bufferOptions = {
    'standard': 'Standard',
    'large': 'Large (~2 min read-ahead)',
    'huge': 'Huge (~5 min read-ahead)',
  };

  bool get isStandard => patience == standard && buffer == standard;

  static Future<NetworkTuning> load() async => NetworkTuning(
        patience: await StorageService.getNetworkConnectPatience(),
        buffer: await StorageService.getNetworkBufferSize(),
      );

  /// mpv properties for a (non-live) open. Empty at Standard — the caller
  /// must then set nothing at all.
  Map<String, String> get mpvProperties {
    final props = <String, String>{};
    switch (patience) {
      case 'extended':
        props['network-timeout'] = '90';
        break;
      case 'patient':
        props['network-timeout'] = '180';
        break;
    }
    switch (buffer) {
      case 'large':
        props['demuxer-max-bytes'] = '256MiB';
        props['demuxer-readahead-secs'] = '120';
        props['cache-secs'] = '120';
        break;
      case 'huge':
        props['demuxer-max-bytes'] = '512MiB';
        props['demuxer-readahead-secs'] = '300';
        props['cache-secs'] = '300';
        break;
    }
    return props;
  }

  /// ffmpeg protocol-layer retry for VOD opens, rider on the same
  /// `stream-lavf-o` slot the live path uses. Deliberately WITHOUT
  /// `reconnect_streamed` (that flag exists for non-seekable live inputs;
  /// finite files reconnect-and-seek without it) and without 4xx retry
  /// (an auth failure answers the same every time — it must surface).
  /// Empty at Standard.
  String get vodLavfOptions {
    switch (patience) {
      case 'extended':
        return 'reconnect=1,reconnect_on_network_error=1,'
            'reconnect_on_http_error=5xx,reconnect_delay_max=10';
      case 'patient':
        return 'reconnect=1,reconnect_on_network_error=1,'
            'reconnect_on_http_error=5xx,reconnect_delay_max=30';
      default:
        return '';
    }
  }
}
