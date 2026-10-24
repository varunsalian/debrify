import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

abstract interface class VpPlayerInstanceHost {
  bool get anyPlayerOverlayOpen;
  ValueNotifier<bool> get controlsVisible;
  IptvChannel? get currentIptvChannel;
  Timer? get hideTimer;
  set isReady(bool v);
  set player(mk.Player v);
  set playerCreated(bool v);
  int get playerInstanceGeneration;
  set playerInstanceGeneration(int v);
  FocusScopeNode get tvBarScope;
  FocusNode get tvPlayPauseFocus;
  bool get tvosForceSoftwareDecode;
  set videoController(mkv.VideoController v);
  void bindPlayerInstanceSubscriptions(
    int instanceGeneration,
    mk.Player player,
  );
  bool get mounted;
  void setState(VoidCallback fn);
  mk.Player createPlayer({required mk.PlayerConfiguration configuration});
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  });
  void raiseDebrifyBanner();
  Future<void> installDecoderObservers(
    int instanceGeneration,
    mk.Player player,
  );
  Future<void> applyAspectVideoZoom();
  void prepareIptvBannerData(IptvChannel channel);
  void raiseIptvZapBanner();
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories});
  void armPipAutoEnter();
  void installTvosDecodeRemedy(mk.Player player);
  void ensureIptvZapPagingArmed();
}

class VpPlayerInstance {
  VpPlayerInstance(this._host);
  final VpPlayerInstanceHost _host;

  bool playerPresentationInitialized = false;

  void createPlayerInstance(AndroidVideoRendererMode rendererMode) {
    final instanceGeneration = ++_host.playerInstanceGeneration;
    _host.isReady = false;
    final player = _host.createPlayer(
      configuration: mk.PlayerConfiguration(
        logLevel: mk.MPVLogLevel.error,
        ready: () => onPlayerInstanceReady(instanceGeneration),
      ),
    );
    _host.player = player;
    _host.playerCreated = true;
    _host.videoController = _host.createVideoController(
      player,
      configuration: mkv.VideoControllerConfiguration(
        vo: rendererMode.videoOutput,
        // The tvOS escape hatch outranks the renderer mode (which is an
        // Android concept; its decoder string is null off-Android anyway).
        hwdec: PlatformUtil.isTvOS && _host.tvosForceSoftwareDecode
            ? 'no'
            : rendererMode.hardwareDecoder,
      ),
    );
    _host.installTvosDecodeRemedy(player);
    _host.bindPlayerInstanceSubscriptions(instanceGeneration, player);
    unawaited(_host.installDecoderObservers(instanceGeneration, player));
    unawaited(_host.applyAspectVideoZoom());
  }

  void onPlayerInstanceReady(int instanceGeneration) {
    if (!_host.mounted || instanceGeneration != _host.playerInstanceGeneration)
      return;
    _host.isReady = true;
    _host.armPipAutoEnter();
    if (PlatformUtil.isTelevision && _host.controlsVisible.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Never while a guide/sheet is up: on tvOS IPTV the instance becomes
        // ready SECONDS after a zap (and again on remedy-ladder restarts), so
        // this fired after the sheet's one-shot focus claim and silently
        // yanked the remote off it — the guide's focus went dead at random.
        if (_host.mounted &&
            instanceGeneration == _host.playerInstanceGeneration &&
            _host.controlsVisible.value &&
            !_host.anyPlayerOverlayOpen &&
            !_host.tvBarScope.hasFocus) {
          _host.tvPlayPauseFocus.requestFocus();
        }
      });
    }
    _host.setState(() {});

    // These are screen-presentation side effects, not player-instance setup.
    // Re-running them during the compatibility restart would re-raise launch
    // banners and reset guide context while preserving the same media item.
    if (playerPresentationInitialized) return;
    playerPresentationInitialized = true;
    final iptvChannel = _host.currentIptvChannel;
    if (iptvChannel != null && iptvChannel.isLive) {
      _host.hideTimer?.cancel();
      _host.controlsVisible.value = false;
      _host.prepareIptvBannerData(iptvChannel);
      _host.raiseIptvZapBanner();
      _host.anchorIptvGuideCategory(iptvChannel);
      _host.ensureIptvZapPagingArmed();
    } else {
      _host.raiseDebrifyBanner();
    }
  }
}
