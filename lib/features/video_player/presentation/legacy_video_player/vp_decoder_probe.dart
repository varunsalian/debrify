import 'dart:async';
import 'dart:io';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/tvos_decode_remedy.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpDecoderProbeHost {
  AndroidVideoRendererMode get androidVideoRendererMode;
  int get decoderProbeGeneration;
  mk.VideoParams? get decoderProbeParams;
  set decoderProbeParams(mk.VideoParams? v);
  Timer? get decoderProbeTimer;
  set decoderProbeTimer(Timer? v);
  int get decoderProbeToken;
  set decoderProbeToken(int v);
  String? get lastDecoderDiagnosticSignature;
  set lastDecoderDiagnosticSignature(String? v);
  Torrent? get openedWatchSource;
  mk.Player get player;
  int get playerInstanceGeneration;
  int get rendererStartupGuardToken;
  set rendererStartupGuardToken(int v);
  set rendererStartupValidationGeneration(int v);
  TvosDecodeRemedy? get tvosDecodeRemedy;
  MethodChannel get tvReleaseLogChannel;
  void resetTvosDisplayMatchForMediaBoundary();
  void scheduleTvosDisplayMatch(mk.VideoParams params);
  void scheduleRendererStartupValidation();
  bool get mounted;
  bool get isAndroidRendererValidation;
}

class VpDecoderProbe {
  VpDecoderProbe(this._host);
  final VpDecoderProbeHost _host;

  static const MethodChannel androidPlayerDiagnosticChannel = MethodChannel(
    'debrify/player_diagnostics',
  );

  int mediaServerFrameGeneration = -1;

