import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../../../utils/app_storage.dart';
import '../../../utils/platform_util.dart';
import 'subtitle_aligner.dart';

typedef AudioFrameStatistics = ({
  double bandRms,
  double broadbandRms,
  int samples,
});

/// A passive, opt-in feature tap for MediaKit's existing decoded-audio path.
///
/// The labelled FFmpeg filters only attach metadata to audio frames. They do
/// not create another decoder, touch the network, or own an audio output. Raw
/// PCM never crosses FFI; Dart receives a handful of numeric statistics per
/// decoded frame and reduces them to the same 32 ms feature shape used by
/// Android TV's ExoPlayer tap.
///
/// Transport, in preference order:
///
/// 1. FILE — `ametadata=mode=print:file=…` makes the FFmpeg filter thread
///    itself write one record per frame, each carrying its own `pts_time`.
///    Nothing crosses mpv's event loop, so nothing can be coalesced away, and
///    feature frames are timestamped from ground truth instead of assumed
///    contiguity. Dart tails the file on a coarse timer.
/// 2. PROPERTY — the previous `af-metadata` observation, kept as a fallback
///    for frameworks built without the `ametadata` filter. libmpv property
///    observation coalesces by design (only the latest value is delivered),
///    which was measured losing ~half the frames on macOS; the [reliable]
///    guard detects that accrual deficit so the controller declines instead
///    of syncing against a time-warped feature timeline.
///
/// Either way, every closed segment's frame grid is validated against real
/// time: in file mode each record's pts must match the accumulated duration
/// (drift re-anchors the segment), so a lossy stream fragments into segments
/// too short for the aligner to use — degrading to "didn't guess", never to a
/// wrong sync.
class MediaKitAudioFeatureTap {
  MediaKitAudioFeatureTap({
    required mk.NativePlayer player,
    required int Function() currentPositionMs,
  }) : _player = player,
       _currentPositionMs = currentPositionMs;

  /// Exercises ingestion and segmentation without a live player. Install /
  /// uninstall paths must not be called on an instance built this way.
  @visibleForTesting
  MediaKitAudioFeatureTap.forTesting({
    required int Function() currentPositionMs,
    int sampleRate = 48000,
    bool fileMode = true,
  }) : _player = null,
       _currentPositionMs = currentPositionMs {
    _sampleRate = sampleRate;
    _installed = true;
    _fileMode = fileMode;
  }

  static const String filterLabel = 'debrify_autosync';
  static const String metadataProperty = 'af-metadata/$filterLabel';

  // astats is sample-transparent. aspectralstats adds frequency-domain
  // metadata used as a conservative speech-band proxy; both forward the same
  // audio frame to the existing output.
  static const String _analysisChain =
      'astats=metadata=1:reset=1:'
      'measure_perchannel=none:'
      'measure_overall=RMS_level+Number_of_samples,'
      'aspectralstats=measure=centroid';

  static const String _propertyFilter =
      '@$filterLabel:lavfi=[$_analysisChain]';

  static String _fileFilter(String path) =>
      '@$filterLabel:lavfi=[$_analysisChain,'
      'ametadata=mode=print:file=$path]';

  static const int _targetFrameMs = 32;
  static const int _rolloverFrames = 18750;
  static const int _maxFrames = 120000;

  /// A record's pts may differ from the segment's accumulated duration by at
  /// most this much before the segment re-anchors. Keeps any accounting error
  /// bounded well inside the aligner's tolerance.
  static const int _maxDriftMs = 120;

  /// File mode tail cadence. The filter writes through FFmpeg's buffered
  /// avio, so records land in bursts; a coarse poll is plenty and keeps all
  /// I/O far away from the audio path.
  static const Duration _tailInterval = Duration(milliseconds: 500);

  final mk.NativePlayer? _player;
  final int Function() _currentPositionMs;

  mk.NativePlayer get _requirePlayer =>
      _player ?? (throw StateError('forTesting tap has no player'));
  final List<_MutableFeatureSegment> _closed = <_MutableFeatureSegment>[];

  _MutableFeatureSegment? _current;
  bool _installed = false;
  bool _fileMode = false;
  bool _disposed = false;
  int _sampleRate = 48000;
  int? _lastObservedPositionMs;

  // File transport state.
  File? _metadataFile;
  Timer? _tailTimer;
  bool _polling = false;
  int _pollFailures = 0;
  int _tailOffset = 0;
  String _tailPartial = '';
  int? _pendingPtsMs;
  final Map<String, String> _pendingRecord = <String, String>{};

