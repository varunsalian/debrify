import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpNetworkTuningHost {
  int get decoderProbeGeneration;
}

class VpNetworkTuning {
  VpNetworkTuning(this._host);
  final VpNetworkTuningHost _host;

  /// Stock values of exactly the player-global properties [VpMediaOpen.networkTuning]
  /// has overridden, captured before the first override. A later live open
  /// on the same player (mixed playlist) restores these, so the tuned live
  /// IPTV pipeline can never inherit VOD tuning. Null until tuning has
  /// actually touched the player — the Standard path never populates it and
  /// so never sets a single property.
  Map<String, String>? networkTuningDefaults;

  /// Serializes tuning applies: a rapid zap starts a newer [VpMediaOpen.openMedia]
  /// while an older one is suspended mid-capture, and interleaved property
  /// writes could land VOD tuning on the newer open's live stream. Each
  /// apply runs WHOLE, in order, and bails via its generation check when a
  /// newer open owns the player.
  Future<void> networkTuningChain = Future<void>.value();

  Future<void> applyNetworkTuning(
    mk.NativePlayer platform,
    NetworkTuning tuning, {
    required bool liveStream,
    required int generation,
  }) {
    return networkTuningChain = networkTuningChain.then(
      (_) => applyNetworkTuningInner(
        platform,
        tuning,
        liveStream: liveStream,
        generation: generation,
      ),
    );
  }

  Future<void> applyNetworkTuningInner(
    mk.NativePlayer platform,
    NetworkTuning tuning, {
    required bool liveStream,
    required int generation,
  }) async {
    final want = liveStream ? const <String, String>{} : tuning.mpvProperties;
    // Standard (and live-before-any-tuning): nothing was ever applied,
    // nothing to restore — the player is untouched.
    if (want.isEmpty && networkTuningDefaults == null) return;
    if (generation != _host.decoderProbeGeneration) {
      return; // superseded in queue
    }
    try {
      if (want.isNotEmpty && networkTuningDefaults == null) {
        final defaults = <String, String>{};
        for (final key in want.keys) {
          final value = await platform.getProperty(key);
          // The vendored getProperty returns '' instead of throwing when mpv
          // has no value. An empty "default" would silently fail to restore
          // later — refuse to tune rather than capture poison.
          if (value.isEmpty) {
            debugPrint('Player: network tuning skipped — $key unreadable');
            return;
          }
          defaults[key] = value;
        }
        if (generation != _host.decoderProbeGeneration) return;
        networkTuningDefaults = defaults;
      }
      for (final entry in networkTuningDefaults!.entries) {
        if (generation != _host.decoderProbeGeneration) return;
        await platform.setProperty(entry.key, want[entry.key] ?? entry.value);
      }
    } catch (e) {
      debugPrint('Player: network tuning apply failed: $e');
    }
  }
}
