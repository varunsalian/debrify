import 'dart:math' as math;

/// One contiguous run of fixed-duration audio features anchored to media time.
class AudioFeatureSegment {
  final int anchorMs;
  final int sampleRate;
  final int frameSamples;
  final List<double> band;
  final List<double> broadband;

  const AudioFeatureSegment({
    required this.anchorMs,
    required this.sampleRate,
    required this.frameSamples,
    required this.band,
    required this.broadband,
  });

  double get frameDurationMs => frameSamples * 1000.0 / sampleRate;
  double get durationMs => band.length * frameDurationMs;
}

class SubtitleCueSpan {
  final int startMs;
  final int endMs;
  final String text;

  const SubtitleCueSpan(this.startMs, this.endMs, this.text);
}

sealed class SubtitleAlignResult {
  const SubtitleAlignResult();
}

class SubtitleAlignSynced extends SubtitleAlignResult {
  final int offsetMs;
  final double confidence;
  final int analyzedSec;
  final double zPeak;
  final int usableCues;

  const SubtitleAlignSynced({
    required this.offsetMs,
    required this.confidence,
    required this.analyzedSec,
    this.zPeak = 0,
    this.usableCues = 0,
  });
}

class SubtitleAlignDrift extends SubtitleAlignResult {
  final double scale;
  final int offsetMs;
  final double confidence;

  const SubtitleAlignDrift({
    required this.scale,
    required this.offsetMs,
    this.confidence = 0,
  });
}

class SubtitleAlignNoMatch extends SubtitleAlignResult {
  final int analyzedSec;
  final int usableCues;
  final int? bestOffsetMs;
  final double bestZ;
  final double bestPsr;

  const SubtitleAlignNoMatch({
    required this.analyzedSec,
    this.usableCues = 0,
    this.bestOffsetMs,
    this.bestZ = 0,
    this.bestPsr = 0,
  });
}

class SubtitleAlignNotEnoughAudio extends SubtitleAlignResult {
  final int analyzedSec;
  final int usableCues;

  const SubtitleAlignNotEnoughAudio({
    required this.analyzedSec,
    this.usableCues = 0,
  });
}

/// Cross-correlates subtitle dialogue spans with a speech-activity timeline.
///
/// This is a direct Dart counterpart of Android TV's [SubtitleAligner]. Keeping
/// the same sign convention and gates lets the MediaKit and ExoPlayer engines
/// make the same decision from equivalent feature input.
class SubtitleAligner {
  static const double gridMs = 32;
  static const double searchMs = 90000;
  static const double narrowSearchMs = 15000;
  static const double narrowMinAudioMs = 20000;
  static const int narrowMinCueOverlapFrames = 300;
  static const int narrowMinCues = 8;
  static const double narrowMinZPeak = 8;
  static const double narrowMinPsr = 2.5;
  static const int minCues = 20;
  static const int maxGrid = 120000;
  static const double minAudioMs = 45000;
  static const int minCueOverlapFrames = 940;
  static const double minZPeak = 4;
  static const double minPsr = 5;
  static const double psrExcludeMs = 2000;
  static const double scaleParsimony = 1.10;
  static const List<double> scales = <double>[
    1,
    25 / 23.976,
    23.976 / 25,
    25 / 24,
    24 / 25,
    24 / 23.976,
    23.976 / 24,
  ];

  static const double actMargin = 0.35;
  static const double actRange = 1.2;
  static const double floorChunkMs = 5000;
  static const double floorPercentile = 0.10;
  static const double varianceWindowMs = 1000;
  static const double varianceLow = 0.15;
  static const double varianceRange = 0.45;
  static const double varianceMinWeight = 0.15;
  static const double dominanceLow = 0.25;
  static const double dominanceRange = 0.5;
  static const double dominanceMinWeight = 0.2;
  static const double cueMsPerCharacter = 70;
  static const double cueMinMs = 700;
  static const double cueMaxMs = 7000;