  // Reliability accounting (matters for the property fallback): how much
  // forward playback the tap has witnessed vs how much feature audio it has
  // accrued over that same span. Accrual is a monotonic counter, NOT derived
  // from anchoredDurationMs — _trim() caps that at ~64 min, which would make
  // a long unbroken session read as ever-growing "loss".
  double _witnessedAdvanceMs = 0;
  double _totalAccruedMs = 0;
  double _accruedAtWitnessStartMs = 0;
  bool _reliable = true;

  bool get installed => _installed;

  /// False once the tap has demonstrably lost a meaningful share of the
  /// audio it should have seen. The controller must decline rather than
  /// align against a distorted feature timeline.
  bool get reliable => _reliable;

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
        await _requirePlayer.getProperty('audio-params/samplerate'),
      );
      if (rate != null && rate > 0) _sampleRate = rate;

      if (await _installFileTransport()) {
        _installed = true;
        _fileMode = true;
        debugPrint('SubtitleAutoSync: tap installed (file transport)');
        return true;
      }

      // tvOS never falls back: mpv_observe_property is the suspected window
      // for a past tvOS SIGABRT (see _installTvosDecodeRemedy's avoidance of
      // it), and this codebase deliberately keeps observers off that
      // platform. No transport ⇒ no auto-sync, fail closed.
      if (PlatformUtil.isTvOS) {
        debugPrint(
          'SubtitleAutoSync: file transport unavailable on tvOS — '
          'no fallback, auto-sync disabled for this session',
        );
        _installed = false;
        _current = null;
        return false;
      }

      // Legacy frameworks without the ametadata filter: fall back to the
      // coalescing-prone property observation, guarded by [reliable].
      _openSegment(_currentPositionMs());
      await _requirePlayer.observePropertyMap(metadataProperty, _onMetadata);
      try {
        await _requirePlayer.command(<String>[
          'af',
          'add',
          _propertyFilter,
        ], throwOnError: true);
      } catch (_) {
        await _requirePlayer.unobserveProperty(metadataProperty);
        rethrow;
      }
      _installed = true;
      _fileMode = false;
      debugPrint('SubtitleAutoSync: tap installed (property fallback)');
      return true;
    } catch (error) {
      debugPrint('SubtitleAutoSync: passive audio filter unavailable: $error');
      _installed = false;
      _current = null;
      await _teardownFileTransport();
      return false;
    }
  }

  /// Where the metadata log lives: the app cache directory, NOT systemTemp.
  /// tvOS purges tmp aggressively under storage pressure (Caches is the
  /// platform's sanctioned scratch space — see AppStorage), and on Linux
  /// /tmp is commonly a RAM-backed tmpfs where a multi-hour log would park
  /// tens of MB in memory; the cache dir is disk-backed.
  Future<Directory> _metadataLogDirectory() => AppStorage.cache();

  /// Best-effort sweep of logs orphaned by force-quits/crashes — they are
  /// uniquely named, so nothing else ever deletes them. Anything older than
  /// a day cannot belong to a live player.
  Future<void> _sweepStaleMetadataLogs() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entry in (await _metadataLogDirectory()).list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!name.startsWith('debrify_autosync_') || !name.endsWith('.log')) {
          continue;
        }
        try {
          final stat = await entry.stat();
          if (stat.modified.isBefore(cutoff)) await entry.delete();
        } catch (_) {}
      }
    } catch (_) {
      // Hygiene only; never let a listing failure block the transport.
    }
  }

  Future<bool> _installFileTransport() async {
    File? file;
    await _sweepStaleMetadataLogs();
    try {
      final path =
          '${(await _metadataLogDirectory()).path}${Platform.pathSeparator}'
          'debrify_autosync_${DateTime.now().microsecondsSinceEpoch}.log';
      // The path is spliced into a lavfi graph, where these characters are
      // syntax. Temp paths never contain them on our platforms; if one ever
      // does, use the fallback instead of building a broken graph.
      if (path.contains(':') || path.contains(',') ||
          path.contains('[') || path.contains(']')) {
        return false;
      }
      file = File(path);
      await file.writeAsString('');
      await _requirePlayer.command(<String>[
        'af',
        'add',
        _fileFilter(path),
      ], throwOnError: true);
      _metadataFile = file;
      _tailOffset = 0;
      _tailPartial = '';
      _pendingPtsMs = null;
      _pendingRecord.clear();
      _tailTimer = Timer.periodic(_tailInterval, (_) => _pollMetadataFile());
      return true;
    } catch (error) {
      debugPrint(
        'SubtitleAutoSync: file transport unavailable, will fall back: $error',
      );
      try {
        await file?.delete();
      } catch (_) {}
      _metadataFile = null;
      return false;
    }
  }

  Future<void> _teardownFileTransport() async {
    _tailTimer?.cancel();
    _tailTimer = null;
    final file = _metadataFile;
    _metadataFile = null;
    _tailOffset = 0;
    _tailPartial = '';
    _pendingPtsMs = null;
    _pendingRecord.clear();
    if (file != null) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _pollMetadataFile() async {
    // Re-entrancy guard: a poll that outlasts the 500ms tick (large buffered
    // flush) must not overlap itself — _tailOffset commits only after the
    // reads, and an overlapping tick would double-ingest the same bytes.
    if (_polling) return;
    _polling = true;
    try {
      final file = _metadataFile;
      if (file == null || _disposed || !_installed) return;
      String chunk;
      try {
        final raf = await file.open();
        try {
          final length = await raf.length();
          if (length < _tailOffset) {
            // FFmpeg reopens the log with O_TRUNC whenever the filter graph
            // re-initializes (audio track switch, layout change). A shrunken
            // file means our offset points into discarded history — restart
            // the tail from the top or the tap goes silent for hours.
            _tailOffset = 0;
            _tailPartial = '';
            _pendingPtsMs = null;
            _pendingRecord.clear();
          }
          if (length <= _tailOffset) return;
          await raf.setPosition(_tailOffset);
          final bytes = await raf.read(length - _tailOffset);
          _tailOffset = length;
          chunk = String.fromCharCodes(bytes);
        } finally {
          await raf.close();
        }
      } catch (error) {
        // A transient read failure only delays features — but a PERSISTENT
        // one (tvOS purging Caches under storage pressure, tmpfs ENOSPC)
        // means the transport is dead and would otherwise become a forever
        // silent no-op: the ladder ticking against a frozen 0s of audio.
        // ~10s of consecutive failures declares the tap unreliable so the
        // controller declines honestly.
        if (++_pollFailures >= 20 && _reliable) {
          _reliable = false;
          debugPrint(
            'SubtitleAutoSync: metadata log unreadable for '
            '$_pollFailures polls ($error) — declining',
          );
        }
        return;
      }
      _pollFailures = 0;
      if (_disposed || !_installed) return;
      _consumeChunk(chunk);
    } finally {
      _polling = false;
    }
  }

  /// One framing path for both production tailing and tests: buffer the
  /// trailing partial line, consume every complete one.
  void _consumeChunk(String chunk) {
    final text = _tailPartial + chunk;
    final lines = text.split('\n');
    _tailPartial = lines.removeLast();
    for (final line in lines) {
      _consumeMetadataLine(line.trimRight());
    }
  }

  /// ametadata=mode=print writes, per frame:
  ///
  ///     frame:182  pts:279552   pts_time:5.824
  ///     lavfi.astats.Overall.RMS_level=-27.417328
  ///     lavfi.astats.Overall.Number_of_samples=1024
  ///     lavfi.aspectralstats.1.centroid=1834.211914
  ///
  /// A record is complete only when the NEXT frame header arrives, so a
  /// half-written tail never produces a truncated feature frame.
  void _consumeMetadataLine(String line) {
    if (line.startsWith('frame:')) {
      _flushPendingRecord();
      _pendingPtsMs = _parsePtsTimeMs(line);
      return;
    }
    final separator = line.indexOf('=');
    if (separator <= 0 || _pendingPtsMs == null) return;
    _pendingRecord[line.substring(0, separator)] =
        line.substring(separator + 1);
  }

  void _flushPendingRecord() {
    final ptsMs = _pendingPtsMs;
    if (ptsMs == null || _pendingRecord.isEmpty) {
      _pendingRecord.clear();
      return;
    }
    final statistics = decodeMetadata(
      Map<String, String>.of(_pendingRecord),
      _sampleRate,
    );
    _pendingRecord.clear();
    _pendingPtsMs = null;
    if (statistics == null) return;
    _ingestTimestamped(statistics, ptsMs);
  }

  static int? _parsePtsTimeMs(String header) {
    for (final token in header.split(RegExp(r'\s+'))) {
      if (!token.startsWith('pts_time:')) continue;
      final value = double.tryParse(token.substring('pts_time:'.length));
      if (value == null || !value.isFinite) return null;
      return (value * 1000).round();
    }
    return null;
  }

  /// File-mode ingestion: the record's own pts is the truth. A record whose
  /// pts disagrees with the segment's accumulated duration by more than
  /// [_maxDriftMs] (seek, dropped write, accounting error — any cause)
  /// re-anchors, so no segment ever carries a time-warped frame grid.
  void _ingestTimestamped(AudioFrameStatistics statistics, int ptsMs) {
    _totalAccruedMs += statistics.samples * 1000.0 / _sampleRate;
    var segment = _current;
    if (segment != null) {
      final expectedMs = segment.anchorMs + segment.elapsedMs;
      if ((ptsMs - expectedMs).abs() > _maxDriftMs) {
        _closeCurrent();
        segment = null;
      }
    }
    if (segment == null) {
      _openSegment(ptsMs);
      segment = _current!;
    }
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
    _trim();
  }

  Future<void> uninstall() async {
    if (!_installed) return;
    _installed = false;
    if (!_fileMode) {
      try {
        await _requirePlayer.unobserveProperty(metadataProperty);
      } catch (_) {
        // Player teardown can win this race. The property observation dies
        // with the native handle, and playback must not wait on cleanup.
      }
    }
    try {
      await _requirePlayer.command(<String>['af', 'remove', '@$filterLabel']);
    } catch (_) {
      // Same fail-soft rule: removing our unique label cannot be allowed to
      // interfere with disposal or a source transition.
    }
    await _teardownFileTransport();
    _fileMode = false;
  }

  void reset({int? anchorMs}) {
    _closed.clear();
    _current = null;
    _lastObservedPositionMs = anchorMs;
    _witnessedAdvanceMs = 0;
    _accruedAtWitnessStartMs = _totalAccruedMs;
    _reliable = true;
    _pollFailures = 0;
    _pendingPtsMs = null;
    _pendingRecord.clear();
    // File mode anchors from record pts; only the property fallback needs a
    // position-derived anchor to exist up front.
    if (_installed && !_fileMode) {
      _openSegment(anchorMs ?? _currentPositionMs());
    }
  }

  Future<void> resetForAudioTrack({required int anchorMs}) async {
    if (!_installed || _disposed) return;
    try {
      final rate = int.tryParse(
        await _requirePlayer.getProperty('audio-params/samplerate'),
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
    final delta = positionMs - previous;
    if (delta.abs() > 1500) {
      _closeCurrent();
      // In file mode the next record's own pts re-anchors; the property
      // fallback has no pts and must anchor from the seek target.
      if (!_fileMode) _openSegment(positionMs);
      _witnessedAdvanceMs = 0;
      _accruedAtWitnessStartMs = _totalAccruedMs;
      return true;
    }
    if (delta > 0) {
      _witnessedAdvanceMs += delta;
      _updateReliability();
    }
    return false;
  }

  /// Property fallback only: after 30s of witnessed continuous playback, the
  /// tap must have accrued most of that span as features. Losing more than
  /// ~20% means the transport is dropping frames (the measured macOS
  /// property-coalescing failure ran at ~50%) and any alignment would be
  /// against a distorted timeline.
  ///
  /// Deliberately NOT applied in file mode: FFmpeg's buffered writer holds
  /// tens of seconds of records before flushing, so accrued always lags
  /// witnessed by a constant latency that this ratio would misread as loss
  /// (field-observed: 26.3s/32.9s ≈ 0.80 → false "unreliable"). File-mode
  /// loss protection is structural instead — pts drift fragments segments
  /// below the aligner's usability floor.
  void _updateReliability() {
    if (_fileMode) return;
    if (!_reliable) return;
    if (_witnessedAdvanceMs < 30000) return;
    final accrued = _totalAccruedMs - _accruedAtWitnessStartMs;
    if (accrued / _witnessedAdvanceMs < 0.8) {
      _reliable = false;
      debugPrint(
        'SubtitleAutoSync: tap unreliable — accrued '
        '${(accrued / 1000).toStringAsFixed(1)}s over '
        '${(_witnessedAdvanceMs / 1000).toStringAsFixed(1)}s of playback '
        '(mode=${_fileMode ? 'file' : 'property'})',
      );
    }
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

  /// Property-fallback ingestion: no per-frame pts exists, so frames are
  /// assumed contiguous from the segment anchor. The [reliable] guard is what
  /// keeps that assumption honest.
  @visibleForTesting
  void ingestMetadata(Map<String, String> metadata) {
    final statistics = decodeMetadata(metadata, _sampleRate);
    if (statistics == null) return;
    _totalAccruedMs += statistics.samples * 1000.0 / _sampleRate;

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

  /// Feeds raw ametadata print output in tests through the SAME framing path
  /// the production tail uses.
  @visibleForTesting
  void ingestPrintOutput(String text) => _consumeChunk(text);

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

  /// Full accumulated time including the partially filled feature frame —
  /// the reference the file transport checks each record's pts against.
  double get elapsedMs =>
      durationMs + _accumulatedSamples * 1000.0 / sampleRate;

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
