// The players behind multi-view tiles.
//
// Android TV uses the native ExoPlayer texture engine (no Flutter video
// output involved, several players allowed; the texture is capped in height
// so four tiles stay within weak TV GPUs). Phones, tablets and desktops use
// media_kit players that skip the app-wide VideoOutputLease: that lease
// exists for tvOS, which aborts on a second video output and never shows
// multi-view (multiViewMaxTiles is 0 there). The caller pauses the IPTV preview
// and finishes every tile's disposal before the full player opens.
import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/utils/media_kit_init.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/trailer_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// This device's multi-view platform (tvOS has none: zero tiles).
MultiViewPlatform currentMultiViewPlatform() {
  if (PlatformUtil.isTvOS) return MultiViewPlatform.tvos;
  if (PlatformUtil.isAndroidTvCached) return MultiViewPlatform.androidTv;
  if (PlatformUtil.isIosMobile) return MultiViewPlatform.ios;
  if (PlatformUtil.isDesktop) return MultiViewPlatform.desktop;
  return MultiViewPlatform.android;
}

/// Builds the engine for one tile of a [tileCount]-tile grid.
Future<TrailerEngine> createMultiViewEngine(
  IptvChannel channel, {
  required int tileCount,
}) async {
  if (PlatformUtil.isAndroidTvCached) {
    return ExoTrailerEngine(maxHeight: tileCount > 2 ? 540 : 720);
  }
  return _TileMediaKitEngine();
}

/// A media_kit player for one tile, without the single-output lease.
final class _TileMediaKitEngine implements TrailerEngine {
  _TileMediaKitEngine() {
    MediaKitInit.ensureInitialized();
    _player = mk.Player();
    _controller = mkv.VideoController(_player);
  }

  late final mk.Player _player;
  late final mkv.VideoController _controller;
  bool _detached = false;
  Future<void>? _disposal;

  @override
  bool get rendersUnderlay => false;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  // mpv reports recoverable stream errors here too; like the trailer
  // engine's default, they are not treated as fatal for a tile.
  @override
  Stream<void> get errorStream => const Stream<void>.empty();
  @override
  Future<void> get firstFrameRendered =>
      _controller.waitUntilFirstFrameRendered;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    // Re-check after every await: media_kit throws on use after dispose.
    await _player.setVolume(volume);
    if (_detached) return;
    await _player.open(mk.Media(videoUrl, httpHeaders: httpHeaders));
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_detached) await _player.setVolume(volume);
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_detached) await _player.seek(position);
  }

  @override
  Future<void> play() async {
    if (!_detached) await _player.play();
  }

  @override
  Future<void> pause() async {
    if (!_detached) await _player.pause();
  }

  @override
  void detach() => _detached = true;

  /// A second call joins the first disposal instead of running beside it.
  @override
  Future<void> dispose() {
    _detached = true;
    return _disposal ??= _player.dispose();
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) =>
      mkv.Video(controller: _controller, controls: null, fit: fit);
}