  static final RegExp _tagPattern = RegExp(r'<[^>]{0,32}>|\{[^}]{0,48}\}');

  static SubtitleAlignResult alignTiered(
    List<AudioFeatureSegment> segments,
    List<SubtitleCueSpan> cues,
  ) {
    final narrow = align(
      segments,
      cues,
      searchWindowMs: narrowSearchMs,
      minimumAudioMs: narrowMinAudioMs,
      minimumCueOverlapFrames: narrowMinCueOverlapFrames,
      minimumCues: narrowMinCues,
      minimumZPeak: narrowMinZPeak,
      minimumPsr: narrowMinPsr,
      scaleCandidates: const <double>[1],
    );
    if (narrow is SubtitleAlignSynced) return narrow;
    return align(segments, cues);
  }

  static SubtitleAlignResult align(
    List<AudioFeatureSegment> segments,
    List<SubtitleCueSpan> cues, {
    double searchWindowMs = searchMs,
    double minimumAudioMs = minAudioMs,
    int minimumCueOverlapFrames = minCueOverlapFrames,
    int minimumCues = minCues,
    double minimumZPeak = minZPeak,
    double minimumPsr = minPsr,
    List<double> scaleCandidates = scales,
  }) {
    final usable = segments
        .where((segment) => segment.durationMs >= 2000)
        .toList(growable: false);
    final analyzedSec =
        (usable.fold<double>(0, (sum, item) => sum + item.durationMs) / 1000)
            .round();
    final speechCues = filterCues(cues);
    final usableDuration = usable.fold<double>(
      0,
      (sum, item) => sum + item.durationMs,
    );
    if (usable.isEmpty ||
        usableDuration < minimumAudioMs ||
        speechCues.length < minimumCues) {
      return SubtitleAlignNotEnoughAudio(
        analyzedSec: analyzedSec,
        usableCues: speechCues.length,
      );
    }

    final spanCapMs = (maxGrid * gridMs).round();
    final picked = <AudioFeatureSegment>[];
    var t0 = 0x7fffffffffffffff;
    var t1 = -0x8000000000000000;
    for (final segment in usable.reversed) {
      final low = math.min(t0, segment.anchorMs);
      final high = math.max(t1, segment.anchorMs + segment.durationMs.round());
      if (high - low > spanCapMs) continue;
      picked.add(segment);
      t0 = low;
      t1 = high;
    }

    final n = ((t1 - t0) / gridMs).floor() + 1;
    final audio = List<double>.filled(n, 0);
    final mask = List<double>.filled(n, 0);
    for (final segment in picked.reversed) {
      final score = speechScore(segment);
      final frameDuration = segment.frameDurationMs;
      for (var i = 0; i < score.length; i++) {
        final grid = ((segment.anchorMs - t0 + i * frameDuration) / gridMs)
            .floor();
        if (grid >= 0 && grid < n) {
          audio[grid] = score[i];
          mask[grid] = 1;
        }
      }
    }

    var maskSum = 0.0;
    var activitySum = 0.0;
    for (var i = 0; i < n; i++) {
      maskSum += mask[i];
      activitySum += audio[i] * mask[i];
    }
    if (maskSum < minimumAudioMs / gridMs) {
      return SubtitleAlignNotEnoughAudio(
        analyzedSec: analyzedSec,
        usableCues: speechCues.length,
      );
    }
    final mean = activitySum / maskSum;
    var varianceSum = 0.0;
    for (var i = 0; i < n; i++) {
      if (mask[i] > 0) {
        final difference = audio[i] - mean;
        varianceSum += difference * difference;
      }
    }
    final sigma = math.sqrt(varianceSum / maskSum);
    if (sigma < 1e-4) {
      return SubtitleAlignNotEnoughAudio(
        analyzedSec: analyzedSec,
        usableCues: speechCues.length,
      );
    }

    final centeredAudio = List<double>.generate(
      n,
      (i) => mask[i] * (audio[i] - mean),
      growable: false,
    );
    final lagRadius = (searchWindowMs / gridMs).floor();
    final transformSize = _nextPowerOfTwo(n + 2 * lagRadius + 1);
    final audioFft = _Fft(transformSize).forwardConjugate(centeredAudio);
    final maskFft = _Fft(transformSize).forwardConjugate(mask);

    _Peak? best;
    _Peak? bestUnscaled;
    for (final scale in scaleCandidates) {
      final cueGrid = _rasterizeCues(speechCues, scale, t0, n, lagRadius);
      final cueFft = _Fft(transformSize).forward(cueGrid);
      final correlation = _Fft(transformSize).inverseProduct(audioFft, cueFft);
      final mass = _Fft(transformSize).inverseProduct(maskFft, cueFft);
      final peak = _bestLag(
        correlation,
        mass,
        sigma,
        lagRadius,
        minimumCueOverlapFrames,
      );
      if (peak == null) continue;
      final scaledPeak = peak.copyWith(scale: scale);
      if (scale == 1) bestUnscaled = scaledPeak;
      if (best == null || scaledPeak.z > best.z) best = scaledPeak;
    }
    if (best == null) {
      return SubtitleAlignNoMatch(
        analyzedSec: analyzedSec,
        usableCues: speechCues.length,
      );
    }

    var effective = best;
    if (best.scale != 1 &&
        bestUnscaled != null &&
        bestUnscaled.z * scaleParsimony >= best.z) {
      effective = bestUnscaled;
    }
    final offsetMs = (effective.lagGrids * gridMs).round();
    if (effective.z < minimumZPeak || effective.psr < minimumPsr) {
      return SubtitleAlignNoMatch(
        analyzedSec: analyzedSec,
        usableCues: speechCues.length,
        bestOffsetMs: offsetMs,
        bestZ: effective.z,
        bestPsr: effective.psr,
      );
    }
    if (effective.scale != 1) {
      return SubtitleAlignDrift(
        scale: effective.scale,
        offsetMs: offsetMs,
        confidence: effective.psr,
      );
    }
    return SubtitleAlignSynced(
      offsetMs: offsetMs,
      confidence: effective.psr,
      analyzedSec: analyzedSec,
      zPeak: effective.z,
      usableCues: speechCues.length,
    );
  }