  void handleDecoderProbeParams(mk.VideoParams params) {
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0) {
      // Player.open() normally resets VideoParams before loading the next item.
      // Treat it as an extra invalidation signal, but do not require it: the
      // app-owned generation started in _openMedia is the session boundary.
      _host.decoderProbeToken++;
      _host.decoderProbeTimer?.cancel();
      _host.decoderProbeTimer = null;
      _host.decoderProbeParams = null;
      _host.rendererStartupGuardToken++;
      _host.rendererStartupValidationGeneration = -1;
      _host.resetTvosDisplayMatchForMediaBoundary();
      return;
    }
    if (_host.openedWatchSource != null &&
        mediaServerFrameGeneration != _host.decoderProbeGeneration) {
      mediaServerFrameGeneration = _host.decoderProbeGeneration;
      logSourceSelection(
        'media_server_first_frame',
        source: _host.openedWatchSource,
        player: 'mpv',
      );
    }
    _host.decoderProbeParams = params;
    _host.scheduleTvosDisplayMatch(params);
    scheduleDecoderProbe();
    _host.scheduleRendererStartupValidation();
    final remedy = _host.tvosDecodeRemedy;
    if (remedy != null) {
      // Only ever STARTS the ladder (from idle, on a triggering format) —
      // the ladder's own transitional events are ignored inside it.
      unawaited(remedy.evaluate(params, _host.decoderProbeGeneration));
    }
  }

  Future<void> installDecoderObservers(
    int instanceGeneration,
    mk.Player player,
  ) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;

    // ANDROID ONLY, deliberately.
    //
    // These observers exist to feed the Android explicit-renderer fallback
    // (`_scheduleRendererStartupValidation`), which is itself
    // gated on `Platform.isAndroid` — so everywhere else they were pure cost.
    //
    // They are also `mpv_observe_property` calls issued unawaited, at the same
    // moment the video controller is building the native render context on its
    // own worker — which is the window a tvOS SIGABRT was landing in.
    //
    // NOT confirmed as the cause: the crash stopped after this change AND a
    // reinstall that wiped the device's preferences, and either could have
    // done it. Kept regardless, because a probe that only feeds an
    // Android-gated fallback has no business running anywhere else.
    if (!_host.isAndroidRendererValidation) return;

    try {
      await platform.observeProperty('hwdec-current', (value) async {
        if (_host.mounted &&
            instanceGeneration == _host.playerInstanceGeneration) {
          scheduleDecoderProbe();
        }
      });
    } catch (_) {
      // The one-shot query below still works if this property is unavailable.
    }
    try {
      await platform.observeProperty('current-vo', (value) async {
        if (_host.mounted &&
            instanceGeneration == _host.playerInstanceGeneration) {
          scheduleDecoderProbe();
        }
      });
    } catch (_) {
      // Keep the independent hwdec observer when only current-vo is unavailable.
    }
  }

  void scheduleDecoderProbe() {
    final params = _host.decoderProbeParams;
    if (params == null) return;
    _host.decoderProbeTimer?.cancel();
    final generation = _host.decoderProbeGeneration;
    final token = ++_host.decoderProbeToken;
    _host.decoderProbeTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(
        reportActiveVideoDecoder(
          params: params,
          generation: generation,
          token: token,
        ),
      );
    });
  }

  Future<void> reportActiveVideoDecoder({
    required mk.VideoParams params,
    required int generation,
    required int token,
  }) async {
    final platform = _host.player.platform;
    if (platform is! mk.NativePlayer) {
      emitDecoderDiagnosticOnce(
        generation: generation,
        signature: 'web',
        fields:
            'phase=stable status=unavailable platform=web backend=web '
            'reason=no_native_decoder',
      );
      return;
    }

    var decoder = '';
    var codec = '';
    var output = '';
    var previousDecoder = '';
    var previousOutput = '';
    var stable = false;
    // Audio, read on the DEVICE side (AUDIO_FIDELITY_PLAN.md): what the AO
    // actually writes, not what the decoder produced — the gap between the
    // two is the downgrade being diagnosed.
    var aoName = '';
    var audioChannels = '';
    var previousAo = '';
    var previousAudioChannels = '';
    var audioCodec = '';
    var decodedChannels = '';
    var audioFormat = '';

    try {
      // VideoParams means a decoder has produced metadata, not necessarily
      // that the output surface has finished attaching. Require two matching
      // reads so an early `current-vo=null` is never presented as the verdict.
      // Audio joins the match condition but not the readiness one: a
      // video-only file has no AO to wait for, and empty-matches-empty.
      for (var attempt = 0; attempt < 12; attempt++) {
        if (!_host.mounted ||
            generation != _host.decoderProbeGeneration ||
            token != _host.decoderProbeToken) {
          return;
        }
        decoder = await platform.getProperty('hwdec-current');
        output = await platform.getProperty('current-vo');
        aoName = await platform.getProperty('current-ao');
        audioChannels = await platform.getProperty(
          'audio-out-params/channel-count',
        );
        final outputReady = output.isNotEmpty && output != 'null';
        final decoderReady = decoder.isNotEmpty;
        if (decoderReady &&
            outputReady &&
            decoder == previousDecoder &&
            output == previousOutput &&
            aoName == previousAo &&
            audioChannels == previousAudioChannels) {
          stable = true;
          break;
        }
        previousDecoder = decoder;
        previousOutput = output;
        previousAo = aoName;
        previousAudioChannels = audioChannels;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!_host.mounted ||
          generation != _host.decoderProbeGeneration ||
          token != _host.decoderProbeToken) {
        return;
      }
      codec = await platform.getProperty('video-codec');
      audioCodec = await platform.getProperty('audio-codec-name');
      decodedChannels = await platform.getProperty(
        'audio-params/channel-count',
      );
      audioFormat = await platform.getProperty('audio-out-params/format');
    } catch (_) {
      if (!_host.mounted || generation != _host.decoderProbeGeneration) return;
      emitDecoderDiagnosticOnce(
        generation: generation,
        signature: 'error',
        fields:
            'phase=error status=unavailable '
            'platform=${Platform.operatingSystem} reason=property_query_failed',
      );
      return;
    }

    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    final status = decoder == 'no'
        ? 'software'
        : decoder.isEmpty
        ? 'unavailable'
        : 'hardware';
    final normalizedOutput = output.isEmpty || output == 'null'
        ? 'unknown'
        : output;
    final requestedRenderer = Platform.isAndroid
        ? _host.androidVideoRendererMode.storageKey
        : 'platform_default';
    // The remedy journey (tvOS): what the decoder produced originally, what
    // it produces now, and where the ladder settled. In the signature too —
    // a settle re-arms this probe, and dedupe on the old signature would
    // swallow exactly the report that proves the remedy ran.
    final remedy = _host.tvosDecodeRemedy;
    final remedyState = switch (remedy?.state) {
      null || TvosRemedyState.none => 'none',
      TvosRemedyState.nv12 => 'nv12',
      TvosRemedyState.software => 'software',
      TvosRemedyState.gaveUp => 'gave_up',
    };
    // confirmed/failed mean the remedy's own settling poll verified the
    // format by DIRECT read — the stream-captured params above can lag
    // behind a settle (no final event is guaranteed after reconfig).
    final remedyOutcome = remedy == null
        ? 'none'
        : remedy.applying
        ? 'pending'
        : switch (remedy.state) {
            TvosRemedyState.none => 'none',
            TvosRemedyState.nv12 || TvosRemedyState.software => 'confirmed',
            TvosRemedyState.gaveUp => 'failed',
          };
    final remedyFields = remedy == null
        ? ''
        : 'pixelformat=${params.pixelformat ?? 'unknown'} '
              'hw_pixelformat=${params.hwPixelformat ?? 'none'} '
              'detected_hw_pixelformat=${remedy.detectedHwPixelformat ?? 'none'} '
              'verified_hw_pixelformat=${remedy.verifiedHwPixelformat ?? 'none'} '
              'gamma=${params.gamma ?? 'unknown'} '
              'primaries=${params.primaries ?? 'unknown'} '
              'remedy=$remedyState remedy_outcome=$remedyOutcome ';
    final signature =
        '$decoder|$normalizedOutput|$codec|${width}x$height|'
        '$remedyState|$remedyOutcome';
    emitDecoderDiagnosticOnce(
      generation: generation,
      signature: signature,
      fields:
          'phase=${stable ? 'stable' : 'partial'} status=$status '
          'platform=${Platform.operatingSystem} backend=libmpv '
          'codec=${codec.isEmpty ? 'unknown' : codec} '
          'decoder=${decoder.isEmpty ? 'unknown' : decoder} '
          'output=$normalizedOutput '
          '$remedyFields'
          'audio_codec=${audioCodec.isEmpty ? 'none' : audioCodec} '
          'decoded_channels=${decodedChannels.isEmpty ? 'none' : decodedChannels} '
          'audio_channels=${audioChannels.isEmpty ? 'none' : audioChannels} '
          'audio_format=${audioFormat.isEmpty ? 'none' : audioFormat} '
          'ao=${aoName.isEmpty ? 'none' : aoName} '
          'requested_renderer=$requestedRenderer '
          'resolution=${width}x$height',
    );
  }

  void emitDecoderDiagnosticOnce({
    required int generation,
    required String signature,
    required String fields,
  }) {
    if (generation != _host.decoderProbeGeneration) return;
    final taggedSignature = '$generation|$signature';
    if (_host.lastDecoderDiagnosticSignature == taggedSignature) return;
    _host.lastDecoderDiagnosticSignature = taggedSignature;
    releasePlayerDiagnostic('generation=$generation $fields');
  }

  void releasePlayerDiagnostic(String fields) {
    final message = 'DEBRIFY_PLAYER_DECODER $fields';
    if (Platform.isAndroid) {
      // A dedicated native tag lets release captures select only this
      // privacy-safe line. Capturing Flutter's general stdout exposed unrelated
      // service logs and must not be required for decoder diagnostics.
      unawaited(
        androidPlayerDiagnosticChannel
            .invokeMethod<void>('logDecoder', {'message': fields})
            .catchError((_) {}),
      );
      return;
    }
    if (PlatformUtil.isTvOS) {
      // tvOS release builds deliberately do not bridge every debugPrint call,
      // because unrelated logs can contain private playback data. This narrow,
      // privacy-safe diagnostic still needs to reach the Xcode/device console.
      unawaited(
        _host.tvReleaseLogChannel
            .invokeMethod<void>('log', message)
            .catchError((_) {}),
      );
      return;
    }

    // Intentional: print reaches desktop process consoles in release builds.
    // Keep this payload free of titles, URLs and account IDs.
    // ignore: avoid_print
    print(message);
  }
}
