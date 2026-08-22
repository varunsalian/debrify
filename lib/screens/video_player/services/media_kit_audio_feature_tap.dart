import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'subtitle_aligner.dart';

typedef AudioFrameStatistics = ({
  double bandRms,
  double broadbandRms,
  int samples,
});

/// A passive, opt-in feature tap for MediaKit's existing decoded-audio path.
///
/// The labelled FFmpeg filters only attach metadata to audio frames. They do
/// not create another decoder, touch the network, write audio to disk, or own
/// an audio output. Raw PCM never crosses FFI; Dart receives a handful of
/// numeric statistics per decoded frame and reduces them to the same 32 ms
/// feature shape used by Android TV's ExoPlayer tap.
class MediaKitAudioFeatureTap {
  MediaKitAudioFeatureTap({
    required mk.NativePlayer player,
    required int Function() currentPositionMs,
  }) : _player = player,
       _currentPositionMs = currentPositionMs;

  static const String filterLabel = 'debrify_autosync';
  static const String metadataProperty = 'af-metadata/$filterLabel';

  // astats is sample-transparent. aspectralstats adds frequency-domain
  // metadata used as a conservative speech-band proxy; both forward the same
  // audio frame to the existing output.
  static const String _filter =
      '@$filterLabel:lavfi=['
      'astats=metadata=1:reset=1:'
      'measure_perchannel=none:'
      'measure_overall=RMS_level+Number_of_samples,'
      'aspectralstats=measure=centroid'
      ']';

  static const int _targetFrameMs = 32;
  static const int _rolloverFrames = 18750;
  static const int _maxFrames = 120000;

  final mk.NativePlayer _player;
  final int Function() _currentPositionMs;
  final List<_MutableFeatureSegment> _closed = <_MutableFeatureSegment>[];

  _MutableFeatureSegment? _current;
  bool _installed = false;
  bool _disposed = false;
  int _sampleRate = 48000;
  int? _lastObservedPositionMs;

  bool get installed => _installed;

  double get anchoredDurationMs {
    var total = 0.0;
    for (final segment in _closed) {
      total += segment.durationMs;
    }
    total += _current?.durationMs ?? 0;
    return total;
  }

  Future<bool> install() async {
    if (_disposed || _installed) return _installed;
    try {
      final rate = int.tryParse(
        await _player.getProperty('audio-params/samplerate'),
      );
      if (rate != null && rate > 0) _sampleRate = rate;
      _openSegment(_currentPositionMs());
      await _player.observePropertyMap(metadataProperty, _onMetadata);
      try {
        await _player.command(<String>[
          'af',
          'add',
          _filter,
        ], throwOnError: true);
      } catch (_) {
        await _player.unobserveProperty(metadataProperty);
        rethrow;
      }
      _installed = true;
      return true;
    } catch (error) {
      debugPrint('SubtitleAutoSync: passive audio filter unavailable: $error');
      _installed = false;
      _current = null;
      return false;
    }
  }

  Future<void> uninstall() async {
    if (!_installed) return;
    _installed = false;
    try {
      await _player.unobserveProperty(metadataProperty);
    } catch (_) {
      // Player teardown can win this race. The property observation dies with
      // the native handle, and playback must not wait on diagnostic cleanup.
    }
    try {
      await _player.command(<String>['af', 'remove', '@$filterLabel']);
    } catch (_) {
      // Same fail-soft rule as above. Removing our unique label cannot be
      // allowed to interfere with disposal or a source transition.
    }
  }

  void reset({int? anchorMs}) {
    _closed.clear();
    _current = null;
    _lastObservedPositionMs = anchorMs;
    if (_installed) _openSegment(anchorMs ?? _currentPositionMs());
  }

  Future<void> resetForAudioTrack({required int anchorMs}) async {
    if (!_installed || _disposed) return;
    try {
      final rate = int.tryParse(
        await _player.getProperty('audio-params/samplerate'),
      );
      if (rate != null && rate > 0) _sampleRate = rate;
    } catch (error) {
      // Keep the last known rate. Most tracks are 48 kHz, and abandoning the
      // feature is safer than disturbing playback over a diagnostic query.
      debugPrint('SubtitleAutoSync: sample-rate refresh failed: $error');
    }
    reset(anchorMs: anchorMs);
  }

  /// Detect app/player seeks without replacing every existing seek call site.
  /// Normal position emissions advance in small steps; a jump starts a fresh
  /// anchored feature segment. Small AO-buffer differences are deliberately
  /// ignored so pause/resume cannot fragment history.
  bool observePosition(int positionMs) {
    final previous = _lastObservedPositionMs;
    _lastObservedPositionMs = positionMs;
    if (!_installed || previous == null) return false;
    if ((positionMs - previous).abs() > 1500) {
      _closeCurrent();
      _openSegment(positionMs);
      return true;
    }
    return false;
  }

  List<AudioFeatureSegment> snapshot() {
    return <AudioFeatureSegment>[
      for (final segment in _closed) segment.snapshot(),
      if (_current case final current?) current.snapshot(),
    ];
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await uninstall();
    _closed.clear();
    _current = null;
  }

  void _openSegment(int anchorMs) {
    final frameSamples = math.max(1, (_sampleRate * _targetFrameMs) ~/ 1000);
    _current = _MutableFeatureSegment(
      anchorMs: anchorMs,
      sampleRate: _sampleRate,
      frameSamples: frameSamples,
    );
  }