  static List<double> speechScore(AudioFeatureSegment segment) {
    final count = segment.band.length;
    final logEnergy = List<double>.generate(
      count,
      (i) => math.log(segment.band[i] + 1e-6),
      growable: false,
    );
    final chunk = math.max(1, (floorChunkMs / segment.frameDurationMs).floor());
    final chunkCount = (count + chunk - 1) ~/ chunk;
    final floors = List<double>.filled(chunkCount, 0);
    for (var c = 0; c < chunkCount; c++) {
      final from = c * chunk;
      final end = math.min(count, from + chunk);
      final values = logEnergy.sublist(from, end)..sort();
      floors[c] =
          values[math.min(
            values.length - 1,
            (values.length * floorPercentile).floor(),
          )];
    }

    double floorAt(int index) {
      if (chunkCount == 1) return floors.first;
      final position = index / chunk - 0.5;
      final low = position.floor().clamp(0, chunkCount - 1);
      final high = math.min(chunkCount - 1, low + 1);
      final fraction = (position - low).clamp(0.0, 1.0);
      return floors[low] * (1 - fraction) + floors[high] * fraction;
    }

    var window = math.max(
      3,
      (varianceWindowMs / segment.frameDurationMs).floor(),
    );
    window |= 1;
    final half = window ~/ 2;
    final prefix = List<double>.filled(count + 1, 0);
    final prefixSquares = List<double>.filled(count + 1, 0);
    for (var i = 0; i < count; i++) {
      prefix[i + 1] = prefix[i] + logEnergy[i];
      prefixSquares[i + 1] = prefixSquares[i] + logEnergy[i] * logEnergy[i];
    }

    final output = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final activity = ((logEnergy[i] - floorAt(i) - actMargin) / actRange)
          .clamp(0.0, 1.0);
      final low = math.max(0, i - half);
      final high = math.min(count, i + half + 1);
      final sampleCount = (high - low).toDouble();
      final localMean = (prefix[high] - prefix[low]) / sampleCount;
      final standardDeviation = math.sqrt(
        math.max(
          0,
          (prefixSquares[high] - prefixSquares[low]) / sampleCount -
              localMean * localMean,
        ),
      );
      final varianceWeight = ((standardDeviation - varianceLow) / varianceRange)
          .clamp(varianceMinWeight, 1.0);
      final dominance = segment.band[i] / (segment.broadband[i] + 1e-6);
      final dominanceWeight = ((dominance - dominanceLow) / dominanceRange)
          .clamp(dominanceMinWeight, 1.0);
      output[i] = activity * varianceWeight * dominanceWeight;
    }
    return output;
  }

  static List<SubtitleCueSpan> filterCues(List<SubtitleCueSpan> cues) {
    return cues
        .where((cue) {
          final text = cue.text.replaceAll(_tagPattern, '').trim();
          if (text.isEmpty || text.contains('♪') || text.contains('♫')) {
            return false;
          }
          final bracketed =
              (text.startsWith('[') && text.endsWith(']')) ||
              (text.startsWith('(') && text.endsWith(')'));
          return !bracketed && cue.endMs > cue.startMs;
        })
        .toList(growable: false);
  }

  static List<double> _rasterizeCues(
    List<SubtitleCueSpan> cues,
    double scale,
    int t0,
    int n,
    int lagRadius,
  ) {
    final output = List<double>.filled(n + 2 * lagRadius, 0);
    for (final cue in cues) {
      final characters = cue.text.replaceAll(_tagPattern, '').trim().length;
      final cap = (characters * cueMsPerCharacter).clamp(cueMinMs, cueMaxMs);
      final start = cue.startMs * scale;
      final end = start + math.min((cue.endMs - cue.startMs) * scale, cap);
      var grid = ((start - t0) / gridMs).floor() + lagRadius;
      final gridEnd = ((end - t0) / gridMs).floor() + lagRadius;
      while (grid <= gridEnd) {
        if (grid >= 0 && grid < output.length) output[grid] = 1;
        grid++;
      }
    }
    return output;
  }

  static _Peak? _bestLag(
    List<double> correlation,
    List<double> mass,
    double sigma,
    int lagRadius,
    int minimumOverlap,
  ) {
    final z = List<double>.filled(2 * lagRadius + 1, double.nan);
    var bestIndex = -1;
    for (var i = 0; i <= 2 * lagRadius; i++) {
      final overlap = mass[i];
      if (overlap < minimumOverlap) continue;
      z[i] = correlation[i] / (sigma * math.sqrt(overlap));
      if (bestIndex < 0 || z[i] > z[bestIndex]) bestIndex = i;
    }
    if (bestIndex < 0) return null;

    final exclusion = (psrExcludeMs / gridMs).floor();
    var count = 0;
    var sum = 0.0;
    var squareSum = 0.0;
    for (var i = 0; i <= 2 * lagRadius; i++) {
      if (z[i].isNaN || (i - bestIndex).abs() <= exclusion) continue;
      count++;
      sum += z[i];
      squareSum += z[i] * z[i];
    }
    if (count < 50) return null;
    final backgroundMean = sum / count;
    final backgroundDeviation = math.sqrt(
      math.max(1e-12, squareSum / count - backgroundMean * backgroundMean),
    );
    final psr = (z[bestIndex] - backgroundMean) / backgroundDeviation;

    var lag = (lagRadius - bestIndex).toDouble();
    if (bestIndex > 0 &&
        bestIndex < 2 * lagRadius &&
        !z[bestIndex - 1].isNaN &&
        !z[bestIndex + 1].isNaN) {
      final denominator =
          z[bestIndex - 1] - 2 * z[bestIndex] + z[bestIndex + 1];
      if (denominator.abs() > 1e-9) {
        final delta = 0.5 * (z[bestIndex - 1] - z[bestIndex + 1]) / denominator;
        if (delta.abs() <= 1) lag -= delta;
      }
    }
    return _Peak(lag, z[bestIndex], psr);
  }

  static int _nextPowerOfTwo(int value) {
    var result = 1;
    while (result < value) {
      result <<= 1;
    }
    return result;
  }
}

