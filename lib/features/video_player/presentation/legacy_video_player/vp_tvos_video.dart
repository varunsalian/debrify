import 'dart:async';

import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/services/tvos_decode_remedy.dart';
import 'package:debrify/services/tvos_display_match_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpTvosVideoHost {
  ContentDisplayMatchMode get contentDisplayMatchMode;
  mk.Player get player;
  bool get screenDisposed;
  TvosDecodeRemedy? get tvosDecodeRemedy;
  set tvosDecodeRemedy(TvosDecodeRemedy? v);
  Timer? get tvosDisplayMatchTimer;
  set tvosDisplayMatchTimer(Timer? v);
  int get tvosDisplayMatchToken;
  set tvosDisplayMatchToken(int v);
  void scheduleDecoderProbe();
  bool get mounted;
}

class VpTvosVideo {
  VpTvosVideo(this._host);
  final VpTvosVideoHost _host;

  String? lastTvosDisplayMatchSignature;

  /// tvOS only: the 10-bit remedy ladder, bound to THIS player instance's
  /// property interface. Plain post-create property access — deliberately
  /// not `mpv_observe_property` (see the SIGABRT note in
  /// [_installDecoderObservers]); the ladder is driven by the existing
  /// Dart-side videoParams stream instead.
  void installTvosDecodeRemedy(mk.Player player) {
    if (!PlatformUtil.isTvOS) return;
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;
    _host.tvosDecodeRemedy?.dispose();
    _host.tvosDecodeRemedy = TvosDecodeRemedy(
      getProperty: platform.getProperty,
      setProperty: platform.setProperty,
      // The standard 8-bit-surface pin, applied before every file's decoder
      // exists: 8-bit content is NV12 already (no change), 10-bit decodes
      // straight to NV12 with no blue flash and no mid-play cycle. The
      // reactive ladder underneath only ever engages if VideoToolbox
      // rejects the pin for some exotic stream.
      pinNv12FromStart: true,
      // A settle is a decode-path change the one-shot probe has already
      // reported around — re-arm it so the diagnostic line carries the
      // remedy journey.
      onStateChanged: () {
        if (_host.mounted) _host.scheduleDecoderProbe();
      },
    );
  }

  void resetTvosDisplayMatchForMediaBoundary() {
    _host.tvosDisplayMatchToken++;
    _host.tvosDisplayMatchTimer?.cancel();
    _host.tvosDisplayMatchTimer = null;
    lastTvosDisplayMatchSignature = null;
    if (!PlatformUtil.isTvOS ||
        !_host.contentDisplayMatchMode.requestsMatching) {
      return;
    }
    // AVDisplayManager retains criteria until explicitly replaced. Clear the
    // outgoing item's request so content with missing/invalid fps metadata can
    // never inherit the previous refresh rate.
    unawaited(
      TvosDisplayMatchService.clear().catchError((Object error) {
        debugPrint('DisplayMatch: tvOS boundary clear failed: $error');
      }),
    );
  }

  void scheduleTvosDisplayMatch(mk.VideoParams params) {
    if (!PlatformUtil.isTvOS ||
        !_host.contentDisplayMatchMode.requestsMatching) {
      return;
    }
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0) return;
    final token = ++_host.tvosDisplayMatchToken;
    _host.tvosDisplayMatchTimer?.cancel();
    _host
        .tvosDisplayMatchTimer = Timer(const Duration(milliseconds: 200), () async {
      if (_host.screenDisposed || token != _host.tvosDisplayMatchToken) return;
      final platform = _host.player.platform;
      if (platform is! mk.NativePlayer) return;
      final selectedTrack = _host.player.state.track.video;
      var fps = selectedTrack.fps;
      if (fps == null || !fps.isFinite || fps <= 0) {
        for (final property in const ['container-fps', 'estimated-vf-fps']) {
          try {
            final candidate = double.tryParse(
              await platform.getProperty(property),
            );
            if (candidate != null && candidate.isFinite && candidate > 0) {
              fps = candidate;
              break;
            }
          } catch (_) {
            // Some containers publish only one of the two fps properties.
          }
        }
      }
      if (_host.screenDisposed ||
          token != _host.tvosDisplayMatchToken ||
          fps == null ||
          !fps.isFinite ||
          fps <= 0) {
        return;
      }
      var codec = selectedTrack.codec;
      if (codec == null || codec.isEmpty) {
        try {
          codec = await platform.getProperty('video-codec');
        } catch (_) {
          codec = null;
        }
      }
      if (_host.screenDisposed || token != _host.tvosDisplayMatchToken) return;
      final signature =
          '${_host.contentDisplayMatchMode.storageKey}|$width|$height|${fps.toStringAsFixed(4)}|${codec ?? ''}';
      if (signature == lastTvosDisplayMatchSignature) return;
      try {
        final status = await TvosDisplayMatchService.apply(
          mode: _host.contentDisplayMatchMode,
          width: width,
          height: height,
          refreshRate: fps,
          codec: codec,
        );
        if (_host.screenDisposed || token != _host.tvosDisplayMatchToken)
          return;
        lastTvosDisplayMatchSignature = signature;
        debugPrint(
          'DisplayMatch: tvOS requested ${width}x$height@${fps.toStringAsFixed(3)} '
          'mode=${_host.contentDisplayMatchMode.storageKey} '
          'enabled=${status['matchingEnabled']}',
        );
      } catch (error) {
        debugPrint('DisplayMatch: tvOS request failed: $error');
      }
    });
  }
}