  void _closeCurrent() {
    final segment = _current;
    _current = null;
    if (segment != null && segment.frameCount > 0) _closed.add(segment);
    _trim();
  }

  void _trim() {
    var frames = _closed.fold<int>(
      0,
      (sum, segment) => sum + segment.frameCount,
    );
    frames += _current?.frameCount ?? 0;
    while (frames > _maxFrames && _closed.isNotEmpty) {
      frames -= _closed.removeAt(0).frameCount;
    }
  }

  void _onMetadata(Map<String, String> metadata) {
    if (!_installed || _disposed) return;
    ingestMetadata(metadata);
  }

  @visibleForTesting
  void ingestMetadata(Map<String, String> metadata) {
    final statistics = decodeMetadata(metadata, _sampleRate);
    if (statistics == null) return;

    var segment = _current;
    segment ??= _MutableFeatureSegment(
      anchorMs: _currentPositionMs(),
      sampleRate: _sampleRate,
      frameSamples: math.max(1, (_sampleRate * _targetFrameMs) ~/ 1000),
    );
    _current = segment;
    segment.addFrameStatistics(
      bandRms: statistics.bandRms,
      broadbandRms: statistics.broadbandRms,
      samples: statistics.samples,
    );
    if (segment.frameCount >= _rolloverFrames) {
      final continuationAnchor = segment.anchorMs + segment.durationMs.round();
      _closeCurrent();
      _openSegment(continuationAnchor);
    }
  }

  @visibleForTesting
  static AudioFrameStatistics? decodeMetadata(
    Map<String, String> metadata,
    int sampleRate,
  ) {
    final rmsText = metadata['lavfi.astats.Overall.RMS_level']?.trim();
    if (rmsText == null) return null;
    final normalizedRms = rmsText.toLowerCase();
    final silent = normalizedRms == '-inf' || normalizedRms == '-infinity';
    final rmsDb = silent ? double.negativeInfinity : double.tryParse(rmsText);
    if (rmsDb == null || (rmsDb.isInfinite && !rmsDb.isNegative)) return null;
    if (rmsDb.isNaN) return null;

    final sampleValue = double.tryParse(
      metadata['lavfi.astats.Overall.Number_of_samples'] ?? '',
    );
    if (sampleValue == null || !sampleValue.isFinite || sampleValue <= 0) {
      return null;
    }
    final samples = sampleValue.round();

    var centroidSum = 0.0;
    var centroidCount = 0;
    for (final entry in metadata.entries) {
      if (!entry.key.startsWith('lavfi.aspectralstats.') ||
          !entry.key.endsWith('.centroid')) {
        continue;
      }
      final value = double.tryParse(entry.value);
      if (value != null && value.isFinite) {
        centroidSum += value;
        centroidCount++;
      }
    }
    final centroid = centroidCount == 0 ? 1700.0 : centroidSum / centroidCount;
    final broadband = silent ? 0.0 : math.pow(10, rmsDb / 20).toDouble();
    final band = broadband * _speechBandProxy(centroid, sampleRate);
    return (bandRms: band, broadbandRms: broadband, samples: samples);
  }

  /// aspectralstats does not expose an integrated 300–3400 Hz band. Its
  /// centroid still lets us conservatively down-weight bass-heavy score and
  /// high-frequency effects while leaving dialogue-band frames untouched.
  static double _speechBandProxy(double centroid, int sampleRate) {
    final nyquist = sampleRate / 2;
    final upper = math.min(5200.0, nyquist * 0.9);
    final lowWeight = ((centroid - 120) / 500).clamp(0.2, 1.0);
    final highWeight = ((upper - centroid) / 1800).clamp(0.2, 1.0);
    return math.min(lowWeight, highWeight);
  }
}

class _MutableFeatureSegment {
  _MutableFeatureSegment({
    required this.anchorMs,
    required this.sampleRate,
    required this.frameSamples,
  });

  final int anchorMs;
  final int sampleRate;
  final int frameSamples;
  final List<double> _band = <double>[];
  final List<double> _broadband = <double>[];

  double _bandEnergy = 0;
  double _broadbandEnergy = 0;
  int _accumulatedSamples = 0;

  int get frameCount => _band.length;
  double get frameDurationMs => frameSamples * 1000.0 / sampleRate;
  double get durationMs => frameCount * frameDurationMs;

  void addFrameStatistics({
    required double bandRms,
    required double broadbandRms,
    required int samples,
  }) {
    var remaining = samples;
    while (remaining > 0) {
      final take = math.min(frameSamples - _accumulatedSamples, remaining);
      _bandEnergy += bandRms * bandRms * take;
      _broadbandEnergy += broadbandRms * broadbandRms * take;
      _accumulatedSamples += take;
      remaining -= take;
      if (_accumulatedSamples == frameSamples) {
        _band.add(math.sqrt(_bandEnergy / frameSamples));
        _broadband.add(math.sqrt(_broadbandEnergy / frameSamples));
        _bandEnergy = 0;
        _broadbandEnergy = 0;
        _accumulatedSamples = 0;
      }
    }
  }

  AudioFeatureSegment snapshot() => AudioFeatureSegment(
    anchorMs: anchorMs,
    sampleRate: sampleRate,
    frameSamples: frameSamples,
    band: List<double>.unmodifiable(_band),
    broadband: List<double>.unmodifiable(_broadband),
  );
}