class _Peak {
  final double lagGrids;
  final double z;
  final double psr;
  final double scale;

  const _Peak(this.lagGrids, this.z, this.psr, [this.scale = 1]);

  _Peak copyWith({double? scale}) =>
      _Peak(lagGrids, z, psr, scale ?? this.scale);
}

class _ComplexVector {
  final List<double> real;
  final List<double> imaginary;

  const _ComplexVector(this.real, this.imaginary);
}

class _Fft {
  final int size;

  const _Fft(this.size);

  _ComplexVector forwardConjugate(List<double> input) {
    final output = forward(input);
    for (var i = 0; i < output.imaginary.length; i++) {
      output.imaginary[i] = -output.imaginary[i];
    }
    return output;
  }

  _ComplexVector forward(List<double> input) {
    final real = List<double>.filled(size, 0);
    final imaginary = List<double>.filled(size, 0);
    for (var i = 0; i < math.min(size, input.length); i++) {
      real[i] = input[i];
    }
    _transform(real, imaginary, inverse: false);
    return _ComplexVector(real, imaginary);
  }

  List<double> inverseProduct(_ComplexVector left, _ComplexVector right) {
    final real = List<double>.filled(size, 0);
    final imaginary = List<double>.filled(size, 0);
    for (var i = 0; i < size; i++) {
      real[i] =
          left.real[i] * right.real[i] - left.imaginary[i] * right.imaginary[i];
      imaginary[i] =
          left.real[i] * right.imaginary[i] + left.imaginary[i] * right.real[i];
    }
    _transform(real, imaginary, inverse: true);
    return real;
  }

  void _transform(
    List<double> real,
    List<double> imaginary, {
    required bool inverse,
  }) {
    var j = 0;
    for (var i = 1; i < size; i++) {
      var bit = size >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j |= bit;
      if (i < j) {
        final realValue = real[i];
        real[i] = real[j];
        real[j] = realValue;
        final imaginaryValue = imaginary[i];
        imaginary[i] = imaginary[j];
        imaginary[j] = imaginaryValue;
      }
    }

    var length = 2;
    while (length <= size) {
      final angle = 2 * math.pi / length * (inverse ? 1 : -1);
      final rotationReal = math.cos(angle);
      final rotationImaginary = math.sin(angle);
      var offset = 0;
      while (offset < size) {
        var currentReal = 1.0;
        var currentImaginary = 0.0;
        for (var p = 0; p < length ~/ 2; p++) {
          final upperReal = real[offset + p];
          final upperImaginary = imaginary[offset + p];
          final lowerReal =
              real[offset + p + length ~/ 2] * currentReal -
              imaginary[offset + p + length ~/ 2] * currentImaginary;
          final lowerImaginary =
              real[offset + p + length ~/ 2] * currentImaginary +
              imaginary[offset + p + length ~/ 2] * currentReal;
          real[offset + p] = upperReal + lowerReal;
          imaginary[offset + p] = upperImaginary + lowerImaginary;
          real[offset + p + length ~/ 2] = upperReal - lowerReal;
          imaginary[offset + p + length ~/ 2] = upperImaginary - lowerImaginary;
          final nextReal =
              currentReal * rotationReal - currentImaginary * rotationImaginary;
          currentImaginary =
              currentReal * rotationImaginary + currentImaginary * rotationReal;
          currentReal = nextReal;
        }
        offset += length;
      }
      length <<= 1;
    }
    if (inverse) {
      for (var i = 0; i < size; i++) {
        real[i] /= size;
        imaginary[i] /= size;
      }
    }
  }
}
